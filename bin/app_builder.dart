import 'dart:convert';
import 'dart:io';

import 'package:local_flutter_builder/models/builder_document.dart';
import 'package:local_flutter_builder/services/dart_generator.dart';
import 'package:local_flutter_builder/services/flutter_project_exporter.dart';
import 'package:local_flutter_builder/services/project_store.dart';
import 'package:local_flutter_builder/services/project_validator.dart';

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
      case 'database':
        await _database(commandArgs);
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
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'ok': false,
        'exitCode': code,
        'error': message,
      }),
    );
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
                'text':
                    'Edit this project manifest, then export it to Flutter.',
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
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'ok': true,
        'path': saved.path,
        'name': saved.document.name,
      }),
    );
  } else {
    stdout.writeln('Created ${saved.path}');
    stdout.writeln(
      'Next: dart run bin/app_builder.dart validate "${saved.path}"',
    );
  }
}

Future<void> _validate(List<String> args) async {
  final _ParsedFileCommand parsed = _parseFileCommand(args);
  final List<_Issue> issues = await _validateFile(parsed.file);
  final bool ok = !issues.any((_Issue issue) => issue.severity == 'error');
  if (parsed.json) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'ok': ok,
        'path': parsed.file.path,
        'issues': issues.map((_Issue issue) => issue.toJson()).toList(),
      }),
    );
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
    return (await ProjectValidator().validate(document, projectPath: file.path))
        .map((ProjectIssue issue) => _Issue(issue.severity, issue.message))
        .toList();
  } on FormatException catch (error) {
    return <_Issue>[_Issue('error', error.message.toString())];
  } on FileSystemException catch (error) {
    return <_Issue>[_Issue('error', error.message)];
  } catch (error) {
    return <_Issue>[_Issue('error', error.toString())];
  }
}

