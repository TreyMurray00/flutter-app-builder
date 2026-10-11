import 'dart:collection';

const int currentSchemaVersion = 4;

enum BuilderDropPosition { before, inside, after }

class BuilderDocument {
  BuilderDocument({
    required this.name,
    required this.seedColor,
    required this.root,
    this.homePageName = 'Home',
    this.homePageRoute = '/',
    List<BuilderPage> pages = const <BuilderPage>[],
    List<BuilderVariable> variables = const <BuilderVariable>[],
    this.initialPageId = 'home',
    this.schemaVersion = currentSchemaVersion,
  }) : pages = List<BuilderPage>.unmodifiable(pages),
       variables = List<BuilderVariable>.unmodifiable(variables);

  final String name;
  final int seedColor;
  final BuilderNode root;
  final String homePageName;
  final String homePageRoute;

  /// Pages other than the home page. The home root stays in [root] to retain
  /// compatibility with older project code and schema version 1 files.
  final List<BuilderPage> pages;
  final List<BuilderVariable> variables;
  final String initialPageId;
  final int schemaVersion;

  List<BuilderPage> get allPages => <BuilderPage>[
    BuilderPage(
      id: 'home',
      name: homePageName,
      route: homePageRoute,
      root: root,
    ),
    ...pages,
  ];

  BuilderPage? pageById(String id) {
    for (final BuilderPage page in allPages) {
      if (page.id == id) return page;
    }
    return null;
  }

  factory BuilderDocument.sample() {
    return BuilderDocument(
      name: 'My First App',
      seedColor: 0xFF6750A4,
      root: BuilderNode(
        id: 'scaffold_1',
        type: 'scaffold',
        properties: <String, Object?>{},
        children: <BuilderNode>[
          BuilderNode(
            id: 'column_1',
            type: 'column',
            properties: <String, Object?>{
              'crossAxisAlignment': 'start',
              'mainAxisAlignment': 'start',
            },
            children: <BuilderNode>[
              BuilderNode(
                id: 'text_1',
                type: 'text',
                properties: <String, Object?>{
                  'text': 'Hello from your local builder',
                  'fontSize': 26.0,
                  'fontWeight': 'bold',
                },
                children: <BuilderNode>[],
              ),
            ],
          ),
        ],
      ),
    );
  }

  BuilderDocument copyWith({
    String? name,
    int? seedColor,
    BuilderNode? root,
    String? homePageName,
    String? homePageRoute,
    List<BuilderPage>? pages,
    List<BuilderVariable>? variables,
    String? initialPageId,
    int? schemaVersion,
  }) {
    return BuilderDocument(
      name: name ?? this.name,
      seedColor: seedColor ?? this.seedColor,
      root: root ?? this.root,
      homePageName: homePageName ?? this.homePageName,
      homePageRoute: homePageRoute ?? this.homePageRoute,
      pages: pages ?? this.pages,
      variables: variables ?? this.variables,
      initialPageId: initialPageId ?? this.initialPageId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'name': name,
    'theme': <String, Object?>{'seedColor': seedColor},
    'root': root.toJson(),
    'pages': allPages.map((BuilderPage page) => page.toJson()).toList(),
    'variables':
        variables.map((BuilderVariable variable) => variable.toJson()).toList(),
    'initialPageId': initialPageId,
  };

  factory BuilderDocument.fromJson(Map<String, Object?> json) {
    final Object? rawVersion = json['schemaVersion'];
    final int schemaVersion = rawVersion is int ? rawVersion : 0;
    if (schemaVersion < 1 || schemaVersion > currentSchemaVersion) {
      throw FormatException(
        'Project schema $schemaVersion is not supported. '
        'This version supports schema $currentSchemaVersion.',
      );
    }

    final Object? rawTheme = json['theme'];
    final Map<String, Object?> theme =
        rawTheme is Map
            ? Map<String, Object?>.from(rawTheme)
            : <String, Object?>{};
    final Object? rawRoot = json['root'];
    if (rawRoot is! Map) {
      throw const FormatException('Project is missing its root widget.');
    }

    final List<BuilderPage> parsedPages = <BuilderPage>[];
    final List<BuilderVariable> parsedVariables = <BuilderVariable>[];
    BuilderNode homeRoot = BuilderNode.fromJson(
      Map<String, Object?>.from(rawRoot),
    );
    String homeName = 'Home';
    String homeRoute = '/';
    final Object? rawPages = json['pages'];
    if (rawPages is List) {
      for (final Object? rawPage in rawPages) {
        if (rawPage is! Map) {
          throw const FormatException('Page entries must be objects.');
        }
        final BuilderPage page = BuilderPage.fromJson(
          Map<String, Object?>.from(rawPage),
        );
        if (page.id == 'home') {
          homeRoot = page.root;
          homeName = page.name;
          homeRoute = page.route;
        } else {
          parsedPages.add(page);
        }
      }
    }
    final Object? rawVariables = json['variables'];
    if (rawVariables is List) {
      for (final Object? rawVariable in rawVariables) {
        if (rawVariable is! Map) {
          throw const FormatException('Variable entries must be objects.');
        }
        parsedVariables.add(
          BuilderVariable.fromJson(Map<String, Object?>.from(rawVariable)),
        );
      }
    }

    return BuilderDocument(
      // Schema 1 documents are accepted and upgraded when they are next saved.
      schemaVersion: currentSchemaVersion,
      name: json['name'] is String ? json['name']! as String : 'Untitled App',
      seedColor:
          theme['seedColor'] is int ? theme['seedColor']! as int : 0xFF6750A4,
      root: homeRoot,
      homePageName: homeName,
      homePageRoute: homeRoute,
      pages: parsedPages,
      variables: parsedVariables,
      initialPageId:
          json['initialPageId'] is String &&
                  <String>{
                    'home',
                    ...parsedPages.map((BuilderPage p) => p.id),
                  }.contains(json['initialPageId'])
              ? json['initialPageId']! as String
              : 'home',
    );
  }
}

class BuilderPage {
  const BuilderPage({
    required this.id,
    required this.name,
    required this.route,
    required this.root,
  });

