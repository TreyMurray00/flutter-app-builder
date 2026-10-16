import 'builder_document.dart';

/// Normalizes the persisted action configuration for an interactive widget.
/// The legacy `route` property remains readable for projects created before
/// the action editor was introduced.
class BuilderAction {
  const BuilderAction._();

  static const List<String> types = <String>[
    'navigate',
    'snackbar',
    'dialog',
    'back',
    'setVariable',
    'incrementVariable',
    'toggleVariable',
    'updateWidget',
    'conditional',
    'loop',
    'httpRequest',
    'databaseInsert',
    'databaseUpdate',
    'databaseQuery',
    'databaseDelete',
    'customFunction',
  ];

  static List<Map<String, Object?>> forNode(BuilderNode node) {
    final Object? raw = node.properties['actions'];
    if (raw is List) {
      final List<Map<String, Object?>> parsed = <Map<String, Object?>>[];
      for (final Object? value in raw) {
        if (value is Map<Object?, Object?>) {
          parsed.add(<String, Object?>{
            for (final MapEntry<Object?, Object?> entry in value.entries)
              entry.key.toString(): entry.value,
          });
        }
      }
      return parsed;
    }
    final Object? legacyRoute = node.properties['route'];
    if (legacyRoute is String && legacyRoute.trim().isNotEmpty) {
      return <Map<String, Object?>>[
        <String, Object?>{
          'id': 'legacy_navigation',
          'type': 'navigate',
          'route': legacyRoute,
          'behavior': 'push',
        },
      ];
    }
    return <Map<String, Object?>>[];
  }

  static List<Map<String, Object?>> allForNode(BuilderNode node) =>
      allInActions(forNode(node));

  static List<Map<String, Object?>> allForFunction(
    BuilderCustomFunction function,
  ) => allInActions(function.actions);

  static List<Map<String, Object?>> allInActions(
    List<Map<String, Object?>> actions,
  ) {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    void visit(List<Map<String, Object?>> entries) {
      for (final Map<String, Object?> action in entries) {
        result.add(action);
        for (final String key in <String>[
          'thenActions',
          'elseActions',
          'actions',
        ]) {
          final Object? raw = action[key];
          if (raw is List) {
            visit(
              raw
                  .whereType<Map<Object?, Object?>>()
                  .map(
                    (Map<Object?, Object?> item) => <String, Object?>{
                      for (final MapEntry<Object?, Object?> entry
                          in item.entries)
                        entry.key.toString(): entry.value,
                    },
                  )
                  .toList(),
            );
          }
        }
      }
    }

    visit(actions);
    return result;
  }

  static Map<String, Object?> create(String id, String type) =>
      <String, Object?>{
        'id': id,
        'type': type,
        if (type == 'navigate') ...<String, Object?>{
          'route': '',
          'behavior': 'push',
        },
        if (type == 'snackbar') 'message': 'Action completed',
        if (type == 'dialog') ...<String, Object?>{
          'title': 'Notice',
          'message': 'Action completed',
        },
        if (type == 'setVariable') ...<String, Object?>{
          'variableId': '',
          'value': '',
        },
        if (type == 'incrementVariable') ...<String, Object?>{
          'variableId': '',
          'amount': 1,
        },
        if (type == 'toggleVariable') 'variableId': '',
        if (type == 'updateWidget') ...<String, Object?>{
          'targetPageId': 'home',
          'targetNodeId': '',
          'property': 'visible',
          'value': true,
        },
        if (type == 'conditional') ...<String, Object?>{
          'variableId': '',
          'operator': 'equals',
          'value': '',
          'thenActions': <Map<String, Object?>>[],
          'elseActions': <Map<String, Object?>>[],
        },
        if (type == 'loop') ...<String, Object?>{
          'iterations': 3,
          'actions': <Map<String, Object?>>[],
        },
        if (type == 'httpRequest') ...<String, Object?>{
          'method': 'GET',
          'url': 'https://',
          'headers': '{}',
          'body': '',
          'responseVariableId': '',
        },
        if (type == 'databaseInsert') ...<String, Object?>{
          'collectionId': '',
          'record': '{}',
        },
        if (type == 'databaseUpdate') ...<String, Object?>{
          'collectionId': '',
          'recordId': '',
          'record': '{}',
        },
        if (type == 'databaseQuery') ...<String, Object?>{
          'collectionId': '',
          'resultVariableId': '',
          'joins': <Map<String, Object?>>[],
          'filters': <Map<String, Object?>>[],
          'filterMode': 'all',
          'sortRelationshipId': '',
          'sortFieldId': '',
          'sortAggregate': 'min',
          'sortDescending': false,
          'limit': 0,
        },
        if (type == 'databaseDelete') ...<String, Object?>{
          'collectionId': '',
          'recordId': '',
        },
        if (type == 'customFunction') 'functionId': '',
      };
}
