import 'dart:convert';
import 'dart:io';

import '../models/builder_document.dart';
import 'dart_generator.dart';

/// Builds a complete Flutter project using the locally installed Flutter SDK.
/// Flutter's own templates provide the native platform runners; generated
/// source and any image assets are then written into that scaffold.
class FlutterProjectExporter {
  FlutterProjectExporter({required DartGenerator generator})
    : _generator = generator;

  final DartGenerator _generator;

  Future<String> export(BuilderDocument document, String destination) async {
    final Directory target = Directory(destination).absolute;
    if (await target.exists()) {
      throw FileSystemException(
        'The export folder already exists. Choose a different parent folder or move it first.',
        target.path,
      );
    }

    final _PreparedAssets preparedAssets = await _prepareAssets(document);
    await target.parent.create(recursive: true);
    final Directory staging = Directory(
      '${target.path}.local_builder_${pid}_${DateTime.now().microsecondsSinceEpoch}',
    );
    final String projectName = DartGenerator.packageNameFor(document.name);

    try {
      final String flutter = _findFlutterExecutable();
      final ProcessResult result = await Process.run(
        flutter,
        <String>[
          'create',
          '--no-pub',
          '--project-name=$projectName',
          '--platforms=android,ios,web,windows,macos,linux',
          staging.path,
        ],
        workingDirectory: target.parent.path,
        runInShell: Platform.isWindows,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        final String output = '${result.stdout}\n${result.stderr}'.trim();
        throw StateError(
          'Flutter could not create the platform scaffold '
          '(exit code ${result.exitCode}).${output.isEmpty ? '' : '\n$output'}',
        );
      }

      final Map<String, String> generatedFiles = _generator
          .generateProjectFiles(
            document,
            projectName: projectName,
            imageAssets: preparedAssets.widgetAssets,
          );
      for (final MapEntry<String, String> entry in generatedFiles.entries) {
        final File output = _fileInside(staging, entry.key);
        await output.parent.create(recursive: true);
        await output.writeAsString(entry.value, flush: true);
      }
      for (final MapEntry<String, String> entry
          in preparedAssets.assetSources.entries) {
        final File output = _fileInside(staging, entry.key);
        await output.parent.create(recursive: true);
        await File(entry.value).copy(output.path);
      }

      // Do not replace a destination that another process created while the
      // scaffold was being generated.
      if (await target.exists()) {
        throw FileSystemException(
          'The export folder was created while exporting. Choose a different parent folder.',
          target.path,
        );
      }
      await staging.rename(target.path);
      return target.path;
    } on ProcessException catch (error) {
      throw StateError(
        'Could not start the Flutter CLI. Add Flutter’s bin folder to PATH '
        'and restart Local Flutter Builder. ${error.message}',
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  String _findFlutterExecutable() {
    final Map<String, String> environment = Platform.environment;
    final String? flutterRoot =
        environment.entries
            .where(
              (MapEntry<String, String> entry) =>
                  entry.key.toLowerCase() == 'flutter_root',
            )
            .map((MapEntry<String, String> entry) => entry.value)
            .firstOrNull;
    final String? userProfile =
        environment.entries
            .where(
              (MapEntry<String, String> entry) =>
                  entry.key.toLowerCase() == 'userprofile',
            )
            .map((MapEntry<String, String> entry) => entry.value)
            .firstOrNull;
    final List<String> searchDirectories = <String>[
      if (flutterRoot != null && flutterRoot.isNotEmpty)
        '${flutterRoot}${Platform.pathSeparator}bin',
      if (Platform.isWindows && userProfile != null && userProfile.isNotEmpty)
        '$userProfile${Platform.pathSeparator}flutter${Platform.pathSeparator}bin',
      ...environment.entries
          .where(
            (MapEntry<String, String> entry) =>
                entry.key.toLowerCase() == 'path',
          )
          .expand(
            (MapEntry<String, String> entry) =>
                entry.value.split(Platform.isWindows ? ';' : ':'),
          ),
    ];
    final String executableName =
        Platform.isWindows ? 'flutter.bat' : 'flutter';
    for (final String directory in searchDirectories) {
      final String candidate =
          '${directory.replaceAll('"', '')}${Platform.pathSeparator}$executableName';
      if (File(candidate).existsSync()) return candidate;
    }
    throw StateError(
      'Flutter was not found on PATH. Add Flutter’s bin folder to PATH '
      'and restart Local Flutter Builder.',
    );
  }

  Future<_PreparedAssets> _prepareAssets(BuilderDocument document) async {
    final Map<String, String> widgetAssets = <String, String>{};
    final Map<String, String> assetSources = <String, String>{};
    int index = 0;
    for (final BuilderPage page in document.allPages) {
      for (final BuilderNode node in page.root.depthFirst()) {
        if (node.type != 'image') continue;
        final Object? rawSource = node.properties['source'];
        final String source = rawSource is String ? rawSource.trim() : '';
        if (source.isEmpty) continue;
        final File sourceFile = File(source);
        if (!await sourceFile.exists()) {
          throw FileSystemException(
            'An image in the design could not be found. Re-select it before exporting.',
            source,
          );
        }
        index++;
        final String originalName = source.split(RegExp(r'[/\\]')).last;
        final String safeName = _safeAssetName(originalName);
        final String asset =
            'assets/images/${index}_${_safeAssetName(node.id)}_$safeName';
        widgetAssets['${page.id}::${node.id}'] = asset;
        assetSources[asset] = sourceFile.absolute.path;
      }
    }
    return _PreparedAssets(widgetAssets, assetSources);
  }

  String _safeAssetName(String value) {
    final String safe = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '.');
    if (safe.isEmpty || safe == '.') return 'image';
    return safe.length > 80 ? safe.substring(0, 80) : safe;
  }

  File _fileInside(Directory root, String relativePath) {
    final String normalized = relativePath.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    final String rootPath = root.absolute.path;
    final File file =
        File('$rootPath${Platform.pathSeparator}$normalized').absolute;
    final String prefix = '$rootPath${Platform.pathSeparator}';
    if (!file.path.startsWith(prefix)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Invalid output path',
      );
    }
    return file;
  }
}

class _PreparedAssets {
  const _PreparedAssets(this.widgetAssets, this.assetSources);

  final Map<String, String> widgetAssets;
  final Map<String, String> assetSources;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
