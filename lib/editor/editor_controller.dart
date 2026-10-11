import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/builder_action.dart';
import '../models/builder_document.dart';

class EditorController extends ChangeNotifier {
  EditorController() {
    _synchronizeAppVariables();
  }

  BuilderDocument _document = BuilderDocument.sample();
  final List<BuilderDocument> _undoStack = <BuilderDocument>[];
  final List<BuilderDocument> _redoStack = <BuilderDocument>[];
  final List<String> _previewPageStack = <String>[];
  final Map<String, Object?> _appVariableValues = <String, Object?>{};
  final Map<String, Map<String, Object?>> _widgetOverrides =
      <String, Map<String, Object?>>{};
  String? _projectPath;
  int _documentSessionId = 0;
  String _selectedNodeId = 'text_1';
  String _activePageId = 'home';
  bool _isDirty = false;

  BuilderDocument get document => _document;
  List<BuilderPage> get pages => _document.allPages;
  String get activePageId => _activePageId;
  BuilderNode get activeRoot =>
      _document.pageById(_activePageId)?.root ?? _document.root;
  String? get projectPath => _projectPath;
  int get documentSessionId => _documentSessionId;
  String get selectedNodeId => _selectedNodeId;
  bool get isDirty => _isDirty;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  BuilderNode? get selectedNode => activeRoot.findById(_selectedNodeId);
  Map<String, Object?> get appVariableValues =>
      Map<String, Object?>.unmodifiable(_appVariableValues);
  Map<String, Map<String, Object?>> get widgetOverrides =>
      Map<String, Map<String, Object?>>.unmodifiable(
        _widgetOverrides.map(
          (String key, Map<String, Object?> value) =>
              MapEntry<String, Map<String, Object?>>(
                key,
                Map<String, Object?>.unmodifiable(value),
              ),
        ),
      );

  String addVariable({
    required String name,
    required String type,
    required Object initialValue,
  }) {
    final String cleanName = _uniqueVariableName(name);
    int suffix = 1;
    final Set<String> ids =
        _document.variables.map((BuilderVariable item) => item.id).toSet();
    while (ids.contains('app_var_$suffix')) {
      suffix++;
    }
    final String id = 'app_var_$suffix';
    final BuilderVariable variable = BuilderVariable(
      id: id,
      name: cleanName,
      type: type,
      initialValue: _coerceVariableValue(type, initialValue),
    );
    _commit(
      _document.copyWith(
        variables: <BuilderVariable>[..._document.variables, variable],
      ),
    );
    _synchronizeAppVariables();
    return id;
  }

  void updateVariable(
    String id, {
    required String name,
    required String type,
    required Object initialValue,
  }) {
    BuilderVariable? current;
    for (final BuilderVariable item in _document.variables) {
      if (item.id == id) current = item;
    }
    if (current == null) return;
    final String cleanName = _uniqueVariableName(name, exceptId: id);
    final BuilderVariable updated = BuilderVariable(
      id: id,
      name: cleanName,
      type: type,
      initialValue: _coerceVariableValue(type, initialValue),
    );
    if (current.name == updated.name &&
        current.type == updated.type &&
        current.initialValue == updated.initialValue) {
      return;
    }
    _commit(
      _document.copyWith(
        variables:
            _document.variables
                .map((BuilderVariable item) => item.id == id ? updated : item)
                .toList(),
      ),
    );
    if (current.type != updated.type) {
      _appVariableValues[id] = updated.initialValue;
    } else {
      _appVariableValues[id] = _coerceVariableValue(
        updated.type,
        _appVariableValues[id] ?? updated.initialValue,
      );
    }
    notifyListeners();
  }

