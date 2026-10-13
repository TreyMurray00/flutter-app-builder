import 'dart:convert';
import 'dart:io';

import 'package:local_flutter_builder/models/builder_document.dart';
import 'package:local_flutter_builder/services/dart_generator.dart';
import 'package:local_flutter_builder/services/flutter_project_exporter.dart';
import 'package:local_flutter_builder/services/project_store.dart';

const String _version = '0.1.0';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == 'help' || args.first == '--help') {
    _printHelp();
    return;
  }

  final String command = args.first;
  final List<String> commandArgs = args.skip(1).toList();
  try {
    switch (command) {
      case '--version':
      case 'version':
        stdout.writeln('app-builder $_version');
        break;
      case 'init':
        await _init(commandArgs);
        break;
      case 'validate':
        await _validate(commandArgs);
        break;
      case 'inspect':
        await _inspect(commandArgs);
        break;
      case 'export':
        await _export(commandArgs);
        break;
      default:
        _writeFailure(
          'Unknown command: $command',
          64,
          jsonOutput: args.contains('--json'),
        );
        if (!args.contains('--json')) {
          _printHelp();
        }
        exitCode = 64;
        break;
    }
  } on _UsageException catch (error) {
    _writeFailure(error.message, 64, jsonOutput: args.contains('--json'));
    if (!args.contains('--json')) {
      stderr.writeln('Run `dart run bin/app_builder.dart help` for usage.');
    }
    exitCode = 64;
  } catch (error) {
    _writeFailure(error.toString(), 1, jsonOutput: args.contains('--json'));
    exitCode = 1;
  }
}

void _writeFailure(String message, int code, {required bool jsonOutput}) {
  if (jsonOutput) {
    stdout.writeln(jsonEncode(<String, Object?>{
      'ok': false,
      'exitCode': code,
      'error': message,
    }));
  } else {
    stderr.writeln('Error: $message');
  }
}

Future<void> _init(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('--')) {
    throw const _UsageException('init requires a project file path.');
  }
  final String path = args.first;
  final Map<String, String?> options = _options(args.skip(1).toList());
  _rejectUnknownOptions(options, <String>{'name', 'json'});
  final File target = File(path).absolute;
  if (await target.exists()) {
    throw FileSystemException('Project file already exists.', target.path);
  }

  final String name = options['name'] ?? _nameFromPath(target.path);
  if (name.trim().isEmpty) {
    throw const _UsageException('The project name must not be empty.');
  }
  final BuilderDocument starter = BuilderDocument.sample();
  final BuilderDocument document = starter.copyWith(
    name: name,
    root: starter.root.copyWith(
      children: <BuilderNode>[
        BuilderNode(
          id: 'column_1',
          type: 'column',
          properties: <String, Object?>{
            'mainAxisAlignment': 'start',
            'crossAxisAlignment': 'start',
          },
          children: <BuilderNode>[
            BuilderNode(
              id: 'text_1',
              type: 'text',
              properties: <String, Object?>{
                'text': 'Welcome to $name',
                'fontSize': 26.0,
                'fontWeight': 'bold',
              },
              children: <BuilderNode>[],
            ),
            BuilderNode(
              id: 'text_2',
              type: 'text',
              properties: <String, Object?>{
                'text': 'Edit this project manifest, then export it to Flutter.',
                'fontSize': 16.0,
              },
              children: <BuilderNode>[],
            ),
          ],
        ),
      ],
    ),
  );

  final StoredProject saved = await ProjectStore().saveProjectWithDocument(
    document,
    target.path,
  );
  if (options.containsKey('json')) {
    stdout.writeln(jsonEncode(<String, Object?>{
      'ok': true,
      'path': saved.path,
      'name': saved.document.name,
    }));
  } else {
    stdout.writeln('Created ${saved.path}');
    stdout.writeln('Next: dart run bin/app_builder.dart validate "${saved.path}"');
  }
}

