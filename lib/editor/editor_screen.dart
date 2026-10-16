import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/builder_action.dart';
import '../models/builder_document.dart';
import '../services/custom_function_preview_runner.dart';
import '../services/database_query_support.dart';
import '../services/dart_generator.dart';
import '../services/flutter_project_exporter.dart';
import '../services/flutter_toolchain_service.dart';
import '../services/project_store.dart';
import '../services/project_validator.dart';
import 'canvas_preview.dart';
import 'editor_controller.dart';
import 'editor_drag_data.dart';
import 'editor_palette.dart';
import 'custom_data_structure_dialog.dart';
import 'flutter_toolchain_dialog.dart';
import 'inspector_panel.dart';
import 'widget_tree_panel.dart';
import '../theme_mode_controller.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const int _minPreviewZoomPercent = 50;
  static const int _maxPreviewZoomPercent = 400;

  PreviewSize _previewSize = PreviewSize.phone;
  Size _customPreviewSize = const Size(390, 844);
  int _previewZoomPercent = 100;
  final TransformationController _previewTransformationController =
      TransformationController();
  final GlobalKey _previewViewportKey = GlobalKey();
  bool _isControlPressed = false;
  bool _isAltPressed = false;
  bool _working = false;
  bool _showPalette = true;
  bool _showInspector = true;
  String? _workingMessage;
  EditorController? _observedEditor;
  Timer? _autosaveTimer;
  Future<void>? _autosaveInFlight;
  int? _autosaveAttemptedRevision;
  int? _autosaveSessionId;
  String? _lastExportPath;
  int? _lastExportRevision;

  Size get _effectivePreviewSize =>
      _previewSize == PreviewSize.custom
          ? _customPreviewSize
          : Size(_previewSize.width, _previewSize.height);

  @override
  void initState() {
    super.initState();
    _previewTransformationController.addListener(_syncPreviewZoomPercent);
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handlePreviewPointerEvent,
    );
    HardwareKeyboard.instance.addHandler(_handleKeyboardEvent);
  }

  bool _handleKeyboardEvent(KeyEvent event) {
    final bool isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final bool isAltPressed = HardwareKeyboard.instance.isAltPressed;
    if (isControlPressed != _isControlPressed ||
        isAltPressed != _isAltPressed) {
      setState(() {
        _isControlPressed = isControlPressed;
        _isAltPressed = isAltPressed;
      });
    }
    if (event is! KeyDownEvent || _isTextEntryFocused()) return false;
    final bool commandPressed =
        isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final EditorController editor = context.read<EditorController>();
    if (commandPressed) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyZ:
          if (HardwareKeyboard.instance.isShiftPressed) {
            editor.redo();
          } else {
            editor.undo();
          }
          return true;
        case LogicalKeyboardKey.keyY:
          editor.redo();
          return true;
        case LogicalKeyboardKey.keyD:
          editor.duplicateSelected();
          return true;
        case LogicalKeyboardKey.keyC:
          final String? serialized = editor.copySelected();
          if (serialized != null) {
            unawaited(Clipboard.setData(ClipboardData(text: serialized)));
          }
          return true;
        case LogicalKeyboardKey.keyX:
          final String? serialized = editor.copySelected();
          if (serialized != null) {
            unawaited(Clipboard.setData(ClipboardData(text: serialized)));
            editor.deleteSelected();
          }
          return true;
        case LogicalKeyboardKey.keyV:
          unawaited(_pasteFromClipboard(editor));
          return true;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      editor.deleteSelected();
      return true;
    }
    if (_isEditorContentFocused()) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        editor.moveSelection(-1);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        editor.moveSelection(1);
        return true;
      }
    }
    return false;
  }

  bool _isTextEntryFocused() {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    return focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  bool _isEditorContentFocused() {
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return true;
    return focusContext.findAncestorWidgetOfExactType<CanvasPreview>() !=
            null ||
        focusContext.findAncestorWidgetOfExactType<WidgetTreePanel>() != null;
  }

  Future<void> _pasteFromClipboard(EditorController editor) async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    if (!mounted || data?.text == null) return;
    editor.pasteNodeJson(data!.text!);
  }

  void _syncPreviewZoomPercent() {
    if (!mounted) return;
    final int zoomPercent =
        (_previewTransformationController.value.getMaxScaleOnAxis() * 100)
            .round()
            .clamp(_minPreviewZoomPercent, _maxPreviewZoomPercent)
            .toInt();
    if (zoomPercent != _previewZoomPercent) {
      setState(() => _previewZoomPercent = zoomPercent);
    }
  }

  Offset _previewViewportCenter() {
    final RenderObject? renderObject =
        _previewViewportKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size.center(Offset.zero);
    }
    return Offset.zero;
  }

  void _zoomPreviewAt(Offset focalPoint, double scaleFactor) {
    final Matrix4 currentTransform = _previewTransformationController.value;
    final double currentScale = currentTransform.getMaxScaleOnAxis();
    final double nextScale =
        (currentScale * scaleFactor).clamp(.5, 4.0).toDouble();
    if ((nextScale - 1).abs() <= .005) {
      _resetPreviewZoom();
      return;
    }
    if (nextScale == currentScale) return;

    _previewTransformationController.value =
        Matrix4.identity()
          ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
          ..scaleByDouble(
            nextScale / currentScale,
            nextScale / currentScale,
            1,
            1,
          )
          ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1)
          ..multiply(currentTransform);
  }

  void _handlePreviewPointerEvent(PointerEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    final RenderObject? renderObject =
        _previewViewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final Offset focalPoint = renderObject.globalToLocal(event.position);
    if (!(Offset.zero & renderObject.size).contains(focalPoint)) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolvedEvent,
    ) {
      if (resolvedEvent is! PointerScrollEvent) return;
      final double scrollAmount =
          resolvedEvent.scrollDelta.dy == 0
              ? resolvedEvent.scrollDelta.dx
              : resolvedEvent.scrollDelta.dy;
      _zoomPreviewAt(focalPoint, math.exp(-scrollAmount / 240));
    });
  }

  void _adjustPreviewZoom(int steps) {
    _zoomPreviewAt(_previewViewportCenter(), math.pow(1.1, steps).toDouble());
  }

  void _resetPreviewZoom() {
    _previewTransformationController.value = Matrix4.identity();
  }

  void _resetPreviewZoomIfAtBase() {
    if ((_previewTransformationController.value.getMaxScaleOnAxis() - 1)
            .abs() <=
        .005) {
      _resetPreviewZoom();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final EditorController editor = context.read<EditorController>();
    if (_observedEditor == editor) return;
    _observedEditor?.removeListener(_scheduleAutosave);
    _observedEditor = editor;
    editor.addListener(_scheduleAutosave);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _observedEditor?.removeListener(_scheduleAutosave);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handlePreviewPointerEvent,
    );
    HardwareKeyboard.instance.removeHandler(_handleKeyboardEvent);
    _previewTransformationController
      ..removeListener(_syncPreviewZoomPercent)
      ..dispose();
    super.dispose();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    final EditorController? editor = _observedEditor;
    if (!mounted ||
        editor == null ||
        !editor.isDirty ||
        editor.projectPath == null) {
      return;
    }
    if (_autosaveSessionId != editor.documentSessionId) {
      _autosaveSessionId = editor.documentSessionId;
      _autosaveAttemptedRevision = null;
    }
    final int revision = editor.documentRevision;
    if (_autosaveAttemptedRevision == revision) return;
    _autosaveAttemptedRevision = revision;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_writeAutosave(editor, revision));
    });
  }

  Future<void> _writeAutosave(EditorController editor, int revision) async {
    if (!mounted ||
        !editor.isDirty ||
        editor.documentRevision != revision ||
        editor.projectPath == null ||
        _autosaveInFlight != null) {
      return;
    }
    final String autosavePath = '${editor.projectPath}.autosave';
    final Future<void> write = context
        .read<ProjectStore>()
        .saveProjectWithDocument(editor.document, autosavePath)
        .then<void>((StoredProject _) {});
    _autosaveInFlight = write;
    try {
      await write;
      _autosaveAttemptedRevision = revision;
    } catch (error) {
      _showMessage('Autosave could not be written: $error', isError: true);
    } finally {
      if (identical(_autosaveInFlight, write)) _autosaveInFlight = null;
      if (mounted && editor.documentRevision != revision) _scheduleAutosave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final EditorController editor = context.read<EditorController>();
    final Size viewport = MediaQuery.sizeOf(context);
    final bool compactLayout = viewport.width < 960;
    final double paletteWidth =
        (viewport.width * .24).clamp(220, 360).toDouble();
    final double inspectorWidth =
        (viewport.width * .22).clamp(220, 360).toDouble();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Toolbar(
              previewSize: _previewSize,
              isWorking: _working,
              onPreviewSizeChanged: _changePreviewSize,
              onNew: _newProject,
              onOpen: _openProject,
              onSave: _saveProject,
              onExportApp: _exportFlutterApp,
              onValidate: _validateCurrentProject,
              onRuntimePreview: _startFlutterRuntimePreview,
              onToolchain: _startToolchainWorkflow,
              onVariables: _manageVariables,
              onDataStructures: _manageCustomDataStructures,
              onGroups: _manageComponentGroups,
              onDatabase: _manageDatabase,
              onUndo: editor.undo,
              onRedo: editor.redo,
            ),
            Selector<EditorController, (int, String, String)>(
              selector:
                  (BuildContext _, EditorController value) => (
                    value.documentRevision,
                    value.activePageId,
                    value.document.initialPageId,
                  ),
              builder: (BuildContext context, _, Widget? child) {
                final EditorController current =
                    context.read<EditorController>();
                return _PagesBar(
                  pages: current.pages,
                  activePageId: current.activePageId,
                  initialPageId: current.document.initialPageId,
                  onSelect: current.selectPage,
                  onAdd: current.addPage,
                  onEdit: _editPage,
                  onSetInitial: current.setInitialPage,
                  onDelete: _deletePage,
                );
              },
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  if (!compactLayout && _showPalette) ...<Widget>[
                    SizedBox(
                      width: paletteWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
                        child: _widgetTreePanel(),
                      ),
                    ),
                    const VerticalDivider(width: 1, thickness: 1),
                  ],
                  Expanded(
                    child: ColoredBox(
                      color: EditorPalette.surfaceInset(context),
                      child: Column(
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 7),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.touch_app_outlined,
                                  size: 15,
                                  color: EditorPalette.mutedText(context),
                                ),
                                const SizedBox(width: 7),
                                if (viewport.width > 1100)
                                  Text(
                                    'Select a widget on the canvas to edit it',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: EditorPalette.mutedText(context),
                                    ),
                                  ),
                                const Spacer(),
                                Tooltip(
                                  message:
                                      'Zoom out preview (Ctrl + scroll down)',
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed:
                                        _previewZoomPercent <=
                                                _minPreviewZoomPercent
                                            ? null
                                            : () => _adjustPreviewZoom(-1),
                                    icon: const Icon(Icons.remove, size: 17),
                                  ),
                                ),
                                Tooltip(
                                  message:
                                      'Reset zoom · Ctrl+scroll or pinch to zoom · Ctrl+drag to pan',
                                  child: TextButton(
                                    onPressed:
                                        _previewZoomPercent == 100
                                            ? null
                                            : _resetPreviewZoom,
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(42, 30),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 10),
                                    ),
                                    child: Text('$_previewZoomPercent%'),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Zoom in preview (Ctrl + scroll up)',
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed:
                                        _previewZoomPercent >=
                                                _maxPreviewZoomPercent
                                            ? null
                                            : () => _adjustPreviewZoom(1),
                                    icon: const Icon(Icons.add, size: 17),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                IconButton(
                                  tooltip:
                                      _showPalette
                                          ? 'Hide component panel'
                                          : 'Show component panel',
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      compactLayout
                                          ? () =>
                                              _showCompactPanel(palette: true)
                                          : () => setState(
                                            () => _showPalette = !_showPalette,
                                          ),
                                  icon: Icon(
                                    Icons.widgets_outlined,
                                    size: 17,
                                    color:
                                        _showPalette
                                            ? EditorPalette.primary(context)
                                            : EditorPalette.mutedText(context),
                                  ),
                                ),
                                IconButton(
                                  tooltip:
                                      _showInspector
                                          ? 'Hide properties panel'
                                          : 'Show properties panel',
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      compactLayout
                                          ? () =>
                                              _showCompactPanel(palette: false)
                                          : () => setState(
                                            () =>
                                                _showInspector =
                                                    !_showInspector,
                                          ),
                                  icon: Icon(
                                    Icons.tune,
                                    size: 17,
                                    color:
                                        _showInspector
                                            ? EditorPalette.primary(context)
                                            : EditorPalette.mutedText(context),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (viewport.width > 1100)
                                  Text(
                                    '${_effectivePreviewSize.width.round()} × ${_effectivePreviewSize.height.round()}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: EditorPalette.mutedText(context),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(child: _canvasPreview()),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ),
                  if (!compactLayout && _showInspector) ...<Widget>[
                    const VerticalDivider(width: 1, thickness: 1),
                    SizedBox(
                      width: inspectorWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                        child: _inspectorPanel(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Selector<EditorController, (int, String?, bool)>(
              selector:
                  (BuildContext _, EditorController value) => (
                    value.documentRevision,
                    value.projectPath,
                    value.isDirty,
                  ),
              builder: (BuildContext context, _, Widget? child) {
                final EditorController current =
                    context.read<EditorController>();
                return _StatusBar(
                  document: current.document,
                  projectPath: current.projectPath,
                  isDirty: current.isDirty,
                  activityMessage: _workingMessage,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _widgetTreePanel() =>
      Selector<EditorController, (int, String, String)>(
        selector:
            (BuildContext _, EditorController editor) => (
              editor.documentRevision,
              editor.activePageId,
              editor.selectedNodeId,
            ),
        builder: (BuildContext context, _, Widget? child) {
          final EditorController editor = context.read<EditorController>();
          return WidgetTreePanel(
            root: editor.activeRoot,
            selectedNodeId: editor.selectedNodeId,
            onSelect: editor.selectNode,
            onAddObject: editor.addObject,
            onDrop: _handleDrop,
            componentGroups: editor.document.componentGroups,
            onAddGroup:
                (BuilderComponentGroup group) =>
                    editor.addObject('componentGroup', groupId: group.id),
          );
        },
      );

  Widget _inspectorPanel() => Selector<EditorController, (int, String, String)>(
    selector:
        (BuildContext _, EditorController editor) => (
          editor.documentRevision,
          editor.activePageId,
          editor.selectedNodeId,
        ),
    builder: (BuildContext context, _, Widget? child) {
      final EditorController editor = context.read<EditorController>();
      return InspectorPanel(
        node: editor.selectedNode,
        seedColor: editor.document.seedColor,
        appTheme: editor.document.appTheme,
        onSetProperty: editor.setProperty,
        onSetProperties: editor.setProperties,
        onSetSeedColor: editor.setSeedColor,
        onSetAppTheme: editor.setAppTheme,
        onDeleteNode: editor.deleteSelected,
        onCreateVariable: _createVariable,
        pages: editor.pages,
        variables: editor.document.variables,
        customFunctions: editor.document.customFunctions,
        databaseCollections: editor.document.databaseCollections,
        databaseRelationships: editor.document.databaseRelationships,
        onSetCustomFunctions: editor.setCustomFunctions,
        onCreateComponentGroup: _createComponentGroup,
        onPickImage: _pickImage,
        fontAssets: editor.document.fontAssets,
        onImportFont: _importFont,
        onRemoveFontAsset: editor.removeFontAsset,
      );
    },
  );

  Widget _canvasPreview() =>
      Selector<EditorController, (int, int, int, String, String, String?)>(
        selector:
            (BuildContext _, EditorController value) => (
              value.documentRevision,
              value.runtimeRevision,
              value.documentSessionId,
              value.selectedNodeId,
              value.activePageId,
              value.projectPath,
            ),
        builder: (BuildContext context, _, Widget? child) {
          final EditorController current = context.read<EditorController>();
          return CanvasPreview(
            key: ValueKey<int>(current.documentSessionId),
            document: current.document,
            root: current.activeRoot,
            selectedNodeId: current.selectedNodeId,
            size: _previewSize,
            customSize:
                _previewSize == PreviewSize.custom ? _customPreviewSize : null,
            transformationController: _previewTransformationController,
            viewportKey: _previewViewportKey,
            panEnabled: _isControlPressed && _previewZoomPercent > 100,
            altDrawerGestureEnabled: _isAltPressed,
            onInteractionEnd: _resetPreviewZoomIfAtBase,
            onSelect: current.selectNode,
            onDrop: _handleDrop,
            onNavigate: current.navigateToRoute,
            onRunActions: _runActions,
            onSetVariable: current.setVariableValue,
            activePageId: current.activePageId,
            projectPath: current.projectPath,
            variableValues: current.appVariableValues,
            widgetOverrides: current.widgetOverrides,
            databaseRecords: current.previewDatabaseRecords,
          );
        },
      );

  Future<void> _showCompactPanel({required bool palette}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => Dialog(
            child: SizedBox(
              width: 360,
              height: MediaQuery.sizeOf(dialogContext).height * .82,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: palette ? _widgetTreePanel() : _inspectorPanel(),
              ),
            ),
          ),
    );
  }

  Future<BuilderFontAsset?> _importFont() async {
    final XTypeGroup fontType = const XTypeGroup(
      label: 'Font files',
      extensions: <String>['ttf', 'otf'],
      mimeTypes: <String>['font/ttf', 'font/otf', 'application/x-font-ttf'],
    );
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[fontType],
      confirmButtonText: 'Import font',
    );
    if (file == null || !mounted) return null;
    final String filename = file.name.split(RegExp(r'[/\\]')).last;
    final String family = filename.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
    if (family.isEmpty) return null;
    final BuilderFontAsset font = BuilderFontAsset(
      id: 'font_${DateTime.now().microsecondsSinceEpoch}',
      family: family,
      source: file.path,
    );
    final EditorController editor = context.read<EditorController>();
    editor.addFontAsset(font);
    await _loadBundledFonts(<BuilderFontAsset>[font], editor.projectPath);
    return font;
  }

  final Set<String> _loadedFontSources = <String>{};

  Future<void> _loadBundledFonts(
    List<BuilderFontAsset> fonts,
    String? projectPath,
  ) async {
    final Map<String, List<BuilderFontAsset>> families =
        <String, List<BuilderFontAsset>>{};
    for (final BuilderFontAsset font in fonts) {
      families.putIfAbsent(font.family, () => <BuilderFontAsset>[]).add(font);
    }
    for (final MapEntry<String, List<BuilderFontAsset>> family
        in families.entries) {
      final List<(BuilderFontAsset, Uint8List)> loadable =
          <(BuilderFontAsset, Uint8List)>[];
      for (final BuilderFontAsset font in family.value) {
        final String path = resolveProjectAssetPath(projectPath, font.source);
        final String key = '${family.key}:$path';
        if (_loadedFontSources.contains(key)) continue;
        try {
          loadable.add((font, await File(path).readAsBytes()));
        } on FileSystemException {
          continue;
        }
      }
      if (loadable.isEmpty) continue;
      final FontLoader loader = FontLoader(family.key);
      for (final (BuilderFontAsset _, Uint8List bytes) in loadable) {
        loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      }
      try {
        await loader.load();
        for (final (BuilderFontAsset font, _) in loadable) {
          _loadedFontSources.add(
            '${family.key}:${resolveProjectAssetPath(projectPath, font.source)}',
          );
        }
      } on FlutterError {
        // Font loading is best-effort; export still bundles the original files.
      }
    }
  }

  Future<void> _newProject() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    context.read<EditorController>().createNew();
    _lastExportPath = null;
    _lastExportRevision = null;
  }

  Future<void> _changePreviewSize(PreviewSize size) async {
    if (size != PreviewSize.custom) {
      setState(() => _previewSize = size);
      return;
    }
    final TextEditingController width = TextEditingController(
      text: _customPreviewSize.width.round().toString(),
    );
    final TextEditingController height = TextEditingController(
      text: _customPreviewSize.height.round().toString(),
    );
    try {
      final Size? next = await showDialog<Size>(
        context: context,
        builder:
            (BuildContext dialogContext) => AlertDialog(
              title: const Text('Custom preview size'),
              content: SizedBox(
                width: 320,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: width,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Width'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: height,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Height'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final int? widthValue = int.tryParse(width.text.trim());
                    final int? heightValue = int.tryParse(height.text.trim());
                    if (widthValue == null || heightValue == null) return;
                    Navigator.pop(
                      dialogContext,
                      Size(
                        widthValue.clamp(240, 3000).toDouble(),
                        heightValue.clamp(320, 4000).toDouble(),
                      ),
                    );
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
      );
      if (next != null && mounted) {
        setState(() {
          _customPreviewSize = next;
          _previewSize = PreviewSize.custom;
        });
      }
    } finally {
      width.dispose();
      height.dispose();
    }
  }

  Future<void> _editPage(BuilderPage page) async {
    final TextEditingController nameController = TextEditingController(
      text: page.name,
    );
    final TextEditingController routeController = TextEditingController(
      text: page.route,
    );
    String? error;
    try {
      await showDialog<void>(
        context: context,
        builder:
            (BuildContext dialogContext) => StatefulBuilder(
              builder:
                  (BuildContext context, StateSetter setDialogState) =>
                      AlertDialog(
                        title: Text('Page settings · ${page.name}'),
                        content: SizedBox(
                          width: 360,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              TextField(
                                controller: nameController,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  labelText: 'Name',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: routeController,
                                decoration: const InputDecoration(
                                  labelText: 'Route',
                                  hintText: '/profile',
                                ),
                                onSubmitted: (_) {
                                  final String? result = context
                                      .read<EditorController>()
                                      .updatePageDetails(
                                        pageId: page.id,
                                        name: nameController.text,
                                        route: routeController.text,
                                      );
                                  if (result == null) {
                                    Navigator.pop(dialogContext);
                                  } else {
                                    setDialogState(() => error = result);
                                  }
                                },
                              ),
                              if (error != null) ...<Widget>[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    error!,
                                    style: const TextStyle(
                                      color: Color(0xFFB3261E),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () {
                              final String? result = context
                                  .read<EditorController>()
                                  .updatePageDetails(
                                    pageId: page.id,
                                    name: nameController.text,
                                    route: routeController.text,
                                  );
                              if (result == null) {
                                Navigator.pop(dialogContext);
                              } else {
                                setDialogState(() => error = result);
                              }
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
            ),
      );
    } finally {
      nameController.dispose();
      routeController.dispose();
    }
  }

  Future<void> _deletePage(BuilderPage page) async {
    final bool shouldDelete =
        await showDialog<bool>(
          context: context,
          builder:
              (BuildContext dialogContext) => AlertDialog(
                title: Text('Delete ${page.name}?'),
                content: const Text(
                  'The page and its widget tree will be removed.',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Delete page'),
                  ),
                ],
              ),
        ) ??
        false;
    if (shouldDelete && mounted) {
      context.read<EditorController>().deletePage(page.id);
    }
  }

  Future<void> _openProject() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    final EditorController editor = context.read<EditorController>();
    final XTypeGroup projectType = const XTypeGroup(
      label: 'Local Flutter Builder project',
      extensions: <String>['json'],
      mimeTypes: <String>['application/json'],
      uniformTypeIdentifiers: <String>['public.json'],
    );
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[projectType],
      initialDirectory:
          editor.projectPath == null
              ? null
              : File(editor.projectPath!).parent.path,
      confirmButtonText: 'Open project',
    );
    if (file == null || !mounted) return;
    setState(() {
      _working = true;
      _workingMessage = 'Opening project…';
    });
    try {
      final StoredProject result = await context
          .read<ProjectStore>()
          .openProject(file.path);
      if (mounted) {
        context.read<EditorController>().open(
          result.document,
          result.path,
          isDirty: result.recoveredFromBackup || result.recoveredFromAutosave,
        );
        _lastExportPath = null;
        _lastExportRevision = null;
        unawaited(_loadBundledFonts(result.document.fontAssets, result.path));
        _showMessage(
          result.recoveredFromAutosave
              ? 'Recovered newer edits for ${_fileName(result.path)}'
              : result.recoveredFromBackup
              ? 'Recovered ${_fileName(result.path)} from its backup'
              : 'Opened ${_fileName(result.path)}',
        );
      }
    } catch (error) {
      _showMessage('Could not open project: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _workingMessage = null;
        });
      }
    }
  }

  Future<void> _saveProject() async {
    final EditorController editor = context.read<EditorController>();
    final bool isNewSave = editor.projectPath == null;
    String? path = editor.projectPath;
    if (path == null) {
      final String? folder = await getDirectoryPath(
        confirmButtonText: 'Save in this folder',
        canCreateDirectories: true,
      );
      if (folder == null) return;
      final String fileName =
          '${DartGenerator.packageNameFor(editor.document.name)}.appbuilder.json';
      path =
          '${Directory(folder).absolute.path}${Platform.pathSeparator}$fileName';
    }
    if (!mounted) return;
    final String savePath = path;
    if (isNewSave && await File(savePath).exists()) {
      if (!mounted) return;
      final bool? replace = await showDialog<bool>(
        context: context,
        builder:
            (BuildContext dialogContext) => AlertDialog(
              title: const Text('Project already exists'),
              content: Text(
                'Replace ${_fileName(savePath)} in the selected folder?',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Replace'),
                ),
              ],
            ),
      );
      if (replace != true || !mounted) return;
    }
    _autosaveTimer?.cancel();
    setState(() => _working = true);
    final BuilderDocument snapshot = editor.document;
    final int savedRevision = editor.documentRevision;
    setState(() => _workingMessage = 'Saving project…');
    try {
      final StoredProject savedProject = await context
          .read<ProjectStore>()
          .saveProjectWithDocument(snapshot, savePath);
      if (mounted) {
        editor.markSaved(
          savedProject.path,
          savedRevision: savedRevision,
          savedDocument: savedProject.document,
        );
        _showMessage(
          editor.isDirty
              ? 'Saved. Newer edits still need saving.'
              : 'Project saved locally',
        );
        if (!editor.isDirty) {
          try {
            final Future<void>? pendingAutosave = _autosaveInFlight;
            if (pendingAutosave != null) await pendingAutosave;
            if (!editor.isDirty && mounted) {
              await context.read<ProjectStore>().clearAutosave(
                savedProject.path,
              );
            }
          } catch (error) {
            _showMessage(
              'Project saved, but its recovery copy could not be removed: $error',
              isError: true,
            );
          }
        }
      }
    } catch (error) {
      _showMessage('Could not save project: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _workingMessage = null;
        });
      }
    }
  }

  Future<void> _pickImage(BuilderNode node) async {
    final XTypeGroup imageType = const XTypeGroup(
      label: 'Images',
      extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      mimeTypes: <String>['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
    );
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[imageType],
      confirmButtonText: 'Choose image',
    );
    if (file != null && mounted) {
      context.read<EditorController>().setProperty(
        node.id,
        'source',
        file.path,
      );
    }
  }

  Future<void> _exportFlutterApp() async {
    final EditorController editor = context.read<EditorController>();
    final List<ProjectIssue> issues = await ProjectValidator().validate(
      editor.document,
      projectPath: editor.projectPath,
    );
    final List<ProjectIssue> errors =
        issues.where((ProjectIssue issue) => issue.isError).toList();
    if (errors.isNotEmpty) {
      await _showValidationResults(issues);
      return;
    }
    if (issues.isNotEmpty &&
        !await _showValidationResults(issues, allowContinue: true)) {
      return;
    }
    final String? parentFolder = await getDirectoryPath(
      confirmButtonText: 'Choose parent folder',
      canCreateDirectories: true,
      initialDirectory:
          editor.projectPath == null
              ? null
              : File(editor.projectPath!).parent.path,
    );
    if (parentFolder == null || !mounted) return;
    final BuilderDocument exportDocument = editor.document;
    final int exportRevision = editor.documentRevision;
    final String? projectPath = editor.projectPath;
    final String destination =
        '${Directory(parentFolder).absolute.path}${Platform.pathSeparator}'
        '${DartGenerator.packageNameFor(editor.document.name)}';
    setState(() {
      _working = true;
      _workingMessage = 'Starting Flutter export…';
    });
    try {
      final String generatedPath = await context
          .read<FlutterProjectExporter>()
          .export(
            exportDocument,
            destination,
            projectPath: projectPath,
            onOutput: (String line) {
              if (mounted) setState(() => _workingMessage = line);
            },
          );
      _lastExportPath = generatedPath;
      _lastExportRevision = exportRevision;
      _showMessage('Exported Flutter app to $generatedPath');
    } catch (error) {
      _showMessage('Could not export Flutter app: $error', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _workingMessage = null;
        });
      }
    }
  }

  Future<void> _startToolchainWorkflow() async {
    final EditorController editor = context.read<EditorController>();
    final String? currentExport = _lastExportPath;
    final bool exportIsCurrent =
        currentExport != null &&
        _lastExportRevision == editor.documentRevision &&
        await Directory(currentExport).exists();
    if (!exportIsCurrent) await _exportFlutterApp();
    if (!mounted) return;
    final String? path = _lastExportPath;
    final EditorController latest = context.read<EditorController>();
    if (path == null || _lastExportRevision != latest.documentRevision) return;
    await showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => FlutterToolchainDialog(
            projectPath: path,
            service: context.read<FlutterToolchainService>(),
          ),
    );
  }

  Future<void> _startFlutterRuntimePreview() async {
    if (_working) return;
    final EditorController editor = context.read<EditorController>();
    final BuilderDocument previewDocument = editor.document;
    final String? sourcePath = editor.projectPath;
    Directory? previewDirectory;
    setState(() {
      _working = true;
      _workingMessage = 'Validating Flutter runtime preview…';
    });
    try {
      final List<ProjectIssue> issues = await ProjectValidator().validate(
        previewDocument,
        projectPath: sourcePath,
      );
      if (!mounted) return;
      if (issues.any((ProjectIssue issue) => issue.isError)) {
        setState(() {
          _working = false;
          _workingMessage = null;
        });
        await _showValidationResults(issues);
        return;
      }
      setState(() => _workingMessage = 'Preparing Flutter runtime preview…');
      previewDirectory = await Directory.systemTemp.createTemp(
        'local_flutter_builder_preview_',
      );
      final String destination =
          '${previewDirectory.path}${Platform.pathSeparator}app';
      final String projectPath = await context
          .read<FlutterProjectExporter>()
          .export(
            previewDocument,
            destination,
            projectPath: sourcePath,
            onOutput: (String line) {
              if (mounted) setState(() => _workingMessage = line);
            },
          );
      if (!mounted) return;
      setState(() {
        _working = false;
        _workingMessage = null;
      });
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (BuildContext dialogContext) => FlutterToolchainDialog(
              projectPath: projectPath,
              service: context.read<FlutterToolchainService>(),
              previewMode: true,
            ),
      );
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Could not start Flutter runtime preview: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _workingMessage = null;
        });
      }
      if (previewDirectory != null) {
        try {
          await _removeFlutterRuntimePreview(previewDirectory);
        } catch (error) {
          if (mounted) {
            _showMessage(
              'Could not remove temporary preview files: $error',
              isError: true,
            );
          }
        }
      }
    }
  }

  Future<void> _removeFlutterRuntimePreview(Directory directory) async {
    if (!await directory.exists()) return;
    final String tempPath = Directory.systemTemp.resolveSymbolicLinksSync();
    final String parentPath = directory.parent.resolveSymbolicLinksSync();
    final bool isTempChild =
        Platform.isWindows
            ? parentPath.toLowerCase() == tempPath.toLowerCase()
            : parentPath == tempPath;
    final String folderName = directory.path.split(Platform.pathSeparator).last;
    if (!isTempChild ||
        !folderName.startsWith('local_flutter_builder_preview_')) {
      throw StateError('Preview folder is outside the temporary directory.');
    }
    await directory.delete(recursive: true);
  }

  Future<void> _validateCurrentProject() async {
    final EditorController editor = context.read<EditorController>();
    final List<ProjectIssue> issues = await ProjectValidator().validate(
      editor.document,
      projectPath: editor.projectPath,
    );
    if (!mounted) return;
    await _showValidationResults(issues);
  }

  Future<bool> _showValidationResults(
    List<ProjectIssue> issues, {
    bool allowContinue = false,
  }) async {
    final int errors =
        issues.where((ProjectIssue issue) => issue.isError).length;
    final int warnings = issues.length - errors;
    final bool? continueExport = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: Text(
              errors == 0
                  ? 'Project checks passed'
                  : 'Fix project issues before export',
            ),
            content: SizedBox(
              width: 480,
              height: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('$errors errors · $warnings warnings'),
                  const SizedBox(height: 10),
                  Expanded(
                    child:
                        issues.isEmpty
                            ? const Center(child: Text('No issues found.'))
                            : ListView.separated(
                              itemCount: issues.length,
                              separatorBuilder:
                                  (_, _) => const Divider(height: 1),
                              itemBuilder: (BuildContext context, int index) {
                                final ProjectIssue issue = issues[index];
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    issue.isError
                                        ? Icons.error_outline
                                        : Icons.warning_amber_outlined,
                                    color:
                                        issue.isError
                                            ? const Color(0xFFB3261E)
                                            : const Color(0xFF9A6700),
                                    size: 19,
                                  ),
                                  title: Text(
                                    issue.message,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  subtitle: Text(
                                    <String?>[
                                      issue.pageId,
                                      issue.nodeId,
                                    ].whereType<String>().join(' · '),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  onTap: () {
                                    final EditorController editor =
                                        context.read<EditorController>();
                                    if (issue.pageId != null) {
                                      editor.selectPage(issue.pageId!);
                                    }
                                    if (issue.nodeId != null) {
                                      editor.selectNode(issue.nodeId!);
                                    }
                                    Navigator.pop(dialogContext, false);
                                  },
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(allowContinue ? 'Cancel' : 'Close'),
              ),
              if (allowContinue && errors == 0)
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Export anyway'),
                ),
            ],
          ),
    );
    return continueExport == true;
  }

  Future<bool> _confirmDiscard() async {
    if (!context.read<EditorController>().isDirty) return true;
    final bool? shouldDiscard = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext context) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text(
              'The current design has edits that are not saved.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
    );
    return shouldDiscard ?? false;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? const Color(0xFF9C3535) : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _fileName(String path) =>
      path.split(RegExp(r'[/\\]')).where((String part) => part.isNotEmpty).last;

  void _handleDrop(
    EditorDragData data,
    String targetId,
    BuilderDropPosition position,
  ) {
    final EditorController editor = context.read<EditorController>();
    if (data case ExistingObjectDrag(:final nodeId)) {
      editor.moveObject(nodeId, targetId, position);
    } else if (data case PaletteObjectDrag(:final type)) {
      editor.addObject(type, targetId: targetId, position: position);
    }
  }

  Future<void> _runActions(
    BuilderNode node,
    Map<String, Object?>? recordContext,
  ) async {
    final EditorController editor = context.read<EditorController>();
    final String sourcePageId = editor.activePageId;
    await _executeActions(
      BuilderAction.forNode(node),
      editor: editor,
      sourcePageId: sourcePageId,
      recordContext: recordContext,
    );
  }

  Future<void> _executeActions(
    List<Map<String, Object?>> actions, {
    required EditorController editor,
    required String sourcePageId,
    Map<String, Object?>? recordContext,
    Set<String> functionCallStack = const <String>{},
  }) async {
    for (final Map<String, Object?> action in actions) {
      switch (action['type']) {
        case 'navigate':
          final String route = _resolveActionText(
            action['route'],
            editor,
            recordContext: recordContext,
          );
          if (route.isNotEmpty) {
            editor.navigateToRoute(
              route,
              replace: action['behavior'] == 'replace',
            );
          }
        case 'snackbar':
          final String message = _resolveActionText(
            action['message'],
            editor,
            recordContext: recordContext,
          );
          if (message.isNotEmpty && mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(message),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          }
        case 'dialog':
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder:
                (BuildContext dialogContext) => AlertDialog(
                  title: Text(
                    _resolveActionText(
                      action['title'] ?? 'Notice',
                      editor,
                      recordContext: recordContext,
                    ),
                  ),
                  content: Text(
                    _resolveActionText(
                      action['message'],
                      editor,
                      recordContext: recordContext,
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('OK'),
                    ),
                  ],
                ),
          );
        case 'back':
          editor.previewBack();
        case 'setVariable':
          final String variableId = action['variableId'] as String? ?? '';
          if (variableId.isNotEmpty) {
            final Object? value = action['value'];
            editor.setVariableValue(
              variableId,
              value is String
                  ? _resolveActionText(
                    value,
                    editor,
                    recordContext: recordContext,
                  )
                  : value,
            );
          }
        case 'incrementVariable':
          final String variableId = action['variableId'] as String? ?? '';
          final Object? rawAmount = action['amount'];
          final double amount =
              rawAmount is num
                  ? rawAmount.toDouble()
                  : double.tryParse(rawAmount?.toString() ?? '') ?? 1;
          if (variableId.isNotEmpty) {
            editor.incrementVariable(variableId, amount: amount);
          }
        case 'toggleVariable':
          final String variableId = action['variableId'] as String? ?? '';
          if (variableId.isNotEmpty) editor.toggleVariable(variableId);
        case 'updateWidget':
          final String targetPageId =
              action['targetPageId'] as String? ?? sourcePageId;
          final String targetNodeId = action['targetNodeId'] as String? ?? '';
          final String property = action['property'] as String? ?? 'visible';
          if (targetNodeId.isNotEmpty) {
            editor.setWidgetRuntimeProperty(
              targetPageId,
              targetNodeId,
              property,
              action['value'] is String &&
                      <String>{
                        'text',
                        'label',
                        'initialValue',
                      }.contains(property)
                  ? _resolveActionText(
                    action['value'],
                    editor,
                    recordContext: recordContext,
                  )
                  : action['value'],
            );
          }
        case 'conditional':
          final bool matches = _conditionMatches(
            action,
            editor,
            recordContext: recordContext,
          );
          await _executeActions(
            _actionMaps(action[matches ? 'thenActions' : 'elseActions']),
            editor: editor,
            sourcePageId: sourcePageId,
            recordContext: recordContext,
            functionCallStack: functionCallStack,
          );
        case 'loop':
          final int iterations =
              _integerValue(action['iterations'], 1).clamp(1, 1000).toInt();
          for (int index = 0; index < iterations; index++) {
            await _executeActions(
              _actionMaps(action['actions']),
              editor: editor,
              sourcePageId: sourcePageId,
              recordContext: recordContext,
              functionCallStack: functionCallStack,
            );
          }
        case 'httpRequest':
          await _runHttpAction(
            action,
            editor,
            recordContext: recordContext,
          );
        case 'databaseInsert':
          final String collectionId = action['collectionId'] as String? ?? '';
          if (!editor.document.databaseCollections.any(
            (BuilderDatabaseCollection item) => item.id == collectionId,
          )) {
            _showActionError('Choose a database collection for this action.');
            break;
          }
          try {
            final Object? decoded = jsonDecode(
              action['record']?.toString() ?? '{}',
            );
            if (decoded is! Map) {
              throw const FormatException('Record must be a JSON object.');
            }
            editor.insertDatabaseRecord(
              collectionId,
              Map<String, Object?>.from(
                _resolveActionJsonValue(decoded, editor, recordContext)
                    as Map,
              ),
            );
          } catch (error) {
            _showActionError('Could not save database record: $error');
          }
        case 'databaseUpdate':
          final String collectionId = action['collectionId'] as String? ?? '';
          final String recordId = _resolveActionText(
            action['recordId'],
            editor,
            recordContext: recordContext,
          );
          if (!editor.document.databaseCollections.any(
            (BuilderDatabaseCollection item) => item.id == collectionId,
          )) {
            _showActionError('Choose a database collection for this action.');
            break;
          }
          try {
            final Object? decoded = jsonDecode(
              action['record']?.toString() ?? '{}',
            );
            if (decoded is! Map) {
              throw const FormatException('Update must be a JSON object.');
            }
            final Map<String, Object?> values = Map<String, Object?>.from(
              _resolveActionJsonValue(decoded, editor, recordContext) as Map,
            );
            values.remove('_id');
            if (!editor.updateDatabaseRecord(collectionId, recordId, values)) {
              _showActionError('Database record $recordId was not found.');
            }
          } catch (error) {
            _showActionError('Could not update database record: $error');
          }
        case 'databaseQuery':
          final String collectionId = action['collectionId'] as String? ?? '';
          final String variableId = action['resultVariableId'] as String? ?? '';
          if (!editor.document.databaseCollections.any(
            (BuilderDatabaseCollection item) => item.id == collectionId,
          )) {
            _showActionError('Choose a database collection for this action.');
            break;
          }
          if (!editor.document.variables.any(
            (BuilderVariable variable) =>
                variable.id == variableId && variable.type == 'json',
          )) {
            _showActionError('Choose a JSON variable for loaded records.');
            break;
          }
          final BuilderDatabaseCollection collection = editor
              .document
              .databaseCollections
              .firstWhere(
                (BuilderDatabaseCollection item) => item.id == collectionId,
              );
          final Map<String, BuilderDatabaseCollection> collectionsById =
              <String, BuilderDatabaseCollection>{
                for (final BuilderDatabaseCollection item
                    in editor.document.databaseCollections)
                  item.id: item,
              };
          final List<Map<String, Object?>> queryJoins =
              resolveDatabaseQueryJoins(
                rootCollectionId: collectionId,
                relationships: editor.document.databaseRelationships,
                collectionsById: collectionsById,
                configuredJoins: action['joins'],
              );
          final List<Map<String, Object?>> filters = <Map<String, Object?>>[];
          for (final Map<String, Object?> configuredFilter in _actionMaps(
            action['filters'],
          )) {
            final String relationshipId =
                configuredFilter['relationshipId'] as String? ?? '';
            final Map<String, Object?>? join = _firstOrNull(
              queryJoins.where(
                (Map<String, Object?> item) =>
                    item['relationshipId'] == relationshipId,
              ),
            );
            final BuilderDatabaseCollection targetCollection =
                join == null
                    ? collection
                    : collectionsById[join['relatedCollectionId']] ??
                        collection;
            final String fieldId = configuredFilter['fieldId'] as String? ?? '';
            final BuilderDatabaseField? field = _firstOrNull(
              targetCollection.fields.where(
                (BuilderDatabaseField item) => item.id == fieldId,
              ),
            );
            if (field == null) continue;
            filters.add(<String, Object?>{
              'field': field.id,
              'type': field.type,
              'joinAlias': join?['alias'] ?? '',
              'operator': configuredFilter['operator'] ?? 'equals',
              'value': _resolveActionText(
                configuredFilter['value'],
                editor,
                recordContext: recordContext,
              ),
            });
          }
          final String sortRelationshipId =
              action['sortRelationshipId'] as String? ?? '';
          final Map<String, Object?>? sortJoin = _firstOrNull(
            queryJoins.where(
              (Map<String, Object?> item) =>
                  item['relationshipId'] == sortRelationshipId,
            ),
          );
          final BuilderDatabaseCollection sortCollection =
              sortJoin == null
                  ? collection
                  : collectionsById[sortJoin['relatedCollectionId']] ??
                      collection;
          final String sortFieldId = action['sortFieldId'] as String? ?? '';
          final String? sortField =
              _firstOrNull(
                sortCollection.fields.where(
                  (BuilderDatabaseField item) => item.id == sortFieldId,
                ),
              )?.id;
          editor.setVariableValue(
            variableId,
            editor.queryDatabaseRecords(
              collectionId,
              joins: queryJoins,
              filters: filters,
              matchAny: action['filterMode'] == 'any',
              sortField: sortField,
              sortAlias: sortJoin?['alias'] as String?,
              sortAggregate: action['sortAggregate'] == 'max' ? 'max' : 'min',
              descending: action['sortDescending'] == true,
              limit: _integerValue(action['limit'], 0).clamp(0, 100000).toInt(),
            ),
          );
        case 'databaseDelete':
          final String collectionId = action['collectionId'] as String? ?? '';
          final String recordId = _resolveActionText(
            action['recordId'],
            editor,
            recordContext: recordContext,
          );
          if (!editor.deleteDatabaseRecord(collectionId, recordId)) {
            _showActionError('Database record $recordId was not found.');
          }
        case 'customFunction':
          final String functionId = action['functionId'] as String? ?? '';
          BuilderCustomFunction? function;
          for (final BuilderCustomFunction candidate
              in editor.document.customFunctions) {
            if (candidate.id == functionId) function = candidate;
          }
          if (function == null) {
            _showActionError(
              functionId.isEmpty
                  ? 'Choose a custom function for this action.'
                  : 'The selected custom function could not be found.',
            );
            break;
          }
          if (functionCallStack.contains(functionId)) {
            _showActionError('Custom function calls cannot be recursive.');
            break;
          }
          if (function.body.trim().isNotEmpty) {
            try {
              final CustomFunctionPreviewResult result =
                  await CustomFunctionPreviewRunner.run(
                    body: function.body,
                    variables: editor.document.variables,
                    appState: editor.appVariableValues,
                    dataStructures: editor.document.customDataStructures,
                  );
              if (!mounted) return;
              for (final MapEntry<String, Object?> entry
                  in result.appState.entries) {
                editor.setVariableValue(entry.key, entry.value);
              }
              for (final Map<String, Object?> effect in result.effects) {
                final String value = effect['value'] as String? ?? '';
                switch (effect['type']) {
                  case 'message':
                    if (value.isNotEmpty) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(value),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                    }
                  case 'navigate':
                    if (value.isNotEmpty) editor.navigateToRoute(value);
                  case 'back':
                    editor.previewBack();
                  case 'log':
                    debugPrint('[Custom function] $value');
                }
              }
            } catch (error) {
              _showActionError(
                'Custom function preview failed: $error. Use Flutter runtime preview for Material APIs.',
              );
            }
            break;
          }
          await _executeActions(
            function.actions,
            editor: editor,
            sourcePageId: sourcePageId,
            recordContext: recordContext,
            functionCallStack: <String>{...functionCallStack, functionId},
          );
      }
    }
  }

  bool _conditionMatches(
    Map<String, Object?> action,
    EditorController editor, {
    Map<String, Object?>? recordContext,
  }) {
    final String variableId = action['variableId'] as String? ?? '';
    final Object? actual = editor.appVariableValues[variableId];
    final String operator = action['operator'] as String? ?? 'equals';
    final String expected = _resolveActionText(
      action['value'],
      editor,
      recordContext: recordContext,
    );
    if (actual is num && <String>{'equals', 'notEquals'}.contains(operator)) {
      final double? number = double.tryParse(expected);
      return number != null &&
          (operator == 'notEquals'
              ? actual.toDouble() != number
              : actual.toDouble() == number);
    }
    if (actual is bool && <String>{'equals', 'notEquals'}.contains(operator)) {
      final bool equal = actual == (expected.trim().toLowerCase() == 'true');
      return operator == 'notEquals' ? !equal : equal;
    }
    switch (operator) {
      case 'isTrue':
        return actual == true;
      case 'isFalse':
        return actual == false;
      case 'notEquals':
        return actual?.toString() != expected;
      case 'greaterThan':
        final double? left = actual is num ? actual.toDouble() : null;
        final double? right = double.tryParse(expected);
        return left != null && right != null && left > right;
      case 'lessThan':
        final double? left = actual is num ? actual.toDouble() : null;
        final double? right = double.tryParse(expected);
        return left != null && right != null && left < right;
      case 'contains':
        return actual is String
            ? actual.contains(expected)
            : actual is List && actual.contains(expected);
      default:
        return actual?.toString() == expected;
    }
  }

  Future<void> _runHttpAction(
    Map<String, Object?> action,
    EditorController editor, {
    Map<String, Object?>? recordContext,
  }) async {
    final String url = _resolveActionText(
      action['url'],
      editor,
      recordContext: recordContext,
    ).trim();
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !<String>{'http', 'https'}.contains(uri.scheme)) {
      _showActionError('Enter a valid HTTP or HTTPS URL.');
      return;
    }
    final String method =
        <String>{
              'GET',
              'POST',
              'PUT',
              'PATCH',
              'DELETE',
            }.contains(action['method'])
            ? action['method']! as String
            : 'GET';
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 30));
      final Object? rawHeaders = action['headers'];
      Object? headers = rawHeaders;
      if (headers is String) {
        try {
          headers = jsonDecode(headers);
        } on FormatException {
          headers = null;
        }
      }
      if (headers is Map) {
        for (final MapEntry<Object?, Object?> header in headers.entries) {
          request.headers.set(
            header.key.toString(),
            _resolveActionText(
              header.value,
              editor,
              recordContext: recordContext,
            ),
          );
        }
      }
      final String body = _resolveActionText(
        action['body'],
        editor,
        recordContext: recordContext,
      );
      if (body.isNotEmpty) request.write(body);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final String responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 30));
      final String responseVariableId =
          action['responseVariableId'] as String? ?? '';
      if (responseVariableId.isNotEmpty) {
        editor.setVariableValue(
          responseVariableId,
          _parseHttpResponse(responseBody, responseVariableId, editor),
        );
      }
      if (response.statusCode >= 400) {
        _showActionError('HTTP request returned ${response.statusCode}.');
      }
    } catch (error) {
      _showActionError('Request failed: $error');
    } finally {
      client.close(force: true);
    }
  }

  Object _parseHttpResponse(
    String body,
    String variableId,
    EditorController editor,
  ) {
    BuilderVariable? variable;
    for (final BuilderVariable candidate in editor.document.variables) {
      if (candidate.id == variableId) variable = candidate;
    }
    if (variable == null) return body;
    switch (variable.type) {
      case 'number':
      case 'double':
        return double.tryParse(body) ?? variable.initialValue;
      case 'integer':
        return int.tryParse(body) ?? variable.initialValue;
      case 'boolean':
        return body.trim().toLowerCase() == 'true';
      case 'json':
        try {
          return (jsonDecode(body) as Object?) ?? body;
        } on FormatException {
          return body;
        }
      case 'stringList':
        try {
          final Object? value = jsonDecode(body);
          return value is List
              ? value.map((Object? item) => item.toString()).toList()
              : <String>[];
        } on FormatException {
          return <String>[];
        }
      default:
        return body;
    }
  }

  String _resolveActionText(
    Object? raw,
    EditorController editor, {
    Map<String, Object?>? recordContext,
  }) {
    final String template = raw?.toString() ?? '';
    final RegExp token = RegExp(r'\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)');
    return template.replaceAllMapped(token, (Match match) {
      final String key = (match[1] ?? match[2] ?? '').trim();
      if (key.startsWith('record.') && recordContext != null) {
        final String field = key.substring('record.'.length);
        return recordContext[field]?.toString() ?? '';
      }
      BuilderVariable? variable;
      for (final BuilderVariable candidate in editor.document.variables) {
        if (candidate.id == key || candidate.name == key) variable = candidate;
      }
      return variable == null
          ? match[0]!
          : editor.appVariableValues[variable.id]?.toString() ?? '';
    });
  }

  Object? _resolveActionJsonValue(
    Object? value,
    EditorController editor,
    Map<String, Object?>? recordContext,
  ) {
    if (value is String) {
      return _resolveActionText(
        value,
        editor,
        recordContext: recordContext,
      );
    }
    if (value is List) {
      return value
          .map(
            (Object? item) =>
                _resolveActionJsonValue(item, editor, recordContext),
          )
          .toList();
    }
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          entry.key.toString(): _resolveActionJsonValue(
            entry.value,
            editor,
            recordContext,
          ),
      };
    }
    return value;
  }

  List<Map<String, Object?>> _actionMaps(Object? raw) =>
      raw is List
          ? raw
              .whereType<Map<Object?, Object?>>()
              .map(
                (Map<Object?, Object?> item) => <String, Object?>{
                  for (final MapEntry<Object?, Object?> entry in item.entries)
                    entry.key.toString(): entry.value,
                },
              )
              .toList()
          : <Map<String, Object?>>[];

  int _integerValue(Object? raw, int fallback) =>
      raw is num
          ? raw.round()
          : int.tryParse(raw?.toString() ?? '') ?? fallback;

  void _showActionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _manageVariables() async {
    final EditorController editor = context.read<EditorController>();
    await showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              Future<void> editVariable([BuilderVariable? existing]) async {
                final (String, String, Object)? draft = await _variableDraft(
                  existing,
                );
                if (draft == null) return;
                if (existing == null) {
                  editor.addVariable(
                    name: draft.$1,
                    type: draft.$2,
                    initialValue: draft.$3,
                  );
                } else {
                  editor.updateVariable(
                    existing.id,
                    name: draft.$1,
                    type: draft.$2,
                    initialValue: draft.$3,
                  );
                }
                setDialogState(() {});
              }

              return AlertDialog(
                title: const Text('App variables'),
                content: SizedBox(
                  width: 460,
                  child:
                      editor.document.variables.isEmpty
                          ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'Create typed app state here, then use it in widget bindings and actions.',
                            ),
                          )
                          : ListView.separated(
                            shrinkWrap: true,
                            itemCount: editor.document.variables.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final BuilderVariable variable =
                                  editor.document.variables[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(switch (variable.type) {
                                  'number' ||
                                  'integer' ||
                                  'double' => Icons.numbers,
                                  'boolean' => Icons.toggle_on_outlined,
                                  'stringList' || 'json' => Icons.data_object,
                                  _ => Icons.text_fields,
                                }),
                                title: Text(variable.name),
                                subtitle: Text(
                                  '${variable.type} · initial ${variable.initialValue}',
                                ),
                                onTap: () => editVariable(variable),
                                trailing: IconButton(
                                  tooltip: 'Delete variable',
                                  onPressed: () {
                                    editor.deleteVariable(variable.id);
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              );
                            },
                          ),
                ),
                actions: <Widget>[
                  TextButton.icon(
                    onPressed: () => editVariable(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add variable'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _manageCustomDataStructures() async {
    final EditorController editor = context.read<EditorController>();
    await showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              Future<void> editStructure([
                BuilderCustomDataStructure? existing,
              ]) async {
                final BuilderCustomDataStructure? saved =
                    await showDialog<BuilderCustomDataStructure>(
                      context: context,
                      builder:
                          (_) => CustomDataStructureDialog(
                            structures: editor.document.customDataStructures,
                            structure: existing,
                          ),
                    );
                if (saved == null) return;
                editor.setCustomDataStructures(<BuilderCustomDataStructure>[
                  ...editor.document.customDataStructures.where(
                    (BuilderCustomDataStructure item) => item.id != saved.id,
                  ),
                  saved,
                ]);
                setDialogState(() {});
              }

              return AlertDialog(
                title: const Text('Custom data structures'),
                content: SizedBox(
                  width: 500,
                  height: 360,
                  child:
                      editor.document.customDataStructures.isEmpty
                          ? const Center(
                            child: Text(
                              'Create Dart classes, enums, or typedefs to use in custom functions and exported apps.',
                              textAlign: TextAlign.center,
                            ),
                          )
                          : ListView.separated(
                            itemCount:
                                editor.document.customDataStructures.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final BuilderCustomDataStructure structure =
                                  editor.document.customDataStructures[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.data_object_outlined),
                                title: Text(structure.name),
                                subtitle: Text(
                                  structure.body.split('\n').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => editStructure(structure),
                                trailing: IconButton(
                                  tooltip: 'Delete data type',
                                  onPressed: () {
                                    editor.setCustomDataStructures(
                                      editor.document.customDataStructures
                                          .where(
                                            (BuilderCustomDataStructure item) =>
                                                item.id != structure.id,
                                          )
                                          .toList(),
                                    );
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              );
                            },
                          ),
                ),
                actions: <Widget>[
                  TextButton.icon(
                    onPressed: () => editStructure(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add data type'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _manageDatabase() async {
    final EditorController editor = context.read<EditorController>();
    String activeTab = 'collections';
    await showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              Future<void> editCollection([
                BuilderDatabaseCollection? existing,
              ]) async {
                final ({
                  String name,
                  List<BuilderDatabaseField> fields,
                  List<Map<String, Object?>> seedRecords,
                })?
                draft = await _databaseCollectionDraft(existing);
                if (draft == null) return;
                final List<BuilderDatabaseCollection> current =
                    editor.document.databaseCollections;
                if (existing == null) {
                  int suffix = 1;
                  final Set<String> ids =
                      current
                          .map((BuilderDatabaseCollection item) => item.id)
                          .toSet();
                  while (ids.contains('db_collection_$suffix')) {
                    suffix++;
                  }
                  editor.setDatabaseCollections(<BuilderDatabaseCollection>[
                    ...current,
                    BuilderDatabaseCollection(
                      id: 'db_collection_$suffix',
                      name: draft.name,
                      fields: draft.fields,
                      seedRecords: draft.seedRecords,
                    ),
                  ]);
                } else {
                  editor.setDatabaseCollections(<BuilderDatabaseCollection>[
                    for (final BuilderDatabaseCollection item in current)
                      item.id == existing.id
                          ? item.copyWith(
                            name: draft.name,
                            fields: draft.fields,
                            seedRecords: draft.seedRecords,
                          )
                          : item,
                  ]);
                }
                setDialogState(() {});
              }

              Future<void> editRelationship([
                BuilderDatabaseRelationship? existing,
              ]) async {
                if (editor.document.databaseCollections.isEmpty) return;
                final Set<String> ids =
                    editor.document.databaseRelationships
                        .map((BuilderDatabaseRelationship item) => item.id)
                        .toSet();
                var suffix = 1;
                while (ids.contains('db_relationship_$suffix')) {
                  suffix++;
                }
                final BuilderDatabaseRelationship? draft =
                    await _databaseRelationshipDraft(
                      editor.document.databaseCollections,
                      existing,
                      existing?.id ?? 'db_relationship_$suffix',
                    );
                if (draft == null) return;
                final List<BuilderDatabaseRelationship> current =
                    editor.document.databaseRelationships;
                editor.setDatabaseRelationships(<BuilderDatabaseRelationship>[
                  for (final BuilderDatabaseRelationship item in current)
                    if (item.id != existing?.id) item,
                  draft,
                ]);
                setDialogState(() {});
              }

              return AlertDialog(
                title: const Text('Local database model'),
                content: SizedBox(
                  width: 650,
                  height: 470,
                  child: Column(
                    children: <Widget>[
                      SegmentedButton<String>(
                        segments: const <ButtonSegment<String>>[
                          ButtonSegment<String>(
                            value: 'collections',
                            icon: Icon(Icons.table_chart_outlined),
                            label: Text('Collections'),
                          ),
                          ButtonSegment<String>(
                            value: 'relationships',
                            icon: Icon(Icons.account_tree_outlined),
                            label: Text('Relationships'),
                          ),
                        ],
                        selected: <String>{activeTab},
                        onSelectionChanged: (Set<String> selection) {
                          setDialogState(() => activeTab = selection.single);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child:
                            activeTab == 'collections'
                                ? editor.document.databaseCollections.isEmpty
                                    ? const Center(
                                      child: Text(
                                        'Create collections, define their fields, and add starter records. Relationships connect a foreign-key field to a unique field in another collection.',
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                    : ListView.separated(
                                      itemCount:
                                          editor
                                              .document
                                              .databaseCollections
                                              .length,
                                      separatorBuilder:
                                          (_, __) => const Divider(height: 1),
                                      itemBuilder: (
                                        BuildContext context,
                                        int index,
                                      ) {
                                        final BuilderDatabaseCollection
                                        collection =
                                            editor
                                                .document
                                                .databaseCollections[index];
                                        final int relationCount =
                                            editor
                                                .document
                                                .databaseRelationships
                                                .where(
                                                  (
                                                    BuilderDatabaseRelationship
                                                    relationship,
                                                  ) =>
                                                      relationship
                                                              .fromCollectionId ==
                                                          collection.id ||
                                                      relationship
                                                              .toCollectionId ==
                                                          collection.id,
                                                )
                                                .length;
                                        return ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: const Icon(
                                            Icons.storage_outlined,
                                          ),
                                          title: Text(collection.name),
                                          subtitle: Text(
                                            '${collection.fields.length} fields · ${collection.seedRecords.length} starter records · $relationCount relationships',
                                          ),
                                          onTap:
                                              () => editCollection(collection),
                                          trailing: IconButton(
                                            tooltip: 'Delete collection',
                                            onPressed: () {
                                              editor.setDatabaseCollections(
                                                editor
                                                    .document
                                                    .databaseCollections
                                                    .where(
                                                      (
                                                        BuilderDatabaseCollection
                                                        item,
                                                      ) =>
                                                          item.id !=
                                                          collection.id,
                                                    )
                                                    .toList(),
                                              );
                                              setDialogState(() {});
                                            },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                : editor.document.databaseRelationships.isEmpty
                                ? const Center(
                                  child: Text(
                                    'No relationships yet. Add fields to your collections, then connect a foreign-key field to a primary-key or unique field.',
                                    textAlign: TextAlign.center,
                                  ),
                                )
                                : ListView.separated(
                                  itemCount:
                                      editor
                                          .document
                                          .databaseRelationships
                                          .length,
                                  separatorBuilder:
                                      (_, __) => const Divider(height: 1),
                                  itemBuilder: (
                                    BuildContext context,
                                    int index,
                                  ) {
                                    final BuilderDatabaseRelationship
                                    relationship =
                                        editor
                                            .document
                                            .databaseRelationships[index];
                                    final BuilderDatabaseCollection?
                                    from = _firstOrNull(
                                      editor.document.databaseCollections.where(
                                        (BuilderDatabaseCollection item) =>
                                            item.id ==
                                            relationship.fromCollectionId,
                                      ),
                                    );
                                    final BuilderDatabaseCollection?
                                    to = _firstOrNull(
                                      editor.document.databaseCollections.where(
                                        (BuilderDatabaseCollection item) =>
                                            item.id ==
                                            relationship.toCollectionId,
                                      ),
                                    );
                                    final BuilderDatabaseField? fromField =
                                        from == null
                                            ? null
                                            : _firstOrNull(
                                              from.fields.where(
                                                (BuilderDatabaseField item) =>
                                                    item.id ==
                                                    relationship.fromFieldId,
                                              ),
                                            );
                                    final BuilderDatabaseField? toField =
                                        to == null
                                            ? null
                                            : _firstOrNull(
                                              to.fields.where(
                                                (BuilderDatabaseField item) =>
                                                    item.id ==
                                                    relationship.toFieldId,
                                              ),
                                            );
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.account_tree_outlined,
                                      ),
                                      title: Text(relationship.name),
                                      subtitle: Text(
                                        '${from?.name ?? relationship.fromCollectionId}.${fromField?.name ?? relationship.fromFieldId} → ${to?.name ?? relationship.toCollectionId}.${toField?.name ?? relationship.toFieldId} · ${fromField?.unique == true || fromField?.primaryKey == true ? 'one-to-one' : 'many-to-one'}',
                                      ),
                                      onTap:
                                          () => editRelationship(relationship),
                                      trailing: IconButton(
                                        tooltip: 'Delete relationship',
                                        onPressed: () {
                                          editor.setDatabaseRelationships(
                                            editor
                                                .document
                                                .databaseRelationships
                                                .where(
                                                  (
                                                    BuilderDatabaseRelationship
                                                    item,
                                                  ) =>
                                                      item.id !=
                                                      relationship.id,
                                                )
                                                .toList(),
                                          );
                                          setDialogState(() {});
                                        },
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton.icon(
                    onPressed: () => editCollection(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add collection'),
                  ),
                  TextButton.icon(
                    onPressed:
                        editor.document.databaseCollections.isEmpty
                            ? null
                            : () => editRelationship(),
                    icon: const Icon(Icons.add_link),
                    label: const Text('Add relationship'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<
    ({
      String name,
      List<BuilderDatabaseField> fields,
      List<Map<String, Object?>> seedRecords,
    })?
  >
  _databaseCollectionDraft(BuilderDatabaseCollection? existing) {
    String name = existing?.name ?? '';
    String fieldsText = const JsonEncoder.withIndent('  ').convert(
      existing?.fields
              .map((BuilderDatabaseField field) => field.toJson())
              .toList() ??
          <Map<String, Object?>>[
            <String, Object?>{
              'id': 'id',
              'name': 'ID',
              'type': 'integer',
              'required': true,
              'primaryKey': true,
              'unique': true,
            },
          ],
    );
    String seedText = const JsonEncoder.withIndent(
      '  ',
    ).convert(existing?.seedRecords ?? <Map<String, Object?>>[]);
    return showDialog<
      ({
        String name,
        List<BuilderDatabaseField> fields,
        List<Map<String, Object?>> seedRecords,
      })
    >(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              String? error;
              List<BuilderDatabaseField> fields = <BuilderDatabaseField>[];
              List<Map<String, Object?>> records = <Map<String, Object?>>[];
              if (name.trim().isEmpty) {
                error = 'Enter a collection name.';
              } else if (context
                  .read<EditorController>()
                  .document
                  .databaseCollections
                  .any(
                    (BuilderDatabaseCollection item) =>
                        item.id != existing?.id &&
                        item.name.toLowerCase() == name.trim().toLowerCase(),
                  )) {
                error = 'A collection with this name already exists.';
              }
              try {
                final Object? decoded = jsonDecode(fieldsText);
                if (decoded is! List ||
                    decoded.any((Object? item) => item is! Map)) {
                  error ??= 'Fields must be a JSON array of field objects.';
                } else {
                  fields =
                      decoded
                          .map(
                            (Object? item) => BuilderDatabaseField.fromJson(
                              Map<String, Object?>.from(item! as Map),
                            ),
                          )
                          .toList();
                }
              } on FormatException catch (exception) {
                error ??= exception.message;
              }
              try {
                final Object? decoded = jsonDecode(seedText);
                if (decoded is! List<Object?> ||
                    decoded.any(
                      (Object? item) => item is! Map<String, Object?>,
                    )) {
                  error ??= 'Starter records must be a JSON array of objects.';
                } else {
                  records =
                      decoded
                          .map(
                            (Object? item) => Map<String, Object?>.from(
                              item! as Map<String, Object?>,
                            ),
                          )
                          .toList();
                }
              } on FormatException {
                error ??= 'Enter valid JSON starter records.';
              }
              return AlertDialog(
                title: Text(
                  existing == null ? 'Add collection' : 'Edit collection',
                ),
                content: SizedBox(
                  width: 540,
                  height: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextFormField(
                          initialValue: name,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Collection name',
                          ),
                          onChanged:
                              (String value) =>
                                  setDialogState(() => name = value),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: fieldsText,
                          minLines: 7,
                          maxLines: 10,
                          decoration: const InputDecoration(
                            labelText: 'Fields (JSON array)',
                            hintText:
                                '[{"id":"id","name":"ID","type":"integer","primaryKey":true}]',
                            helperText:
                                'Use each field id as a JSON record key. Types: string, integer, number, boolean, date, json. Mark referenced keys primaryKey or unique.',
                            border: OutlineInputBorder(),
                          ),
                          onChanged:
                              (String value) =>
                                  setDialogState(() => fieldsText = value),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: seedText,
                          minLines: 5,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Starter records (JSON array)',
                            hintText: '[{"title":"First item"}]',
                            border: OutlineInputBorder(),
                          ),
                          onChanged:
                              (String value) =>
                                  setDialogState(() => seedText = value),
                        ),
                        if (error != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            error,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        error == null
                            ? () => Navigator.pop(dialogContext, (
                              name: name.trim(),
                              fields: fields,
                              seedRecords: records,
                            ))
                            : null,
                    child: const Text('Save collection'),
                  ),
                ],
              );
            },
          ),
    );
  }

  T? _firstOrNull<T>(Iterable<T> values) {
    final Iterator<T> iterator = values.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  Future<BuilderDatabaseRelationship?> _databaseRelationshipDraft(
    List<BuilderDatabaseCollection> collections,
    BuilderDatabaseRelationship? existing,
    String relationshipId,
  ) {
    String name = existing?.name ?? '';
    String? fromCollectionId =
        existing?.fromCollectionId ?? collections.first.id;
    String? toCollectionId =
        existing?.toCollectionId ??
        (collections.length > 1 ? collections[1].id : collections.first.id);
    String? fromFieldId = existing?.fromFieldId;
    String? toFieldId = existing?.toFieldId;
    return showDialog<BuilderDatabaseRelationship>(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              final BuilderDatabaseCollection? from = _firstOrNull(
                collections.where(
                  (BuilderDatabaseCollection item) =>
                      item.id == fromCollectionId,
                ),
              );
              final BuilderDatabaseCollection? to = _firstOrNull(
                collections.where(
                  (BuilderDatabaseCollection item) => item.id == toCollectionId,
                ),
              );
              final List<BuilderDatabaseField> targetFields =
                  to?.fields
                      .where(
                        (BuilderDatabaseField field) =>
                            field.primaryKey || field.unique,
                      )
                      .toList() ??
                  <BuilderDatabaseField>[];
              final BuilderDatabaseField? fromField =
                  from == null
                      ? null
                      : _firstOrNull(
                        from.fields.where(
                          (BuilderDatabaseField field) =>
                              field.id == fromFieldId,
                        ),
                      );
              final BuilderDatabaseField? toField = _firstOrNull(
                targetFields.where(
                  (BuilderDatabaseField field) => field.id == toFieldId,
                ),
              );
              String? error;
              if (name.trim().isEmpty) {
                error = 'Enter a relationship name.';
              } else if (fromField == null) {
                error = 'Choose a foreign-key field in the child collection.';
              } else if (toField == null) {
                error =
                    'Choose a primary-key or unique field in the parent collection.';
              } else if (fromField.type != toField.type) {
                error =
                    'The foreign-key and target fields must have the same type.';
              } else if (context
                  .read<EditorController>()
                  .document
                  .databaseRelationships
                  .any(
                    (BuilderDatabaseRelationship item) =>
                        item.id != existing?.id &&
                        item.fromCollectionId == fromCollectionId &&
                        item.fromFieldId == fromFieldId &&
                        item.toCollectionId == toCollectionId &&
                        item.toFieldId == toFieldId,
                  )) {
                error = 'This field relationship already exists.';
              }
              return AlertDialog(
                title: Text(
                  existing == null ? 'Add relationship' : 'Edit relationship',
                ),
                content: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextFormField(
                        initialValue: name,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Relationship name',
                          hintText: 'orders.customer',
                        ),
                        onChanged:
                            (String value) =>
                                setDialogState(() => name = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('child-$fromCollectionId'),
                        initialValue:
                            collections.any(
                                  (BuilderDatabaseCollection item) =>
                                      item.id == fromCollectionId,
                                )
                                ? fromCollectionId
                                : null,
                        decoration: const InputDecoration(
                          labelText: 'Child collection (holds the foreign key)',
                        ),
                        items:
                            collections
                                .map(
                                  (BuilderDatabaseCollection item) =>
                                      DropdownMenuItem<String>(
                                        value: item.id,
                                        child: Text(item.name),
                                      ),
                                )
                                .toList(),
                        onChanged: (String? value) {
                          setDialogState(() {
                            fromCollectionId = value;
                            fromFieldId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('child-$fromCollectionId'),
                        initialValue:
                            from?.fields.any(
                                      (BuilderDatabaseField item) =>
                                          item.id == fromFieldId,
                                    ) ==
                                    true
                                ? fromFieldId
                                : null,
                        decoration: const InputDecoration(
                          labelText: 'Foreign-key field',
                        ),
                        items:
                            from?.fields
                                .map(
                                  (
                                    BuilderDatabaseField item,
                                  ) => DropdownMenuItem<String>(
                                    value: item.id,
                                    child: Text(
                                      '${item.name} · ${item.id} (${item.type})',
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (String? value) =>
                                setDialogState(() => fromFieldId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue:
                            collections.any(
                                  (BuilderDatabaseCollection item) =>
                                      item.id == toCollectionId,
                                )
                                ? toCollectionId
                                : null,
                        decoration: const InputDecoration(
                          labelText: 'Parent collection',
                        ),
                        items:
                            collections
                                .map(
                                  (BuilderDatabaseCollection item) =>
                                      DropdownMenuItem<String>(
                                        value: item.id,
                                        child: Text(item.name),
                                      ),
                                )
                                .toList(),
                        onChanged: (String? value) {
                          setDialogState(() {
                            toCollectionId = value;
                            toFieldId = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('target-$toCollectionId'),
                        initialValue:
                            targetFields.any(
                                  (BuilderDatabaseField item) =>
                                      item.id == toFieldId,
                                )
                                ? toFieldId
                                : null,
                        decoration: const InputDecoration(
                          labelText: 'Referenced key (primary or unique)',
                        ),
                        items:
                            targetFields
                                .map(
                                  (
                                    BuilderDatabaseField item,
                                  ) => DropdownMenuItem<String>(
                                    value: item.id,
                                    child: Text(
                                      '${item.name} · ${item.id} (${item.type})',
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (String? value) =>
                                setDialogState(() => toFieldId = value),
                      ),
                      if (targetFields.isEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        const Text(
                          'The parent collection needs a primary-key or unique field.',
                        ),
                      ],
                      if (error != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(error, style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        error == null
                            ? () => Navigator.pop(
                              dialogContext,
                              BuilderDatabaseRelationship(
                                id: relationshipId,
                                name: name.trim(),
                                fromCollectionId: fromCollectionId!,
                                fromFieldId: fromFieldId!,
                                toCollectionId: toCollectionId!,
                                toFieldId: toFieldId!,
                              ),
                            )
                            : null,
                    child: const Text('Save relationship'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _createComponentGroup(BuilderNode node) async {
    final EditorController editor = context.read<EditorController>();
    final TextEditingController name = TextEditingController(
      text:
          node.type == 'componentGroup' &&
                  node.properties['groupName'] is String
              ? '${node.properties['groupName']} copy'
              : 'Reusable group',
    );
    String? error;
    final String? result = await showDialog<String>(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              final bool duplicate = editor.document.componentGroups.any(
                (BuilderComponentGroup group) =>
                    group.name.toLowerCase() == name.text.trim().toLowerCase(),
              );
              error =
                  name.text.trim().isEmpty
                      ? 'Enter a group name.'
                      : duplicate
                      ? 'A group with that name already exists.'
                      : null;
              return AlertDialog(
                title: const Text('Save reusable group'),
                content: SizedBox(
                  width: 360,
                  child: TextField(
                    controller: name,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Group name',
                      errorText: error,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (_) {
                      if (error == null)
                        Navigator.pop(dialogContext, name.text.trim());
                    },
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        error == null
                            ? () =>
                                Navigator.pop(dialogContext, name.text.trim())
                            : null,
                    child: const Text('Save group'),
                  ),
                ],
              );
            },
          ),
    );
    name.dispose();
    if (result == null || !mounted) return;
    final String id = editor.addComponentGroup(
      name: result,
      sourceNodeId: node.id,
    );
    if (id.isNotEmpty) _showMessage('Saved $result to reusable groups');
  }

  Future<void> _manageComponentGroups() async {
    final EditorController editor = context.read<EditorController>();
    await showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              Future<void> renameGroup(BuilderComponentGroup group) async {
                final TextEditingController name = TextEditingController(
                  text: group.name,
                );
                String? error;
                final String? result = await showDialog<String>(
                  context: context,
                  builder:
                      (BuildContext context) => StatefulBuilder(
                        builder: (
                          BuildContext context,
                          StateSetter setNameState,
                        ) {
                          final bool duplicate = editor.document.componentGroups
                              .any(
                                (BuilderComponentGroup item) =>
                                    item.id != group.id &&
                                    item.name.toLowerCase() ==
                                        name.text.trim().toLowerCase(),
                              );
                          error =
                              name.text.trim().isEmpty
                                  ? 'Enter a group name.'
                                  : duplicate
                                  ? 'A group with that name already exists.'
                                  : null;
                          return AlertDialog(
                            title: const Text('Rename component group'),
                            content: TextField(
                              controller: name,
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: 'Group name',
                                errorText: error,
                              ),
                              onChanged: (_) => setNameState(() {}),
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed:
                                    error == null
                                        ? () => Navigator.pop(
                                          context,
                                          name.text.trim(),
                                        )
                                        : null,
                                child: const Text('Save name'),
                              ),
                            ],
                          );
                        },
                      ),
                );
                name.dispose();
                if (result == null) return;
                editor.setComponentGroups(<BuilderComponentGroup>[
                  for (final BuilderComponentGroup item
                      in editor.document.componentGroups)
                    item.id == group.id ? item.copyWith(name: result) : item,
                ]);
                setDialogState(() {});
              }

              return AlertDialog(
                title: const Text('Reusable component groups'),
                content: SizedBox(
                  width: 460,
                  height: 340,
                  child:
                      editor.document.componentGroups.isEmpty
                          ? const Center(
                            child: Text(
                              'Select a component and choose “Save as reusable group” in the inspector to create one.',
                              textAlign: TextAlign.center,
                            ),
                          )
                          : ListView.separated(
                            itemCount: editor.document.componentGroups.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final BuilderComponentGroup group =
                                  editor.document.componentGroups[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.dashboard_customize_outlined,
                                ),
                                title: Text(group.name),
                                subtitle: Text(
                                  '${group.root.type} · ${group.root.depthFirst().length} components',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    IconButton(
                                      tooltip: 'Rename group',
                                      onPressed: () => renameGroup(group),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete group',
                                      onPressed: () {
                                        editor.setComponentGroups(
                                          editor.document.componentGroups
                                              .where(
                                                (BuilderComponentGroup item) =>
                                                    item.id != group.id,
                                              )
                                              .toList(),
                                        );
                                        setDialogState(() {});
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<(String, String, Object)?> _variableDraft(BuilderVariable? existing) =>
      showDialog<(String, String, Object)?>(
        context: context,
        builder:
            (BuildContext context) => _VariableEditorDialog(variable: existing),
      );

  Future<void> _createVariable() async {
    final (String, String, Object)? draft = await _variableDraft(null);
    if (draft == null || !mounted) return;
    context.read<EditorController>().addVariable(
      name: draft.$1,
      type: draft.$2,
      initialValue: draft.$3,
    );
  }
}

class _VariableEditorDialog extends StatefulWidget {
  const _VariableEditorDialog({this.variable});

  final BuilderVariable? variable;

  @override
  State<_VariableEditorDialog> createState() => _VariableEditorDialogState();
}

class _VariableEditorDialogState extends State<_VariableEditorDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.variable?.name ?? '',
  );
  late final TextEditingController _valueController = TextEditingController(
    text: _initialValueText,
  );
  late String _type = widget.variable?.type ?? 'string';
  late bool _boolValue = widget.variable?.initialValue == true;

  String get _initialValueText {
    final BuilderVariable? variable = widget.variable;
    if (variable == null) return '';
    if (variable.type == 'json' || variable.type == 'stringList') {
      return const JsonEncoder.withIndent('  ').convert(variable.initialValue);
    }
    return variable.initialValue.toString();
  }

  Object? get _parsedValue {
    final String text = _valueController.text;
    switch (_type) {
      case 'number':
      case 'double':
        return double.tryParse(text);
      case 'integer':
        return int.tryParse(text);
      case 'stringList':
        try {
          final Object? value = jsonDecode(text);
          return value is List
              ? value.map((Object? item) => item.toString()).toList()
              : null;
        } on FormatException {
          return null;
        }
      case 'json':
        try {
          return jsonDecode(text);
        } on FormatException {
          return null;
        }
      default:
        return text;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Object? parsedValue = _type == 'boolean' ? _boolValue : _parsedValue;
    final bool invalidValue =
        _type != 'boolean' &&
        (_type == 'number' || _type == 'double' || _type == 'integer'
            ? parsedValue == null
            : (_type == 'stringList' || _type == 'json') &&
                parsedValue == null);
    return AlertDialog(
      title: Text(widget.variable == null ? 'New variable' : 'Edit variable'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nameController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'string', child: Text('String')),
                DropdownMenuItem(value: 'integer', child: Text('Integer')),
                DropdownMenuItem(value: 'double', child: Text('Double')),
                DropdownMenuItem(
                  value: 'number',
                  child: Text('Number (legacy)'),
                ),
                DropdownMenuItem(value: 'boolean', child: Text('Boolean')),
                DropdownMenuItem(
                  value: 'stringList',
                  child: Text('List of strings'),
                ),
                DropdownMenuItem(value: 'json', child: Text('JSON')),
              ],
              onChanged: (String? next) {
                if (next == null) return;
                setState(() {
                  _type = next;
                  _valueController.text = switch (next) {
                    'number' || 'double' => '0.0',
                    'integer' => '0',
                    'stringList' => '[]',
                    'json' => '{}',
                    _ => '',
                  };
                });
              },
            ),
            const SizedBox(height: 12),
            if (_type == 'boolean')
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Initial value'),
                value: _boolValue,
                onChanged: (bool value) => setState(() => _boolValue = value),
              )
            else
              TextField(
                controller: _valueController,
                keyboardType:
                    _type == 'number' || _type == 'double' || _type == 'integer'
                        ? const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        )
                        : TextInputType.text,
                minLines: _type == 'json' || _type == 'stringList' ? 3 : 1,
                maxLines: _type == 'json' || _type == 'stringList' ? 6 : 1,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Initial value',
                  helperText: switch (_type) {
                    'stringList' =>
                      'Enter a JSON array, for example ["red", "blue"]',
                    'json' => 'Enter a valid JSON value.',
                    _ => null,
                  },
                  errorText:
                      invalidValue
                          ? switch (_type) {
                            'integer' => 'Enter a whole number',
                            'number' || 'double' => 'Enter a number',
                            'stringList' => 'Enter a valid JSON array',
                            'json' => 'Enter valid JSON',
                            _ => null,
                          }
                          : null,
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _nameController.text.trim().isEmpty || invalidValue
                  ? null
                  : () {
                    final Object value =
                        (_type == 'boolean' ? _boolValue : _parsedValue)
                            as Object;
                    Navigator.pop(context, (
                      _nameController.text.trim(),
                      _type,
                      value,
                    ));
                  },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PagesBar extends StatelessWidget {
  const _PagesBar({
    required this.pages,
    required this.activePageId,
    required this.initialPageId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onSetInitial,
    required this.onDelete,
  });

  final List<BuilderPage> pages;
  final String activePageId;
  final String initialPageId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<BuilderPage> onEdit;
  final ValueChanged<String> onSetInitial;
  final ValueChanged<BuilderPage> onDelete;

  @override
  Widget build(BuildContext context) => Container(
    height: 45,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: EditorPalette.surfaceRaised(context),
      border: Border(bottom: BorderSide(color: EditorPalette.border(context))),
    ),
    child: Row(
      children: <Widget>[
        Icon(
          Icons.web_asset_outlined,
          size: 16,
          color: EditorPalette.mutedText(context),
        ),
        const SizedBox(width: 8),
        Text(
          'Pages',
          style: TextStyle(
            color: EditorPalette.text(context),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: pages.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (BuildContext context, int index) {
              final BuilderPage page = pages[index];
              final bool selected = page.id == activePageId;
              final bool initial = page.id == initialPageId;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => onSelect(page.id),
                    child: Container(
                      height: 32,
                      constraints: const BoxConstraints(maxWidth: 190),
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color:
                            selected
                                ? EditorPalette.primaryContainer(context)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color:
                              selected
                                  ? EditorPalette.selectedContainer(context)
                                  : EditorPalette.border(context),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            initial ? Icons.home_outlined : Icons.web_outlined,
                            size: 14,
                            color:
                                selected
                                    ? EditorPalette.primary(context)
                                    : EditorPalette.mutedText(context),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              page.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight:
                                    selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                color: EditorPalette.text(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            page.route,
                            style: TextStyle(
                              color: EditorPalette.mutedText(context),
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 27,
                    height: 32,
                    child: PopupMenuButton<String>(
                      tooltip: 'Page options',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: Icon(
                        Icons.more_vert,
                        color: EditorPalette.mutedText(context),
                      ),
                      onSelected: (String action) {
                        switch (action) {
                          case 'edit':
                            onEdit(page);
                          case 'initial':
                            onSetInitial(page.id);
                          case 'delete':
                            onDelete(page);
                        }
                      },
                      itemBuilder:
                          (BuildContext context) => <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'edit',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined, size: 17),
                                title: Text('Name and route'),
                              ),
                            ),
                            if (!initial)
                              const PopupMenuItem<String>(
                                value: 'initial',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.home_outlined, size: 17),
                                  title: Text('Set as initial page'),
                                ),
                              ),
                            if (page.id != 'home')
                              const PopupMenuItem<String>(
                                value: 'delete',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.delete_outline, size: 17),
                                  title: Text('Delete page'),
                                ),
                              ),
                          ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 5),
        Tooltip(
          message: 'Add page',
          child: IconButton(
            onPressed: onAdd,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 19),
          ),
        ),
      ],
    ),
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.previewSize,
    required this.isWorking,
    required this.onPreviewSizeChanged,
    required this.onNew,
    required this.onOpen,
    required this.onSave,
    required this.onExportApp,
    required this.onValidate,
    required this.onRuntimePreview,
    required this.onToolchain,
    required this.onVariables,
    required this.onDataStructures,
    required this.onGroups,
    required this.onDatabase,
    required this.onUndo,
    required this.onRedo,
  });

  final PreviewSize previewSize;
  final bool isWorking;
  final ValueChanged<PreviewSize> onPreviewSizeChanged;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onExportApp;
  final VoidCallback onValidate;
  final VoidCallback onRuntimePreview;
  final VoidCallback onToolchain;
  final VoidCallback onVariables;
  final VoidCallback onDataStructures;
  final VoidCallback onGroups;
  final VoidCallback onDatabase;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final EditorController editor = context.watch<EditorController>();
    final bool canUndo = editor.canUndo;
    final bool canRedo = editor.canRedo;
    final ThemeModeController? themeMode =
        context.watch<ThemeModeController?>();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double viewportWidth = MediaQuery.sizeOf(context).width;
    final bool compactToolbar = viewportWidth < 1200;
    final bool condensedActions = viewportWidth < 1750;
    final bool ultraCompactToolbar = viewportWidth < 850;
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: compactToolbar ? 8 : 18),
      decoration: BoxDecoration(
        color: EditorPalette.surface(context),
        border: Border(
          bottom: BorderSide(color: EditorPalette.border(context)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: EditorPalette.primaryContainer(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 19,
                color: EditorPalette.primary(context),
              ),
            ),
            if (!ultraCompactToolbar) ...<Widget>[
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'LOCAL FLOW',
                    style: TextStyle(
                      color: EditorPalette.text(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (!compactToolbar)
                    Text(
                      'Flutter app builder',
                      style: TextStyle(
                        color: EditorPalette.mutedText(context),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
              SizedBox(width: compactToolbar ? 8 : 19),
              Container(
                width: 1,
                height: 28,
                color: EditorPalette.border(context),
              ),
            ] else ...<Widget>[
              const SizedBox(width: 5),
              Container(
                width: 1,
                height: 28,
                color: EditorPalette.border(context),
              ),
            ],
            const SizedBox(width: 9),
            Tooltip(
              message: 'New project',
              child: IconButton(
                onPressed: isWorking ? null : onNew,
                icon: const Icon(Icons.note_add_outlined, size: 19),
                visualDensity: VisualDensity.compact,
              ),
            ),
            Tooltip(
              message: 'Open project',
              child: IconButton(
                onPressed: isWorking ? null : onOpen,
                icon: const Icon(Icons.folder_open_outlined, size: 19),
                visualDensity: VisualDensity.compact,
              ),
            ),
            Tooltip(
              message: 'Save project',
              child: IconButton(
                onPressed: isWorking ? null : onSave,
                icon: Icon(
                  editor.isDirty ? Icons.save_as_outlined : Icons.save_outlined,
                  size: 19,
                  color: editor.isDirty ? EditorPalette.primary(context) : null,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              width: 1,
              height: 28,
              color: EditorPalette.border(context),
            ),
            const SizedBox(width: 5),
            IconButton(
              onPressed: canUndo && !isWorking ? onUndo : null,
              tooltip: 'Undo',
              icon: const Icon(Icons.undo, size: 19),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: canRedo && !isWorking ? onRedo : null,
              tooltip: 'Redo',
              icon: const Icon(Icons.redo, size: 19),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: isWorking ? null : onValidate,
              tooltip: 'Validate project',
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              visualDensity: VisualDensity.compact,
            ),
            if (compactToolbar)
              Tooltip(
                message: 'App variables',
                child: IconButton(
                  onPressed: isWorking ? null : onVariables,
                  icon: const Icon(Icons.data_object_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              )
            else
              Tooltip(
                message: 'App variables',
                child: OutlinedButton.icon(
                  onPressed: isWorking ? null : onVariables,
                  icon: const Icon(Icons.data_object_outlined, size: 17),
                  label: const Text('Variables'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    textStyle: const TextStyle(fontSize: 11),
                    side: BorderSide(color: EditorPalette.border(context)),
                    foregroundColor: EditorPalette.primary(context),
                  ),
                ),
              ),
            const SizedBox(width: 5),
            PopupMenuButton<String>(
              enabled: !isWorking,
              tooltip: 'Project resources',
              onSelected: (String value) {
                switch (value) {
                  case 'dataTypes':
                    onDataStructures();
                  case 'groups':
                    onGroups();
                  case 'database':
                    onDatabase();
                }
              },
              itemBuilder:
                  (BuildContext context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: 'dataTypes',
                      child: Text('Data types'),
                    ),
                    PopupMenuItem(value: 'groups', child: Text('Groups')),
                    PopupMenuItem(value: 'database', child: Text('Database')),
                  ],
              child: Container(
                height: 32,
                padding: EdgeInsets.symmetric(
                  horizontal: compactToolbar ? 7 : 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: EditorPalette.border(context)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.storage_outlined, size: 16),
                    if (!compactToolbar) ...<Widget>[
                      const SizedBox(width: 6),
                      const Text('Resources', style: TextStyle(fontSize: 11)),
                    ],
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
            SizedBox(width: compactToolbar ? 5 : 24),
            IconButton(
              onPressed: themeMode?.toggle,
              tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 19,
              ),
              visualDensity: VisualDensity.compact,
            ),
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: EditorPalette.surfaceInset(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EditorPalette.border(context)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PreviewSize>(
                  value: previewSize,
                  borderRadius: BorderRadius.circular(8),
                  icon: const Icon(Icons.expand_more, size: 17),
                  style: TextStyle(
                    fontSize: 11,
                    color: EditorPalette.text(context),
                  ),
                  items:
                      PreviewSize.values.map((PreviewSize size) {
                        return DropdownMenuItem<PreviewSize>(
                          value: size,
                          child: Row(
                            children: <Widget>[
                              Icon(
                                _previewIcon(size),
                                size: 15,
                                color: EditorPalette.mutedText(context),
                              ),
                              const SizedBox(width: 7),
                              Text(size.label),
                            ],
                          ),
                        );
                      }).toList(),
                  onChanged: (PreviewSize? value) {
                    if (value != null) onPreviewSizeChanged(value);
                  },
                ),
              ),
            ),
            const SizedBox(width: 11),
            Tooltip(
              message: 'Export Flutter App',
              child: FilledButton.icon(
                onPressed: isWorking ? null : onExportApp,
                icon:
                    isWorking
                        ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.code, size: 17),
                label: Text(compactToolbar ? 'Export' : 'Export Flutter App'),
                style: FilledButton.styleFrom(
                  backgroundColor: EditorPalette.primary(context),
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: EdgeInsets.symmetric(
                    horizontal: compactToolbar ? 8 : 14,
                    vertical: 11,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Preview with the full Flutter runtime',
              child:
                  condensedActions
                      ? IconButton(
                        onPressed: isWorking ? null : onRuntimePreview,
                        icon: const Icon(Icons.play_circle_outline, size: 19),
                        visualDensity: VisualDensity.compact,
                      )
                      : OutlinedButton.icon(
                        onPressed: isWorking ? null : onRuntimePreview,
                        icon: const Icon(Icons.play_circle_outline, size: 16),
                        label: Text(
                          compactToolbar ? 'Preview' : 'Flutter Preview',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: compactToolbar ? 7 : 10,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Run or build exported app',
              child:
                  condensedActions
                      ? IconButton(
                        onPressed: isWorking ? null : onToolchain,
                        icon: const Icon(Icons.terminal, size: 19),
                        visualDensity: VisualDensity.compact,
                      )
                      : OutlinedButton.icon(
                        onPressed: isWorking ? null : onToolchain,
                        icon: const Icon(Icons.terminal, size: 16),
                        label: const Text('Run / Build'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _previewIcon(PreviewSize size) => switch (size) {
    PreviewSize.phone => Icons.smartphone,
    PreviewSize.tablet => Icons.tablet_mac,
    PreviewSize.desktop => Icons.desktop_windows_outlined,
    PreviewSize.custom => Icons.aspect_ratio_outlined,
  };
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.document,
    required this.projectPath,
    required this.isDirty,
    this.activityMessage,
  });

  final BuilderDocument document;
  final String? projectPath;
  final bool isDirty;
  final String? activityMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: EditorPalette.surface(context),
        border: Border(top: BorderSide(color: EditorPalette.border(context))),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isDirty ? Icons.circle : Icons.check_circle,
            size: 9,
            color: isDirty ? const Color(0xFFCF8A2B) : const Color(0xFF3A9A72),
          ),
          const SizedBox(width: 7),
          Text(
            isDirty ? 'Unsaved changes' : 'All changes saved',
            style: TextStyle(
              fontSize: 10,
              color: EditorPalette.mutedText(context),
            ),
          ),
          if (activityMessage != null) ...<Widget>[
            const SizedBox(width: 14),
            Icon(Icons.sync, size: 12, color: EditorPalette.primary(context)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                activityMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: EditorPalette.mutedText(context),
                ),
              ),
            ),
          ],
          const Spacer(),
          Flexible(
            child: Text(
              projectPath ?? '${document.name} · not saved yet',
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                color: EditorPalette.mutedText(context),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Icon(
            Icons.computer,
            size: 13,
            color: EditorPalette.mutedText(context),
          ),
          const SizedBox(width: 5),
          Text(
            'Local project',
            style: TextStyle(
              fontSize: 10,
              color: EditorPalette.mutedText(context),
            ),
          ),
        ],
      ),
    );
  }
}
