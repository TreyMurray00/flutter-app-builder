import 'dart:convert';
import 'dart:io';

import '../models/builder_document.dart';

class StoredProject {
  const StoredProject({
    required this.document,
    required this.path,
    this.recoveredFromBackup = false,
    this.recoveredFromAutosave = false,
  });

  final BuilderDocument document;
  final String path;
  final bool recoveredFromBackup;
  final bool recoveredFromAutosave;
}

class ProjectStore {
  Future<StoredProject> openProject(String path) async {
    final String absolutePath = File(path).absolute.path;
    final File projectFile = File(absolutePath);
    final File autosave = File('$absolutePath.autosave');
    bool autosaveIsNewer = false;
    try {
      autosaveIsNewer =
          await autosave.exists() &&
          (!await projectFile.exists() ||
              (await autosave.lastModified()).isAfter(
                await projectFile.lastModified(),
              ));
    } catch (_) {
      // A missing or inaccessible recovery file should not block the project.
    }
    if (autosaveIsNewer) {
      try {
        return StoredProject(
          document: await _readDocument(autosave),
          path: absolutePath,
          recoveredFromAutosave: true,
        );
      } catch (_) {
        // Continue with the project and its normal backup when recovery data
        // is incomplete or unreadable.
      }
    }
    try {
      return StoredProject(
        document: await _readDocument(projectFile),
        path: absolutePath,
      );
    } catch (primaryError) {
      final File backup = File('$absolutePath.bak');
      if (!await backup.exists()) rethrow;
      try {
        return StoredProject(
          document: await _readDocument(backup),
          path: absolutePath,
          recoveredFromBackup: true,
        );
      } catch (backupError) {
        throw FormatException(
          'The project and its recovery backup could not be opened. '
          'Project error: $primaryError Backup error: $backupError',
        );
      }
    }
  }

  Future<BuilderDocument> _readDocument(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('Project file does not exist.', file.path);
    }
    final String contents = await file.readAsString();
    final Object? decoded = jsonDecode(contents);
    if (decoded is! Map) {
      throw const FormatException(
        'The selected file is not a builder project.',
      );
    }
    return BuilderDocument.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<String> saveProject(BuilderDocument document, String path) async {
    return (await saveProjectWithDocument(document, path)).path;
  }

  Future<StoredProject> saveProjectWithDocument(
    BuilderDocument document,
    String path,
  ) async {
    final File target = File(path).absolute;
    final File temp = File('${target.path}.tmp');
    final File backup = File('${target.path}.bak');
    await target.parent.create(recursive: true);
    final BuilderDocument portableDocument = await _copyProjectAssets(
      document,
      target,
    );
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(portableDocument.toJson()),
      flush: true,
    );

