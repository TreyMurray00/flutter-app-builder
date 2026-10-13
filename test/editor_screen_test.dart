import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:local_flutter_builder/editor/canvas_preview.dart';
import 'package:local_flutter_builder/editor/editor_controller.dart';
import 'package:local_flutter_builder/editor/editor_screen.dart';
import 'package:local_flutter_builder/editor/signature_pad.dart';
import 'package:local_flutter_builder/main.dart';
import 'package:local_flutter_builder/models/builder_document.dart';
import 'package:local_flutter_builder/services/dart_generator.dart';
import 'package:local_flutter_builder/services/flutter_project_exporter.dart';
import 'package:local_flutter_builder/services/project_store.dart';

class _ImmediateFlutterProjectExporter extends FlutterProjectExporter {
  _ImmediateFlutterProjectExporter() : super(generator: DartGenerator());

  @override
  Future<String> export(BuilderDocument document, String destination) async =>
      destination;
}

void main() {
  testWidgets('switching pages keeps preview element keys page-scoped', (
    WidgetTester tester,
  ) async {
    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderNode homeRoot = sample.root.updateById(
      'column_1',
      (BuilderNode column) => column.copyWith(
        children: <BuilderNode>[
          ...column.children,
          BuilderNode(
            id: 'field_1',
            type: 'textField',
            properties: <String, Object?>{'label': 'Home field'},
            children: <BuilderNode>[],
          ),
        ],
      ),
    );
    final BuilderPage otherPage = BuilderPage(
      id: 'other',
      name: 'Other',
      route: '/other',
      root: BuilderNode(
        id: 'scaffold_1',
        type: 'scaffold',
        properties: const <String, Object?>{},
        children: <BuilderNode>[
          BuilderNode(
            id: 'column_1',
            type: 'column',
            properties: const <String, Object?>{},
            children: <BuilderNode>[
              BuilderNode(
                id: 'listView_1',
                type: 'listView',
                properties: const <String, Object?>{
                  'width': 240.0,
                  'height': 120.0,
                },
                children: <BuilderNode>[
                  BuilderNode(
                    id: 'field_1',
                    type: 'textField',
                    properties: <String, Object?>{'label': 'Other field'},
                    children: <BuilderNode>[],
                  ),
                ],
              ),
              BuilderNode(
                id: 'swipeableStack_1',
                type: 'swipeableStack',
                properties: const <String, Object?>{
                  'width': 240.0,
                  'height': 120.0,
                },
                children: <BuilderNode>[
                  BuilderNode(
                    id: 'card_1',
                    type: 'card',
                    properties: <String, Object?>{'height': 80.0},
                    children: <BuilderNode>[],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final BuilderDocument document = sample.copyWith(
      root: homeRoot,
      pages: <BuilderPage>[otherPage],
    );
    String activePageId = 'home';

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            final BuilderPage activePage = document.pageById(activePageId)!;
            return Scaffold(
              body: Column(
                children: <Widget>[
                  TextButton(
                    onPressed:
                        () => setState(
                          () =>
                              activePageId =
                                  activePageId == 'home' ? 'other' : 'home',
                        ),
                    child: const Text('Switch preview page'),
                  ),
                  Expanded(
                    child: CanvasPreview(
                      document: document,
                      root: activePage.root,
                      selectedNodeId: '',
                      size: PreviewSize.phone,
                      activePageId: activePageId,
                      onSelect: (_) {},
                      onDrop: (_, __, ___) {},
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (int index = 0; index < 4; index++) {
      await tester.tap(find.text('Switch preview page'));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a project resets the preview for reused widget ids', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final EditorController editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorController>.value(value: editor),
          Provider<ProjectStore>(create: (_) => ProjectStore()),
          Provider<DartGenerator>(create: (_) => DartGenerator()),
          Provider<FlutterProjectExporter>(
            create: (_) => FlutterProjectExporter(generator: DartGenerator()),
          ),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderDocument counter = sample.copyWith(
      name: 'Counter',
      root: sample.root.updateById(
        'column_1',
        (BuilderNode column) => column.copyWith(
          children: <BuilderNode>[
            ...column.children,
            BuilderNode(
              id: 'row_1',
              type: 'row',
              properties: const <String, Object?>{},
              children: <BuilderNode>[
                BuilderNode(
                  id: 'button_1',
                  type: 'button',
                  properties: const <String, Object?>{'label': 'Increment'},
                  children: const <BuilderNode>[],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final Key? previousPreviewKey =
        tester.widget<CanvasPreview>(find.byType(CanvasPreview)).key;

    editor.open(counter, r'C:\projects\counter.appbuilder.json');
    await tester.pumpAndSettle();

    final Key? openedPreviewKey =
        tester.widget<CanvasPreview>(find.byType(CanvasPreview)).key;
    expect(openedPreviewKey, isNot(previousPreviewKey));
    expect(find.text('Increment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export uses the native folder picker and completes cleanly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final EditorController editor = EditorController();
    addTearDown(editor.dispose);
    const MethodChannel fileSelectorChannel = MethodChannel(
      'plugins.flutter.io/file_selector',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          fileSelectorChannel,
          (MethodCall call) async {
            expect(call.method, 'getDirectoryPath');
            return r'C:\output';
          },
        );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorController>.value(value: editor),
          Provider<ProjectStore>(create: (_) => ProjectStore()),
          Provider<FlutterProjectExporter>(
            create: (_) => _ImmediateFlutterProjectExporter(),
          ),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Export Flutter App'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Exported Flutter app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workbench renders and adding text updates the preview', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();

    expect(find.text('LOCAL FLOW'), findsOneWidget);
    expect(find.text('Widget Palette'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Text && widget.data == 'Hello from your local builder',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Add Text').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Widget tree'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is Text && widget.data == 'New text',
      ),
      findsOneWidget,
    );
    expect(find.text('Text · New text'), findsOneWidget);
  });

  testWidgets('can add a button and edit its label and style', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Button').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Widget tree'));
    await tester.pumpAndSettle();

    expect(find.text('Button · Button'), findsOneWidget);
    final Finder labelField = find.byKey(
      const ValueKey<String>('button_4-label'),
    );
    await tester.enterText(labelField, 'Continue');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is Text && widget.data == 'Continue',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      <String>{'outlined'},
    );
  });

  testWidgets('creates an app variable in the variables manager', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();
    expect(find.text('Variables'), findsOneWidget);
    await tester.tap(find.byTooltip('App variables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add variable'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Greeting',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Initial value',
      ),
      'Welcome',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Greeting'), findsOneWidget);
    expect(find.text('string · initial Welcome'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'visibility is shown first and bindings offer variable creation',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const LocalBuilderApp());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('text_1-visible')),
        findsOneWidget,
      );
      await tester.tap(find.text('Variable bindings'));
      await tester.pumpAndSettle();
      expect(find.text('Create app variable'), findsOneWidget);

      await tester.tap(find.text('Create app variable'));
      await tester.pumpAndSettle();
      expect(find.text('New variable'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('adds an action and runs it in the canvas preview', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Button').first);
    await tester.pumpAndSettle();

    final Finder addAction = find.byTooltip('Add action');
    await tester.ensureVisible(addAction);
    await tester.tap(addAction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show snackbar').last);
    await tester.pumpAndSettle();

    final Finder messageField = find.byType(TextFormField).last;
    await tester.ensureVisible(messageField);
    await tester.enterText(messageField, 'Action ran');
    await tester.pumpAndSettle();
    final Finder previewButton = find.byWidgetPredicate(
      (Widget widget) =>
          widget is FilledButton &&
          widget.child is Text &&
          (widget.child as Text).data == 'Button',
    );
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    final SnackBar snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect((snackBar.content as Text).data, 'Action ran');
  });

  testWidgets('canvas preview resolves app variable bindings', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderDocument bound = sample.copyWith(
      variables: const <BuilderVariable>[
        BuilderVariable(
          id: 'title',
          name: 'Title',
          type: 'string',
          initialValue: 'Initial',
        ),
        BuilderVariable(
          id: 'show_hint',
          name: 'Show hint',
          type: 'boolean',
          initialValue: true,
        ),
      ],
      root: sample.root
          .updateById(
            'text_1',
            (BuilderNode node) => node.copyWith(
              properties: <String, Object?>{
                ...node.properties,
                'bindings': <String, Object?>{'text': 'title'},
              },
            ),
          )
          .updateById(
            'column_1',
            (BuilderNode node) => node.copyWith(
              children: <BuilderNode>[
                ...node.children,
                BuilderNode(
                  id: 'hint_text',
                  type: 'text',
                  properties: const <String, Object?>{
                    'text': 'Hint',
                    'bindings': <String, Object?>{'visible': 'show_hint'},
                  },
                  children: const <BuilderNode>[],
                ),
              ],
            ),
          ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: CanvasPreview(
            document: bound,
            selectedNodeId: '',
            size: PreviewSize.desktop,
            activePageId: 'home',
            variableValues: const <String, Object?>{
              'title': 'From app state',
              'show_hint': false,
            },
            onSelect: (_) {},
            onDrop: (_, __, ___) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('From app state'), findsOneWidget);
    expect(
      tester
          .widgetList<Visibility>(find.byType(Visibility))
          .any((Visibility widget) => widget.visible == false),
      isTrue,
    );
  });

  testWidgets('canvas interpolates numeric variables in text and text fields', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final BuilderDocument sample = BuilderDocument.sample();
    final BuilderNode field = BuilderNode(
      id: 'score_field',
      type: 'textField',
      properties: const <String, Object?>{
        'label': r'Score ${score}',
        'initialValue': r'Current: ${Score}',
      },
      children: const <BuilderNode>[],
    );
    final BuilderDocument templated = sample.copyWith(
      variables: const <BuilderVariable>[
        BuilderVariable(
          id: 'score',
          name: 'Score',
          type: 'integer',
          initialValue: 12,
        ),
      ],
      root: sample.root
          .updateById(
            'text_1',
            (BuilderNode node) => node.copyWith(
              properties: <String, Object?>{
                ...node.properties,
                'text': r'Points: ${Score}',
              },
            ),
          )
          .updateById(
            'column_1',
            (BuilderNode node) =>
                node.copyWith(children: <BuilderNode>[...node.children, field]),
          ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: CanvasPreview(
            document: templated,
            selectedNodeId: '',
            size: PreviewSize.desktop,
            variableValues: const <String, Object?>{'score': 42},
            onSelect: (_) {},
            onDrop: (_, __, ___) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Points: 42'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
      'Current: 42',
    );
    expect(find.text('Score 42'), findsOneWidget);
  });

  testWidgets('button actions update another widget in the live preview', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final EditorController editor = EditorController();
    addTearDown(editor.dispose);
    editor.addObject('button');
    final String buttonId = editor.selectedNodeId;
    editor.setProperty(buttonId, 'actions', <Map<String, Object?>>[
      <String, Object?>{
        'id': 'update_title',
        'type': 'updateWidget',
        'targetPageId': 'home',
        'targetNodeId': 'text_1',
        'property': 'text',
        'value': 'Changed by action',
      },
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EditorController>.value(value: editor),
          Provider<ProjectStore>(create: (_) => ProjectStore()),
          Provider<DartGenerator>(create: (_) => DartGenerator()),
          Provider<FlutterProjectExporter>(
            create: (_) => FlutterProjectExporter(generator: DartGenerator()),
          ),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder previewButton = find.byWidgetPredicate(
      (Widget widget) =>
          widget is FilledButton &&
          widget.child is Text &&
          (widget.child as Text).data == 'Button',
    );
    await tester.tap(previewButton);
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is Text && widget.data == 'Changed by action',
      ),
      findsOneWidget,
    );
    expect(
      editor.widgetOverrides['home::text_1']?['text'],
      'Changed by action',
    );
  });

  testWidgets('can size a container and add a child inside it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Container').first);
    await tester.pumpAndSettle();

    final Finder widthField = find.byKey(
      const ValueKey<String>('container_4-width'),
    );
    await tester.enterText(widthField, '280');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(widthField).controller?.text, '280');

    await tester.tap(find.byTooltip('Add Text').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Widget tree'));
    await tester.pumpAndSettle();
    expect(find.text('Text · New text'), findsOneWidget);
    expect(find.text('Container'), findsOneWidget);
  });

  testWidgets('padding and margin controls edit linked and per-side values', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Container').first);
    await tester.pumpAndSettle();

    final Finder paddingTop = find.byKey(
      const ValueKey<String>('container_4-paddingTop'),
    );
    await tester.ensureVisible(paddingTop);
    await tester.enterText(paddingTop, '20');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(paddingTop).controller?.text, '20');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('container_4-paddingRight')),
          )
          .controller
          ?.text,
      '20',
    );

    final Finder unlinkPadding = find.byTooltip('Unlink spacing values').first;
    await tester.ensureVisible(unlinkPadding);
    await tester.tap(unlinkPadding);
    await tester.pumpAndSettle();
    final Finder paddingLeft = find.byKey(
      const ValueKey<String>('container_4-paddingLeft'),
    );
    await tester.ensureVisible(paddingLeft);
    await tester.enterText(paddingLeft, '12');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(paddingTop).controller?.text, '20');
    expect(tester.widget<TextField>(paddingLeft).controller?.text, '12');

    expect(
      find.byKey(const ValueKey<String>('container_4-marginTop')),
      findsOneWidget,
    );
  });

  testWidgets('spacing attributes remain editable on text widgets', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Padding').last);
    await tester.pumpAndSettle();

    final Finder topPadding = find.byKey(
      const ValueKey<String>('text_1-paddingTop'),
    );
    await tester.ensureVisible(topPadding);
    await tester.enterText(topPadding, '18');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(topPadding).controller?.text, '18');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a palette item onto the canvas adds an object', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();

    final Offset start = tester.getCenter(find.byTooltip('Add Button').first);
    final Offset target = tester.getCenter(find.byType(CanvasPreview));
    await tester.dragFrom(start, target - start);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Widget tree'));
    await tester.pumpAndSettle();

    expect(find.text('Button · Button'), findsOneWidget);
  });

  testWidgets('dragging a palette item onto a canvas container nests it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Container').first);
    await tester.pumpAndSettle();

    final Offset start = tester.getCenter(find.byTooltip('Add Text').first);
    final Offset target = tester.getCenter(
      find.byKey(const ValueKey<String>('preview-node-home-container_4')),
    );
    await tester.dragFrom(start, target - start);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Widget tree'));
    await tester.pumpAndSettle();

    expect(find.text('Text · New text'), findsOneWidget);
    await tester.tap(find.text('Container').first);
    await tester.pumpAndSettle();
    expect(
      find.text('This container holds 1 child object(s).'),
      findsOneWidget,
    );
  });

  testWidgets('dragging a tree object onto a container nests it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LocalBuilderApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Container').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Widget tree'));
    await tester.pumpAndSettle();

    final Finder source = find.text('Text · Hello from your local builder');
    final Finder target = find.text('Container').first;
    final double originalX = tester.getTopLeft(source).dx;
    final Offset sourceCenter = tester.getCenter(source);
    final Offset targetCenter = tester.getCenter(target);
    await tester.drag(source, targetCenter - sourceCenter);
    await tester.pumpAndSettle();

    expect(find.text('Text · Hello from your local builder'), findsOneWidget);
    expect(tester.getTopLeft(source).dx, greaterThan(originalX));
  });

  testWidgets(
    'previews collection, signature, divider, image, and page widgets',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final BuilderDocument sample = BuilderDocument.sample();
      BuilderNode leaf(
        String id,
        String type, [
        Map<String, Object?> properties = const <String, Object?>{},
        List<BuilderNode>? children,
      ]) => BuilderNode(
        id: id,
        type: type,
        properties: properties,
        children: children ?? const <BuilderNode>[],
      );
      final BuilderNode root = sample.root.copyWith(
        children: <BuilderNode>[
          leaf('appbar_preview', 'appBar', const <String, Object?>{
            'title': 'Demo',
          }),
          sample.root.children.single.copyWith(
            children: <BuilderNode>[
              leaf(
                'list_preview',
                'listView',
                const <String, Object?>{'width': 260.0, 'height': 100.0},
                <BuilderNode>[
                  leaf('list_item', 'text', const <String, Object?>{
                    'text': 'List item',
                  }),
                ],
              ),
              leaf(
                'swipe_preview',
                'swipeableStack',
                const <String, Object?>{'width': 260.0, 'height': 120.0},
                <BuilderNode>[
                  leaf('swipe_card', 'text', const <String, Object?>{
                    'text': 'Swipe card',
                  }),
                ],
              ),
              leaf('image_preview', 'image', const <String, Object?>{
                'width': 100.0,
                'height': 60.0,
              }),
              leaf('signature_preview', 'signature', const <String, Object?>{
                'width': 260.0,
                'height': 100.0,
              }),
              leaf('divider_preview', 'divider'),
              leaf('vertical_preview', 'verticalDivider'),
            ],
          ),
          leaf('fab_preview', 'floatingActionButton'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: CanvasPreview(
              document: sample.copyWith(root: root),
              selectedNodeId: 'signature_preview',
              size: PreviewSize.desktop,
              onSelect: (_) {},
              onDrop: (_, __, ___) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('swipe-card-home::swipe_preview-0')),
        findsOneWidget,
      );
      expect(find.byType(LocalSignaturePad), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