  void deleteVariable(String id) {
    if (!_document.variables.any((BuilderVariable item) => item.id == id))
      return;
    BuilderNode cleanTree(BuilderNode node) {
      final Map<String, Object?> props = <String, Object?>{...node.properties};
      final Object? rawBindings = props['bindings'];
      if (rawBindings is Map) {
        final Map<String, Object?> bindings = Map<String, Object?>.from(
          rawBindings,
        )..removeWhere((String _, Object? value) => value == id);
        if (bindings.isEmpty) {
          props.remove('bindings');
        } else {
          props['bindings'] = bindings;
        }
      }
      final Object? rawActions = props['actions'];
      if (rawActions is List) {
        props['actions'] =
            rawActions.where((Object? raw) {
              if (raw is! Map) return true;
              return raw['variableId'] != id;
            }).toList();
      }
      return node.copyWith(
        properties: props,
        children: node.children.map(cleanTree).toList(),
      );
    }

    _commit(
      _document.copyWith(
        variables:
            _document.variables
                .where((BuilderVariable item) => item.id != id)
                .toList(),
        root: cleanTree(_document.root),
        pages:
            _document.pages
                .map(
                  (BuilderPage page) =>
                      page.copyWith(root: cleanTree(page.root)),
                )
                .toList(),
      ),
    );
    _appVariableValues.remove(id);
  }

  void setVariableValue(String id, Object? value) {
    BuilderVariable? variable;
    for (final BuilderVariable item in _document.variables) {
      if (item.id == id) variable = item;
    }
    if (variable == null) return;
    final Object next = _coerceVariableValue(variable.type, value);
    if (_appVariableValues[id] == next) return;
    _appVariableValues[id] = next;
    notifyListeners();
  }

  void incrementVariable(String id, {double amount = 1}) {
    final Object? current = _appVariableValues[id];
    if (current is num) {
      setVariableValue(
        id,
        current is int && amount == amount.roundToDouble()
            ? current + amount.toInt()
            : current + amount,
      );
    }
  }

  void toggleVariable(String id) {
    final Object? current = _appVariableValues[id];
    if (current is bool) setVariableValue(id, !current);
  }

  void setWidgetRuntimeProperty(
    String pageId,
    String nodeId,
    String property,
    Object? value,
  ) {
    final BuilderNode? node = _document.pageById(pageId)?.root.findById(nodeId);
    if (node == null ||
        !<String>{
          'text',
          'label',
          'initialValue',
          'visible',
          'opacity',
          'width',
          'height',
        }.contains(property)) {
      return;
    }
    final String key = _widgetRuntimeKey(pageId, nodeId);
    final Map<String, Object?> overrides = _widgetOverrides.putIfAbsent(
      key,
      () => <String, Object?>{},
    );
    final Object? normalized = switch (property) {
      'visible' => value == true,
      'opacity' => _coerceNumber(value, 1).clamp(0, 1).toDouble(),
      'width' || 'height' => _coerceNumber(value, 0).clamp(0, 1200).toDouble(),
      _ => value?.toString() ?? '',
    };
    if (overrides[property] == normalized) return;
    overrides[property] = normalized;
    notifyListeners();
  }

  static String widgetRuntimeKey(String pageId, String nodeId) =>
      '$pageId::$nodeId';

  String _widgetRuntimeKey(String pageId, String nodeId) =>
      widgetRuntimeKey(pageId, nodeId);

  String _uniqueVariableName(String name, {String? exceptId}) {
    String clean = name.trim();
    if (clean.isEmpty) clean = 'variable';
    final Set<String> used =
        _document.variables
            .where((BuilderVariable item) => item.id != exceptId)
            .map((BuilderVariable item) => item.name.toLowerCase())
            .toSet();
    if (!used.contains(clean.toLowerCase())) return clean;
    int suffix = 2;
    while (used.contains('$clean $suffix'.toLowerCase())) {
      suffix++;
    }
    return '$clean $suffix';
  }

  Object _coerceVariableValue(String type, Object? value) => switch (type) {
    'number' || 'double' => _coerceNumber(value, 0),
    'integer' => _coerceNumber(value, 0).round(),
    'boolean' => value == true,
    'stringList' => _stringListValue(value),
    'json' => _jsonValue(value),
    _ => value?.toString() ?? '',
  };

  List<String> _stringListValue(Object? value) {
    final Object? decoded = _decodeJsonInput(value);
    return decoded is List
        ? decoded.map((Object? item) => item.toString()).toList()
        : <String>[];
  }

  Object _jsonValue(Object? value) {
    Object? decoded = _decodeJsonInput(value);
    if (decoded == null && value is String) decoded = value;
    return decoded is Map ||
            decoded is List ||
            decoded is num ||
            decoded is bool ||
            decoded is String
        ? decoded!
        : <String, Object?>{};
  }