Future<void> _inspect(List<String> args) async {
  final _ParsedFileCommand parsed = _parseFileCommand(args);
  final BuilderDocument document = await _readDocument(parsed.file);
  final Map<String, Object?> result = <String, Object?>{
    'name': document.name,
    'schemaVersion': document.schemaVersion,
    'initialPageId': document.initialPageId,
    'pages':
        document.allPages
            .map(
              (BuilderPage page) => <String, Object?>{
                'id': page.id,
                'name': page.name,
                'route': page.route,
                'widgets':
                    page.root
                        .depthFirst()
                        .map(
                          (BuilderNode node) => <String, Object?>{
                            'id': node.id,
                            'type': node.type,
                            'properties': node.properties,
                            if (node.type == 'image' &&
                                node.properties['source'] is String)
                              'source': node.properties['source'],
                          },
                        )
                        .toList(),
              },
            )
            .toList(),
    'variables':
        document.variables
            .map(
              (BuilderVariable variable) => <String, Object?>{
                'id': variable.id,
                'name': variable.name,
                'type': variable.type,
                'initialValue': variable.initialValue,
              },
            )
            .toList(),
    'customFunctions':
        document.customFunctions
            .map(
              (BuilderCustomFunction function) => <String, Object?>{
                'id': function.id,
                'name': function.name,
              },
            )
            .toList(),
    'customDataStructures':
        document.customDataStructures
            .map(
              (BuilderCustomDataStructure structure) => <String, Object?>{
                'id': structure.id,
                'name': structure.name,
              },
            )
            .toList(),
    'databaseCollections':
        document.databaseCollections
            .map(
              (BuilderDatabaseCollection collection) => <String, Object?>{
                'id': collection.id,
                'name': collection.name,
                'fields':
                    collection.fields
                        .map(
                          (BuilderDatabaseField field) => <String, Object?>{
                            'id': field.id,
                            'name': field.name,
                            'type': field.type,
                            'primaryKey': field.primaryKey,
                            'unique': field.unique,
                          },
                        )
                        .toList(),
                'seedRecordCount': collection.seedRecords.length,
              },
            )
            .toList(),
    'databaseRelationships':
        document.databaseRelationships
            .map(
              (BuilderDatabaseRelationship relationship) =>
                  relationship.toJson(),
            )
            .toList(),
    'componentGroups':
        document.componentGroups
            .map(
              (BuilderComponentGroup group) => <String, Object?>{
                'id': group.id,
                'name': group.name,
              },
            )
            .toList(),
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
  stdout.writeln(
    'Database collections: ${document.databaseCollections.length}  '
    'relationships: ${document.databaseRelationships.length}',
  );
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

Future<void> _database(List<String> args) async {
  if (args.length < 2 || args.first.startsWith('--')) {
    throw const _UsageException(
      'database requires a project file and an operation. See help for operations.',
    );
  }
  final File file = File(args.first).absolute;
  final String operation = args[1];
  final Map<String, String?> options = _options(args.skip(2).toList());
  final bool jsonOutput = options.containsKey('json');
  final BuilderDocument document = await _readDocument(file);
  if (operation == 'list') {
    _rejectUnknownOptions(options, <String>{'json'});
    if (jsonOutput) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'ok': true,
          'path': file.path,
          'collections':
              document.databaseCollections
                  .map((BuilderDatabaseCollection item) => item.toJson())
                  .toList(),
          'relationships':
              document.databaseRelationships
                  .map((BuilderDatabaseRelationship item) => item.toJson())
                  .toList(),
        }),
      );
    } else {
      for (final BuilderDatabaseCollection collection
          in document.databaseCollections) {
        stdout.writeln(
          '${collection.name} [${collection.id}] '
          '(${collection.fields.length} fields, '
          '${collection.seedRecords.length} seed records)',
        );
        for (final BuilderDatabaseField field in collection.fields) {
          stdout.writeln(
            '  ${field.name} [${field.id}]: ${field.type}'
            '${field.primaryKey ? ' primary key' : ''}'
            '${field.unique ? ' unique' : ''}'
            '${field.required ? ' required' : ''}',
          );
        }
      }
      for (final BuilderDatabaseRelationship relationship
          in document.databaseRelationships) {
        stdout.writeln(
          'Relationship: ${relationship.name} [${relationship.id}] '
          '${relationship.fromCollectionId}.${relationship.fromFieldId} -> '
          '${relationship.toCollectionId}.${relationship.toFieldId}',
        );
      }
      if (document.databaseCollections.isEmpty &&
          document.databaseRelationships.isEmpty) {
        stdout.writeln('No database resources.');
      }
    }
    return;
  }

  BuilderDocument updated;
  String description;
  switch (operation) {
    case 'add-collection':
      _rejectUnknownOptions(options, <String>{'id', 'name', 'json'});
      final String id = _requiredOption(options, 'id');
      final String name = _requiredOption(options, 'name');
      updated = document.copyWith(
        databaseCollections: <BuilderDatabaseCollection>[
          ...document.databaseCollections,
          BuilderDatabaseCollection(id: id, name: name),
        ],
      );
      description = 'Added collection $id';
      break;
    case 'add-field':
      _rejectUnknownOptions(options, <String>{
        'collection',
        'id',
        'name',
        'type',
        'required',
        'primary-key',
        'unique',
        'json',
      });
      final String collectionId = _requiredOption(options, 'collection');
      final String id = _requiredOption(options, 'id');
      final String name = _requiredOption(options, 'name');
      final String type = options['type'] ?? 'string';
      if (!<String>{
        'string',
        'integer',
        'number',
        'boolean',
        'date',
        'json',
      }.contains(type)) {
        throw _UsageException('Unsupported database field type: $type');
      }
      final BuilderDatabaseCollection collection = _databaseCollection(
        document,
        collectionId,
      );
      updated = _replaceDatabaseCollection(
        document,
        collection.copyWith(
          fields: <BuilderDatabaseField>[
            ...collection.fields,
            BuilderDatabaseField(
              id: id,
              name: name,
              type: type,
              required: options.containsKey('required'),
              primaryKey: options.containsKey('primary-key'),
              unique: options.containsKey('unique'),
            ),
          ],
        ),
      );
      description = 'Added field $collectionId.$id';
      break;
    case 'add-relationship':
      _rejectUnknownOptions(options, <String>{
        'id',
        'name',
        'from-collection',
        'from-field',
        'to-collection',
        'to-field',
        'json',
      });
      final String id = _requiredOption(options, 'id');
      final String name = _requiredOption(options, 'name');
      updated = document.copyWith(
        databaseRelationships: <BuilderDatabaseRelationship>[
          ...document.databaseRelationships,
          BuilderDatabaseRelationship(
            id: id,
            name: name,
            fromCollectionId: _requiredOption(options, 'from-collection'),
            fromFieldId: _requiredOption(options, 'from-field'),
            toCollectionId: _requiredOption(options, 'to-collection'),
            toFieldId: _requiredOption(options, 'to-field'),
          ),
        ],
      );
      description = 'Added relationship $id';
      break;
    case 'add-seed':
      _rejectUnknownOptions(options, <String>{
        'collection',
        'record',
        'record-file',
        'json',
      });
      final String collectionId = _requiredOption(options, 'collection');
      if (options.containsKey('record') == options.containsKey('record-file')) {
        throw const _UsageException(
          'add-seed requires exactly one of --record or --record-file.',
        );
      }
      final String recordSource =
          options['record'] ??
          await File(_requiredOption(options, 'record-file')).readAsString();
      final Object? decoded = jsonDecode(recordSource);
      if (decoded is! Map) {
        throw const _UsageException('The seed record must be a JSON object.');
      }
      final Map<String, Object?> record = Map<String, Object?>.from(decoded);
      if (record.containsKey('_id')) {
        throw const _UsageException(
          'Seed records cannot set the reserved _id key.',
        );
      }
      final BuilderDatabaseCollection collection = _databaseCollection(
        document,
        collectionId,
      );
      final Set<String> fieldIds =
          collection.fields
              .map((BuilderDatabaseField field) => field.id)
              .toSet();
      final Iterable<String> unknown = record.keys.where(
        (String key) => !fieldIds.contains(key),
      );
      if (unknown.isNotEmpty) {
        throw _UsageException(
          'Seed record uses unknown field(s): ${unknown.join(', ')}',
        );
      }
      updated = _replaceDatabaseCollection(
        document,
        collection.copyWith(
          seedRecords: <Map<String, Object?>>[
            ...collection.seedRecords,
            record,
          ],
        ),
      );
      description = 'Added seed record to $collectionId';
      break;
    case 'remove-collection':
      _rejectUnknownOptions(options, <String>{'id', 'json'});
      final String id = _requiredOption(options, 'id');
      _databaseCollection(document, id);
      updated = document.copyWith(
        databaseCollections:
            document.databaseCollections
                .where((BuilderDatabaseCollection item) => item.id != id)
                .toList(),
      );
      description = 'Removed collection $id';
      break;
    case 'remove-field':
      _rejectUnknownOptions(options, <String>{'collection', 'id', 'json'});
      final String collectionId = _requiredOption(options, 'collection');
      final String id = _requiredOption(options, 'id');
      final BuilderDatabaseCollection collection = _databaseCollection(
        document,
        collectionId,
      );
      if (!collection.fields.any(
        (BuilderDatabaseField item) => item.id == id,
      )) {
        throw _UsageException('Field $collectionId.$id does not exist.');
      }
      if (collection.seedRecords.any(
        (Map<String, Object?> record) => record.containsKey(id),
      )) {
        throw _UsageException(
          'Field $collectionId.$id is used by seed records. Remove those records first.',
        );
      }
      updated = _replaceDatabaseCollection(
        document,
        collection.copyWith(
          fields:
              collection.fields
                  .where((BuilderDatabaseField item) => item.id != id)
                  .toList(),
        ),
      );
      description = 'Removed field $collectionId.$id';
      break;
    case 'remove-relationship':
      _rejectUnknownOptions(options, <String>{'id', 'json'});
      final String id = _requiredOption(options, 'id');
      if (!document.databaseRelationships.any(
        (BuilderDatabaseRelationship item) => item.id == id,
      )) {
        throw _UsageException('Relationship $id does not exist.');
      }
      updated = document.copyWith(
        databaseRelationships:
            document.databaseRelationships
                .where((BuilderDatabaseRelationship item) => item.id != id)
                .toList(),
      );
      description = 'Removed relationship $id';
      break;
    case 'remove-seed':
      _rejectUnknownOptions(options, <String>{'collection', 'index', 'json'});
      final String collectionId = _requiredOption(options, 'collection');
      final String rawIndex = _requiredOption(options, 'index');
      final int? index = int.tryParse(rawIndex);
      final BuilderDatabaseCollection collection = _databaseCollection(
        document,
        collectionId,
      );
      if (index == null ||
          index < 0 ||
          index >= collection.seedRecords.length) {
        throw _UsageException('Seed index $rawIndex is out of range.');
      }
      updated = _replaceDatabaseCollection(
        document,
        collection.copyWith(
          seedRecords: <Map<String, Object?>>[
            ...collection.seedRecords.take(index),
            ...collection.seedRecords.skip(index + 1),
          ],
        ),
      );
      description = 'Removed seed record $index from $collectionId';
      break;
    default:
      throw _UsageException('Unknown database operation: $operation');
  }

  final List<ProjectIssue> issues = await ProjectValidator().validate(
    updated,
    projectPath: file.path,
  );
  final List<ProjectIssue> errors =
      issues.where((ProjectIssue issue) => issue.isError).toList();
  if (errors.isNotEmpty) {
    if (jsonOutput) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'ok': false,
          'path': file.path,
          'issues':
              errors
                  .map(
                    (ProjectIssue issue) => <String, String>{
                      'severity': issue.severity,
                      'message': issue.message,
                    },
                  )
                  .toList(),
        }),
      );
    } else {
      for (final ProjectIssue issue in errors) {
        stderr.writeln('ERROR: ${issue.message}');
      }
    }
    exitCode = 2;
    return;
  }
  await ProjectStore().saveProjectWithDocument(updated, file.path);
  if (jsonOutput) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'ok': true,
        'path': file.path,
        'operation': operation,
      }),
    );
  } else {
    stdout.writeln('$description in ${file.path}');
  }
}