Future<void> _validate(List<String> args) async {
  final _ParsedFileCommand parsed = _parseFileCommand(args);
  final List<_Issue> issues = await _validateFile(parsed.file);
  final bool ok = !issues.any((_Issue issue) => issue.severity == 'error');
  if (parsed.json) {
    stdout.writeln(jsonEncode(<String, Object?>{
      'ok': ok,
      'path': parsed.file.path,
      'issues': issues.map((_Issue issue) => issue.toJson()).toList(),
    }));
  } else {
    if (issues.isEmpty) {
      stdout.writeln('Valid builder project: ${parsed.file.path}');
    } else {
      for (final _Issue issue in issues) {
        stdout.writeln('${issue.severity.toUpperCase()}: ${issue.message}');
      }
      stdout.writeln(
        ok ? 'Project is valid with warnings.' : 'Project is invalid.',
      );
    }
  }
  if (!ok) exitCode = 2;
}

Future<List<_Issue>> _validateFile(File file) async {
  final List<_Issue> issues = <_Issue>[];
  try {
    if (!await file.exists()) {
      return <_Issue>[
        _Issue('error', 'Project file does not exist: ${file.path}'),
      ];
    }
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return <_Issue>[
        const _Issue('error', 'Project root must be a JSON object.'),
      ];
    }
    final BuilderDocument document = BuilderDocument.fromJson(
      Map<String, Object?>.from(decoded),
    );
    _checkPageMetadata(document, issues);

    for (final BuilderPage page in document.allPages) {
      final Set<String> nodeIds = <String>{};
      for (final BuilderNode node in page.root.depthFirst()) {
        if (node.id.trim().isEmpty) {
          issues.add(_Issue(
            'error',
            'Page "${page.name}" contains a widget with an empty id.',
          ));
        }
        if (!nodeIds.add(node.id)) {
          issues.add(
            _Issue(
              'error',
              'Page "${page.name}" contains duplicate widget id "${node.id}".',
            ),
          );
        }
        if (node.children.isNotEmpty && !node.acceptsChildren) {
          issues.add(
            _Issue(
              'warning',
              'Widget "${node.id}" (${node.type}) has children that its layout may ignore.',
            ),
          );
        }
        if (node.type == 'expanded') {
          BuilderNode? parent = page.root.parentOfId(node.id);
          while (parent != null &&
              parent.type == 'componentGroup' &&
              parent.children.length == 1) {
            parent = page.root.parentOfId(parent.id);
          }
          final bool isValidFlexChild =
              parent?.type == 'row' ||
              parent?.type == 'column' ||
              (parent != null &&
                  parent.type == 'componentGroup' &&
                  parent.children.length > 1);
          if (!isValidFlexChild) {
            issues.add(
              _Issue(
                'error',
                'Expanded widget "${node.id}" must be a direct child of a Row or Column.',
              ),
            );
          }
        }
        if (node.type == 'image') {
          final Object? rawSource = node.properties['source'];
          final String source = rawSource is String ? rawSource.trim() : '';
          if (source.isNotEmpty &&
              !await File(
                resolveProjectAssetPath(file.path, source),
              ).exists()) {
            issues.add(
              _Issue(
                'error',
                'Image asset for widget "${node.id}" was not found: $source',
              ),
            );
          }
        }
      }
    }

    final Set<String> routes = <String>{};
    final Set<String> pageIds = <String>{};
    for (final BuilderPage page in document.allPages) {
      if (!pageIds.add(page.id)) {
        issues.add(_Issue('error', 'Duplicate page id "${page.id}".'));
      }
      if (page.name.trim().isEmpty) {
        issues.add(_Issue('error', 'Page "${page.id}" has an empty name.'));
      }
      if (page.route.trim().isEmpty) {
        issues.add(_Issue('error', 'Page "${page.name}" has an empty route.'));
      } else if (!routes.add(page.route)) {
        issues.add(_Issue('error', 'Duplicate page route "${page.route}".'));
      }
    }

    try {
      DartGenerator().generate(document);
    } catch (error) {
      issues.add(_Issue('error', 'Flutter code generation failed: $error'));
    }
  } on FormatException catch (error) {
    issues.add(_Issue('error', error.message.toString()));
  } on FileSystemException catch (error) {
    issues.add(_Issue('error', error.message));
  } catch (error) {
    issues.add(_Issue('error', error.toString()));
  }
  return issues;
}