  final String id;
  final String name;
  final String route;
  final BuilderNode root;

  BuilderPage copyWith({String? name, String? route, BuilderNode? root}) =>
      BuilderPage(
        id: id,
        name: name ?? this.name,
        route: route ?? this.route,
        root: root ?? this.root,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'route': route,
    'root': root.toJson(),
  };

  factory BuilderPage.fromJson(Map<String, Object?> json) {
    final Object? rawRoot = json['root'];
    if (json['id'] is! String ||
        json['name'] is! String ||
        json['route'] is! String ||
        rawRoot is! Map) {
      throw const FormatException(
        'A page is missing its id, name, route, or root.',
      );
    }
    return BuilderPage(
      id: json['id']! as String,
      name: json['name']! as String,
      route: json['route']! as String,
      root: BuilderNode.fromJson(Map<String, Object?>.from(rawRoot)),
    );
  }
}

class BuilderVariable {
  const BuilderVariable({
    required this.id,
    required this.name,
    required this.type,
    required this.initialValue,
  });

  final String id;
  final String name;

  /// Supported: `string`, `number` (legacy), `integer`, `double`, `boolean`,
  /// `stringList`, and `json`.
  final String type;
  final Object initialValue;

  BuilderVariable copyWith({
    String? name,
    String? type,
    Object? initialValue,
  }) => BuilderVariable(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    initialValue: initialValue ?? this.initialValue,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'type': type,
    'initialValue': initialValue,
  };

  factory BuilderVariable.fromJson(Map<String, Object?> json) {
    final String type =
        json['type'] is String ? json['type']! as String : 'string';
    final Object? rawValue = json['initialValue'];
    final Object initialValue = switch (type) {
      'number' || 'double' => rawValue is num ? rawValue : 0,
      'integer' => rawValue is num ? rawValue.toInt() : 0,
      'boolean' => rawValue is bool ? rawValue : false,
      'stringList' =>
        rawValue is List
            ? rawValue.map((Object? item) => item.toString()).toList()
            : <String>[],
      'json' =>
        rawValue is Map ||
                rawValue is List ||
                rawValue is String ||
                rawValue is num ||
                rawValue is bool
            ? rawValue!
            : <String, Object?>{},
      _ => rawValue is String ? rawValue : '',
    };
    if (json['id'] is! String ||
        json['name'] is! String ||
        !<String>{
          'string',
          'number',
          'integer',
          'double',
          'boolean',
          'stringList',
          'json',
        }.contains(type)) {
      throw const FormatException('An app variable has invalid metadata.');
    }
    return BuilderVariable(
      id: json['id']! as String,
      name: json['name']! as String,
      type: type,
      initialValue: initialValue,
    );
  }
}

class BuilderNode {
  BuilderNode({
    required this.id,
    required this.type,
    required Map<String, Object?> properties,
    required List<BuilderNode> children,
  }) : properties = UnmodifiableMapView<String, Object?>(properties),
       children = List<BuilderNode>.unmodifiable(children);

  final String id;
  final String type;
  final Map<String, Object?> properties;
  final List<BuilderNode> children;

  bool get acceptsChildren =>
      type == 'scaffold' ||
      type == 'column' ||
      type == 'row' ||
      type == 'container' ||
      type == 'stack' ||
      type == 'listView' ||
      type == 'gridView' ||
      type == 'pageView' ||
      type == 'swipeableStack' ||
      type == 'card' ||
      type == 'padding';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'properties': properties,
    'children': children.map((BuilderNode child) => child.toJson()).toList(),
  };

