import 'package:flutter_test/flutter_test.dart';
import 'package:local_flutter_builder/editor/editor_controller.dart';
import 'package:local_flutter_builder/models/builder_document.dart';

void main() {
  late EditorController editor;

  setUp(() {
    editor = EditorController();
  });

  tearDown(() {
    editor.dispose();
  });

  test('property edits can be undone and redone', () {
    editor.setText('text_1', 'Changed locally');

    expect(
      editor.document.root.findById('text_1')?.properties['text'],
      'Changed locally',
    );
    expect(editor.isDirty, isTrue);
    expect(editor.canUndo, isTrue);
    expect(editor.canRedo, isFalse);

    editor.undo();
    expect(
      editor.document.root.findById('text_1')?.properties['text'],
      'Hello from your local builder',
    );
    expect(editor.canRedo, isTrue);

    editor.redo();
    expect(
      editor.document.root.findById('text_1')?.properties['text'],
      'Changed locally',
    );
  });

  test('adding text selects the node and participates in history', () {
    editor.addText();
    final String addedId = editor.selectedNodeId;

    expect(editor.selectedNode?.type, 'text');
    expect(editor.selectedNode?.properties['text'], 'New text');
    expect(editor.canUndo, isTrue);

    editor.undo();
    expect(editor.document.root.findById(addedId), isNull);

    editor.redo();
    expect(
      editor.document.root.findById(addedId)?.properties['text'],
      'New text',
    );
  });

  test('adds supported objects and nests new children in selected layouts', () {
    editor.addObject('button');
    expect(editor.selectedNode?.type, 'button');
    expect(editor.selectedNode?.properties['label'], 'Button');

    editor.addObject('container');
    final String containerId = editor.selectedNodeId;
    expect(editor.selectedNode?.type, 'container');

    editor.setProperty(containerId, 'width', 280.0);
    editor.addObject('text');
    final String childId = editor.selectedNodeId;
    expect(
      editor.document.root.findById(containerId)?.children.single.id,
      childId,
    );

    editor.deleteSelected();
    expect(editor.document.root.findById(childId), isNull);
    expect(editor.selectedNodeId, containerId);
    expect(
      editor.document.root.findById(containerId)?.properties['width'],
      280.0,
    );
  });

  test('moves objects between siblings and into containers', () {
    editor.addObject('container');
    final String containerId = editor.selectedNodeId;

    editor.moveObject(containerId, 'text_1', BuilderDropPosition.before);
    final BuilderNode column = editor.document.root.findById('column_1')!;
    expect(column.children.first.id, containerId);

    editor.moveObject('text_1', containerId, BuilderDropPosition.inside);
    expect(
      editor.document.root.findById(containerId)?.children.single.id,
      'text_1',
    );

    final Map<String, Object?> treeBeforeInvalidMove =
        editor.document.root.toJson();
    editor.moveObject(containerId, 'text_1', BuilderDropPosition.inside);
    expect(editor.document.root.toJson(), treeBeforeInvalidMove);
  });

  test('creates pages, edits unique routes, and switches independently', () {
    editor.addPage();
    final String pageId = editor.activePageId;
    expect(pageId, isNot('home'));
    expect(editor.activeRoot.type, 'scaffold');

    editor.addObject('text');
    editor.setProperty(editor.selectedNodeId, 'text', 'Settings page');
    expect(
      editor.activeRoot.findById(editor.selectedNodeId)?.properties['text'],
      'Settings page',
    );

    final String? duplicateRoute = editor.updatePageDetails(
      pageId: pageId,
      name: 'Settings',
      route: '/',
    );
    expect(duplicateRoute, contains('already uses'));
    expect(
      editor.updatePageDetails(
        pageId: pageId,
        name: 'Settings',
        route: 'settings',
      ),
      isNull,
    );

    editor.navigateToRoute('/settings');
    expect(editor.activePageId, pageId);
    editor.selectPage('home');
    expect(
      editor.activeRoot.findById('text_1')?.properties['text'],
      'Hello from your local builder',
    );
    editor.addObject('button');
    final String buttonId = editor.selectedNodeId;
    editor.setProperty(buttonId, 'route', '/settings');
    editor.setProperty(buttonId, 'actions', <Map<String, Object?>>[
      <String, Object?>{
        'id': 'settings_navigation',
        'type': 'navigate',
        'route': '/settings',
        'behavior': 'push',
      },
    ]);
    expect(
      editor.updatePageDetails(
        pageId: pageId,
        name: 'Profile',
        route: '/profile',
      ),
      isNull,
    );
    expect(
      editor.document.root.findById(buttonId)?.properties['route'],
      '/profile',
    );
    final List<Map<String, Object?>> actions =
        editor.document.root.findById(buttonId)!.properties['actions']!
            as List<Map<String, Object?>>;
    expect(actions.single['route'], '/profile');
    editor.navigateToRoute('/profile');
    expect(editor.activePageId, pageId);
    editor.setInitialPage(pageId);
    expect(editor.document.initialPageId, pageId);

    editor.deletePage(pageId);
    expect(editor.activePageId, 'home');
    expect(editor.document.pageById(pageId), isNull);
    expect(editor.document.initialPageId, 'home');
    expect(editor.document.root.findById(buttonId)?.properties['route'], '');
    expect(
      (editor.document.root.findById(buttonId)!.properties['actions']!
              as List<Map<String, Object?>>)
          .single['route'],
      '',
    );
  });

  test('adds collection, media, form, and page widgets with child nesting', () {
    editor.addObject('listView');
    final String listId = editor.selectedNodeId;
    expect(editor.selectedNode?.acceptsChildren, isTrue);
    editor.addObject('text');
    expect(editor.document.root.findById(listId)?.children.single.type, 'text');

    for (final String type in <String>[
      'gridView',
      'pageView',
      'swipeableStack',
      'image',
      'signature',
      'divider',
      'verticalDivider',
      'textField',
      'checkbox',
      'switch',
      'icon',
      'appBar',
      'floatingActionButton',
    ]) {
      editor.addObject(type);
      expect(editor.selectedNode?.type, type);
      expect(editor.document.root.findById(editor.selectedNodeId), isNotNull);
    }
    final BuilderNode appBar = editor.document.root.depthFirst().firstWhere(
      (BuilderNode node) => node.type == 'appBar',
    );
    expect(editor.document.root.parentOfId(appBar.id)?.type, 'scaffold');
  });

  test('manages typed app state and runtime widget overrides', () {
    final String scoreId = editor.addVariable(
      name: 'Score',
      type: 'number',
      initialValue: 2,
    );
    final String isOpenId = editor.addVariable(
      name: 'Open',
      type: 'boolean',
      initialValue: false,
    );
    expect(editor.appVariableValues[scoreId], 2.0);

    editor.incrementVariable(scoreId, amount: 2.5);
    editor.toggleVariable(isOpenId);
    editor.setWidgetRuntimeProperty('home', 'text_1', 'text', 'Updated');

    expect(editor.appVariableValues[scoreId], 4.5);
    expect(editor.appVariableValues[isOpenId], isTrue);
    expect(editor.widgetOverrides['home::text_1']?['text'], 'Updated');
    expect(editor.isDirty, isTrue);

    editor.setProperty('text_1', 'bindings', <String, Object?>{
      'text': scoreId,
    });
    editor.deleteVariable(scoreId);
    expect(editor.document.variables.map((BuilderVariable item) => item.id), [
      isOpenId,
    ]);
    expect(
      editor.document.root.findById('text_1')?.properties['bindings'],
      isNull,
    );
    expect(editor.appVariableValues.containsKey(scoreId), isFalse);
  });

  test('supports integer, double, string-list, and JSON app variables', () {
    final String countId = editor.addVariable(
      name: 'Count',
      type: 'integer',
      initialValue: 2.9,
    );
    final String ratioId = editor.addVariable(
      name: 'Ratio',
      type: 'double',
      initialValue: 1,
    );
    final String tagsId = editor.addVariable(
      name: 'Tags',
      type: 'stringList',
      initialValue: <String>['one'],
    );
    final String settingsId = editor.addVariable(
      name: 'Settings',
      type: 'json',
      initialValue: <String, Object?>{'enabled': false},
    );

    expect(editor.appVariableValues[countId], 3);
    expect(editor.appVariableValues[ratioId], 1.0);
    editor.incrementVariable(countId, amount: 2);
    editor.setVariableValue(tagsId, '["one", "two"]');
    editor.setVariableValue(settingsId, '{"enabled": true}');

    expect(editor.appVariableValues[countId], 5);
    expect(editor.appVariableValues[tagsId], <String>['one', 'two']);
    expect(editor.appVariableValues[settingsId], <String, Object?>{
      'enabled': true,
    });
  });
}
