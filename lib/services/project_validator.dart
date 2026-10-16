import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';

import '../models/builder_action.dart';
import '../models/builder_document.dart';
import '../models/builder_widget_definition.dart';
import 'dart_generator.dart';
import 'project_store.dart';

class ProjectIssue {
  const ProjectIssue({
    required this.severity,
    required this.message,
    this.pageId,
    this.nodeId,
  });

  final String severity;
  final String message;
  final String? pageId;
  final String? nodeId;

  bool get isError => severity == 'error';
}

class ProjectValidator {
  Future<List<ProjectIssue>> validate(
    BuilderDocument document, {
    String? projectPath,
  }) async {
    final List<ProjectIssue> issues = <ProjectIssue>[];
    void add(
      String severity,
      String message, {
      String? pageId,
      String? nodeId,
    }) {
      issues.add(
        ProjectIssue(
          severity: severity,
          message: message,
          pageId: pageId,
          nodeId: nodeId,
        ),
      );
    }

    if (document.name.trim().isEmpty) {
      add('error', 'Project name must not be empty.');
    }
    final Set<String> pageIds = <String>{};
    final Set<String> routes = <String>{};
    for (final BuilderPage page in document.allPages) {
      if (!pageIds.add(page.id)) {
        add('error', 'Duplicate page id "${page.id}".', pageId: page.id);
      }
      if (page.name.trim().isEmpty) {
        add('error', 'Page "${page.id}" has an empty name.', pageId: page.id);
      }
      if (page.route.trim().isEmpty) {
        add(
          'error',
          'Page "${page.name}" has an empty route.',
          pageId: page.id,
        );
      } else if (!routes.add(page.route.toLowerCase())) {
        add('error', 'Duplicate page route "${page.route}".', pageId: page.id);
      }
    }
    if (!pageIds.contains(document.initialPageId)) {
      add('error', 'Initial page "${document.initialPageId}" does not exist.');
    }

    final Set<String> variableIds =
        document.variables.map((BuilderVariable item) => item.id).toSet();
    final Set<String> jsonVariableIds =
        document.variables
            .where((BuilderVariable item) => item.type == 'json')
            .map((BuilderVariable item) => item.id)
            .toSet();
    final Set<String> functionIds =
        document.customFunctions
            .map((BuilderCustomFunction item) => item.id)
            .toSet();
    final Set<String> collectionIds =
        document.databaseCollections
            .map((BuilderDatabaseCollection item) => item.id)
            .toSet();
    final Set<String> validRoutes =
        document.allPages.map((BuilderPage page) => page.route).toSet();
    final Map<String, BuilderPage> pagesById = <String, BuilderPage>{
      for (final BuilderPage page in document.allPages) page.id: page,
    };
    final Map<String, BuilderDatabaseCollection> collectionsById =
        <String, BuilderDatabaseCollection>{
          for (final BuilderDatabaseCollection collection
              in document.databaseCollections)
            collection.id: collection,
        };

    final Set<String> collectionNames = <String>{};
    final Set<String> seenCollectionIds = <String>{};
    final Map<String, Map<String, BuilderDatabaseField>> fieldsByCollection =
        <String, Map<String, BuilderDatabaseField>>{};
    for (final BuilderDatabaseCollection collection
        in document.databaseCollections) {
      if (collection.id.trim().isEmpty) {
        add('error', 'A database collection has an empty id.');
      } else if (!seenCollectionIds.add(collection.id)) {
        add('error', 'Duplicate database collection id "${collection.id}".');
      }
      if (collection.name.trim().isEmpty) {
        add(
          'error',
          'Database collection "${collection.id}" has an empty name.',
        );
      } else if (!collectionNames.add(collection.name.trim().toLowerCase())) {
        add(
          'error',
          'Duplicate database collection name "${collection.name}".',
        );
      }
      final Set<String> fieldNames = <String>{};
      final Map<String, BuilderDatabaseField> fields =
          <String, BuilderDatabaseField>{};
      var primaryKeyCount = 0;
      for (final BuilderDatabaseField field in collection.fields) {
        if (field.id.trim().isEmpty) {
          add(
            'error',
            'Collection "${collection.name}" has a field with an empty id.',
          );
        }
        if (fields.containsKey(field.id)) {
          add(
            'error',
            'Collection "${collection.name}" has duplicate field id "${field.id}".',
          );
        }
        fields[field.id] = field;
        if (field.name.trim().isEmpty) {
          add(
            'error',
            'A field in collection "${collection.name}" has an empty name.',
          );
        } else if (!fieldNames.add(field.name.trim().toLowerCase())) {
          add(
            'error',
            'Collection "${collection.name}" has duplicate field name "${field.name}".',
          );
        }
        if (!<String>{
          'string',
          'integer',
          'number',
          'boolean',
          'date',
          'json',
        }.contains(field.type)) {
          add(
            'error',
            'Field "${field.name}" in collection "${collection.name}" has unsupported type "${field.type}".',
          );
        }
        if (field.primaryKey) primaryKeyCount++;
      }
      if (primaryKeyCount > 1) {
        add(
          'error',
          'Collection "${collection.name}" can have only one primary key field.',
        );
      }
      fieldsByCollection[collection.id] = fields;
    }

    final Set<String> relationshipIds = <String>{};
    final Set<String> relationshipPairs = <String>{};
    for (final BuilderDatabaseRelationship relationship
        in document.databaseRelationships) {
      if (relationship.id.trim().isEmpty) {
        add('error', 'A database relationship has an empty id.');
      } else if (!relationshipIds.add(relationship.id)) {
        add(
          'error',
          'Duplicate database relationship id "${relationship.id}".',
        );
      }
      if (relationship.name.trim().isEmpty) {
        add(
          'error',
          'Database relationship "${relationship.id}" has an empty name.',
        );
      }
      final BuilderDatabaseCollection? fromCollection =
          collectionsById[relationship.fromCollectionId];
      final BuilderDatabaseCollection? toCollection =
          collectionsById[relationship.toCollectionId];
      final BuilderDatabaseField? fromField =
          fieldsByCollection[relationship.fromCollectionId]?[relationship
              .fromFieldId];
      final BuilderDatabaseField? toField =
          fieldsByCollection[relationship.toCollectionId]?[relationship
              .toFieldId];
      final String label =
          relationship.name.trim().isEmpty
              ? relationship.id
              : relationship.name;
      if (fromCollection == null) {
        add(
          'error',
          'Relationship "$label" references missing child collection "${relationship.fromCollectionId}".',
        );
      } else if (fromField == null) {
        add(
          'error',
          'Relationship "$label" references missing foreign-key field "${relationship.fromFieldId}" in "${fromCollection.name}".',
        );
      }
      if (toCollection == null) {
        add(
          'error',
          'Relationship "$label" references missing parent collection "${relationship.toCollectionId}".',
        );
      } else if (toField == null) {
        add(
          'error',
          'Relationship "$label" references missing target field "${relationship.toFieldId}" in "${toCollection.name}".',
        );
      } else if (!toField.primaryKey && !toField.unique) {
        add(
          'error',
          'Relationship "$label" must target a primary-key or unique field.',
        );
      }
      if (fromField != null &&
          toField != null &&
          fromField.type != toField.type) {
        add(
          'error',
          'Relationship "$label" has mismatched field types (${fromField.type} and ${toField.type}).',
        );
      }
      final String pair =
          '${relationship.fromCollectionId}:${relationship.fromFieldId}->'
          '${relationship.toCollectionId}:${relationship.toFieldId}';
      if (!relationshipPairs.add(pair)) {
        add('error', 'Duplicate database relationship "$label".');
      }
    }

    for (final BuilderPage page in document.allPages) {
      final Set<String> nodeIds = <String>{};
      for (final BuilderNode node in page.root.depthFirst()) {
        if (!builderWidgetTypes.contains(node.type)) {
          add(
            'error',
            'Widget type "${node.type}" is not supported by this builder version.',
            pageId: page.id,
            nodeId: node.id,
          );
        }
        if (node.type == 'databaseList') {
          final String collectionId =
              _optionalString(node.properties['collectionId']) ?? '';
          if (collectionId.isEmpty) {
            add(
              'warning',
              'Choose a database collection for this Database List.',
              pageId: page.id,
              nodeId: node.id,
            );
          } else if (!collectionIds.contains(collectionId)) {
            add(
              'error',
              'Database List refers to missing data collection "$collectionId".',
              pageId: page.id,
              nodeId: node.id,
            );
          }
        }
        if (node.type == 'textField') {
          final String inputVariableId =
              _optionalString(node.properties['inputVariableId']) ?? '';
          if (inputVariableId.isNotEmpty &&
              !document.variables.any(
                (BuilderVariable variable) =>
                    variable.id == inputVariableId &&
                    variable.type == 'string',
              )) {
            add(
              'error',
              'Text Field input binding must reference a string variable.',
              pageId: page.id,
              nodeId: node.id,
            );
          }
        }
        final Object? rawResponsive = node.properties['responsiveOverrides'];
        if (rawResponsive is Map && rawResponsive.isNotEmpty) {
          if (<String>{
            'expanded',
            'flexible',
            'spacer',
            'appBar',
            'floatingActionButton',
            'extendedFloatingActionButton',
            'bottomAppBar',
            'bottomSheet',
            'navigationBar',
            'navigationDrawer',
            'navigationRail',
          }.contains(node.type)) {
            add(
              'error',
              'Responsive overrides cannot wrap this widget because Flutter requires it in a special layout slot.',
              pageId: page.id,
              nodeId: node.id,
            );
          }
          for (final Object? breakpoint in rawResponsive.keys) {
            if (!<String>{'phone', 'tablet', 'desktop'}.contains(breakpoint)) {
              add(
                'error',
                'Unknown responsive breakpoint "$breakpoint".',
                pageId: page.id,
                nodeId: node.id,
              );
            } else if (rawResponsive[breakpoint] is! Map) {
              add(
                'error',
                'Responsive breakpoint "$breakpoint" must contain a property map.',
                pageId: page.id,
                nodeId: node.id,
              );
            }
          }
        }
        if (node.id.trim().isEmpty) {
          add(
            'error',
            'Page "${page.name}" contains a widget with an empty id.',
            pageId: page.id,
            nodeId: node.id,
          );
        }
        if (!nodeIds.add(node.id)) {
          add(
            'error',
            'Page "${page.name}" contains duplicate widget id "${node.id}".',
            pageId: page.id,
            nodeId: node.id,
          );
        }
        if (node.children.isNotEmpty && !node.acceptsChildren) {
          add(
            'warning',
            'Widget "${node.id}" (${node.type}) has children its layout may ignore.',
            pageId: page.id,
            nodeId: node.id,
          );
        }
        if (<String>{'expanded', 'flexible', 'spacer'}.contains(node.type)) {
          BuilderNode? parent = page.root.parentOfId(node.id);
          while (parent != null &&
              parent.type == 'componentGroup' &&
              parent.children.length == 1) {
            parent = page.root.parentOfId(parent.id);
          }
          if (parent?.type != 'row' && parent?.type != 'column') {
            add(
              'error',
              '${node.type} widget "${node.id}" must be a direct child of a Row or Column.',
              pageId: page.id,
              nodeId: node.id,
            );
          }
        }
        if (node.type == 'image') {
          final String source =
              (node.properties['source'] is String
                      ? node.properties['source']! as String
                      : '')
                  .trim();
          if (source.isNotEmpty &&
              !await File(
                resolveProjectAssetPath(projectPath, source),
              ).exists()) {
            add(
              'error',
              'Image asset was not found: $source',
              pageId: page.id,
              nodeId: node.id,
            );
          }
          if ((node.properties['altText'] is String
                  ? node.properties['altText']! as String
                  : '')
              .trim()
              .isEmpty) {
            add(
              'warning',
              'Add alternative text to this image for screen reader users.',
              pageId: page.id,
              nodeId: node.id,
            );
          }
        }
        if (node.type == 'textField' &&
            (node.properties['label'] is String
                    ? node.properties['label']! as String
                    : '')
                .trim()
                .isEmpty &&
            (node.properties['hintText'] is String
                    ? node.properties['hintText']! as String
                    : '')
                .trim()
                .isEmpty) {
          add(
            'warning',
            'Add a label or hint to this text field for screen reader users.',
            pageId: page.id,
            nodeId: node.id,
          );
        }
        if (node.type == 'button' &&
            (node.properties['label'] is String
                    ? node.properties['label']! as String
                    : '')
                .trim()
                .isEmpty) {
          add(
            'warning',
            'This button has no visible label.',
            pageId: page.id,
            nodeId: node.id,
          );
        }
        _validateActions(
          BuilderAction.allForNode(node),
          page: page,
          node: node,
          pagesById: pagesById,
          validRoutes: validRoutes,
          variableIds: variableIds,
          jsonVariableIds: jsonVariableIds,
          functionIds: functionIds,
          collectionIds: collectionIds,
          databaseCollectionsById: collectionsById,
          databaseRelationships: document.databaseRelationships,
          add: add,
        );
      }
    }

    final BuilderPage home = document.allPages.first;
    for (final BuilderCustomFunction function in document.customFunctions) {
      _validateActions(
        BuilderAction.allForFunction(function),
        page: home,
        node: home.root,
        pagesById: pagesById,
        validRoutes: validRoutes,
        variableIds: variableIds,
        jsonVariableIds: jsonVariableIds,
        functionIds: functionIds,
        collectionIds: collectionIds,
        databaseCollectionsById: collectionsById,
        databaseRelationships: document.databaseRelationships,
        add: add,
      );
    }

    for (final BuilderFontAsset font in document.fontAssets) {
      if (font.family.trim().isEmpty) {
        add('error', 'A bundled font has an empty family name.');
      }
      if (!await File(
        resolveProjectAssetPath(projectPath, font.source),
      ).exists()) {
        add('error', 'Bundled font was not found: ${font.source}');
      }
    }

    try {
      final DartGenerator generator = DartGenerator();
      final Map<String, String> generatedFiles = generator.generateProjectFiles(
        document,
        projectName: document.name,
        fontAssets: document.fontAssets,
      );
      for (final MapEntry<String, String> file in generatedFiles.entries) {
        if (!file.key.endsWith('.dart')) continue;
        final parsed = parseString(
          content: file.value,
          throwIfDiagnostics: false,
        );
        for (final error in parsed.errors) {
          add(
            'error',
            'Generated ${file.key} has a Dart syntax error at offset ${error.offset}: ${error.message}',
          );
        }
      }
    } catch (error) {
      add('error', 'Flutter code generation failed: $error');
    }
    return issues;
  }

