import 'dart:collection';

import 'builder_widget_definition.dart';

const int currentSchemaVersion = 10;

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
    List<BuilderCustomFunction> customFunctions =
        const <BuilderCustomFunction>[],
    List<BuilderCustomDataStructure> customDataStructures =
        const <BuilderCustomDataStructure>[],
    List<BuilderComponentGroup> componentGroups =
        const <BuilderComponentGroup>[],
    this.appTheme = const BuilderTheme(),
    List<BuilderDatabaseCollection> databaseCollections =
        const <BuilderDatabaseCollection>[],
    List<BuilderDatabaseRelationship> databaseRelationships =
        const <BuilderDatabaseRelationship>[],
    List<BuilderFontAsset> fontAssets = const <BuilderFontAsset>[],
    this.initialPageId = 'home',
    this.schemaVersion = currentSchemaVersion,
  }) : pages = List<BuilderPage>.unmodifiable(pages),
       variables = List<BuilderVariable>.unmodifiable(variables),
       customFunctions = List<BuilderCustomFunction>.unmodifiable(
         customFunctions,
       ),
       customDataStructures = List<BuilderCustomDataStructure>.unmodifiable(
         customDataStructures,
       ),
       componentGroups = List<BuilderComponentGroup>.unmodifiable(
         componentGroups,
       ),
       databaseCollections = List<BuilderDatabaseCollection>.unmodifiable(
         databaseCollections,
       ),
       databaseRelationships =
           List<BuilderDatabaseRelationship>.unmodifiable(
             databaseRelationships,
           ),
       fontAssets = List<BuilderFontAsset>.unmodifiable(fontAssets);

  final String name;
  final int seedColor;
  final BuilderNode root;
  final String homePageName;
  final String homePageRoute;

  /// Pages other than the home page. The home root stays in [root] to retain
  /// compatibility with older project code and schema version 1 files.
  final List<BuilderPage> pages;
  final List<BuilderVariable> variables;
  final List<BuilderCustomFunction> customFunctions;
  final List<BuilderCustomDataStructure> customDataStructures;
  final List<BuilderComponentGroup> componentGroups;
  final BuilderTheme appTheme;
  final List<BuilderDatabaseCollection> databaseCollections;
  final List<BuilderDatabaseRelationship> databaseRelationships;
  final List<BuilderFontAsset> fontAssets;
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
    List<BuilderCustomFunction>? customFunctions,
    List<BuilderCustomDataStructure>? customDataStructures,
    List<BuilderComponentGroup>? componentGroups,
    BuilderTheme? appTheme,
    List<BuilderDatabaseCollection>? databaseCollections,
    List<BuilderDatabaseRelationship>? databaseRelationships,
    List<BuilderFontAsset>? fontAssets,
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
      customFunctions: customFunctions ?? this.customFunctions,
      customDataStructures: customDataStructures ?? this.customDataStructures,
      componentGroups: componentGroups ?? this.componentGroups,
      appTheme: appTheme ?? this.appTheme,
      databaseCollections: databaseCollections ?? this.databaseCollections,
      databaseRelationships:
          databaseRelationships ?? this.databaseRelationships,
      fontAssets: fontAssets ?? this.fontAssets,
      initialPageId: initialPageId ?? this.initialPageId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'name': name,
    'theme': <String, Object?>{'seedColor': seedColor, ...appTheme.toJson()},
    'root': root.toJson(),
    'pages': allPages.map((BuilderPage page) => page.toJson()).toList(),
    'variables':
        variables.map((BuilderVariable variable) => variable.toJson()).toList(),
    'customFunctions':
        customFunctions
            .map((BuilderCustomFunction function) => function.toJson())
            .toList(),
    'customDataStructures':
        customDataStructures
            .map((BuilderCustomDataStructure structure) => structure.toJson())
            .toList(),
    'componentGroups':
        componentGroups
            .map((BuilderComponentGroup group) => group.toJson())
            .toList(),
    'databaseCollections':
        databaseCollections
            .map((BuilderDatabaseCollection collection) => collection.toJson())
            .toList(),
    'databaseRelationships':
        databaseRelationships
            .map((BuilderDatabaseRelationship relationship) =>
                relationship.toJson())
            .toList(),
    'fontAssets':
        fontAssets.map((BuilderFontAsset font) => font.toJson()).toList(),
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
    final List<BuilderCustomFunction> parsedFunctions =
        <BuilderCustomFunction>[];
    final List<BuilderCustomDataStructure> parsedDataStructures =
        <BuilderCustomDataStructure>[];
    final List<BuilderComponentGroup> parsedComponentGroups =
        <BuilderComponentGroup>[];
    final List<BuilderDatabaseCollection> parsedDatabaseCollections =
        <BuilderDatabaseCollection>[];
    final List<BuilderDatabaseRelationship> parsedDatabaseRelationships =
        <BuilderDatabaseRelationship>[];
    final List<BuilderFontAsset> parsedFontAssets = <BuilderFontAsset>[];
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
    final Object? rawFunctions = json['customFunctions'];
    if (rawFunctions is List) {
      for (final Object? rawFunction in rawFunctions) {
        if (rawFunction is! Map) {
          throw const FormatException(
            'Custom function entries must be objects.',
          );
        }
        parsedFunctions.add(
          BuilderCustomFunction.fromJson(
            Map<String, Object?>.from(rawFunction),
          ),
        );
      }
    }
    final Object? rawDataStructures = json['customDataStructures'];
    if (rawDataStructures is List) {
      for (final Object? rawStructure in rawDataStructures) {
        if (rawStructure is! Map) {
          throw const FormatException(
            'Custom data structure entries must be objects.',
          );
        }
        parsedDataStructures.add(
          BuilderCustomDataStructure.fromJson(
            Map<String, Object?>.from(rawStructure),
          ),
        );
      }
    }
    final Object? rawGroups = json['componentGroups'];
    if (rawGroups is List) {
      for (final Object? rawGroup in rawGroups) {
        if (rawGroup is! Map) {
          throw const FormatException(
            'Component group entries must be objects.',
          );
        }
        parsedComponentGroups.add(
          BuilderComponentGroup.fromJson(Map<String, Object?>.from(rawGroup)),
        );
      }
    }
    final Object? rawCollections = json['databaseCollections'];
    if (rawCollections is List) {
      for (final Object? rawCollection in rawCollections) {
        if (rawCollection is! Map) {
          throw const FormatException('Database collections must be objects.');
        }
        parsedDatabaseCollections.add(
          BuilderDatabaseCollection.fromJson(
            Map<String, Object?>.from(rawCollection),
          ),
        );
      }
    }
    final Object? rawRelationships = json['databaseRelationships'];
    if (rawRelationships is List) {
      for (final Object? rawRelationship in rawRelationships) {
        if (rawRelationship is! Map) {
          throw const FormatException(
            'Database relationships must be objects.',
          );
        }
        parsedDatabaseRelationships.add(
          BuilderDatabaseRelationship.fromJson(
            Map<String, Object?>.from(rawRelationship),
          ),
        );
      }
    }
    final Object? rawFonts = json['fontAssets'];
    if (rawFonts is List) {
      for (final Object? rawFont in rawFonts) {
        if (rawFont is! Map) {
          throw const FormatException('Font assets must be objects.');
        }
        parsedFontAssets.add(
          BuilderFontAsset.fromJson(Map<String, Object?>.from(rawFont)),
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
      customFunctions: parsedFunctions,
      customDataStructures: parsedDataStructures,
      componentGroups: parsedComponentGroups,
      appTheme: BuilderTheme.fromJson(theme),
      databaseCollections: parsedDatabaseCollections,
      databaseRelationships: parsedDatabaseRelationships,
      fontAssets: parsedFontAssets,
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

class BuilderTheme {
  const BuilderTheme({
    this.brightness = 'light',
    this.fontFamily = '',
    this.cornerRadius = 12,
    this.backgroundColor,
    this.textColor,
  });

  /// `system` follows the device; existing documents default to `light`.
  final String brightness;
  final String fontFamily;
  final double cornerRadius;
  final int? backgroundColor;
  final int? textColor;

  BuilderTheme copyWith({
    String? brightness,
    String? fontFamily,
    double? cornerRadius,
    int? backgroundColor,
    int? textColor,
    bool clearBackgroundColor = false,
    bool clearTextColor = false,
  }) => BuilderTheme(
    brightness: brightness ?? this.brightness,
    fontFamily: fontFamily ?? this.fontFamily,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    backgroundColor:
        clearBackgroundColor ? null : backgroundColor ?? this.backgroundColor,
    textColor: clearTextColor ? null : textColor ?? this.textColor,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'brightness': brightness,
    'fontFamily': fontFamily,
    'cornerRadius': cornerRadius,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
    if (textColor != null) 'textColor': textColor,
  };

  factory BuilderTheme.fromJson(Map<String, Object?> json) => BuilderTheme(
    brightness:
        <String>{'light', 'dark', 'system'}.contains(json['brightness'])
            ? json['brightness']! as String
            : 'light',
    fontFamily:
        json['fontFamily'] is String ? json['fontFamily']! as String : '',
    cornerRadius:
        json['cornerRadius'] is num
            ? (json['cornerRadius']! as num)
                .toDouble()
                .clamp(0.0, 48.0)
                .toDouble()
            : 12,
    backgroundColor:
        json['backgroundColor'] is int ? json['backgroundColor']! as int : null,
    textColor: json['textColor'] is int ? json['textColor']! as int : null,
  );
}

class BuilderFontAsset {
  const BuilderFontAsset({
    required this.id,
    required this.family,
    required this.source,
    this.weight = 400,
  });

  final String id;
  final String family;
  final String source;
  final int weight;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'family': family,
    'source': source,
    'weight': weight,
  };

  factory BuilderFontAsset.fromJson(Map<String, Object?> json) {
    if (json['id'] is! String ||
        json['family'] is! String ||
        json['source'] is! String) {
      throw const FormatException(
        'A font asset is missing its id, family, or source path.',
      );
    }
    final int weight =
        json['weight'] is num ? (json['weight']! as num).round() : 400;
    return BuilderFontAsset(
      id: json['id']! as String,
      family: json['family']! as String,
      source: json['source']! as String,
      weight: weight.clamp(100, 900),
    );
  }
}

class BuilderDatabaseCollection {
  BuilderDatabaseCollection({
    required this.id,
    required this.name,
    List<BuilderDatabaseField> fields = const <BuilderDatabaseField>[],
    List<Map<String, Object?>> seedRecords = const <Map<String, Object?>>[],
  }) : fields = List<BuilderDatabaseField>.unmodifiable(fields),
       seedRecords = List<Map<String, Object?>>.unmodifiable(
         seedRecords.map(
           (Map<String, Object?> record) =>
               Map<String, Object?>.unmodifiable(record),
         ),
       );

  final String id;
  final String name;
  final List<BuilderDatabaseField> fields;
  final List<Map<String, Object?>> seedRecords;

  BuilderDatabaseCollection copyWith({
    String? name,
    List<BuilderDatabaseField>? fields,
    List<Map<String, Object?>>? seedRecords,
  }) => BuilderDatabaseCollection(
    id: id,
    name: name ?? this.name,
    fields: fields ?? this.fields,
    seedRecords: seedRecords ?? this.seedRecords,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'fields': fields.map((BuilderDatabaseField field) => field.toJson()).toList(),
    'seedRecords': seedRecords,
  };

  factory BuilderDatabaseCollection.fromJson(Map<String, Object?> json) {
    final Object? rawRecords = json['seedRecords'];
    if (json['id'] is! String || json['name'] is! String) {
      throw const FormatException(
        'A database collection needs an id and name.',
      );
    }
    if (rawRecords != null && rawRecords is! List) {
      throw const FormatException('Seed records must be a list.');
    }
    final Object? rawFields = json['fields'];
    if (rawFields != null && rawFields is! List) {
      throw const FormatException('Database fields must be a list.');
    }
    final List<BuilderDatabaseField> fields = <BuilderDatabaseField>[];
    if (rawFields is List) {
      for (final Object? rawField in rawFields) {
        if (rawField is! Map) {
          throw const FormatException('Each database field must be an object.');
        }
        fields.add(
          BuilderDatabaseField.fromJson(Map<String, Object?>.from(rawField)),
        );
      }
    }
    final List<Map<String, Object?>> records = <Map<String, Object?>>[];
    if (rawRecords is List) {
      for (final Object? record in rawRecords) {
        if (record is! Map) {
          throw const FormatException('Each seed record must be an object.');
        }
        records.add(Map<String, Object?>.from(record));
      }
    }
    return BuilderDatabaseCollection(
      id: json['id']! as String,
      name: json['name']! as String,
      fields: fields,
      seedRecords: records,
    );
  }
}

class BuilderDatabaseField {
  const BuilderDatabaseField({
    required this.id,
    required this.name,
    this.type = 'string',
    this.required = false,
    this.primaryKey = false,
    this.unique = false,
  });

  final String id;
  final String name;
  final String type;
  final bool required;
  final bool primaryKey;
  final bool unique;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'type': type,
    'required': required,
    'primaryKey': primaryKey,
    'unique': unique,
  };

  factory BuilderDatabaseField.fromJson(Map<String, Object?> json) {
    if (json['id'] is! String || json['name'] is! String) {
      throw const FormatException('A database field needs an id and name.');
    }
    return BuilderDatabaseField(
      id: json['id']! as String,
      name: json['name']! as String,
      type: json['type'] is String ? json['type']! as String : 'string',
      required: json['required'] == true,
      primaryKey: json['primaryKey'] == true,
      unique: json['unique'] == true,
    );
  }
}

class BuilderDatabaseRelationship {
  const BuilderDatabaseRelationship({
    required this.id,
    required this.name,
    required this.fromCollectionId,
    required this.fromFieldId,
    required this.toCollectionId,
    required this.toFieldId,
  });

  /// The collection holding the foreign key (the many side).
  final String fromCollectionId;
  final String fromFieldId;

  /// The referenced collection and its primary or unique field (the one side).
  final String toCollectionId;
  final String toFieldId;
  final String id;
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'fromCollectionId': fromCollectionId,
    'fromFieldId': fromFieldId,
    'toCollectionId': toCollectionId,
    'toFieldId': toFieldId,
  };

  factory BuilderDatabaseRelationship.fromJson(Map<String, Object?> json) {
    for (final String key in <String>[
      'id',
      'name',
      'fromCollectionId',
      'fromFieldId',
      'toCollectionId',
      'toFieldId',
    ]) {
      if (json[key] is! String) {
        throw const FormatException(
          'A database relationship needs an id, name, and both field references.',
        );
      }
    }
    return BuilderDatabaseRelationship(
      id: json['id']! as String,
      name: json['name']! as String,
      fromCollectionId: json['fromCollectionId']! as String,
      fromFieldId: json['fromFieldId']! as String,
      toCollectionId: json['toCollectionId']! as String,
      toFieldId: json['toFieldId']! as String,
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

class BuilderCustomFunction {
  BuilderCustomFunction({
    required this.id,
    required this.name,
    this.body = '',
    List<Map<String, Object?>> actions = const <Map<String, Object?>>[],
  }) : actions = List<Map<String, Object?>>.unmodifiable(
         actions.map(
           (Map<String, Object?> action) =>
               Map<String, Object?>.unmodifiable(action),
         ),
       );

  final String id;
  final String name;
  final String body;
  final List<Map<String, Object?>> actions;

  BuilderCustomFunction copyWith({
    String? name,
    String? body,
    List<Map<String, Object?>>? actions,
  }) => BuilderCustomFunction(
    id: id,
    name: name ?? this.name,
    body: body ?? this.body,
    actions: actions ?? this.actions,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'body': body,
    'actions': actions,
  };

  factory BuilderCustomFunction.fromJson(Map<String, Object?> json) {
    final Object? rawBody = json['body'];
    final Object? rawActions = json['actions'];
    if (json['id'] is! String || json['name'] is! String) {
      throw const FormatException(
        'A custom function is missing its id or name.',
      );
    }
    if (rawBody != null && rawBody is! String) {
      throw const FormatException('Custom function body must be text.');
    }
    if (rawActions != null && rawActions is! List) {
      throw const FormatException('Custom function actions must be a list.');
    }
    final List<Map<String, Object?>> actions = <Map<String, Object?>>[];
    if (rawActions is List) {
      for (final Object? rawAction in rawActions) {
        if (rawAction is! Map) {
          throw const FormatException(
            'Custom function actions must be objects.',
          );
        }
        actions.add(<String, Object?>{
          for (final MapEntry<Object?, Object?> entry in rawAction.entries)
            entry.key.toString(): entry.value,
        });
      }
    }
    return BuilderCustomFunction(
      id: json['id']! as String,
      name: json['name']! as String,
      body: rawBody is String ? rawBody : '',
      actions: actions,
    );
  }
}

/// A Dart type declaration available to custom functions and generated apps.
class BuilderCustomDataStructure {
  const BuilderCustomDataStructure({
    required this.id,
    required this.name,
    required this.body,
  });

  final String id;
  final String name;
  final String body;

  BuilderCustomDataStructure copyWith({String? name, String? body}) =>
      BuilderCustomDataStructure(
        id: id,
        name: name ?? this.name,
        body: body ?? this.body,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'body': body,
  };

  factory BuilderCustomDataStructure.fromJson(Map<String, Object?> json) {
    if (json['id'] is! String ||
        json['name'] is! String ||
        json['body'] is! String) {
      throw const FormatException(
        'A custom data structure is missing its id, name, or Dart declaration.',
      );
    }
    return BuilderCustomDataStructure(
      id: json['id']! as String,
      name: json['name']! as String,
      body: json['body']! as String,
    );
  }
}

/// A saved component subtree that can be inserted again as an editable group.
class BuilderComponentGroup {
  const BuilderComponentGroup({
    required this.id,
    required this.name,
    required this.root,
  });

  final String id;
  final String name;
  final BuilderNode root;

  BuilderComponentGroup copyWith({String? name, BuilderNode? root}) =>
      BuilderComponentGroup(
        id: id,
        name: name ?? this.name,
        root: root ?? this.root,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'root': root.toJson(),
  };

  factory BuilderComponentGroup.fromJson(Map<String, Object?> json) {
    final Object? rawRoot = json['root'];
    if (json['id'] is! String || json['name'] is! String || rawRoot is! Map) {
      throw const FormatException(
        'A component group is missing its id, name, or root component.',
      );
    }
    return BuilderComponentGroup(
      id: json['id']! as String,
      name: json['name']! as String,
      root: BuilderNode.fromJson(Map<String, Object?>.from(rawRoot)),
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
      builderWidgetDefinitionFor(type)?.acceptsChildren ?? false;

  bool canAcceptChildType(String childType) =>
      builderWidgetAcceptsChild(type, childType);

  bool canAcceptChild(BuilderNode child) => canAcceptChildType(child.type);

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
      if (!node.canAcceptChild(child)) return node;
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
    if (position == BuilderDropPosition.inside &&
        !target.canAcceptChild(source)) {
      return null;
    }
    final BuilderNode withoutSource = removeById(sourceId);
    if (position == BuilderDropPosition.inside) {
      return withoutSource.updateById(targetId, (BuilderNode node) {
        return node.copyWith(children: <BuilderNode>[...node.children, source]);
      });
    }

    final BuilderNode? targetParent = parentOfId(targetId);
    if (targetParent == null || !targetParent.canAcceptChild(source))
      return null;
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
