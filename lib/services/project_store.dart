import 'dart:convert';
import 'dart:io';

import '../models/builder_document.dart';

class StoredProject {
  const StoredProject({required this.document, required this.path});

  final BuilderDocument document;
  final String path;
}

class ProjectStore {
  Future<StoredProject> openProject(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Project file does not exist.', path);
    }
    final String contents = await file.readAsString();
    final Object? decoded = jsonDecode(contents);
    if (decoded is! Map) {
      throw const FormatException(
        'The selected file is not a builder project.',
      );
    }
    final BuilderDocument document = BuilderDocument.fromJson(
      Map<String, Object?>.from(decoded),
    );
    return StoredProject(document: document, path: file.absolute.path);
  }

  Future<String> saveProject(BuilderDocument document, String path) async {
    final File target = File(path).absolute;
    final File temp = File('${target.path}.tmp');
    final File backup = File('${target.path}.bak');
    await target.parent.create(recursive: true);
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document.toJson()),
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
    return target.path;
  }

  Future<String> saveDartOutput(String code, String path) async {
    final File file = File(path).absolute;
    await file.parent.create(recursive: true);
    await file.writeAsString(code, flush: true);
    return file.path;
  }
}
