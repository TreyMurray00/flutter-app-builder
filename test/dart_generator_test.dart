import 'package:flutter_test/flutter_test.dart';
import 'package:local_flutter_builder/models/builder_document.dart';
import 'package:local_flutter_builder/services/dart_generator.dart';

void main() {
  test('generates the source and manifest files for a Flutter app', () {
    final Map<String, String> files = DartGenerator().generateProjectFiles(
      BuilderDocument.sample(),
      projectName: '42 My Demo App',
    );

    expect(
      files.keys,
      containsAll(<String>[
        'pubspec.yaml',
        'lib/main.dart',
        'README.md',
        'analysis_options.yaml',
        'test/widget_test.dart',
      ]),
    );
    expect(files['pubspec.yaml'], contains('name: app_42_my_demo_app'));
    expect(
      files['test/widget_test.dart'],
      contains('package:app_42_my_demo_app/main.dart'),
    );
    expect(files['lib/main.dart'], contains('class GeneratedApp'));
  });

  test('bundles referenced images as Flutter assets', () {
    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderNode image = BuilderNode(
      id: 'image_1',
      type: 'image',
      properties: const <String, Object?>{'source': r'C:\assets\photo.png'},
      children: const <BuilderNode>[],
    );
    final BuilderDocument document = sample.copyWith(
      root: sample.root.updateById(
        'column_1',
        (BuilderNode column) =>
            column.copyWith(children: <BuilderNode>[...column.children, image]),
      ),
    );
    final Map<String, String> files = DartGenerator().generateProjectFiles(
      document,
      projectName: 'demo',
      imageAssets: <String, String>{
        'home::image_1': 'assets/images/1_image_1_photo.png',
      },
    );

    expect(
      files['lib/main.dart'],
      contains('Image.asset("assets/images/1_image_1_photo.png"'),
    );
    expect(files['lib/main.dart'], isNot(contains("import 'dart:io';")));
    expect(
      files['pubspec.yaml'],
      contains("- 'assets/images/1_image_1_photo.png'"),
    );
  });

  test('generates a standalone Flutter application from the design', () {
    final String source = DartGenerator().generate(BuilderDocument.sample());

    expect(source, contains("import 'package:flutter/material.dart';"));
    expect(source, contains('class GeneratedApp extends StatefulWidget'));
    expect(source, contains("title: \"My First App\""));
    expect(source, contains('Color(0xff6750a4)'));
    expect(source, contains('Hello from your local builder'));
    expect(source, contains('FontWeight.bold'));
  });

  test('generates named routes and button navigation for project pages', () {
    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderNode button = BuilderNode(
      id: 'button_settings',
      type: 'button',
      properties: const <String, Object?>{
        'label': 'Open settings',
        'route': '/settings',
      },
      children: const <BuilderNode>[],
    );
    final BuilderNode homeRoot = sample.root.updateById(
      'column_1',
      (BuilderNode node) =>
          node.copyWith(children: <BuilderNode>[...node.children, button]),
    );
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
    final BuilderDocument document = sample.copyWith(
      root: homeRoot,
      pages: <BuilderPage>[settings],
      initialPageId: settings.id,
    );

    final String source = DartGenerator().generate(document);

    expect(source, contains('initialRoute: "/settings"'));
    expect(
      source,
      contains('"/settings": (BuildContext context) => Scaffold('),
    );
    expect(source, contains('Navigator.of(context).pushNamed("/settings")'));
  });

  test('generates runnable button action sequences', () {
    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderNode button = BuilderNode(
      id: 'actions_button',
      type: 'button',
      properties: const <String, Object?>{
        'label': 'Continue',
        'actions': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'go',
            'type': 'navigate',
            'route': '/settings',
            'behavior': 'replace',
          },
          <String, Object?>{
            'id': 'toast',
            'type': 'snackbar',
            'message': 'Saved locally',
          },
          <String, Object?>{
            'id': 'notice',
            'type': 'dialog',
            'title': 'Done',
            'message': 'The action completed.',
          },
          <String, Object?>{'id': 'back', 'type': 'back'},
        ],
      },
      children: const <BuilderNode>[],
    );
    final BuilderDocument document = sample.copyWith(
      root: sample.root.updateById(
        'column_1',
        (BuilderNode column) => column.copyWith(
          children: <BuilderNode>[...column.children, button],
        ),
      ),
    );

    final String source = DartGenerator().generate(document);

    expect(source, contains('pushReplacementNamed("/settings")'));
    expect(
      source,
      contains('showSnackBar(SnackBar(content: Text("Saved locally")))'),
    );
    expect(source, contains('await showDialog<void>('));
    expect(source, contains('await Navigator.of(context).maybePop()'));
  });

  test('generates app variables, bindings, and widget state actions', () {
    final BuilderDocument sample = BuilderDocument.sample();
    const BuilderVariable count = BuilderVariable(
      id: 'count',
      name: 'Count',
      type: 'number',
      initialValue: 2,
    );
    const BuilderVariable enabled = BuilderVariable(
      id: 'enabled',
      name: 'Enabled',
      type: 'boolean',
      initialValue: true,
    );
    const BuilderVariable message = BuilderVariable(
      id: 'message',
      name: 'Message',
      type: 'string',
      initialValue: 'Hello',
    );
    final BuilderNode button = BuilderNode(
      id: 'state_button',
      type: 'button',
      properties: const <String, Object?>{
        'label': 'Update state',
        'actions': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'increment',
            'type': 'incrementVariable',
            'variableId': 'count',
            'amount': 3,
          },
          <String, Object?>{
            'id': 'toggle',
            'type': 'toggleVariable',
            'variableId': 'enabled',
          },
          <String, Object?>{
            'id': 'rename',
            'type': 'updateWidget',
            'targetPageId': 'home',
            'targetNodeId': 'text_1',
            'property': 'text',
            'value': 'Updated from action',
          },
          <String, Object?>{
            'id': 'hide',
            'type': 'updateWidget',
            'targetPageId': 'home',
            'targetNodeId': 'text_1',
            'property': 'visible',
            'value': false,
          },
        ],
      },
      children: const <BuilderNode>[],
    );
    final BuilderDocument document = sample.copyWith(
      variables: <BuilderVariable>[count, enabled, message],
      root: sample.root
          .updateById(
            'text_1',
            (BuilderNode node) => node.copyWith(
              properties: <String, Object?>{
                ...node.properties,
                'bindings': <String, Object?>{'text': 'message'},
              },
            ),
          )
          .updateById(
            'column_1',
            (BuilderNode node) => node.copyWith(
              children: <BuilderNode>[...node.children, button],
            ),
          ),
    );

    final String source = DartGenerator().generate(document);

    expect(source, contains('"count": 2'));
    expect(source, contains('_appState["count"]'));
    expect(source, contains('_appState["enabled"]'));
    expect(source, contains('_appState["message"]'));
    expect(source, contains('_widgetState["home::text_1.text"]'));
    expect(source, contains('_widgetState["home::text_1.visible"]'));
    expect(source, contains('Updated from action'));
  });

  test('interpolates variables in text and text field initial values', () {
    const BuilderVariable score = BuilderVariable(
      id: 'score',
      name: 'Score',
      type: 'integer',
      initialValue: 12,
    );
    final BuilderNode field = BuilderNode(
      id: 'name_field',
      type: 'textField',
      properties: const <String, Object?>{
        'label': 'Player',
        'initialValue': r'Score: ${Score}',
      },
      children: const <BuilderNode>[],
    );
    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderDocument document = sample.copyWith(
      variables: const <BuilderVariable>[score],
      root: sample.root
          .updateById(
            'text_1',
            (BuilderNode node) => node.copyWith(
              properties: <String, Object?>{
                ...node.properties,
                'text': r'Current score: ${Score}',
              },
            ),
          )
          .updateById(
            'column_1',
            (BuilderNode node) =>
                node.copyWith(children: <BuilderNode>[...node.children, field]),
          ),
    );

    final String source = DartGenerator().generate(document);

    expect(
      source,
      contains('"Current score: " + (_appState["score"]?.toString() ?? "")'),
    );
    expect(
      source,
      contains(
        'initialValue: "Score: " + (_appState["score"]?.toString() ?? "")',
      ),
    );
    expect(source, contains('TextFormField('));
  });

  test('escapes interpolations and clamps generated font sizes', () {
    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderDocument customized = sample.copyWith(
      name: r"Sam's $app",
      root: sample.root.updateById('text_1', (BuilderNode node) {
        return node.copyWith(
          properties: <String, Object?>{
            ...node.properties,
            'text': r'Hello $name "friend"',
            'fontSize': 120,
          },
        );
      }),
    );

    final String source = DartGenerator().generate(customized);

    expect(source, contains(r'''title: "Sam's \$app"'''));
    expect(source, contains(r'Hello \$name \"friend\"'));
    expect(source, contains('fontSize: 96.0'));
  });

  test('generates nested containers, rows, and styled buttons', () {
    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderNode button = BuilderNode(
      id: 'button_1',
      type: 'button',
      properties: const <String, Object?>{
        'label': 'Continue',
        'style': 'outlined',
      },
      children: const <BuilderNode>[],
    );
    final BuilderNode row = BuilderNode(
      id: 'row_1',
      type: 'row',
      properties: const <String, Object?>{'mainAxisAlignment': 'center'},
      children: <BuilderNode>[button],
    );
    final BuilderNode container = BuilderNode(
      id: 'container_1',
      type: 'container',
      properties: const <String, Object?>{
        'width': 260.0,
        'height': 120.0,
        'padding': 8.0,
        'borderRadius': 16.0,
        'backgroundColor': 0xFFEFF4FF,
      },
      children: <BuilderNode>[row],
    );
    final BuilderDocument document = sample.copyWith(
      root: sample.root.updateById('column_1', (BuilderNode node) {
        return node.copyWith(
          children: <BuilderNode>[...node.children, container],
        );
      }),
    );

    final String source = DartGenerator().generate(document);

    expect(source, contains('Container('));
    expect(source, contains('width: 260.0'));
    expect(source, contains('EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 8.0)'));
    expect(source, contains('Row('));
    expect(source, contains('OutlinedButton('));
    expect(source, contains('Text("Continue")'));
  });

  test('generates padding, margin, visibility, and opacity attributes', () {
    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderDocument customized = sample.copyWith(
      root: sample.root.updateById('text_1', (BuilderNode node) {
        return node.copyWith(
          properties: <String, Object?>{
            ...node.properties,
            'paddingTop': 8.0,
            'marginLeft': 4.0,
            'opacity': 0.5,
            'visible': false,
          },
        );
      }),
    );

    final String source = DartGenerator().generate(customized);

    expect(source, contains('EdgeInsets.fromLTRB(0.0, 8.0, 0.0, 0.0)'));
    expect(source, contains('EdgeInsets.fromLTRB(4.0, 0.0, 0.0, 0.0)'));
    expect(source, contains('opacity: 0.5'));
    expect(source, contains('visible: false'));
  });

  test(
    'generates local media, collection layouts, signature, dividers, and page elements',
    () {
      final BuilderDocument sample = BuilderDocument.sample();
      BuilderNode leaf(
        String id,
        String type, [
        Map<String, Object?> properties = const <String, Object?>{},
      ]) => BuilderNode(
        id: id,
        type: type,
        properties: properties,
        children: const <BuilderNode>[],
      );
      final BuilderNode list = BuilderNode(
        id: 'list_1',
        type: 'listView',
        properties: const <String, Object?>{
          'width': 300.0,
          'height': 220.0,
          'itemSpacing': 8.0,
        },
        children: <BuilderNode>[
          leaf('list_text', 'text', const <String, Object?>{
            'text': 'List item',
          }),
        ],
      );
      final BuilderNode swipeable = BuilderNode(
        id: 'swipe_1',
        type: 'swipeableStack',
        properties: const <String, Object?>{
          'width': 300.0,
          'height': 220.0,
          'visibleCount': 3,
          'loop': true,
        },
        children: <BuilderNode>[
          leaf('swipe_card', 'text', const <String, Object?>{
            'text': 'Swipe me',
          }),
        ],
      );
      final BuilderNode pageRoot = sample.root.copyWith(
        children: <BuilderNode>[
          leaf('appbar_1', 'appBar', const <String, Object?>{
            'title': 'Local page',
          }),
          ...sample.root.children,
          leaf('fab_1', 'floatingActionButton'),
        ],
      );
      final BuilderDocument document = sample.copyWith(
        root: pageRoot.updateById(
          'column_1',
          (BuilderNode column) => column.copyWith(
            children: <BuilderNode>[
              ...column.children,
              leaf('image_1', 'image', const <String, Object?>{
                'source': r'C:\\assets\\image.png',
                'width': 100.0,
                'height': 80.0,
              }),
              list,
              swipeable,
              leaf('signature_1', 'signature'),
              leaf('divider_1', 'divider'),
              leaf('vertical_divider_1', 'verticalDivider'),
            ],
          ),
        ),
      );

      final String source = DartGenerator().generate(document);

      expect(source, contains("import 'dart:io';"));
      expect(source, contains('Image.file(File('));
      expect(source, contains('ListView.separated('));
      expect(source, contains('_LocalSwipeableStack('));
      expect(
        source,
        contains('class _LocalSwipeableStack extends StatefulWidget'),
      );
      expect(source, contains('_LocalSignaturePad('));
      expect(
        source,
        contains('class _LocalSignaturePad extends StatefulWidget'),
      );
      expect(source, contains('Divider('));
      expect(source, contains('VerticalDivider('));
      expect(source, contains('appBar: AppBar('));
      expect(source, contains('floatingActionButton: FloatingActionButton('));
    },
  );
}