  Object? _decodeJsonInput(Object? value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  double _coerceNumber(Object? value, double fallback) =>
      value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? fallback;

  void _synchronizeAppVariables() {
    final Set<String> existing =
        _document.variables.map((BuilderVariable item) => item.id).toSet();
    _appVariableValues.removeWhere(
      (String id, Object? _) => !existing.contains(id),
    );
    for (final BuilderVariable variable in _document.variables) {
      _appVariableValues[variable.id] = _coerceVariableValue(
        variable.type,
        _appVariableValues[variable.id] ?? variable.initialValue,
      );
    }
  }

  void selectNode(String id) {
    if (activeRoot.findById(id) == null || id == _selectedNodeId) return;
    _selectedNodeId = id;
    notifyListeners();
  }

  void setText(String nodeId, String text) {
    setProperty(nodeId, 'text', text);
  }

  void setProperty(String nodeId, String key, Object? value) {
    setProperties(nodeId, <String, Object?>{key: value});
  }

  void setProperties(String nodeId, Map<String, Object?> values) {
    final BuilderNode? node = activeRoot.findById(nodeId);
    if (node == null) return;
    final Map<String, Object?> changed = <String, Object?>{
      for (final MapEntry<String, Object?> entry in values.entries)
        if (node.properties[entry.key] != entry.value) entry.key: entry.value,
    };
    if (changed.isEmpty) return;
    _commit(
      _copyWithActiveRoot(
        activeRoot.updateById(nodeId, (BuilderNode current) {
          return current.copyWith(
            properties: <String, Object?>{...current.properties, ...changed},
          );
        }),
      ),
    );
  }

  void setSeedColor(int color) {
    if (_document.seedColor == color) return;
    _commit(_document.copyWith(seedColor: color));
  }

  void addPage() {
    int suffix = pages.length + 1;
    final Set<String> ids = pages.map((BuilderPage page) => page.id).toSet();
    final Set<String> routes =
        pages.map((BuilderPage page) => page.route.toLowerCase()).toSet();
    while (ids.contains('page_$suffix') ||
        routes.contains('/page-$suffix'.toLowerCase())) {
      suffix++;
    }
    final String id = 'page_$suffix';
    final String name = 'Page $suffix';
    final BuilderPage page = BuilderPage(
      id: id,
      name: name,
      route: '/page-$suffix',
      root: BuilderNode(
        id: 'scaffold_1',
        type: 'scaffold',
        properties: const <String, Object?>{},
        children: const <BuilderNode>[],
      ),
    );
    _activePageId = id;
    _selectedNodeId = page.root.id;
    _commit(_document.copyWith(pages: <BuilderPage>[..._document.pages, page]));
  }

  void selectPage(String pageId) {
    final BuilderPage? page = _document.pageById(pageId);
    if (page == null || page.id == _activePageId) return;
    _activePageId = page.id;
    _selectedNodeId = page.root.id;
    notifyListeners();
  }

  void navigateToRoute(String route, {bool replace = false}) {
    final String normalized = _normalizeRoute(route);
    for (final BuilderPage page in pages) {
      if (page.route == normalized) {
        if (page.id == _activePageId) return;
        if (!replace) {
          _previewPageStack.add(_activePageId);
        }
        selectPage(page.id);
        return;
      }
    }
  }

  void previewBack() {
    while (_previewPageStack.isNotEmpty) {
      final String previousId = _previewPageStack.removeLast();
      if (_document.pageById(previousId) != null) {
        selectPage(previousId);
        return;
      }
    }
  }

  /// Updates page metadata. Returns an error message when the route is invalid
  /// or already used, otherwise commits the changes and returns null.
  String? updatePageDetails({
    required String pageId,
    required String name,
    required String route,
  }) {
    final BuilderPage? page = _document.pageById(pageId);
    if (page == null) return 'That page no longer exists.';
    final String cleanName = name.trim();
    if (cleanName.isEmpty) return 'Page name cannot be empty.';
    final String cleanRoute = _normalizeRoute(route);
    if (cleanRoute.contains('?') || cleanRoute.contains('#')) {
      return 'Routes cannot contain query strings or fragments.';
    }
    if (pages.any(
      (BuilderPage other) =>
          other.id != pageId &&
          other.route.toLowerCase() == cleanRoute.toLowerCase(),
    )) {
      return 'Another page already uses $cleanRoute.';
    }
    if (page.name == cleanName && page.route == cleanRoute) return null;
    final BuilderDocument metadataUpdated;
    if (pageId == 'home') {
      metadataUpdated = _document.copyWith(
        homePageName: cleanName,
        homePageRoute: cleanRoute,
      );
    } else {
      metadataUpdated = _document.copyWith(
        pages:
            _document.pages
                .map(
                  (BuilderPage current) =>
                      current.id == pageId
                          ? current.copyWith(name: cleanName, route: cleanRoute)
                          : current,
                )
                .toList(),
      );
    }
    _commit(
      page.route == cleanRoute
          ? metadataUpdated
          : _replaceRoute(metadataUpdated, page.route, cleanRoute),
    );
    return null;
  }

  void setInitialPage(String pageId) {
    if (_document.pageById(pageId) == null ||
        _document.initialPageId == pageId) {
      return;
    }
    _commit(_document.copyWith(initialPageId: pageId));
  }

  void deletePage(String pageId) {
    final BuilderPage? page = _document.pageById(pageId);
    if (pageId == 'home' || page == null) return;
    final List<BuilderPage> remaining =
        _document.pages.where((BuilderPage page) => page.id != pageId).toList();
    final BuilderDocument withoutPage = _document.copyWith(
      pages: remaining,
      initialPageId:
          _document.initialPageId == pageId ? 'home' : _document.initialPageId,
    );
    final BuilderDocument unlinked = _replaceRoute(withoutPage, page.route, '');
    _previewPageStack.removeWhere((String id) => id == pageId);
    _activePageId = _activePageId == pageId ? 'home' : _activePageId;
    _selectedNodeId = activeRoot.id;
    _commit(unlinked);
  }

  void addText() {
    addObject('text');
  }

  void addObject(
    String type, {
    String? targetId,
    BuilderDropPosition position = BuilderDropPosition.inside,
  }) {
    final Map<String, Object?> properties = switch (type) {
      'text' => <String, Object?>{
        'text': 'New text',
        'fontSize': 18.0,
        'fontWeight': 'regular',
        'color': 0xFF303644,
      },
      'button' => <String, Object?>{'label': 'Button', 'style': 'filled'},
      'container' => <String, Object?>{
        'width': 220.0,
        'height': 100.0,
        'padding': 12.0,
        'backgroundColor': 0xFFF1EFF8,
        'borderRadius': 12.0,
      },
      'row' => <String, Object?>{
        'mainAxisAlignment': 'start',
        'crossAxisAlignment': 'center',
      },
      'column' => <String, Object?>{
        'mainAxisAlignment': 'start',
        'crossAxisAlignment': 'start',
      },
      'stack' => <String, Object?>{
        'width': 260.0,
        'height': 160.0,
        'alignment': 'topLeft',
        'fit': 'loose',
      },
      'listView' => <String, Object?>{
        'width': 300.0,
        'height': 220.0,
        'scrollDirection': 'vertical',
        'itemSpacing': 8.0,
      },
      'gridView' => <String, Object?>{
        'width': 300.0,
        'height': 220.0,
        'crossAxisCount': 2,
        'itemSpacing': 8.0,
      },
      'pageView' => <String, Object?>{'width': 300.0, 'height': 220.0},
      'swipeableStack' => <String, Object?>{
        'width': 300.0,
        'height': 220.0,
        'visibleCount': 3,
        'loop': false,
      },
      'card' => <String, Object?>{
        'width': 240.0,
        'height': 140.0,
        'padding': 12.0,
        'backgroundColor': 0xFFFFFFFF,
        'borderRadius': 12.0,
        'elevation': 2.0,
      },
      'padding' => <String, Object?>{'padding': 16.0},
      'image' => <String, Object?>{
        'source': '',
        'width': 180.0,
        'height': 120.0,
        'fit': 'cover',
      },
      'icon' => <String, Object?>{
        'iconName': 'star',
        'size': 32.0,
        'color': 0xFF6750A4,
      },
      'divider' => <String, Object?>{
        'thickness': 1.0,
        'height': 24.0,
        'indent': 0.0,
        'endIndent': 0.0,
        'color': 0xFFB8BEC9,
      },
      'verticalDivider' => <String, Object?>{
        'thickness': 1.0,
        'width': 24.0,
        'height': 48.0,
        'indent': 0.0,
        'endIndent': 0.0,
        'color': 0xFFB8BEC9,
      },
      'textField' => <String, Object?>{
        'hintText': 'Enter text',
        'label': 'Text field',
        'initialValue': '',
        'width': 240.0,
      },
      'checkbox' => <String, Object?>{
        'label': 'Checkbox',
        'value': false,
        'activeColor': 0xFF6750A4,
      },
      'switch' => <String, Object?>{
        'label': 'Switch',
        'value': false,
        'activeColor': 0xFF6750A4,
      },
      'signature' => <String, Object?>{
        'width': 280.0,
        'height': 160.0,
        'strokeWidth': 2.0,
        'penColor': 0xFF20242C,
        'backgroundColor': 0xFFFFFFFF,
      },
      'appBar' => <String, Object?>{
        'title': 'App Bar',
        'backgroundColor': 0xFF6750A4,
        'foregroundColor': 0xFFFFFFFF,
        'elevation': 2.0,
      },
      'floatingActionButton' => <String, Object?>{
        'iconName': 'add',
        'backgroundColor': 0xFF6750A4,
        'foregroundColor': 0xFFFFFFFF,
      },
      _ => <String, Object?>{},
    };
    if (properties.isEmpty) return;

    BuilderNode? parent;
    if (targetId == null &&
        (type == 'appBar' || type == 'floatingActionButton')) {
      parent = _firstScaffold() ?? _insertionParent();
    } else if (targetId == null) {
      parent = _insertionParent();
    } else if (position == BuilderDropPosition.inside) {
      final BuilderNode? target = activeRoot.findById(targetId);
      parent = target?.acceptsChildren == true ? target : _insertionParent();
    } else {
      parent = activeRoot.parentOfId(targetId);
    }
    if (parent == null) return;
    final Set<String> ids =
        activeRoot.depthFirst().map((BuilderNode node) => node.id).toSet();
    final String prefix = type;
    int suffix = ids.length + 1;
    while (ids.contains('${prefix}_$suffix')) {
      suffix++;
    }
    final String id = '${prefix}_$suffix';
    final BuilderNode node = BuilderNode(
      id: id,
      type: type,
      properties: properties,
      children: const <BuilderNode>[],
    );
    BuilderNode nextRoot = activeRoot.appendToId(parent.id, node);
    if (targetId != null && position != BuilderDropPosition.inside) {
      nextRoot = nextRoot.moveNode(id, targetId, position) ?? nextRoot;
    }
    _selectedNodeId = id;
    _commit(_copyWithActiveRoot(nextRoot));
  }

  void moveObject(
    String sourceId,
    String targetId,
    BuilderDropPosition position,
  ) {
    final BuilderNode? nextRoot = activeRoot.moveNode(
      sourceId,
      targetId,
      position,
    );
    if (nextRoot == null) return;
    _commit(_copyWithActiveRoot(nextRoot));
  }

  void deleteSelected() {
    final BuilderNode? selectedNode = activeRoot.findById(_selectedNodeId);
    if (selectedNode == null) return;
    final BuilderNode selected = selectedNode;
    if (selected.id == activeRoot.id) return;
    final BuilderNode parent = activeRoot.parentOfId(selected.id) ?? activeRoot;
    _selectedNodeId = parent.id;
    _commit(_copyWithActiveRoot(activeRoot.removeById(selected.id)));
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_document);
    _document = _undoStack.removeLast();
    _isDirty = true;
    _synchronizeAppVariables();
    _normalizeSelection();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_document);
    _document = _redoStack.removeLast();
    _isDirty = true;
    _synchronizeAppVariables();
    _normalizeSelection();
    notifyListeners();
  }

  void open(BuilderDocument document, String path) {
    _documentSessionId++;
    _document = document;
    _projectPath = path;
    _previewPageStack.clear();
    _activePageId = document.pageById(document.initialPageId)?.id ?? 'home';
    _selectedNodeId = activeRoot.id;
    _undoStack.clear();
    _redoStack.clear();
    _isDirty = false;
    _appVariableValues.clear();
    _widgetOverrides.clear();
    _synchronizeAppVariables();
    notifyListeners();
  }

  void createNew() {
    _documentSessionId++;
    _document = BuilderDocument.sample();
    _projectPath = null;
    _previewPageStack.clear();
    _activePageId = 'home';
    _selectedNodeId = 'text_1';
    _undoStack.clear();
    _redoStack.clear();
    _isDirty = false;
    _appVariableValues.clear();
    _widgetOverrides.clear();
    _synchronizeAppVariables();
    notifyListeners();
  }

  void markSaved(String path) {
    _projectPath = path;
    _isDirty = false;
    notifyListeners();
  }

  void _commit(BuilderDocument next) {
    _undoStack.add(_document);
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
    _document = next;
    _synchronizeAppVariables();
    _isDirty = true;
    notifyListeners();
  }

  BuilderNode? _insertionParent() {
    final BuilderNode? selected = activeRoot.findById(_selectedNodeId);
    if (selected == null) return _firstContainer();
    if (selected.acceptsChildren) return selected;
    final BuilderNode? parent = activeRoot.parentOfId(selected.id);
    if (parent?.acceptsChildren ?? false) return parent;
    return _firstContainer();
  }

  BuilderNode? _firstContainer() {
    for (final BuilderNode node in activeRoot.depthFirst()) {
      if (node.acceptsChildren && node.type != 'scaffold') return node;
    }
    return activeRoot.acceptsChildren ? activeRoot : null;
  }

  BuilderNode? _firstScaffold() {
    for (final BuilderNode node in activeRoot.depthFirst()) {
      if (node.type == 'scaffold') return node;
    }
    return null;
  }

  BuilderDocument _copyWithActiveRoot(BuilderNode root) {
    if (_activePageId == 'home') return _document.copyWith(root: root);
    return _document.copyWith(
      pages:
          _document.pages
              .map(
                (BuilderPage page) =>
                    page.id == _activePageId ? page.copyWith(root: root) : page,
              )
              .toList(),
    );
  }

  void _normalizeSelection() {
    if (_document.pageById(_activePageId) == null) _activePageId = 'home';
    if (activeRoot.findById(_selectedNodeId) == null) {
      _selectedNodeId = activeRoot.id;
    }
  }

  String _normalizeRoute(String route) {
    final String trimmed = route.trim();
    if (trimmed.isEmpty || trimmed == '/') return '/';
    final String normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return normalized.replaceAll(RegExp(r'/+'), '/');
  }

  BuilderDocument _replaceRoute(
    BuilderDocument document,
    String oldRoute,
    String newRoute,
  ) {
    BuilderNode updateTree(BuilderNode node) {
      final List<BuilderNode> children = node.children.map(updateTree).toList();
      final Map<String, Object?> properties = <String, Object?>{
        ...node.properties,
      };
      bool propertiesChanged = false;
      if (node.properties['route'] == oldRoute) {
        properties['route'] = newRoute;
        propertiesChanged = true;
      }
      if (node.properties['actions'] is List) {
        final List<Map<String, Object?>> actions = BuilderAction.forNode(node);
        bool actionsChanged = false;
        for (int index = 0; index < actions.length; index++) {
          if (actions[index]['type'] == 'navigate' &&
              actions[index]['route'] == oldRoute) {
            actions[index] = <String, Object?>{
              ...actions[index],
              'route': newRoute,
            };
            actionsChanged = true;
          }
        }
        if (actionsChanged) {
          properties['actions'] = actions;
          propertiesChanged = true;
        }
      }
      final bool childrenChanged = children.asMap().entries.any(
        (MapEntry<int, BuilderNode> entry) =>
            !identical(entry.value, node.children[entry.key]),
      );
      if (!propertiesChanged && !childrenChanged) return node;
      return node.copyWith(
        properties: propertiesChanged ? properties : null,
        children: children,
      );
    }

    return document.copyWith(
      root: updateTree(document.root),
      pages:
          document.pages
              .map(
                (BuilderPage page) =>
                    page.copyWith(root: updateTree(page.root)),
              )
              .toList(),
    );
  }
}