  void _validateActions(
    List<Map<String, Object?>> actions, {
    required BuilderPage page,
    required BuilderNode node,
    required Map<String, BuilderPage> pagesById,
    required Set<String> validRoutes,
    required Set<String> variableIds,
    required Set<String> jsonVariableIds,
    required Set<String> functionIds,
    required Set<String> collectionIds,
    required Map<String, BuilderDatabaseCollection> databaseCollectionsById,
    required List<BuilderDatabaseRelationship> databaseRelationships,
    required void Function(
      String severity,
      String message, {
      String? pageId,
      String? nodeId,
    })
    add,
  }) {
    for (final Map<String, Object?> action in actions) {
      final String type = _optionalString(action['type']) ?? '';
      if (!BuilderAction.types.contains(type)) {
        add(
          'error',
          'Unsupported action type "$type".',
          pageId: page.id,
          nodeId: node.id,
        );
        continue;
      }
      final String? variableId = switch (type) {
        'setVariable' ||
        'incrementVariable' ||
        'toggleVariable' ||
        'conditional' => _optionalString(action['variableId']),
        'httpRequest' => _optionalString(action['responseVariableId']),
        'databaseQuery' => _optionalString(action['resultVariableId']),
        _ => null,
      };
      if (variableId != null &&
          variableId.isNotEmpty &&
          !variableIds.contains(variableId)) {
        add(
          'error',
          'Action "$type" refers to missing variable "$variableId".',
          pageId: page.id,
          nodeId: node.id,
        );
      }
      if (<String>{
            'setVariable',
            'incrementVariable',
            'toggleVariable',
            'conditional',
          }.contains(type) &&
          (variableId == null || variableId.isEmpty)) {
        add(
          'warning',
          'Choose an app variable for this action.',
          pageId: page.id,
          nodeId: node.id,
        );
      }
      if (type == 'navigate') {
        final String route = _optionalString(action['route']) ?? '';
        if (route.isEmpty) {
          add(
            'warning',
            'Choose a destination route for this navigation action.',
            pageId: page.id,
            nodeId: node.id,
          );
        } else if (!validRoutes.contains(route)) {
          add(
            'error',
            'Navigation action points to missing route "$route".',
            pageId: page.id,
            nodeId: node.id,
          );
        }
      }
      if (type == 'updateWidget') {
        final String targetPageId =
            _optionalString(action['targetPageId']) ?? '';
        final String targetNodeId =
            _optionalString(action['targetNodeId']) ?? '';
        final BuilderPage? targetPage = pagesById[targetPageId];
        if (targetPageId.isEmpty || targetNodeId.isEmpty) {
          add(
            'warning',
            'Complete the target page and widget for this update action.',
            pageId: page.id,
            nodeId: node.id,
          );
        } else if (targetPage == null ||
            targetPage.root.findById(targetNodeId) == null) {
          add(
            'error',
            'Update action points to a missing page or widget.',
            pageId: page.id,
            nodeId: node.id,
          );
        }
      }
      if (type == 'customFunction') {
        final String id = _optionalString(action['functionId']) ?? '';
        if (id.isEmpty) {
          add(
            'warning',
            'Choose a custom function for this action.',
            pageId: page.id,
            nodeId: node.id,
          );
        } else if (!functionIds.contains(id)) {
          add(
            'error',
            'Action calls missing custom function "$id".',
            pageId: page.id,
            nodeId: node.id,
          );
        }
      }
      if (type == 'databaseQuery') {
        final String resultId =
            _optionalString(action['resultVariableId']) ?? '';
        if (resultId.isEmpty) {
          add(
            'warning',
            'Choose a JSON variable to store the query results.',
            pageId: page.id,
            nodeId: node.id,
          );
        } else if (!jsonVariableIds.contains(resultId)) {
          add(
            'error',
            'Database query results must be stored in a JSON variable.',
            pageId: page.id,
            nodeId: node.id,
          );
        }
      }
      if (type.startsWith('database')) {
        final String id = _optionalString(action['collectionId']) ?? '';
        if (id.isEmpty) {
          add(
            'warning',
            'Choose a data collection for this action.',
            pageId: page.id,
            nodeId: node.id,
          );
        } else if (!collectionIds.contains(id)) {
          add(
            'error',
            'Action refers to missing data collection "$id".',
            pageId: page.id,
            nodeId: node.id,
          );
        }
        if (type == 'databaseQuery' && id.isNotEmpty) {
          final BuilderDatabaseCollection? collection =
              databaseCollectionsById[id];
          if (collection != null) {
            final String filterMode =
                _optionalString(action['filterMode']) ?? 'all';
            if (!<String>{'all', 'any'}.contains(filterMode)) {
              add(
                'error',
                'Database query match mode must be "all" or "any".',
                pageId: page.id,
                nodeId: node.id,
              );
            }
            final Map<String, BuilderDatabaseField> fieldsById =
                <String, BuilderDatabaseField>{
                  for (final BuilderDatabaseField field in collection.fields)
                    field.id: field,
                };
            final Map<String, BuilderDatabaseCollection> joinedCollections =
                <String, BuilderDatabaseCollection>{};
            final Set<String> relationshipIds = <String>{};
            final Set<String> aliases = <String>{};
            final Map<String, BuilderDatabaseRelationship> relationshipsById =
                <String, BuilderDatabaseRelationship>{
                  for (final BuilderDatabaseRelationship relationship
                      in databaseRelationships)
                    relationship.id: relationship,
                };
            final Object? rawJoins = action['joins'];
            if (rawJoins is List) {
              for (final Object? rawJoin in rawJoins) {
                if (rawJoin is! Map) {
                  add(
                    'error',
                    'A database query join must be an object.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                  continue;
                }
                final Map<String, Object?> join = Map<String, Object?>.from(
                  rawJoin,
                );
                final String relationshipId =
                    _optionalString(join['relationshipId']) ?? '';
                final BuilderDatabaseRelationship? relationship =
                    relationshipsById[relationshipId];
                if (relationshipId.isEmpty || relationship == null) {
                  add(
                    'error',
                    'A database query join refers to a missing relationship.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                  continue;
                }
                if (!relationshipIds.add(relationshipId)) {
                  add(
                    'error',
                    'A database query cannot add the same relationship twice.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
                final bool fromSide =
                    relationship.fromCollectionId == collection.id;
                final bool toSide =
                    relationship.toCollectionId == collection.id;
                if (!fromSide && !toSide) {
                  add(
                    'error',
                    'A database query join must connect directly to its base collection.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                  continue;
                }
                final String relatedId =
                    fromSide
                        ? relationship.toCollectionId
                        : relationship.fromCollectionId;
                final BuilderDatabaseCollection? relatedCollection =
                    databaseCollectionsById[relatedId];
                if (relatedCollection == null) continue;
                joinedCollections[relationshipId] = relatedCollection;
                final String alias =
                    _optionalString(join['alias'])?.trim() ?? '';
                if (alias.isEmpty) {
                  add(
                    'error',
                    'Every related collection needs a result key (alias).',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                } else if (!aliases.add(alias) ||
                    alias == '_id' ||
                    fieldsById.containsKey(alias)) {
                  add(
                    'error',
                    'Database query result key "$alias" is duplicated or reserved.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
                if (!<String>{'left', 'inner'}.contains(join['joinType'])) {
                  add(
                    'error',
                    'Database query join type must be "left" or "inner".',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
              }
            } else if (rawJoins != null) {
              add(
                'error',
                'Database query joins must be a list.',
                pageId: page.id,
                nodeId: node.id,
              );
            }
            final Set<String> conditionIds = <String>{};
            final Object? rawFilters = action['filters'];
            if (rawFilters is List) {
              for (final Object? rawFilter in rawFilters) {
                if (rawFilter is! Map) {
                  add(
                    'error',
                    'A database query condition must be an object.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                  continue;
                }
                final Map<String, Object?> filter = Map<String, Object?>.from(
                  rawFilter,
                );
                final String conditionId = _optionalString(filter['id']) ?? '';
                if (conditionId.isEmpty) {
                  add(
                    'error',
                    'A database query condition needs a stable id.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                } else if (!conditionIds.add(conditionId)) {
                  add(
                    'error',
                    'Database query condition id "$conditionId" is duplicated.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
                final String fieldId = _optionalString(filter['fieldId']) ?? '';
                final String conditionRelationshipId =
                    _optionalString(filter['relationshipId']) ?? '';
                final String operator =
                    _optionalString(filter['operator']) ?? 'equals';
                final BuilderDatabaseCollection? targetCollection =
                    conditionRelationshipId.isEmpty
                        ? collection
                        : joinedCollections[conditionRelationshipId];
                final BuilderDatabaseField? field =
                    targetCollection == null
                        ? null
                        : _firstFieldById(targetCollection, fieldId);
                if (field == null) {
                  add(
                    'error',
                    conditionRelationshipId.isNotEmpty &&
                            !joinedCollections.containsKey(
                              conditionRelationshipId,
                            )
                        ? 'A database query condition refers to a relationship that is not joined.'
                        : 'A database query condition refers to a missing field in "${targetCollection?.name ?? collection.name}".',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
                if (!<String>{
                  'equals',
                  'notEquals',
                  'contains',
                  'greaterThan',
                  'greaterThanOrEqual',
                  'lessThan',
                  'lessThanOrEqual',
                  'isNull',
                  'isNotNull',
                }.contains(operator)) {
                  add(
                    'error',
                    'Database query operator "$operator" is not supported.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
                if (<String>{
                      'greaterThan',
                      'greaterThanOrEqual',
                      'lessThan',
                      'lessThanOrEqual',
                    }.contains(operator) &&
                    field != null &&
                    <String>{'boolean', 'json'}.contains(field.type)) {
                  add(
                    'error',
                    'Database query comparisons require a string, number, integer, or date field.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
                if (operator == 'contains' &&
                    field != null &&
                    !<String>{'string', 'date', 'json'}.contains(field.type)) {
                  add(
                    'error',
                    'The contains operator requires a string, date, or JSON field.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
                if (!<String>{'isNull', 'isNotNull'}.contains(operator) &&
                    filter['value'] == null) {
                  add(
                    'warning',
                    'Add a value for the database query condition.',
                    pageId: page.id,
                    nodeId: node.id,
                  );
                }
              }
            } else if (rawFilters != null) {
              add(
                'error',
                'Database query conditions must be a list.',
                pageId: page.id,
                nodeId: node.id,
              );
            }
            final String sortFieldId =
                _optionalString(action['sortFieldId']) ?? '';
            final String sortRelationshipId =
                _optionalString(action['sortRelationshipId']) ?? '';
            final BuilderDatabaseCollection? sortCollection =
                sortRelationshipId.isEmpty
                    ? collection
                    : joinedCollections[sortRelationshipId];
            if (sortRelationshipId.isNotEmpty && sortCollection == null) {
              add(
                'error',
                'Database query sort refers to a relationship that is not joined.',
                pageId: page.id,
                nodeId: node.id,
              );
            }
            if (sortFieldId.isNotEmpty &&
                (sortCollection == null ||
                    _firstFieldById(sortCollection, sortFieldId) == null)) {
              add(
                'error',
                'Database query sort field does not exist in "${sortCollection?.name ?? collection.name}".',
                pageId: page.id,
                nodeId: node.id,
              );
            }
            final Object? rawLimit = action['limit'];
            if (rawLimit != null &&
                (rawLimit is! num || rawLimit < 0 || rawLimit > 100000)) {
              add(
                'error',
                'Database query maximum rows must be between 0 and 100000.',
                pageId: page.id,
                nodeId: node.id,
              );
            }
          }
        }
      }
    }
  }

  String? _optionalString(Object? value) => value is String ? value : null;

  BuilderDatabaseField? _firstFieldById(
    BuilderDatabaseCollection collection,
    String fieldId,
  ) {
    for (final BuilderDatabaseField field in collection.fields) {
      if (field.id == fieldId) return field;
    }
    return null;
  }
}