    bool movedOriginal = false;
    try {
      if (await target.exists()) {
        if (await backup.exists()) await backup.delete();
        await target.rename(backup.path);
        movedOriginal = true;
      }
      await temp.rename(target.path);
    } catch (_) {
      if (movedOriginal && await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
    return StoredProject(document: portableDocument, path: target.path);
  }

  Future<void> clearAutosave(String projectPath) async {
    final File autosave = File('${File(projectPath).absolute.path}.autosave');
    if (await autosave.exists()) await autosave.delete();
  }

  Future<BuilderDocument> _copyProjectAssets(
    BuilderDocument document,
    File projectFile,
  ) async {
    final String projectStem = _safeAssetName(
      _fileName(projectFile.path)
          .replaceFirst(
            RegExp(r'\.appbuilder\.json$', caseSensitive: false),
            '',
          )
          .replaceFirst(RegExp(r'\.json$', caseSensitive: false), ''),
    );
    final String assetDirectoryName = '${projectStem}_assets';

    Future<BuilderNode> copyNode(BuilderNode node, String namespace) async {
      final Map<String, Object?> properties = <String, Object?>{
        ...node.properties,
      };
      if (node.type == 'image' && properties['source'] is String) {
        final String source = (properties['source']! as String).trim();
        if (source.isNotEmpty) {
          final String resolvedSource = resolveProjectAssetPath(
            projectFile.path,
            source,
          );
          final File sourceFile = File(resolvedSource);
          if (!await sourceFile.exists()) {
            throw FileSystemException(
              'An image in the design could not be found. Re-select it before saving.',
              source,
            );
          }
          final String fileName = _safeAssetName(_fileName(source));
          final String relativePath =
              '$assetDirectoryName/images/${_safeAssetName(namespace)}_${_safeAssetName(node.id)}_$fileName';
          final File destination =
              File(
                '${projectFile.parent.path}${Platform.pathSeparator}'
                '${relativePath.replaceAll('/', Platform.pathSeparator)}',
              ).absolute;
          final String sourcePath = _normalizedPath(sourceFile.absolute.path);
          final String destinationPath = _normalizedPath(destination.path);
          if (sourcePath != destinationPath) {
            await destination.parent.create(recursive: true);
            await sourceFile.copy(destination.path);
          }
          properties['source'] = relativePath;
        }
      }
      final List<BuilderNode> children = await Future.wait(
        node.children.map((BuilderNode child) => copyNode(child, namespace)),
      );
      return node.copyWith(properties: properties, children: children);
    }

    final BuilderNode root = await copyNode(document.root, 'home');
    final List<BuilderPage> pages = await Future.wait(
      document.pages.map(
        (BuilderPage page) async =>
            page.copyWith(root: await copyNode(page.root, page.id)),
      ),
    );
    final List<BuilderComponentGroup> componentGroups = await Future.wait(
      document.componentGroups.map(
        (BuilderComponentGroup group) async =>
            group.copyWith(root: await copyNode(group.root, group.id)),
      ),
    );
    final List<BuilderFontAsset> fontAssets = await Future.wait(
      document.fontAssets.map((BuilderFontAsset font) async {
        final File source = File(
          resolveProjectAssetPath(projectFile.path, font.source),
        );
        if (!await source.exists()) {
          throw FileSystemException(
            'A bundled font could not be found. Import it again before saving.',
            font.source,
          );
        }
        final String relativePath =
            '$assetDirectoryName/fonts/${_safeAssetName(font.family)}_${_safeAssetName(_fileName(font.source))}';
        final File destination =
            File(
              '${projectFile.parent.path}${Platform.pathSeparator}'
              '${relativePath.replaceAll('/', Platform.pathSeparator)}',
            ).absolute;
        if (_normalizedPath(source.absolute.path) !=
            _normalizedPath(destination.path)) {
          await destination.parent.create(recursive: true);
          await source.copy(destination.path);
        }
        return BuilderFontAsset(
          id: font.id,
          family: font.family,
          source: relativePath,
          weight: font.weight,
        );
      }),
    );
    return document.copyWith(
      root: root,
      pages: pages,
      componentGroups: componentGroups,
      fontAssets: fontAssets,
    );
  }

  String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

  String _safeAssetName(String value) {
    final String safe = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '.');
    if (safe.isEmpty || safe == '.') return 'asset';
    return safe.length > 80 ? safe.substring(0, 80) : safe;
  }

  String _normalizedPath(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;

  Future<String> saveDartOutput(String code, String path) async {
    final File file = File(path).absolute;
    await file.parent.create(recursive: true);
    await file.writeAsString(code, flush: true);
    return file.path;
  }
}

String resolveProjectAssetPath(String? projectPath, String source) {
  final bool isAbsolutePath =
      Platform.isWindows
          ? RegExp(r'^(?:[A-Za-z]:[\\/]|[\\/]{1,2})').hasMatch(source)
          : source.startsWith('/');
  final File file = File(source);
  if (isAbsolutePath) return file.absolute.path;
  if (projectPath == null) return file.absolute.path;
  final String projectDirectory = File(projectPath).parent.path;
  return File(
    '$projectDirectory${Platform.pathSeparator}'
    '${source.replaceAll('/', Platform.pathSeparator)}',
  ).absolute.path;
}