String _requiredOption(Map<String, String?> options, String key) {
  final String? value = options[key]?.trim();
  if (value == null || value.isEmpty) {
    throw _UsageException('--$key requires a non-empty value.');
  }
  return value;
}

BuilderDatabaseCollection _databaseCollection(
  BuilderDocument document,
  String id,
) {
  for (final BuilderDatabaseCollection collection
      in document.databaseCollections) {
    if (collection.id == id) return collection;
  }
  throw _UsageException('Collection $id does not exist.');
}

BuilderDocument _replaceDatabaseCollection(
  BuilderDocument document,
  BuilderDatabaseCollection replacement,
) => document.copyWith(
  databaseCollections:
      document.databaseCollections
          .map(
            (BuilderDatabaseCollection collection) =>
                collection.id == replacement.id ? replacement : collection,
          )
          .toList(),
);

Future<void> _export(List<String> args) async {
  final _ParsedFileCommand parsed = _parseFileCommand(
    args,
    extra: <String>{'output'},
  );
  final String? output = parsed.options['output'];
  if (output == null || output.trim().isEmpty) {
    throw const _UsageException(
      'export requires --output <project-directory>.',
    );
  }
  final BuilderDocument document = await _readDocument(parsed.file);
  final List<_Issue> issues = await _validateFile(parsed.file);
  final List<_Issue> errors =
      issues.where((_Issue issue) => issue.severity == 'error').toList();
  if (errors.isNotEmpty) {
    if (parsed.json) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'ok': false,
          'path': parsed.file.path,
          'issues': errors.map((_Issue issue) => issue.toJson()).toList(),
        }),
      );
    } else {
      for (final _Issue issue in errors) {
        stderr.writeln('ERROR: ${issue.message}');
      }
    }
    exitCode = 2;
    return;
  }

  final List<String> flutterOutput = <String>[];
  final String result = await FlutterProjectExporter(
    generator: DartGenerator(),
  ).export(
    document,
    output,
    projectPath: parsed.file.path,
    onOutput: (String line) {
      flutterOutput.add(line);
      if (!parsed.json) stdout.writeln(line);
    },
  );
  if (parsed.json) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'ok': true,
        'path': result,
        'flutterOutput': flutterOutput,
        'warnings':
            issues
                .where((_Issue issue) => issue.severity == 'warning')
                .map((_Issue issue) => issue.message)
                .toList(),
      }),
    );
  } else {
    stdout.writeln('Exported Flutter project to $result');
  }
}

