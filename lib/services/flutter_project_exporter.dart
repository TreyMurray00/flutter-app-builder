import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../models/builder_document.dart';
import 'dart_generator.dart';
import 'flutter_toolchain_service.dart';
import 'project_store.dart';

/// Builds a complete Flutter project using the locally installed Flutter SDK.
/// Flutter's own templates provide the native platform runners; generated
/// source and any image assets are then written into that scaffold.
class FlutterProjectExporter {
  FlutterProjectExporter({required DartGenerator generator})
    : _generator = generator;

  final DartGenerator _generator;

  Future<String> export(
    BuilderDocument document,
    String destination, {
    String? projectPath,
    void Function(String line)? onOutput,
  }) async {
    final Directory target = Directory(destination).absolute;
    if (await target.exists()) {
      throw FileSystemException(
        'The export folder already exists. Choose a different parent folder or move it first.',
        target.path,
      );
    }

    final _PreparedAssets preparedAssets = await _prepareAssets(
      document,
      projectPath,
    );
    await target.parent.create(recursive: true);
    final Directory staging = Directory(
      '${target.path}.local_builder_${pid}_${DateTime.now().microsecondsSinceEpoch}',
    );
    final String projectName = DartGenerator.packageNameFor(document.name);

    try {
      final String flutter = FlutterToolchainService.findFlutterExecutable();
      final Process process = await Process.start(
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
      );
      final Queue<String> output = Queue<String>();
      void captureLine(String line) {
        final String cleanLine = line.trimRight();
        if (cleanLine.isEmpty) return;
        if (output.length == 250) output.removeFirst();
        output.addLast(cleanLine);
        onOutput?.call(cleanLine);
      }

      final Future<void> stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(captureLine);
      final Future<void> stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(captureLine);
      final int exitCode = await process.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      if (exitCode != 0) {
        final String log = output.join('\n').trim();
        throw StateError(
          'Flutter could not create the platform scaffold '
          '(exit code $exitCode).${log.isEmpty ? '' : '\n$log'}',
        );
      }

      final Map<String, String> generatedFiles = _generator
          .generateProjectFiles(
            document,
            projectName: projectName,
            imageAssets: preparedAssets.widgetAssets,
            fontAssets: preparedAssets.fontAssets,
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

  Future<_PreparedAssets> _prepareAssets(
    BuilderDocument document,
    String? projectPath,
  ) async {
    final Map<String, String> widgetAssets = <String, String>{};
    final Map<String, String> assetSources = <String, String>{};
    final List<BuilderFontAsset> fontAssets = <BuilderFontAsset>[];
    int index = 0;
    for (final BuilderPage page in document.allPages) {
      for (final BuilderNode node in page.root.depthFirst()) {
        if (node.type != 'image') continue;
        final Object? rawSource = node.properties['source'];
        final String source = rawSource is String ? rawSource.trim() : '';
        if (source.isEmpty) continue;
        final File sourceFile = File(
          resolveProjectAssetPath(projectPath, source),
        );
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
    for (int index = 0; index < document.fontAssets.length; index++) {
      final BuilderFontAsset font = document.fontAssets[index];
      final File sourceFile = File(
        resolveProjectAssetPath(projectPath, font.source),
      );
      if (!await sourceFile.exists()) {
        throw FileSystemException(
          'A bundled font could not be found. Import it again before exporting.',
          font.source,
        );
      }
      final String fileName = font.source.split(RegExp(r'[/\\]')).last;
      final String asset =
          'assets/fonts/${index + 1}_${_safeAssetName(font.family)}_${_safeAssetName(fileName)}';
      assetSources[asset] = sourceFile.absolute.path;
      fontAssets.add(
        BuilderFontAsset(
          id: font.id,
          family: font.family,
          source: asset,
          weight: font.weight,
        ),
      );
    }
    return _PreparedAssets(widgetAssets, assetSources, fontAssets);
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
  const _PreparedAssets(this.widgetAssets, this.assetSources, this.fontAssets);

  final Map<String, String> widgetAssets;
  final Map<String, String> assetSources;
  final List<BuilderFontAsset> fontAssets;
}