void _checkPageMetadata(BuilderDocument document, List<_Issue> issues) {
  if (document.name.trim().isEmpty) {
    issues.add(const _Issue('error', 'Project name must not be empty.'));
  }
  if (!document.allPages.any((BuilderPage page) => page.id == document.initialPageId)) {
    issues.add(
      _Issue(
        'error',
        'Initial page "${document.initialPageId}" does not exist.',
      ),
    );
  }
}

Future<void> _inspect(List<String> args) async {
  final _ParsedFileCommand parsed = _parseFileCommand(args);
  final BuilderDocument document = await _readDocument(parsed.file);
  final Map<String, Object?> result = <String, Object?>{
    'name': document.name,
    'schemaVersion': document.schemaVersion,
    'initialPageId': document.initialPageId,
    'pages': document.allPages.map((BuilderPage page) => <String, Object?>{
      'id': page.id,
      'name': page.name,
      'route': page.route,
      'widgets': page.root.depthFirst().map((BuilderNode node) => <String, Object?>{
        'id': node.id,
        'type': node.type,
        'properties': node.properties,
        if (node.type == 'image' && node.properties['source'] is String)
          'source': node.properties['source'],
      }).toList(),
    }).toList(),
    'variables': document.variables.map((BuilderVariable variable) => <String, Object?>{
      'id': variable.id,
      'name': variable.name,
      'type': variable.type,
      'initialValue': variable.initialValue,
    }).toList(),
    'customFunctions': document.customFunctions.map((BuilderCustomFunction function) => <String, Object?>{
      'id': function.id,
      'name': function.name,
    }).toList(),
    'customDataStructures': document.customDataStructures.map((BuilderCustomDataStructure structure) => <String, Object?>{
      'id': structure.id,
      'name': structure.name,
    }).toList(),
    'databaseCollections': document.databaseCollections.map((BuilderDatabaseCollection collection) => <String, Object?>{
      'id': collection.id,
      'name': collection.name,
      'seedRecordCount': collection.seedRecords.length,
    }).toList(),
    'componentGroups': document.componentGroups.map((BuilderComponentGroup group) => <String, Object?>{
      'id': group.id,
      'name': group.name,
    }).toList(),
  };

  if (parsed.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return;
  }
  stdout.writeln('${document.name} (schema ${document.schemaVersion})');
  for (final BuilderPage page in document.allPages) {
    stdout.writeln('Page: ${page.name}  ${page.route}  [${page.id}]');
    for (final BuilderNode node in page.root.depthFirst()) {
      stdout.writeln('  ${node.type}  [${node.id}]');
    }
  }
  stdout.writeln('Variables: ${document.variables.length}');
  stdout.writeln('Custom functions: ${document.customFunctions.length}');
  stdout.writeln('Database collections: ${document.databaseCollections.length}');
}

Future<BuilderDocument> _readDocument(File file) async {
  if (!await file.exists()) {
    throw FileSystemException('Project file does not exist.', file.path);
  }
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Project root must be a JSON object.');
  }
  return BuilderDocument.fromJson(Map<String, Object?>.from(decoded));
}