_ParsedFileCommand _parseFileCommand(
  List<String> args, {
  Set<String> extra = const <String>{},
}) {
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
    if (<String>{'json', 'required', 'primary-key', 'unique'}.contains(key)) {
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
  final Iterable<String> unknown = options.keys.where(
    (String key) => !allowed.contains(key),
  );
  if (unknown.isNotEmpty) {
    throw _UsageException(
      'Unknown option(s): ${unknown.map((String key) => '--$key').join(', ')}',
    );
  }
}

String _nameFromPath(String path) {
  String name =
      path
          .split(RegExp(r'[/\\]'))
          .last
          .replaceFirst(
            RegExp(r'\.appbuilder\.json$', caseSensitive: false),
            '',
          )
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
  database <file> list [--json]         Show collections, fields, seed counts, and relationships.
  database <file> add-collection --id <id> --name <name> [--json]
  database <file> add-field --collection <id> --id <id> --name <name>
                  [--type string|integer|number|boolean|date|json]
                  [--required] [--primary-key] [--unique] [--json]
  database <file> add-relationship --id <id> --name <name>
                  --from-collection <id> --from-field <id>
                  --to-collection <id> --to-field <id> [--json]
  database <file> add-seed --collection <id>
                  (--record <json-object> | --record-file <json-file>) [--json]
  database <file> remove-collection --id <id> [--json]
  database <file> remove-field --collection <id> --id <id> [--json]
  database <file> remove-relationship --id <id> [--json]
  database <file> remove-seed --collection <id> --index <zero-based-index> [--json]
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