  factory BuilderNode.fromJson(Map<String, Object?> json) {
    final Object? rawProperties = json['properties'];
    final Object? rawChildren = json['children'];
    if (json['id'] is! String || json['type'] is! String) {
      throw const FormatException('A widget is missing its id or type.');
    }
    if (rawProperties != null && rawProperties is! Map) {
      throw const FormatException('Widget properties must be an object.');
    }
    if (rawChildren != null && rawChildren is! List) {
      throw const FormatException('Widget children must be a list.');
    }
    final Map<String, Object?> properties =
        rawProperties is Map
            ? Map<String, Object?>.from(rawProperties)
            : <String, Object?>{};
    final List<BuilderNode> children =
        rawChildren is List
            ? rawChildren.map((Object? child) {
              if (child is! Map) {
                throw const FormatException('Widget child must be an object.');
              }
              return BuilderNode.fromJson(Map<String, Object?>.from(child));
            }).toList()
            : <BuilderNode>[];
    return BuilderNode(
      id: json['id']! as String,
      type: json['type']! as String,
      properties: properties,
      children: children,
    );
  }

  BuilderNode copyWith({
    Map<String, Object?>? properties,
    List<BuilderNode>? children,
  }) {
    return BuilderNode(
      id: id,
      type: type,
      properties: properties ?? this.properties,
      children: children ?? this.children,
    );
  }

  BuilderNode? findById(String targetId) {
    if (id == targetId) return this;
    for (final BuilderNode child in children) {
      final BuilderNode? match = child.findById(targetId);
      if (match != null) return match;
    }
    return null;
  }

  BuilderNode updateById(
    String targetId,
    BuilderNode Function(BuilderNode node) update,
  ) {
    if (id == targetId) return update(this);
    bool changed = false;
    final List<BuilderNode> updatedChildren =
        children.map((BuilderNode child) {
          final BuilderNode next = child.updateById(targetId, update);
          changed = changed || !identical(child, next);
          return next;
        }).toList();
    return changed ? copyWith(children: updatedChildren) : this;
  }

  BuilderNode appendToId(String targetId, BuilderNode child) {
    return updateById(targetId, (BuilderNode node) {
      if (!node.acceptsChildren) return node;
      return node.copyWith(children: <BuilderNode>[...node.children, child]);
    });
  }

  BuilderNode? parentOfId(String targetId) {
    for (final BuilderNode child in children) {
      if (child.id == targetId) return this;
      final BuilderNode? parent = child.parentOfId(targetId);
      if (parent != null) return parent;
    }
    return null;
  }

  BuilderNode removeById(String targetId) {
    bool changed = false;
    final List<BuilderNode> remainingChildren = <BuilderNode>[];
    for (final BuilderNode child in children) {
      if (child.id == targetId) {
        changed = true;
      } else {
        final BuilderNode remaining = child.removeById(targetId);
        changed = changed || !identical(child, remaining);
        remainingChildren.add(remaining);
      }
    }
    return changed ? copyWith(children: remainingChildren) : this;
  }

  BuilderNode? moveNode(
    String sourceId,
    String targetId,
    BuilderDropPosition position,
  ) {
    final BuilderNode? source = findById(sourceId);
    final BuilderNode? target = findById(targetId);
    if (source == null || target == null || sourceId == id) return null;
    if (sourceId == targetId ||
        source.depthFirst().any((BuilderNode node) => node.id == targetId)) {
      return null;
    }
    if (position == BuilderDropPosition.inside && !target.acceptsChildren) {
      return null;
    }
    final BuilderNode withoutSource = removeById(sourceId);
    if (position == BuilderDropPosition.inside) {
      return withoutSource.updateById(targetId, (BuilderNode node) {
        return node.copyWith(children: <BuilderNode>[...node.children, source]);
      });
    }

    final BuilderNode? targetParent = parentOfId(targetId);
    if (targetParent == null) return null;
    return withoutSource.updateById(targetParent.id, (BuilderNode parent) {
      final List<BuilderNode> children = List<BuilderNode>.of(parent.children);
      final int targetIndex = children.indexWhere(
        (BuilderNode node) => node.id == targetId,
      );
      if (targetIndex < 0) return parent;
      final int insertIndex =
          position == BuilderDropPosition.before
              ? targetIndex
              : targetIndex + 1;
      children.insert(insertIndex, source);
      return parent.copyWith(children: children);
    });
  }

  Iterable<BuilderNode> depthFirst() sync* {
    yield this;
    for (final BuilderNode child in children) {
      yield* child.depthFirst();
    }
  }
}
