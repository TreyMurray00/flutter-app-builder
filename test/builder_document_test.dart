import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_flutter_builder/models/builder_action.dart';
import 'package:local_flutter_builder/models/builder_document.dart';

void main() {
  group('BuilderDocument', () {
    test('round-trips the sample document through JSON', () {
      final BuilderDocument original = BuilderDocument.sample();
      final BuilderDocument restored = BuilderDocument.fromJson(
        original.toJson(),
      );

      expect(restored.name, original.name);
      expect(restored.seedColor, original.seedColor);
      expect(
        restored.root.depthFirst().map((BuilderNode node) => node.id),
        <String>['scaffold_1', 'column_1', 'text_1'],
      );
      expect(restored.root.toJson(), original.root.toJson());
    });

    test('rejects a project schema it does not support', () {
      final Map<String, Object?> unsupported = <String, Object?>{
        ...BuilderDocument.sample().toJson(),
        'schemaVersion': currentSchemaVersion + 1,
      };

      expect(
        () => BuilderDocument.fromJson(unsupported),
        throwsA(isA<FormatException>()),
      );
    });

    test('round-trips pages and upgrades legacy one-page projects', () {
      final BuilderDocument sample = BuilderDocument.sample();
      final BuilderPage settings = BuilderPage(
        id: 'settings',
        name: 'Settings',
        route: '/settings',
        root: BuilderNode(
          id: 'settings_scaffold',
          type: 'scaffold',
          properties: const <String, Object?>{},
          children: const <BuilderNode>[],
        ),
      );
      final BuilderDocument multiPage = sample.copyWith(
        pages: <BuilderPage>[settings],
        initialPageId: settings.id,
      );
      final BuilderDocument restored = BuilderDocument.fromJson(
        multiPage.toJson(),
      );

      expect(restored.allPages.map((BuilderPage page) => page.route), <String>[
        '/',
        '/settings',
      ]);
      expect(restored.initialPageId, 'settings');
      expect(restored.pageById('settings')?.root.id, 'settings_scaffold');

      final Map<String, Object?> legacy =
          sample.toJson()
            ..['schemaVersion'] = 1
            ..remove('pages')
            ..remove('initialPageId');
      final BuilderDocument upgraded = BuilderDocument.fromJson(legacy);
      expect(upgraded.schemaVersion, currentSchemaVersion);
      expect(upgraded.allPages.single.route, '/');
    });

    test('round-trips typed app variables', () {
      final BuilderDocument original = BuilderDocument.sample().copyWith(
        variables: const <BuilderVariable>[
          BuilderVariable(
            id: 'user_name',
            name: 'User name',
            type: 'string',
            initialValue: 'Ada',
          ),
          BuilderVariable(
            id: 'score',
            name: 'Score',
            type: 'number',
            initialValue: 7.5,
          ),
          BuilderVariable(
            id: 'enabled',
            name: 'Enabled',
            type: 'boolean',
            initialValue: true,
          ),
          BuilderVariable(
            id: 'attempts',
            name: 'Attempts',
            type: 'integer',
            initialValue: 3,
          ),
          BuilderVariable(
            id: 'tags',
            name: 'Tags',
            type: 'stringList',
            initialValue: <String>['local', 'offline'],
          ),
          BuilderVariable(
            id: 'settings',
            name: 'Settings',
            type: 'json',
            initialValue: <String, Object?>{'theme': 'dark'},
          ),
        ],
      );
      final BuilderDocument restored = BuilderDocument.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );

      expect(restored.variables.map((BuilderVariable item) => item.type), [
        'string',
        'number',
        'boolean',
        'integer',
        'stringList',
        'json',
      ]);
      expect(
        restored.variables.map((BuilderVariable item) => item.initialValue),
        <Object>[
          'Ada',
          7.5,
          true,
          3,
          <String>['local', 'offline'],
          <String, Object?>{'theme': 'dark'},
        ],
      );
    });

    test('persists ordered widget actions in the local project JSON', () {
      final BuilderDocument sample = BuilderDocument.sample();
      final BuilderNode button = BuilderNode(
        id: 'action_button',
        type: 'button',
        properties: const <String, Object?>{
          'label': 'Save',
          'actions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'toast',
              'type': 'snackbar',
              'message': 'Saved offline',
            },
            <String, Object?>{
              'id': 'open',
              'type': 'navigate',
              'route': '/settings',
              'behavior': 'push',
            },
          ],
        },
        children: const <BuilderNode>[],
      );
      final BuilderDocument withActions = sample.copyWith(
        root: sample.root.updateById(
          'column_1',
          (BuilderNode column) => column.copyWith(
            children: <BuilderNode>[...column.children, button],
          ),
        ),
      );
      final Map<String, Object?> json = Map<String, Object?>.from(
        jsonDecode(jsonEncode(withActions.toJson())) as Map<String, dynamic>,
      );
      final BuilderDocument restored = BuilderDocument.fromJson(json);
      final BuilderNode restoredButton =
          restored.root.findById('action_button')!;

      expect(
        BuilderAction.forNode(
          restoredButton,
        ).map((Map<String, Object?> action) => action['type']),
        <String>['snackbar', 'navigate'],
      );
      expect(
        BuilderAction.forNode(restoredButton).first['message'],
        'Saved offline',
      );
    });
  });
}
