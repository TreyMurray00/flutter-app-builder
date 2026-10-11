import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/builder_action.dart';
import '../models/builder_document.dart';
import '../services/flutter_project_exporter.dart';
import '../services/project_store.dart';
import 'canvas_preview.dart';
import 'editor_controller.dart';
import 'editor_drag_data.dart';
import 'inspector_panel.dart';
import 'widget_tree_panel.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  PreviewSize _previewSize = PreviewSize.phone;
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final EditorController editor = context.watch<EditorController>();
    final Size viewport = MediaQuery.sizeOf(context);
    final double paletteWidth = (viewport.width * .24).clamp(300, 390);
    final double inspectorWidth = (viewport.width * .22).clamp(300, 360);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Toolbar(
              previewSize: _previewSize,
              isWorking: _working,
              canUndo: editor.canUndo,
              canRedo: editor.canRedo,
              onPreviewSizeChanged:
                  (PreviewSize size) => setState(() => _previewSize = size),
              onNew: _newProject,
              onOpen: _openProject,
              onSave: _saveProject,
              onExportApp: _exportFlutterApp,
              onVariables: _manageVariables,
              onUndo: editor.undo,
              onRedo: editor.redo,
            ),
            _PagesBar(
              pages: editor.pages,
              activePageId: editor.activePageId,
              initialPageId: editor.document.initialPageId,
              onSelect: editor.selectPage,
              onAdd: editor.addPage,
              onEdit: _editPage,
              onSetInitial: editor.setInitialPage,
              onDelete: _deletePage,
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: paletteWidth,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
                      child: WidgetTreePanel(
                        root: editor.activeRoot,
                        selectedNodeId: editor.selectedNodeId,
                        onSelect: editor.selectNode,
                        onAddObject: editor.addObject,
                        onDrop: _handleDrop,
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFFEAECF1),
                      child: Column(
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 7),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.touch_app_outlined,
                                  size: 15,
                                  color: Color(0xFF7D8491),
                                ),
                                const SizedBox(width: 7),
                                const Text(
                                  'Select a widget on the canvas to edit it',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF737B8A),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_previewSize.width.round()} × ${_previewSize.height.round()}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF838A97),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: CanvasPreview(
                              key: ValueKey<int>(editor.documentSessionId),
                              document: editor.document,
                              root: editor.activeRoot,
                              selectedNodeId: editor.selectedNodeId,
                              size: _previewSize,
                              onSelect: editor.selectNode,
                              onDrop: _handleDrop,
                              onNavigate: editor.navigateToRoute,
                              onRunActions: _runActions,
                              activePageId: editor.activePageId,
                              variableValues: editor.appVariableValues,
                              widgetOverrides: editor.widgetOverrides,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  SizedBox(
                    width: inspectorWidth,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(17, 19, 17, 17),
                      child: InspectorPanel(
                        node: editor.selectedNode,
                        seedColor: editor.document.seedColor,
                        onSetProperty: editor.setProperty,
                        onSetProperties: editor.setProperties,
                        onSetSeedColor: editor.setSeedColor,
                        onDeleteNode: editor.deleteSelected,
                        onCreateVariable: _createVariable,
                        pages: editor.pages,
                        variables: editor.document.variables,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _StatusBar(
              document: editor.document,
              projectPath: editor.projectPath,
              isDirty: editor.isDirty,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newProject() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    context.read<EditorController>().createNew();
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
    final String? path = await _requestPath(
      title: 'Open local project',
      helpText: 'Enter the full path to an .appbuilder.json file.',
      confirmLabel: 'Open',
    );
    if (path == null || !mounted) return;
    setState(() => _working = true);
    try {
      final StoredProject result = await context
          .read<ProjectStore>()
          .openProject(path);
      if (mounted) {
        context.read<EditorController>().open(result.document, result.path);
        _showMessage('Opened ${_fileName(result.path)}');
      }
    } catch (error) {
      _showMessage('Could not open project: $error', isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveProject() async {
    final EditorController editor = context.read<EditorController>();
    final String? path =
        editor.projectPath ??
        await _requestPath(
          title: 'Save local project',
          helpText: 'Choose a full path for the JSON design file.',
          confirmLabel: 'Save',
          initialPath: 'my_first_app.appbuilder.json',
        );
    if (path == null || !mounted) return;
    setState(() => _working = true);
    try {
      final String savedPath = await context.read<ProjectStore>().saveProject(
        editor.document,
        path,
      );
      if (mounted) {
        editor.markSaved(savedPath);
        _showMessage('Project saved locally');
      }
    } catch (error) {
      _showMessage('Could not save project: $error', isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportFlutterApp() async {
    final String? path = await _requestPath(
      title: 'Export Flutter app',
      helpText:
          'Choose a new folder for a complete Flutter project, including native platform files and copied image assets.',
      confirmLabel: 'Export app',
      initialPath: 'my_flutter_app',
      pathLabel: 'Project folder',
      pathHint: 'C:\\Users\\you\\Projects\\my_flutter_app',
    );
    if (path == null || !mounted) return;
    setState(() => _working = true);
    try {
      final String generatedPath = await context
          .read<FlutterProjectExporter>()
          .export(context.read<EditorController>().document, path);
      _showMessage('Exported Flutter app to $generatedPath');
    } catch (error) {
      _showMessage('Could not export Flutter app: $error', isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
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

  Future<String?> _requestPath({
    required String title,
    required String helpText,
    required String confirmLabel,
    String initialPath = '',
    String pathLabel = 'File path',
    String pathHint = 'C:\\Users\\you\\Projects\\app.json',
  }) async {
    return showDialog<String>(
      context: context,
      builder:
          (BuildContext dialogContext) => _PathRequestDialog(
            title: title,
            helpText: helpText,
            confirmLabel: confirmLabel,
            initialPath: initialPath,
            pathLabel: pathLabel,
            pathHint: pathHint,
          ),
    );
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

  Future<void> _runActions(BuilderNode node) async {
    final EditorController editor = context.read<EditorController>();
    final String sourcePageId = editor.activePageId;
    for (final Map<String, Object?> action in BuilderAction.forNode(node)) {
      switch (action['type']) {
        case 'navigate':
          final String route =
              action['route'] is String ? action['route']! as String : '';
          if (route.isNotEmpty) {
            editor.navigateToRoute(
              route,
              replace: action['behavior'] == 'replace',
            );
          }
        case 'snackbar':
          final String message =
              action['message'] is String ? action['message']! as String : '';
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
                    action['title'] is String
                        ? action['title']! as String
                        : 'Notice',
                  ),
                  content: Text(
                    action['message'] is String
                        ? action['message']! as String
                        : '',
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
            editor.setVariableValue(variableId, action['value']);
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
              action['value'],
            );
          }
      }
    }
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
    decoration: const BoxDecoration(
      color: Color(0xFFF8F9FB),
      border: Border(bottom: BorderSide(color: Color(0xFFE1E4EA))),
    ),
    child: Row(
      children: <Widget>[
        const Icon(
          Icons.web_asset_outlined,
          size: 16,
          color: Color(0xFF727987),
        ),
        const SizedBox(width: 8),
        const Text(
          'Pages',
          style: TextStyle(
            color: Color(0xFF606775),
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
                                ? const Color(0xFFEDE9F8)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color:
                              selected
                                  ? const Color(0xFFD5CDEF)
                                  : const Color(0xFFE2E5EB),
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
                                    ? const Color(0xFF6750A4)
                                    : const Color(0xFF777F8D),
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
                                color: const Color(0xFF373D49),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            page.route,
                            style: const TextStyle(
                              color: Color(0xFF858C99),
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
                      icon: const Icon(
                        Icons.more_vert,
                        color: Color(0xFF858C99),
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
    required this.canUndo,
    required this.canRedo,
    required this.onPreviewSizeChanged,
    required this.onNew,
    required this.onOpen,
    required this.onSave,
    required this.onExportApp,
    required this.onVariables,
    required this.onUndo,
    required this.onRedo,
  });

  final PreviewSize previewSize;
  final bool isWorking;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<PreviewSize> onPreviewSizeChanged;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onExportApp;
  final VoidCallback onVariables;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final EditorController editor = context.watch<EditorController>();
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE1E4EA))),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 19,
              color: Color(0xFF6750A4),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'LOCAL FLOW',
                style: TextStyle(
                  color: Color(0xFF303644),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'Flutter app builder',
                style: TextStyle(color: Color(0xFF858B98), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 19),
          Container(width: 1, height: 28, color: const Color(0xFFE4E6EB)),
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
                color: editor.isDirty ? const Color(0xFF6750A4) : null,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 5),
          Container(width: 1, height: 28, color: const Color(0xFFE4E6EB)),
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
                side: const BorderSide(color: Color(0xFFE0DCEC)),
                foregroundColor: const Color(0xFF5D4A91),
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE4E6EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<PreviewSize>(
                value: previewSize,
                borderRadius: BorderRadius.circular(8),
                icon: const Icon(Icons.expand_more, size: 17),
                style: const TextStyle(fontSize: 11, color: Color(0xFF414857)),
                items:
                    PreviewSize.values.map((PreviewSize size) {
                      return DropdownMenuItem<PreviewSize>(
                        value: size,
                        child: Row(
                          children: <Widget>[
                            Icon(
                              _previewIcon(size),
                              size: 15,
                              color: const Color(0xFF737B8A),
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
          FilledButton.icon(
            onPressed: isWorking ? null : onExportApp,
            icon:
                isWorking
                    ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.code, size: 17),
            label: const Text('Export Flutter App'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6750A4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _previewIcon(PreviewSize size) => switch (size) {
    PreviewSize.phone => Icons.smartphone,
    PreviewSize.tablet => Icons.tablet_mac,
    PreviewSize.desktop => Icons.desktop_windows_outlined,
  };
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.document,
    required this.projectPath,
    required this.isDirty,
  });

  final BuilderDocument document;
  final String? projectPath;
  final bool isDirty;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE1E4EA))),
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
            style: const TextStyle(fontSize: 10, color: Color(0xFF6D7482)),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              projectPath ?? '${document.name} · not saved yet',
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10, color: Color(0xFF8A909D)),
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.computer, size: 13, color: Color(0xFF8A909D)),
          const SizedBox(width: 5),
          const Text(
            'Local project',
            style: TextStyle(fontSize: 10, color: Color(0xFF6D7482)),
          ),
        ],
      ),
    );
  }
}

class _PathRequestDialog extends StatefulWidget {
  const _PathRequestDialog({
    required this.title,
    required this.helpText,
    required this.confirmLabel,
    required this.initialPath,
    required this.pathLabel,
    required this.pathHint,
  });

  final String title;
  final String helpText;
  final String confirmLabel;
  final String initialPath;
  final String pathLabel;
  final String pathHint;

  @override
  State<_PathRequestDialog> createState() => _PathRequestDialogState();
}

class _PathRequestDialogState extends State<_PathRequestDialog> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.initialPath);
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void submit() {
      final String path = _pathController.text.trim();
      if (path.isNotEmpty) Navigator.pop(context, path);
    }

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.helpText, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: _pathController,
              autofocus: true,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: widget.pathLabel,
                hintText: widget.pathHint,
                border: const OutlineInputBorder(),
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
        FilledButton(onPressed: submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
