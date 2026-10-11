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
      };
}
