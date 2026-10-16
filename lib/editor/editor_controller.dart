import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/builder_document.dart';
import '../models/builder_widget_definition.dart';

class EditorController extends ChangeNotifier {
  EditorController() {
    _synchronizeAppVariables();
    _resetPreviewDatabase();
  }

  BuilderDocument _document = BuilderDocument.sample();
  final List<BuilderDocument> _undoStack = <BuilderDocument>[];
  final List<BuilderDocument> _redoStack = <BuilderDocument>[];
  static const Duration _editMergeWindow = Duration(milliseconds: 900);
  DateTime? _lastEditAt;
  String? _lastEditKey;
  final List<String> _previewPageStack = <String>[];
  final Map<String, Object?> _appVariableValues = <String, Object?>{};
  final Map<String, Map<String, Object?>> _widgetOverrides =
      <String, Map<String, Object?>>{};
  final Map<String, List<Map<String, Object?>>> _previewDatabase =
      <String, List<Map<String, Object?>>>{};
  final Map<String, int> _nextDatabaseId = <String, int>{};
  String? _projectPath;
  int _documentSessionId = 0;
  int _documentRevision = 0;
  String _selectedNodeId = 'text_1';
  String _activePageId = 'home';
  bool _isDirty = false;
  BuilderNode? _copiedNode;

  BuilderDocument get document => _document;
  List<BuilderPage> get pages => _document.allPages;
  String get activePageId => _activePageId;
  BuilderNode get activeRoot =>
      _document.pageById(_activePageId)?.root ?? _document.root;
  String? get projectPath => _projectPath;
  int get documentSessionId => _documentSessionId;
  int get documentRevision => _documentRevision;
  String get selectedNodeId => _selectedNodeId;
  bool get isDirty => _isDirty;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get runtimeRevision => _runtimeRevision;
  int _runtimeRevision = 0;
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
  Map<String, List<Map<String, Object?>>> get previewDatabaseRecords =>
      Map<String, List<Map<String, Object?>>>.unmodifiable(
        _previewDatabase.map(
          (String collectionId, List<Map<String, Object?>> rows) =>
              MapEntry<String, List<Map<String, Object?>>>(
                collectionId,
                List<Map<String, Object?>>.unmodifiable(
                  rows.map(
                    (Map<String, Object?> row) =>
                        Map<String, Object?>.unmodifiable(row),
                  ),
                ),
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
    List<Map<String, Object?>> cleanActions(Object? raw) {
      if (raw is! List) return <Map<String, Object?>>[];
      final List<Map<String, Object?>> result = <Map<String, Object?>>[];
      for (final Object? value in raw) {
        if (value is! Map) continue;
        final Map<String, Object?> action = <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in value.entries)
            entry.key.toString(): entry.value,
        };
        if (action['variableId'] == id) continue;
        if (action['responseVariableId'] == id) {
          action['responseVariableId'] = '';
        }
        for (final String key in <String>[
          'thenActions',
          'elseActions',
          'actions',
        ]) {
          if (action[key] is List) action[key] = cleanActions(action[key]);
        }
        result.add(action);
      }
      return result;
    }

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
        props['actions'] = cleanActions(rawActions);
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
        customFunctions:
            _document.customFunctions
                .map(
                  (BuilderCustomFunction function) => function.copyWith(
                    actions: cleanActions(function.actions),
                  ),
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
    _runtimeRevision++;
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
    _runtimeRevision++;
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
      historyKey: 'property:$nodeId:${changed.keys.toList()..sort()}',
    );
  }

  String? copySelected() {
    final BuilderNode? selected = activeRoot.findById(_selectedNodeId);
    if (selected == null || selected.id == activeRoot.id) return null;
    _copiedNode = selected;
    return jsonEncode(selected.toJson());
  }

