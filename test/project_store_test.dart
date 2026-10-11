import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_flutter_builder/models/builder_document.dart';
import 'package:local_flutter_builder/services/project_store.dart';

void main() {
  late Directory temporaryDirectory;
  late ProjectStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'local_builder_test_',
    );
    store = ProjectStore();
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'saves and reopens a project, preserving a backup when overwritten',
    () async {
      final String path =
          '${temporaryDirectory.path}${Platform.pathSeparator}sample.appbuilder.json';
      final BuilderDocument original = BuilderDocument.sample();
      await store.saveProject(original, path);

      final StoredProject opened = await store.openProject(path);
      expect(opened.document.toJson(), original.toJson());
      expect(opened.path, File(path).absolute.path);

      final BuilderDocument updated = original.copyWith(name: 'Updated App');
      await store.saveProject(updated, path);
      expect((await store.openProject(path)).document.name, 'Updated App');

      final Map<String, Object?> backup = Map<String, Object?>.from(
        jsonDecode(await File('$path.bak').readAsString()) as Map,
      );
      expect(BuilderDocument.fromJson(backup).name, original.name);
    },
  );

  test('rejects missing project files', () async {
    final String missingPath =
        '${temporaryDirectory.path}${Platform.pathSeparator}missing.json';

    await expectLater(
      store.openProject(missingPath),
      throwsA(isA<FileSystemException>()),
    );
  });
}