Future<void> _export(List<String> args) async {
  final _ParsedFileCommand parsed = _parseFileCommand(args, extra: <String>{'output'});
  final String? output = parsed.options['output'];
  if (output == null || output.trim().isEmpty) {
    throw const _UsageException('export requires --output <project-directory>.');
  }
  final BuilderDocument document = await _readDocument(parsed.file);
  final List<_Issue> issues = await _validateFile(parsed.file);
  final List<_Issue> errors = issues.where((_Issue issue) => issue.severity == 'error').toList();
  if (errors.isNotEmpty) {
    if (parsed.json) {
      stdout.writeln(jsonEncode(<String, Object?>{
        'ok': false,
        'path': parsed.file.path,
        'issues': errors.map((_Issue issue) => issue.toJson()).toList(),
      }));
    } else {
      for (final _Issue issue in errors) {
        stderr.writeln('ERROR: ${issue.message}');
      }
    }
    exitCode = 2;
    return;
  }

  final List<String> flutterOutput = <String>[];
  final String result = await FlutterProjectExporter(generator: DartGenerator()).export(
    document,
    output,
    projectPath: parsed.file.path,
    onOutput: (String line) {
      flutterOutput.add(line);
      if (!parsed.json) stdout.writeln(line);
    },
  );
  if (parsed.json) {
    stdout.writeln(jsonEncode(<String, Object?>{
      'ok': true,
      'path': result,
      'flutterOutput': flutterOutput,
      'warnings': issues.where((_Issue issue) => issue.severity == 'warning')
          .map((_Issue issue) => issue.message).toList(),
    }));
  } else {
    stdout.writeln('Exported Flutter project to $result');
  }
}

_ParsedFileCommand _parseFileCommand(List<String> args, {Set<String> extra = const <String>{}}) {
  if (args.isEmpty || args.first.startsWith('--')) {
    throw const _UsageException('A project file path is required.');
  }
  final Map<String, String?> options = _options(args.skip(1).toList());
  _rejectUnknownOptions(options, <String>{'json', ...extra});
  return _ParsedFileCommand(
    File(args.first).absolute,
    options.containsKey('json'),
    options,
  );
}

Map<String, String?> _options(List<String> args) {
  final Map<String, String?> options = <String, String?>{};
  for (int index = 0; index < args.length; index++) {
    final String arg = args[index];
    if (!arg.startsWith('--')) {
      throw _UsageException('Unexpected argument: $arg');
    }
    final String key = arg.substring(2);
    if (key.isEmpty || options.containsKey(key)) {
      throw _UsageException('Invalid or repeated option: $arg');
    }
    if (key == 'json') {
      options[key] = null;
    } else {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw _UsageException('$arg requires a value.');
      }
      options[key] = args[++index];
    }
  }
  return options;
}

void _rejectUnknownOptions(Map<String, String?> options, Set<String> allowed) {
  final Iterable<String> unknown = options.keys.where((String key) => !allowed.contains(key));
  if (unknown.isNotEmpty) {
    throw _UsageException('Unknown option(s): ${unknown.map((String key) => '--$key').join(', ')}');
  }
}

String _nameFromPath(String path) {
  String name = path.split(RegExp(r'[/\\]')).last
      .replaceFirst(RegExp(r'\.appbuilder\.json$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\.json$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();
  if (name.isEmpty) name = 'My App';
  return name;
}

void _printHelp() {
  stdout.writeln('''Local Flutter Builder CLI $_version

Usage:
  dart run bin/app_builder.dart <command> [arguments]

Commands:
  init <file> [--name <name>] [--json]  Create a starter .appbuilder.json project.
  validate <file> [--json]              Check the project schema, assets, and generated widgets.
  inspect <file> [--json]               Summarize pages, widgets, state, and resources.
  export <file> --output <directory> [--json]
                                        Generate a complete Flutter app in a new directory.
  help                                  Show this help.
  --version                             Show the CLI version.

All commands run locally. Export uses the Flutter SDK found on PATH or FLUTTER_ROOT.
''');
}

class _ParsedFileCommand {
  const _ParsedFileCommand(this.file, this.json, this.options);

  final File file;
  final bool json;
  final Map<String, String?> options;
}

class _Issue {
  const _Issue(this.severity, this.message);

  final String severity;
  final String message;

  Map<String, String> toJson() => <String, String>{
    'severity': severity,
    'message': message,
  };
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}