  void pasteNodeJson(String json) {
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is! Map) return;
      final BuilderNode source = BuilderNode.fromJson(
        Map<String, Object?>.from(decoded),
      );
      _insertClonedNode(source, afterSelected: false);
    } on FormatException {
      // Ignore clipboard data that is not a builder widget subtree.
    } on TypeError {
      // Ignore malformed clipboard data without changing the document.
    }
  }

  void pasteCopied() {
    final BuilderNode? copied = _copiedNode;
    if (copied != null) _insertClonedNode(copied, afterSelected: false);
  }

  void duplicateSelected() {
    final BuilderNode? selected = activeRoot.findById(_selectedNodeId);
    if (selected == null || selected.id == activeRoot.id) return;
    _insertClonedNode(selected, afterSelected: true);
  }

  void moveSelection(int offset) {
    final List<BuilderNode> nodes = activeRoot.depthFirst().toList();
    final int index = nodes.indexWhere(
      (BuilderNode node) => node.id == _selectedNodeId,
    );
    final int next = (index + offset).clamp(0, nodes.length - 1);
    if (index >= 0 && next != index) selectNode(nodes[next].id);
  }

  void _insertClonedNode(BuilderNode source, {required bool afterSelected}) {
    final BuilderNode? selected = activeRoot.findById(_selectedNodeId);
    if (selected == null || (afterSelected && selected.id == activeRoot.id)) {
      return;
    }
    final BuilderNode? parent =
        afterSelected
            ? activeRoot.parentOfId(selected.id)
            : selected.acceptsChildren
            ? selected
            : activeRoot.parentOfId(selected.id) ?? _insertionParent();
    if (parent == null || !parent.canAcceptChildType(source.type)) return;

    final Set<String> ids =
        activeRoot.depthFirst().map((BuilderNode node) => node.id).toSet();
    int serial = 1;
    String nextId(String type) {
      String candidate;
      do {
        candidate = '${type}_copy_$serial';
        serial++;
      } while (ids.contains(candidate));
      ids.add(candidate);
      return candidate;
    }

    final Map<String, String> idMap = <String, String>{
      for (final BuilderNode node in source.depthFirst())
        node.id: nextId(node.type),
    };
    final BuilderNode copy = _cloneComponentGroupNode(source, idMap);
    BuilderNode nextRoot = activeRoot.appendToId(parent.id, copy);
    if (afterSelected) {
      nextRoot =
          nextRoot.moveNode(copy.id, selected.id, BuilderDropPosition.after) ??
          nextRoot;
    }
    _selectedNodeId = copy.id;
    _commit(_copyWithActiveRoot(nextRoot));
  }

  void setCustomFunctions(List<BuilderCustomFunction> functions) {
    final String current = jsonEncode(
      _document.customFunctions
          .map((BuilderCustomFunction function) => function.toJson())
          .toList(),
    );
    final String next = jsonEncode(
      functions
          .map((BuilderCustomFunction function) => function.toJson())
          .toList(),
    );
    if (current == next) return;
    _commit(_document.copyWith(customFunctions: functions));
  }

  void setCustomDataStructures(List<BuilderCustomDataStructure> structures) {
    final String current = jsonEncode(
      _document.customDataStructures
          .map((BuilderCustomDataStructure item) => item.toJson())
          .toList(),
    );
    final String next = jsonEncode(
      structures
          .map((BuilderCustomDataStructure item) => item.toJson())
          .toList(),
    );
    if (current == next) return;
    _commit(_document.copyWith(customDataStructures: structures));
  }

  void setAppTheme(BuilderTheme theme) {
    if (jsonEncode(_document.appTheme.toJson()) == jsonEncode(theme.toJson())) {
      return;
    }
    _commit(_document.copyWith(appTheme: theme));
  }

  void addFontAsset(BuilderFontAsset font) {
    final List<BuilderFontAsset> next = <BuilderFontAsset>[
      ..._document.fontAssets.where(
        (BuilderFontAsset item) => item.id != font.id,
      ),
      font,
    ];
    _commit(_document.copyWith(fontAssets: next));
  }

  void removeFontAsset(String id) {
    BuilderFontAsset? removed;
    for (final BuilderFontAsset font in _document.fontAssets) {
      if (font.id == id) removed = font;
    }
    if (removed == null) return;
    final List<BuilderFontAsset> remaining =
        _document.fontAssets
            .where((BuilderFontAsset font) => font.id != id)
            .toList();
    final String selectedFamily = _document.appTheme.fontFamily;
    final bool selectedStillBundled = remaining.any(
      (BuilderFontAsset font) => font.family == selectedFamily,
    );
    _commit(
      _document.copyWith(
        fontAssets: remaining,
        appTheme:
            removed.family == selectedFamily && !selectedStillBundled
                ? _document.appTheme.copyWith(fontFamily: '')
                : _document.appTheme,
      ),
    );
  }

  void setDatabaseCollections(List<BuilderDatabaseCollection> collections) {
    final String current = jsonEncode(
      _document.databaseCollections
          .map((BuilderDatabaseCollection item) => item.toJson())
          .toList(),
    );
    final String next = jsonEncode(
      collections
          .map((BuilderDatabaseCollection item) => item.toJson())
          .toList(),
    );
    if (current == next) return;
    final Set<String> collectionIds =
        collections.map((BuilderDatabaseCollection item) => item.id).toSet();
    final List<BuilderDatabaseRelationship> relationships =
        _document.databaseRelationships
            .where(
              (BuilderDatabaseRelationship relationship) =>
                  collectionIds.contains(relationship.fromCollectionId) &&
                  collectionIds.contains(relationship.toCollectionId),
            )
            .toList();
    _commit(
      _document.copyWith(
        databaseCollections: collections,
        databaseRelationships: relationships,
      ),
      resetDatabase: true,
    );
  }

  void setDatabaseRelationships(
    List<BuilderDatabaseRelationship> relationships,
  ) {
    final String current = jsonEncode(
      _document.databaseRelationships
          .map((BuilderDatabaseRelationship item) => item.toJson())
          .toList(),
    );
    final String next = jsonEncode(
      relationships
          .map((BuilderDatabaseRelationship item) => item.toJson())
          .toList(),
    );
    if (current == next) return;
    _commit(_document.copyWith(databaseRelationships: relationships));
  }

  int? insertDatabaseRecord(String collectionId, Map<String, Object?> record) {
    final List<Map<String, Object?>>? rows = _previewDatabase[collectionId];
    if (rows == null) return null;
    final int id = _nextDatabaseId[collectionId] ?? 1;
    _nextDatabaseId[collectionId] = id + 1;
    rows.add(<String, Object?>{...record, '_id': id});
    _runtimeRevision++;
    notifyListeners();
    return id;
  }

  bool updateDatabaseRecord(
    String collectionId,
    Object? id,
    Map<String, Object?> values,
  ) {
    final List<Map<String, Object?>>? rows = _previewDatabase[collectionId];
    final int? recordId = int.tryParse(id?.toString() ?? '');
    if (rows == null || recordId == null) return false;
    final int index = rows.indexWhere(
      (Map<String, Object?> row) => row['_id'] == recordId,
    );
    if (index < 0) return false;
    rows[index] = <String, Object?>{
      ...rows[index],
      ...values,
      '_id': recordId,
    };
    _runtimeRevision++;
    notifyListeners();
    return true;
  }

  List<Map<String, Object?>> queryDatabaseRecords(
    String collectionId, {
    List<Map<String, Object?>> joins = const <Map<String, Object?>>[],
    List<Map<String, Object?>> filters = const <Map<String, Object?>>[],
    bool matchAny = false,
    String? sortField,
    String? sortAlias,
    String sortAggregate = 'min',
    bool descending = false,
    int limit = 0,
  }) {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Map<String, Object?> baseRow
        in _previewDatabase[collectionId] ?? <Map<String, Object?>>[]) {
      final Map<String, Object?> row = <String, Object?>{...baseRow};
      bool include = true;
      for (final Map<String, Object?> join in joins) {
        final String alias = join['alias']?.toString() ?? '';
        final String relatedCollectionId =
            join['relatedCollectionId']?.toString() ?? '';
        final String baseFieldId = join['baseFieldId']?.toString() ?? '';
        final String relatedFieldId = join['relatedFieldId']?.toString() ?? '';
        final Object? key = baseRow[baseFieldId];
        final List<Map<String, Object?>> matches =
            (_previewDatabase[relatedCollectionId] ?? <Map<String, Object?>>[])
                .where((Map<String, Object?> related) {
                  final Object? relatedKey = related[relatedFieldId];
                  return key != null && _databaseValuesEqual(key, relatedKey);
                })
                .map(
                  (Map<String, Object?> related) => <String, Object?>{
                    ...related,
                  },
                )
                .toList();
        if (join['joinType'] == 'inner' && matches.isEmpty) {
          include = false;
          break;
        }
        row[alias] =
            join['many'] == true
                ? matches
                : matches.isEmpty
                ? null
                : matches.first;
      }
      if (include && _matchesDatabaseQuery(row, filters, matchAny)) {
        rows.add(row);
      }
    }
    if (sortField != null && sortField.isNotEmpty) {
      rows.sort((Map<String, Object?> left, Map<String, Object?> right) {
        final Object? leftValue = _databaseSortValue(
          left,
          sortAlias,
          sortField,
          sortAggregate,
        );
        final Object? rightValue = _databaseSortValue(
          right,
          sortAlias,
          sortField,
          sortAggregate,
        );
        final int order = _compareDatabaseValues(leftValue, rightValue);
        return descending ? -order : order;
      });
    }
    final List<Map<String, Object?>> limitedRows =
        limit > 0 && rows.length > limit ? rows.take(limit).toList() : rows;
    return List<Map<String, Object?>>.unmodifiable(
      limitedRows.map(
        (Map<String, Object?> row) => Map<String, Object?>.unmodifiable(row),
      ),
    );
  }

  Object? _databaseSortValue(
    Map<String, Object?> row,
    String? alias,
    String field,
    String aggregate,
  ) {
    if (alias == null || alias.isEmpty) return row[field];
    final Object? related = row[alias];
    if (related is Map) return related[field];
    if (related is! List) return null;
    final List<Object?> values =
        related
            .whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> item) => item[field])
            .where((Object? value) => value != null)
            .toList();
    if (values.isEmpty) return null;
    values.sort(_compareDatabaseValues);
    return aggregate == 'max' ? values.last : values.first;
  }

  bool _matchesDatabaseQuery(
    Map<String, Object?> row,
    List<Map<String, Object?>> filters,
    bool matchAny,
  ) {
    if (filters.isEmpty) return true;
    if (matchAny) {
      return filters.any((Map<String, Object?> filter) {
        final String alias = filter['joinAlias']?.toString() ?? '';
        final Object? related = alias.isEmpty ? null : row[alias];
        if (alias.isEmpty) return _matchesDatabaseFilterValue(row, filter);
        final Iterable<Object?> candidates =
            related is List
                ? related.isEmpty
                    ? <Object?>[null]
                    : related
                : <Object?>[related];
        return candidates.any(
          (Object? candidate) => _matchesDatabaseFilterValue(candidate, filter),
        );
      });
    }
    final Map<String, List<Map<String, Object?>>> joinedGroups =
        <String, List<Map<String, Object?>>>{};
    for (final Map<String, Object?> filter in filters) {
      final String alias = filter['joinAlias']?.toString() ?? '';
      if (alias.isEmpty) {
        if (!_matchesDatabaseFilterValue(row, filter)) return false;
      } else {
        (joinedGroups[alias] ??= <Map<String, Object?>>[]).add(filter);
      }
    }
    for (final MapEntry<String, List<Map<String, Object?>>> group
        in joinedGroups.entries) {
      final Object? related = row[group.key];
      final Iterable<Object?> candidates =
          related is List
              ? related.isEmpty
                  ? <Object?>[null]
                  : related
              : <Object?>[related];
      if (!candidates.any(
        (Object? candidate) => group.value.every(
          (Map<String, Object?> filter) =>
              _matchesDatabaseFilterValue(candidate, filter),
        ),
      )) {
        return false;
      }
    }
    return true;
  }

  bool _matchesDatabaseFilterValue(
    Object? record,
    Map<String, Object?> filter,
  ) {
    final Map<Object?, Object?>? related =
        record is Map ? Map<Object?, Object?>.from(record) : null;
    final Object? actual =
        related == null ? null : related[filter['field']?.toString() ?? ''];
    final String operator = filter['operator']?.toString() ?? 'equals';
    final String type = filter['type']?.toString() ?? 'string';
    final Object? expected = _databaseFilterValue(filter['value'], type);
    final bool orderedComparable =
        !<String>{'boolean', 'json'}.contains(type) &&
        (!<String>{'integer', 'number'}.contains(type) ||
            (actual is num && expected is num));
    switch (operator) {
      case 'notEquals':
        return !_databaseValuesEqual(actual, expected);
      case 'contains':
        if (actual is String)
          return actual.contains(expected?.toString() ?? '');
        if (actual is Iterable) {
          return actual.any(
            (Object? item) => _databaseValuesEqual(item, expected),
          );
        }
        if (actual is Map) return actual.containsKey(expected);
        return false;
      case 'greaterThan':
        return orderedComparable &&
            actual != null &&
            expected != null &&
            _compareDatabaseValues(actual, expected) > 0;
      case 'greaterThanOrEqual':
        return orderedComparable &&
            actual != null &&
            expected != null &&
            _compareDatabaseValues(actual, expected) >= 0;
      case 'lessThan':
        return orderedComparable &&
            actual != null &&
            expected != null &&
            _compareDatabaseValues(actual, expected) < 0;
      case 'lessThanOrEqual':
        return orderedComparable &&
            actual != null &&
            expected != null &&
            _compareDatabaseValues(actual, expected) <= 0;
      case 'isNull':
        return actual == null;
      case 'isNotNull':
        return actual != null;
      default:
        return _databaseValuesEqual(actual, expected);
    }
  }

  Object? _databaseFilterValue(Object? raw, String type) {
    if (raw is! String) return raw;
    switch (type) {
      case 'integer':
        return int.tryParse(raw) ?? raw;
      case 'number':
        return num.tryParse(raw) ?? raw;
      case 'boolean':
        if (raw.toLowerCase() == 'true') return true;
        if (raw.toLowerCase() == 'false') return false;
        return raw;
      case 'json':
        try {
          return jsonDecode(raw);
        } on FormatException {
          return raw;
        }
      default:
        return raw;
    }
  }

  int _compareDatabaseValues(Object? left, Object? right) {
    if (left == null) return right == null ? 0 : -1;
    if (right == null) return 1;
    if (left is num && right is num) return left.compareTo(right);
    return left.toString().compareTo(right.toString());
  }

  bool _databaseValuesEqual(Object? left, Object? right) {
    if (left is Map && right is Map || left is List && right is List) {
      return jsonEncode(left) == jsonEncode(right);
    }
    return left == right;
  }

  bool deleteDatabaseRecord(String collectionId, Object? id) {
    final List<Map<String, Object?>>? rows = _previewDatabase[collectionId];
    final int? recordId = int.tryParse(id?.toString() ?? '');
    if (rows == null || recordId == null) return false;
    final int before = rows.length;
    rows.removeWhere((Map<String, Object?> row) => row['_id'] == recordId);
    if (rows.length != before) {
      _runtimeRevision++;
      notifyListeners();
    }
    return rows.length != before;
  }

  void _resetPreviewDatabase() {
    _previewDatabase.clear();
    _nextDatabaseId.clear();
    for (final BuilderDatabaseCollection collection
        in _document.databaseCollections) {
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      for (final Map<String, Object?> record in collection.seedRecords) {
        final int id = rows.length + 1;
        rows.add(<String, Object?>{...record, '_id': id});
      }
      _previewDatabase[collection.id] = rows;
      _nextDatabaseId[collection.id] = rows.length + 1;
    }
  }

  void setComponentGroups(List<BuilderComponentGroup> groups) {
    final String current = jsonEncode(
      _document.componentGroups
          .map((BuilderComponentGroup item) => item.toJson())
          .toList(),
    );
    final String next = jsonEncode(
      groups.map((BuilderComponentGroup item) => item.toJson()).toList(),
    );
    if (current == next) return;
    final Map<String, String> namesById = <String, String>{
      for (final BuilderComponentGroup group in groups) group.id: group.name,
    };
    BuilderNode refreshGroupLabels(BuilderNode node) {
      final List<BuilderNode> children =
          node.children.map(refreshGroupLabels).toList();
      final Map<String, Object?> properties = <String, Object?>{
        ...node.properties,
      };
      bool propertiesChanged = false;
      final Object? groupId = properties['groupId'];
      if (node.type == 'componentGroup' &&
          groupId is String &&
          namesById.containsKey(groupId) &&
          properties['groupName'] != namesById[groupId]) {
        properties['groupName'] = namesById[groupId];
        propertiesChanged = true;
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

    _commit(
      _document.copyWith(
        componentGroups:
            groups
                .map(
                  (BuilderComponentGroup group) =>
                      group.copyWith(root: refreshGroupLabels(group.root)),
                )
                .toList(),
        root: refreshGroupLabels(_document.root),
        pages:
            _document.pages
                .map(
                  (BuilderPage page) =>
                      page.copyWith(root: refreshGroupLabels(page.root)),
                )
                .toList(),
      ),
    );
  }

  String addComponentGroup({
    required String name,
    required String sourceNodeId,
  }) {
    final BuilderNode? source = activeRoot.findById(sourceNodeId);
    if (source == null ||
        source.id == activeRoot.id ||
        <String>{
          'scaffold',
          'appBar',
          'floatingActionButton',
        }.contains(source.type)) {
      return '';
    }
    int suffix = 1;
    final Set<String> ids =
        _document.componentGroups
            .map((BuilderComponentGroup group) => group.id)
            .toSet();
    while (ids.contains('component_group_$suffix')) {
      suffix++;
    }
    final String id = 'component_group_$suffix';
    _commit(
      _document.copyWith(
        componentGroups: <BuilderComponentGroup>[
          ..._document.componentGroups,
          BuilderComponentGroup(id: id, name: name, root: source),
        ],
      ),
    );
    return id;
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
    String? groupId,
  }) {
    BuilderComponentGroup? componentGroup;
    if (type == 'componentGroup') {
      for (final BuilderComponentGroup group in _document.componentGroups) {
        if (group.id == groupId) componentGroup = group;
      }
      if (componentGroup == null) return;
    }
    final Map<String, Object?> properties = defaultBuilderWidgetProperties(
      type,
      componentGroupId: componentGroup?.id,
      componentGroupName: componentGroup?.name,
    );
    if (properties.isEmpty) return;

    BuilderNode? parent;
    if (targetId == null &&
        <String>{
          'appBar',
          'floatingActionButton',
          'extendedFloatingActionButton',
          'bottomAppBar',
          'bottomSheet',
          'navigationBar',
          'navigationDrawer',
          'navigationRail',
        }.contains(type)) {
      parent = _firstScaffold() ?? _insertionParent();
    } else if (targetId == null) {
      parent = _insertionParent();
    } else if (position == BuilderDropPosition.inside) {
      final BuilderNode? target = activeRoot.findById(targetId);
      parent = target?.acceptsChildren == true ? target : _insertionParent();
    } else {
      parent = activeRoot.parentOfId(targetId);
    }
    if (type == 'expanded') {
      if (targetId == null) {
        parent = _flexInsertionParent();
      } else if (parent?.type != 'row' && parent?.type != 'column') {
        return;
      }
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
    ids.add(id);
    final List<BuilderNode> children = <BuilderNode>[];
    if (componentGroup != null) {
      final Map<String, String> idMap = <String, String>{};
      for (final BuilderNode templateNode in componentGroup.root.depthFirst()) {
        String templatePrefix = templateNode.type;
        int templateSuffix = ids.length + 1;
        while (ids.contains('${templatePrefix}_$templateSuffix')) {
          templateSuffix++;
        }
        final String clonedId = '${templatePrefix}_$templateSuffix';
        ids.add(clonedId);
        idMap[templateNode.id] = clonedId;
      }
      children.add(_cloneComponentGroupNode(componentGroup.root, idMap));
    }
    final BuilderNode node = BuilderNode(
      id: id,
      type: type,
      properties: properties,
      children: children,
    );
    BuilderNode nextRoot = activeRoot.appendToId(parent.id, node);
    if (targetId != null && position != BuilderDropPosition.inside) {
      nextRoot = nextRoot.moveNode(id, targetId, position) ?? nextRoot;
    }
    _selectedNodeId = id;
    _commit(_copyWithActiveRoot(nextRoot));
  }

  BuilderNode _cloneComponentGroupNode(
    BuilderNode source,
    Map<String, String> idMap,
  ) {
    final Map<String, Object?> properties = <String, Object?>{
      ...source.properties,
    };
    final Object? rawActions = properties['actions'];
    if (rawActions is List) {
      properties['actions'] = _remapGroupActionTargets(rawActions, idMap);
    }
    return BuilderNode(
      id: idMap[source.id] ?? source.id,
      type: source.type,
      properties: properties,
      children:
          source.children
              .map(
                (BuilderNode child) => _cloneComponentGroupNode(child, idMap),
              )
              .toList(),
    );
  }

  List<Object?> _remapGroupActionTargets(
    List<Object?> rawActions,
    Map<String, String> idMap,
  ) =>
      rawActions.map<Object?>((Object? rawAction) {
        if (rawAction is! Map) return rawAction;
        final Map<String, Object?> action = <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in rawAction.entries)
            entry.key.toString(): entry.value,
        };
        if (action['targetNodeId'] is String &&
            idMap.containsKey(action['targetNodeId'])) {
          action['targetNodeId'] = idMap[action['targetNodeId']];
          if (action['targetPageId'] is String) {
            action['targetPageId'] = _activePageId;
          }
        }
        for (final String key in <String>[
          'thenActions',
          'elseActions',
          'actions',
        ]) {
          final Object? nested = action[key];
          if (nested is List) {
            action[key] = _remapGroupActionTargets(nested, idMap);
          }
        }
        return action;
      }).toList();

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
    _clearEditMerge();
    _redoStack.add(_document);
    _document = _undoStack.removeLast();
    _documentRevision++;
    _isDirty = true;
    _synchronizeAppVariables();
    _resetPreviewDatabase();
    _normalizeSelection();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _clearEditMerge();
    _undoStack.add(_document);
    _document = _redoStack.removeLast();
    _documentRevision++;
    _isDirty = true;
    _synchronizeAppVariables();
    _resetPreviewDatabase();
    _normalizeSelection();
    notifyListeners();
  }

  void open(BuilderDocument document, String path, {bool isDirty = false}) {
    _clearEditMerge();
    _copiedNode = null;
    _documentSessionId++;
    _documentRevision++;
    _document = document;
    _projectPath = path;
    _previewPageStack.clear();
    _activePageId = document.pageById(document.initialPageId)?.id ?? 'home';
    _selectedNodeId = activeRoot.id;
    _undoStack.clear();
    _redoStack.clear();
    _isDirty = isDirty;
    _appVariableValues.clear();
    _widgetOverrides.clear();
    _synchronizeAppVariables();
    _resetPreviewDatabase();
    notifyListeners();
  }

  void createNew() {
    _clearEditMerge();
    _copiedNode = null;
    _documentSessionId++;
    _documentRevision++;
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
    _resetPreviewDatabase();
    notifyListeners();
  }

  void markSaved(
    String path, {
    required int savedRevision,
    required BuilderDocument savedDocument,
  }) {
    _projectPath = path;
    if (_documentRevision == savedRevision) {
      _document = savedDocument;
      _isDirty = false;
    }
    notifyListeners();
  }

  void _commit(
    BuilderDocument next, {
    bool resetDatabase = false,
    String? historyKey,
  }) {
    final DateTime now = DateTime.now();
    final bool mergeEdit =
        historyKey != null &&
        historyKey == _lastEditKey &&
        _lastEditAt != null &&
        now.difference(_lastEditAt!) <= _editMergeWindow;
    if (!mergeEdit) {
      _undoStack.add(_document);
      if (_undoStack.length > 100) _undoStack.removeAt(0);
    }
    _lastEditKey = historyKey;
    _lastEditAt = historyKey == null ? null : now;
    _redoStack.clear();
    _document = next;
    _documentRevision++;
    _synchronizeAppVariables();
    if (resetDatabase) _resetPreviewDatabase();
    _isDirty = true;
    notifyListeners();
  }

  void _clearEditMerge() {
    _lastEditAt = null;
    _lastEditKey = null;
  }

  BuilderNode? _insertionParent() {
    final BuilderNode? selected = activeRoot.findById(_selectedNodeId);
    if (selected == null) return _firstContainer();
    if (selected.acceptsChildren) return selected;
    final BuilderNode? parent = activeRoot.parentOfId(selected.id);
    if (parent?.acceptsChildren ?? false) return parent;
    return _firstContainer();
  }

  BuilderNode? _flexInsertionParent() {
    BuilderNode? current = activeRoot.findById(_selectedNodeId);
    while (current != null) {
      if (current.type == 'row' || current.type == 'column') return current;
      current = activeRoot.parentOfId(current.id);
    }
    for (final BuilderNode node in activeRoot.depthFirst()) {
      if (node.type == 'row' || node.type == 'column') return node;
    }
    return null;
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
    List<Map<String, Object?>> updateActions(Object? raw) {
      if (raw is! List) return <Map<String, Object?>>[];
      return raw.whereType<Map<Object?, Object?>>().map((
        Map<Object?, Object?> value,
      ) {
        final Map<String, Object?> action = <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in value.entries)
            entry.key.toString(): entry.value,
        };
        if (action['type'] == 'navigate' && action['route'] == oldRoute) {
          action['route'] = newRoute;
        }
        for (final String key in <String>[
          'thenActions',
          'elseActions',
          'actions',
        ]) {
          if (action[key] is List) action[key] = updateActions(action[key]);
        }
        return action;
      }).toList();
    }

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
        final List<Map<String, Object?>> actions = updateActions(
          node.properties['actions'],
        );
        if (jsonEncode(actions) != jsonEncode(node.properties['actions'])) {
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
