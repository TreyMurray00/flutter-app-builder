import 'dart:convert';

import '../models/builder_action.dart';
import '../models/builder_document.dart';

class DartGenerator {
  String _currentPageId = 'home';
  Map<String, BuilderVariable> _variablesById = <String, BuilderVariable>{};
  Map<String, BuilderCustomFunction> _customFunctionsById =
      <String, BuilderCustomFunction>{};
  Map<String, BuilderDatabaseCollection> _databaseCollectionsById =
      <String, BuilderDatabaseCollection>{};
  final Map<String, Set<String>> _widgetActionTargets = <String, Set<String>>{};
  Map<String, String> _imageAssets = <String, String>{};

  String generate(
    BuilderDocument document, {
    Map<String, String> imageAssets = const <String, String>{},
  }) {
    _imageAssets = imageAssets;
    _variablesById = <String, BuilderVariable>{
      for (final BuilderVariable variable in document.variables)
        variable.id: variable,
    };
    _customFunctionsById = <String, BuilderCustomFunction>{
      for (final BuilderCustomFunction function in document.customFunctions)
        function.id: function,
    };
    _databaseCollectionsById = <String, BuilderDatabaseCollection>{
      for (final BuilderDatabaseCollection collection
          in document.databaseCollections)
        collection.id: collection,
    };
    final List<Map<String, Object?>> functionActions =
        document.customFunctions.expand(BuilderAction.allForFunction).toList();
    _widgetActionTargets.clear();
    for (final BuilderPage page in document.allPages) {
      for (final BuilderNode node in page.root.depthFirst()) {
        for (final Map<String, Object?> action in BuilderAction.allForNode(
          node,
        )) {
          if (action['type'] == 'updateWidget' &&
              action['targetPageId'] is String &&
              action['targetNodeId'] is String &&
              action['property'] is String) {
            final String key = _runtimeWidgetKey(
              action['targetPageId']! as String,
              action['targetNodeId']! as String,
            );
            _widgetActionTargets
                .putIfAbsent(key, () => <String>{})
                .add(action['property']! as String);
          }
        }
      }
    }
    for (final Map<String, Object?> action in functionActions) {
      if (action['type'] == 'updateWidget' &&
          action['targetPageId'] is String &&
          action['targetNodeId'] is String &&
          action['property'] is String) {
        final String key = _runtimeWidgetKey(
          action['targetPageId']! as String,
          action['targetNodeId']! as String,
        );
        _widgetActionTargets
            .putIfAbsent(key, () => <String>{})
            .add(action['property']! as String);
      }
    }
    final String seedColor = _colorLiteral(document.seedColor);
    final BuilderTheme appTheme = document.appTheme;
    final String backgroundOverride =
        appTheme.backgroundColor == null
            ? ''
            : 'surface: const Color(${_colorLiteral(appTheme.backgroundColor!)}),';
    final String textOverride =
        appTheme.textColor == null
            ? ''
            : 'onSurface: const Color(${_colorLiteral(appTheme.textColor!)}),';
    final String fontFamily =
        appTheme.fontFamily.trim().isEmpty
            ? 'null'
            : _dartString(appTheme.fontFamily.trim());
    final String themeMode = switch (appTheme.brightness) {
      'dark' => 'ThemeMode.dark',
      'system' => 'ThemeMode.system',
      _ => 'ThemeMode.light',
    };
    final List<BuilderPage> pages = document.allPages;
    final Iterable<BuilderNode> allNodes = pages.expand(
      (BuilderPage page) => page.root.depthFirst(),
    );
    final bool usesImageFile = pages.any(
      (BuilderPage page) => page.root.depthFirst().any((BuilderNode node) {
        final bool hasAsset =
            _imageAssets.containsKey(_imageAssetKey(page.id, node.id)) ||
            _imageAssets.containsKey(node.id);
        return node.type == 'image' &&
            !hasAsset &&
            (node.properties['source'] is String
                    ? node.properties['source']! as String
                    : '')
                .isNotEmpty;
      }),
    );
    final bool usesSignature = allNodes.any(
      (BuilderNode node) => node.type == 'signature',
    );
    final bool usesSwipeableStack = allNodes.any(
      (BuilderNode node) => node.type == 'swipeableStack',
    );
    final bool usesDatabaseActions =
        functionActions.any(
          (Map<String, Object?> action) =>
              (action['type'] as String? ?? '').startsWith('database'),
        ) ||
        allNodes.any(
          (BuilderNode node) => BuilderAction.allForNode(node).any(
            (Map<String, Object?> action) =>
                (action['type'] as String? ?? '').startsWith('database'),
          ),
        );
    final bool usesHttp =
        document.customFunctions.any(
          (BuilderCustomFunction function) =>
              RegExp(r'\bhttp\.').hasMatch(function.body),
        ) ||
        document.customDataStructures.any(
          (BuilderCustomDataStructure structure) =>
              RegExp(r'\bhttp\.').hasMatch(structure.body),
        ) ||
        functionActions.any(
          (Map<String, Object?> action) => action['type'] == 'httpRequest',
        ) ||
        allNodes.any(
          (BuilderNode node) => BuilderAction.allForNode(node).any(
            (Map<String, Object?> action) => action['type'] == 'httpRequest',
          ),
        );
    final String ioImport = usesImageFile ? "import 'dart:io';\n" : '';
    final bool usesJson =
        usesHttp ||
        (usesDatabaseActions &&
            functionActions.any(
              (Map<String, Object?> action) =>
                  action['type'] == 'databaseInsert',
            )) ||
        (usesDatabaseActions &&
            allNodes.any(
              (BuilderNode node) => BuilderAction.allForNode(node).any(
                (Map<String, Object?> action) =>
                    action['type'] == 'databaseInsert',
              ),
            )) ||
        document.customFunctions.any(
          (BuilderCustomFunction function) =>
              RegExp(r'\bjson(Encode|Decode)\b').hasMatch(function.body),
        ) ||
        document.customDataStructures.any(
          (BuilderCustomDataStructure structure) =>
              RegExp(r'\bjson(Encode|Decode)\b').hasMatch(structure.body),
        );
    final String jsonImport = usesJson ? "import 'dart:convert';\n" : '';
    final bool usesMath =
        document.customFunctions.any(
          (BuilderCustomFunction function) =>
              RegExp(r'\bmath\.').hasMatch(function.body),
        ) ||
        document.customDataStructures.any(
          (BuilderCustomDataStructure structure) =>
              RegExp(r'\bmath\.').hasMatch(structure.body),
        );
    final String mathImport = usesMath ? "import 'dart:math' as math;\n" : '';
    final String httpImport =
        usesHttp ? "import 'package:http/http.dart' as http;\n" : '';
    final String databaseImport =
        usesDatabaseActions && document.databaseCollections.isNotEmpty
            ? "import 'local_database.dart';\n"
            : '';
    final StringBuffer routeBuffer = StringBuffer();
    for (final BuilderPage page in pages) {
      _currentPageId = page.id;
      routeBuffer.writeln(
        '      ${_dartString(page.route)}: (BuildContext context) => ${_emitNode(page.root, 8)},',
      );
    }
    final String routes = routeBuffer.toString();
    _currentPageId = 'home';
    final String initialRoute =
        document.pageById(document.initialPageId)?.route ?? '/';
    return '''// Generated by Local Flutter Builder. Edit the design document to regenerate.
${ioImport}import 'package:material_ui/material_ui.dart';
$jsonImport$mathImport$httpImport$databaseImport
${document.customDataStructures.map((BuilderCustomDataStructure structure) => structure.body).join('\n\n')}

void main() {
  runApp(const GeneratedApp());
}

class GeneratedApp extends StatefulWidget {
  const GeneratedApp({super.key});

  @override
  State<GeneratedApp> createState() => _GeneratedAppState();
}

class _GeneratedAppState extends State<GeneratedApp> {
  final Map<String, Object?> _appState = <String, Object?>{
${document.variables.map((BuilderVariable variable) => "    ${_dartString(variable.id)}: ${_dartValue(variable.initialValue)},").join('\n')}
  };
  final Map<String, Object?> _widgetState = <String, Object?>{};
  final Set<String> _activeCustomFunctions = <String>{};
${usesDatabaseActions && document.databaseCollections.isNotEmpty ? '  final LocalDatabaseRepository _database = LocalDatabaseRepository();' : ''}

${usesHttp ? _httpHelper : ''}
${document.customFunctions.map(_emitCustomFunction).join('\n')}

  ThemeData _buildTheme(Brightness brightness) {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: const Color($seedColor),
      brightness: brightness,
    );
    final ColorScheme colors = base.copyWith(
      $backgroundOverride
      $textOverride
    );
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(${appTheme.cornerRadius}),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      fontFamily: $fontFamily,
      cardTheme: CardThemeData(shape: shape),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(${appTheme.cornerRadius}),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: shape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: shape),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: ${_dartString(document.name)},
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: $themeMode,
      initialRoute: ${_dartString(initialRoute)},
      routes: <String, WidgetBuilder>{
$routes      },
    );
  }
}
${usesSignature ? _signatureHelper : ''}
${usesSwipeableStack ? _swipeableStackHelper : ''}
''';
  }

  /// Creates the editable source files that sit on top of Flutter's generated
  /// platform scaffold. The exporter adds the native platform directories.
  Map<String, String> generateProjectFiles(
    BuilderDocument document, {
    required String projectName,
    Map<String, String> imageAssets = const <String, String>{},
  }) {
    final List<String> assets = imageAssets.values.toSet().toList()..sort();
    final String assetsSection =
        assets.isEmpty
            ? ''
            : '  assets:\n${assets.map((String asset) => "    - '$asset'\n").join()}';
    return <String, String>{
      'pubspec.yaml': '''name: ${packageNameFor(projectName)}
description: A Flutter app generated by Local Flutter Builder.
publish_to: none
version: 1.0.0+1

environment:
  sdk: '>=3.13.0 <4.0.0'
  flutter: '>=3.47.0'

dependencies:
  material_ui: ^1.6.0
  flutter:
    sdk: flutter
${_projectHttpDependency(document)}
${_projectDatabaseDependency(document)}

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
$assetsSection''',
      'lib/main.dart': generate(document, imageAssets: imageAssets),
      if (document.databaseCollections.isNotEmpty) ...<String, String>{
        'lib/local_database.dart': _generateDatabaseRepository(document),
        'lib/local_database_io.dart': _databaseIoSource,
        'lib/local_database_web.dart': _databaseWebSource,
      },
      'README.md': '''# ${document.name}

This Flutter app was generated locally by Local Flutter Builder.

## Run

Install Flutter 3.47 or later, then run `flutter pub get` and `flutter run` from this directory.
The project includes Android, iOS, web, Windows, macOS, and Linux scaffolding.
${document.databaseCollections.isEmpty ? '' : '\n## Local data\n\nRecords are stored on this device using Sembast. The web build uses IndexedDB in the current browser. Starter records are added only when each collection is first opened.\n'}
''',
      'analysis_options.yaml': '''analyzer:
  exclude:
    - build/**

linter:
  rules:
    - avoid_print
''',
      'test/widget_test.dart':
          '''import 'package:flutter_test/flutter_test.dart';
import 'package:${packageNameFor(projectName)}/main.dart';

void main() {
  testWidgets('generated app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const GeneratedApp());
    await tester.pumpAndSettle();
    expect(find.byType(GeneratedApp), findsOneWidget);
  });
}
''',
    };
  }

  static String packageNameFor(String name) {
    String result = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (result.isEmpty) result = 'generated_app';
    if (RegExp(r'^[0-9]').hasMatch(result)) result = 'app_$result';
    const Set<String> reserved = <String>{
      'assert',
      'break',
      'case',
      'catch',
      'class',
      'const',
      'continue',
      'default',
      'do',
      'else',
      'enum',
      'extends',
      'false',
      'final',
      'finally',
      'for',
      'if',
      'in',
      'is',
      'new',
      'null',
      'rethrow',
      'return',
      'super',
      'switch',
      'this',
      'throw',
      'true',
      'try',
      'var',
      'void',
      'while',
      'with',
      'yield',
    };
    if (reserved.contains(result)) result = 'app_$result';
    return result;
  }

  static String _imageAssetKey(String pageId, String nodeId) =>
      '$pageId::$nodeId';

  String _actionHandler(BuilderNode node, int indent) {
    final List<Map<String, Object?>> actions = BuilderAction.forNode(node);
    if (actions.isEmpty) return 'null';
    final String pad = _spaces(indent);
    final String body = _emitActionStatements(actions, indent + 4);
    if (body.isEmpty) return 'null';
    return '() async {\n$body$pad}';
  }

  String _actionInvocation(BuilderNode node, int indent) {
    final String handler = _actionHandler(node, indent);
    return handler == 'null' ? '' : ' await ($handler)();';
  }

  String _emitCustomFunction(BuilderCustomFunction function) {
    final String body =
        function.body.trim().isEmpty
            ? _emitActionStatements(function.actions, 4)
            : _indentCustomFunctionBody(function.body);
    final List<String> variableIdEntries = <String>[];
    for (final BuilderVariable variable in _variablesById.values) {
      variableIdEntries
        ..add('      ${_dartString(variable.id)}: ${_dartString(variable.id)},')
        ..add(
          '      ${_dartString(variable.name)}: ${_dartString(variable.id)},',
        );
    }
    final String previewHelpers =
        function.body.trim().isEmpty
            ? ''
            : '''
    final Map<String, String> _customFunctionVariableIds = <String, String>{
${variableIdEntries.join('\n')}
    };
    Object? getVariable(String nameOrId) {
      final String? id = _customFunctionVariableIds[nameOrId];
      return _appState[id ?? nameOrId];
    }
    void setVariable(String nameOrId, Object? value) {
      final String? id = _customFunctionVariableIds[nameOrId];
      if (id != null) setState(() => _appState[id] = value);
    }
    void showMessage(String message) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    void navigateTo(String route) {
      Navigator.of(context).pushNamed(route);
    }
    Future<void> back() async {
      await Navigator.of(context).maybePop();
    }
''';
    return '  Future<void> ${_customFunctionMethodName(function)}(BuildContext context) async {\n'
        '$previewHelpers'
        '$body'
        '  }\n';
  }

  String _indentCustomFunctionBody(String source) {
    final List<String> lines = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    final int commonIndent =
        lines
            .where((String line) => line.trim().isNotEmpty)
            .map(
              (String line) =>
                  RegExp(r'^\s*').firstMatch(line)!.group(0)!.length,
            )
            .fold<int?>(
              null,
              (int? minimum, int indent) =>
                  minimum == null || indent < minimum ? indent : minimum,
            ) ??
        0;
    return lines
        .map(
          (String line) =>
              line.trim().isEmpty
                  ? '\n'
                  : '    ${line.substring(commonIndent)}\n',
        )
        .join();
  }

  String _customFunctionMethodName(BuilderCustomFunction function) {
    final String token = packageNameFor('custom_${function.id}');
    return '_run_$token';
  }

  String _emitActionStatements(List<Map<String, Object?>> actions, int indent) {
    final String inner = _spaces(indent);
    final StringBuffer body = StringBuffer();
    for (final Map<String, Object?> action in actions) {
      switch (action['type']) {
        case 'navigate':
          final String route = _stringActionValue(action, 'route').trim();
          if (route.isEmpty) break;
          final String method =
              action['behavior'] == 'replace'
                  ? 'pushReplacementNamed'
                  : 'pushNamed';
          body.writeln(
            '$inner Navigator.of(context).$method(${_templateExpression(route)});',
          );
        case 'snackbar':
          body.writeln(
            '$inner ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(${_templateExpression(_stringActionValue(action, 'message'))})));',
          );
        case 'dialog':
          body
            ..writeln('$inner await showDialog<void>(')
            ..writeln('${_spaces(indent + 4)}context: context,')
            ..writeln(
              '${_spaces(indent + 4)}builder: (BuildContext dialogContext) => AlertDialog(',
            )
            ..writeln(
              '${_spaces(indent + 6)}title: Text(${_templateExpression(_stringActionValue(action, 'title', fallback: 'Notice'))}),',
            )
            ..writeln(
              '${_spaces(indent + 6)}content: Text(${_templateExpression(_stringActionValue(action, 'message'))}),',
            )
            ..writeln('${_spaces(indent + 6)}actions: <Widget>[')
            ..writeln(
              '${_spaces(indent + 8)}TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("OK")),',
            )
            ..writeln('${_spaces(indent + 6)}],')
            ..writeln('${_spaces(indent + 4)}),')
            ..writeln('$inner);');
        case 'back':
          body.writeln('$inner await Navigator.of(context).maybePop();');
        case 'setVariable':
          final String variableId = action['variableId'] as String? ?? '';
          final BuilderVariable? variable = _variablesById[variableId];
          if (variable == null) break;
          final Object? rawValue = action['value'];
          final String value =
              variable.type == 'string' && rawValue is String
                  ? _templateExpression(rawValue)
                  : _dartValue(_coerceActionValue(variable, rawValue));
          body.writeln(
            '$inner setState(() => _appState[${_dartString(variableId)}] = $value);',
          );
        case 'incrementVariable':
          final String variableId = action['variableId'] as String? ?? '';
          final BuilderVariable? variable = _variablesById[variableId];
          if (variable == null || !_isNumericType(variable.type)) break;
          final double amount = _number(action['amount'], 1, -1000000, 1000000);
          final String numericExpression =
              variable.type == 'integer'
                  ? '(((_appState[${_dartString(variableId)}] as num?)?.toInt() ?? 0) + ${amount.round()})'
                  : '(((_appState[${_dartString(variableId)}] as num?)?.toDouble() ?? 0) + $amount)';
          body.writeln(
            '$inner setState(() => _appState[${_dartString(variableId)}] = $numericExpression);',
          );
        case 'toggleVariable':
          final String variableId = action['variableId'] as String? ?? '';
          final BuilderVariable? variable = _variablesById[variableId];
          if (variable == null || variable.type != 'boolean') break;
          body.writeln(
            '$inner setState(() => _appState[${_dartString(variableId)}] = !((_appState[${_dartString(variableId)}] as bool?) ?? false));',
          );
        case 'updateWidget':
          final String pageId = action['targetPageId'] as String? ?? 'home';
          final String targetNodeId = action['targetNodeId'] as String? ?? '';
          final String property = action['property'] as String? ?? '';
          if (targetNodeId.isEmpty ||
              !<String>{
                'text',
                'label',
                'initialValue',
                'visible',
                'opacity',
              }.contains(property))
            break;
          final Object? rawValue = action['value'];
          final String value =
              rawValue is String &&
                      <String>{
                        'text',
                        'label',
                        'initialValue',
                      }.contains(property)
                  ? _templateExpression(rawValue)
                  : _dartValue(_coerceWidgetActionValue(property, rawValue));
          body.writeln(
            '$inner setState(() => _widgetState[${_dartString('${_runtimeWidgetKey(pageId, targetNodeId)}.$property')}] = $value);',
          );
        case 'conditional':
          final String condition = _conditionExpression(action);
          body.writeln('$inner if ($condition) {');
          body.write(
            _emitActionStatements(
              _actionList(action['thenActions']),
              indent + 2,
            ),
          );
          final List<Map<String, Object?>> elseActions = _actionList(
            action['elseActions'],
          );
          if (elseActions.isNotEmpty) {
            body.writeln('${inner}} else {');
            body.write(_emitActionStatements(elseActions, indent + 2));
          }
          body.writeln('$inner}');
        case 'loop':
          final int count =
              _integer(action['iterations'], 1).clamp(1, 1000).toInt();
          body.writeln(
            '${inner}for (int _actionLoop = 0; _actionLoop < $count; _actionLoop++) {',
          );
          body.write(
            _emitActionStatements(_actionList(action['actions']), indent + 2),
          );
          body.writeln('$inner}');
        case 'httpRequest':
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
          final String uri = _templateExpression(
            _stringActionValue(action, 'url'),
          );
          final String headers = _httpHeadersExpression(action['headers']);
          final String requestBody = _templateExpression(
            _stringActionValue(action, 'body'),
          );
          body
            ..writeln('${inner}try {')
            ..writeln(
              '${_spaces(indent + 2)}final Uri? _actionUri = Uri.tryParse($uri);',
            )
            ..writeln(
              '${_spaces(indent + 2)}if (_actionUri != null && const <String>{"http", "https"}.contains(_actionUri.scheme)) {',
            )
            ..writeln(
              '${_spaces(indent + 4)}final http.Response _actionResponse = await _sendHttpRequest(${_dartString(method)}, _actionUri, $headers, $requestBody);',
            );
          final String responseId =
              action['responseVariableId'] as String? ?? '';
          final BuilderVariable? responseVariable = _variablesById[responseId];
          if (responseVariable != null) {
            body.writeln(
              '${_spaces(indent + 4)}setState(() => _appState[${_dartString(responseId)}] = ${_httpResponseExpression(responseVariable, '_actionResponse.body')});',
            );
          }
          body.writeln(
            '${_spaces(indent + 4)}if (_actionResponse.statusCode >= 400 && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("HTTP request returned \${_actionResponse.statusCode}.")));',
          );
          body
            ..writeln('${_spaces(indent + 2)}}')
            ..writeln('${inner}} catch (error) {')
            ..writeln(
              '${_spaces(indent + 2)}if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request failed: \${error}")));',
            )
            ..writeln('$inner}');
        case 'databaseInsert':
          final String collectionId = action['collectionId'] as String? ?? '';
          if (!_databaseCollectionsById.containsKey(collectionId)) break;
          final String record = _templateExpression(
            _stringActionValue(action, 'record', fallback: '{}'),
          );
          body
            ..writeln('${inner}try {')
            ..writeln(
              '${_spaces(indent + 2)}final Object? decoded = jsonDecode($record);',
            )
            ..writeln(
              '${_spaces(indent + 2)}if (decoded is! Map) throw const FormatException("Record must be a JSON object.");',
            )
            ..writeln(
              '${_spaces(indent + 2)}await _database.insert(${_dartString(collectionId)}, Map<String, Object?>.from(decoded));',
            )
            ..writeln('$inner} catch (error) {')
            ..writeln(
              '${_spaces(indent + 2)}if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not save record: " + error.toString())));',
            )
            ..writeln('$inner}');
        case 'databaseQuery':
          final String collectionId = action['collectionId'] as String? ?? '';
          final String variableId = action['resultVariableId'] as String? ?? '';
          if (!_databaseCollectionsById.containsKey(collectionId) ||
              _variablesById[variableId]?.type != 'json')
            break;
          body
            ..writeln('${inner}try {')
            ..writeln(
              '${_spaces(indent + 2)}final records = await _database.query(${_dartString(collectionId)});',
            )
            ..writeln(
              '${_spaces(indent + 2)}if (mounted) setState(() => _appState[${_dartString(variableId)}] = records);',
            )
            ..writeln('$inner} catch (error) {')
            ..writeln(
              '${_spaces(indent + 2)}if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not load records: " + error.toString())));',
            )
            ..writeln('$inner}');
        case 'databaseDelete':
          final String collectionId = action['collectionId'] as String? ?? '';
          if (!_databaseCollectionsById.containsKey(collectionId)) break;
          final String recordId = _templateExpression(
            _stringActionValue(action, 'recordId'),
          );
          body
            ..writeln('${inner}try {')
            ..writeln(
              '${_spaces(indent + 2)}await _database.delete(${_dartString(collectionId)}, $recordId);',
            )
            ..writeln('$inner} catch (error) {')
            ..writeln(
              '${_spaces(indent + 2)}if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not delete record: " + error.toString())));',
            )
            ..writeln('$inner}');
        case 'customFunction':
          final String functionId = action['functionId'] as String? ?? '';
          final BuilderCustomFunction? function =
              _customFunctionsById[functionId];
          if (function == null) break;
          body
            ..writeln(
              '$inner if (_activeCustomFunctions.add(${_dartString(functionId)})) {',
            )
            ..writeln('${_spaces(indent + 2)}try {')
            ..writeln(
              '${_spaces(indent + 4)}await ${_customFunctionMethodName(function)}(context);',
            )
            ..writeln('${_spaces(indent + 2)}} finally {')
            ..writeln(
              '${_spaces(indent + 4)}_activeCustomFunctions.remove(${_dartString(functionId)});',
            )
            ..writeln('${_spaces(indent + 2)}}')
            ..writeln('$inner}');
      }
    }
    return body.toString();
  }

  List<Map<String, Object?>> _actionList(Object? raw) =>
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

  String _stringActionValue(
    Map<String, Object?> action,
    String key, {
    String fallback = '',
  }) => action[key] is String ? action[key]! as String : fallback;

  String _conditionExpression(Map<String, Object?> action) {
    final String id = action['variableId'] as String? ?? '';
    final BuilderVariable? variable = _variablesById[id];
    if (variable == null) return 'false';
    final String state = '_appState[${_dartString(id)}]';
    final String value = _templateExpression(
      _stringActionValue(action, 'value'),
    );
    if (_isNumericType(variable.type) &&
        <String>{'equals', 'notEquals'}.contains(action['operator'])) {
      final String comparison =
          '(($state as num?)?.toDouble() == double.tryParse($value))';
      return action['operator'] == 'notEquals' ? '!$comparison' : comparison;
    }
    if (variable.type == 'boolean' &&
        <String>{'equals', 'notEquals'}.contains(action['operator'])) {
      final String comparison =
          '($state == ($value.trim().toLowerCase() == "true"))';
      return action['operator'] == 'notEquals' ? '!$comparison' : comparison;
    }
    return switch (action['operator']) {
      'notEquals' => '($state?.toString() != $value)',
      'greaterThan' =>
        '(($state is num ? ($state as num).toDouble() : double.nan) > (double.tryParse($value) ?? double.nan))',
      'lessThan' =>
        '(($state is num ? ($state as num).toDouble() : double.nan) < (double.tryParse($value) ?? double.nan))',
      'contains' =>
        variable.type == 'stringList'
            ? '((($state as List?) ?? const <Object?>[]).contains($value))'
            : '(($state?.toString() ?? "").contains($value))',
      'isTrue' => '($state == true)',
      'isFalse' => '($state == false)',
      _ => '($state?.toString() == $value)',
    };
  }

  String _httpHeadersExpression(Object? raw) {
    Object? decoded = raw;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        decoded = null;
      }
    }
    if (decoded is! Map<Object?, Object?>) return '<String, String>{}';
    final Iterable<String> entries = decoded.entries.map((
      MapEntry<Object?, Object?> entry,
    ) {
      final String key = entry.key.toString();
      final String value =
          entry.value is String
              ? _templateExpression(entry.value as String)
              : _dartString(entry.value?.toString() ?? '');
      return '${_dartString(key)}: $value';
    });
    return '<String, String>{${entries.join(', ')}}';
  }

  String _httpResponseExpression(
    BuilderVariable variable,
    String body,
  ) => switch (variable.type) {
    'number' || 'double' =>
      '(double.tryParse($body) ?? ${_dartValue(variable.initialValue)})',
    'integer' =>
      '(int.tryParse($body) ?? ${_dartValue(variable.initialValue)})',
    'boolean' => '($body.trim().toLowerCase() == "true")',
    'json' =>
      '(() { try { return jsonDecode($body); } on FormatException { return $body; } })()',
    'stringList' =>
      '(() { try { final Object? value = jsonDecode($body); if (value is List) return value.map((Object? item) => item.toString()).toList(); } on FormatException {} return <String>[]; })()',
    _ => body,
  };

  String _projectHttpDependency(BuilderDocument document) {
    final bool usesHttp =
        document.customFunctions.any(
          (BuilderCustomFunction function) =>
              RegExp(r'\bhttp\.').hasMatch(function.body),
        ) ||
        document.customDataStructures.any(
          (BuilderCustomDataStructure structure) =>
              RegExp(r'\bhttp\.').hasMatch(structure.body),
        ) ||
        document.customFunctions.any(
          (BuilderCustomFunction function) => BuilderAction.allForFunction(
            function,
          ).any(
            (Map<String, Object?> action) => action['type'] == 'httpRequest',
          ),
        ) ||
        document.allPages.any(
          (BuilderPage page) => page.root.depthFirst().any(
            (BuilderNode node) => BuilderAction.allForNode(node).any(
              (Map<String, Object?> action) => action['type'] == 'httpRequest',
            ),
          ),
        );
    return usesHttp ? '  http: ^1.2.0\n' : '';
  }

  String _projectDatabaseDependency(BuilderDocument document) =>
      document.databaseCollections.isEmpty
          ? ''
          : '  sembast: ^3.8.4\n  sembast_web: ^2.4.2\n  path_provider: ^2.1.5\n  path: ^1.9.1\n';

  String _generateDatabaseRepository(BuilderDocument document) {
    final String seeds = document.databaseCollections
        .map(
          (BuilderDatabaseCollection collection) =>
              '    ${_dartString(collection.id)}: ${_dartString(jsonEncode(collection.seedRecords))},',
        )
        .join('\n');
    return '''import 'dart:convert';

import 'package:sembast/sembast.dart';
import 'local_database_io.dart'
    if (dart.library.js_interop) 'local_database_web.dart' as local_database;

class LocalDatabaseRepository {
  Future<Database>? _databaseFuture;
  final Map<String, String> _seedJson = <String, String>{
$seeds
  };

  Future<Database> _database() => _databaseFuture ??= _open();

  Future<Database> _open() async {
    final Database database = await local_database.openBuilderDatabase();
    final StoreRef<String, Map<String, Object?>> meta =
        stringMapStoreFactory.store('_builder_meta');
    for (final MapEntry<String, String> entry in _seedJson.entries) {
      await database.transaction((Transaction transaction) async {
        final RecordRef<String, Map<String, Object?>> marker =
            meta.record(entry.key);
        if (await marker.get(transaction) != null) return;
        final StoreRef<int, Map<String, Object?>> store =
            intMapStoreFactory.store(entry.key);
        final List<Object?> records = jsonDecode(entry.value) as List<Object?>;
        for (final Object? record in records) {
          await store.add(transaction,
              Map<String, Object?>.from(record! as Map<String, Object?>));
        }
        await marker.put(transaction, <String, Object?>{'seeded': true});
      });
    }
    return database;
  }

  Future<int> insert(String collectionId, Map<String, Object?> record) async {
    final Database database = await _database();
    return intMapStoreFactory.store(collectionId).add(database, record);
  }

  Future<List<Map<String, Object?>>> query(String collectionId) async {
    final Database database = await _database();
    final List<RecordSnapshot<int, Map<String, Object?>>> records =
        await intMapStoreFactory.store(collectionId).find(database);
    return records.map((RecordSnapshot<int, Map<String, Object?>> record) =>
        <String, Object?>{...record.value, '_id': record.key}).toList();
  }

  Future<bool> delete(String collectionId, String recordId) async {
    final int? id = int.tryParse(recordId.trim());
    if (id == null) return false;
    final Database database = await _database();
    return await intMapStoreFactory.store(collectionId)
            .record(id).delete(database) != null;
  }
}
''';
  }

  static const String _databaseIoSource =
      '''import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openBuilderDatabase() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase(
    path.join(directory.path, 'local_builder.db'),
  );
}
''';

  static const String _databaseWebSource =
      '''import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

Future<Database> openBuilderDatabase() =>
    databaseFactoryWeb.openDatabase('local_builder.db');
''';

  String _emitNode(BuilderNode node, int indent) {
    final bool isExpanded = node.type == 'expanded';
    final bool hasPadding =
        !isExpanded &&
        node.type != 'container' &&
        node.type != 'padding' &&
        _hasInsets(node, 'padding');
    final bool hasOpacity =
        !isExpanded &&
        (_number(node.properties['opacity'], 1, 0, 1) < 1 ||
            _hasDynamicProperty(node, 'opacity'));
    final bool hasMargin = !isExpanded && _hasInsets(node, 'margin');
    final bool hasVisibility =
        !isExpanded &&
        (node.properties['visible'] == false ||
            _hasDynamicProperty(node, 'visible'));
    final bool hasResponsiveSize =
        !isExpanded &&
        (_sizeFactor(node.properties['widthMode']) != null ||
            _sizeFactor(node.properties['heightMode']) != null);
    final int wrapperCount =
        (hasResponsiveSize ? 1 : 0) +
        (hasPadding ? 1 : 0) +
        (hasOpacity ? 1 : 0) +
        (hasMargin ? 1 : 0) +
        (hasVisibility ? 1 : 0);
    String output = _emitRawNode(node, indent + wrapperCount * 4);
    int wrapperIndent = indent + (wrapperCount - 1) * 4;

    if (hasResponsiveSize) {
      output = _wrapResponsiveSize(output, node, wrapperIndent);
      wrapperIndent -= 4;
    }
    if (hasPadding) {
      output = _wrapWidget(
        'Padding',
        '${_spaces(wrapperIndent + 2)}padding: const ${_edgeInsetsLiteral(node, 'padding')},\n',
        output,
        wrapperIndent,
      );
      wrapperIndent -= 4;
    }
    if (hasOpacity) {
      final double opacity = _number(node.properties['opacity'], 1, 0, 1);
      output = _wrapWidget(
        'Opacity',
        '${_spaces(wrapperIndent + 2)}opacity: ${_propertyExpression(node, 'opacity', '$opacity', 'number')},\n',
        output,
        wrapperIndent,
      );
      wrapperIndent -= 4;
    }
    if (hasMargin) {
      output = _wrapWidget(
        'Padding',
        '${_spaces(wrapperIndent + 2)}padding: const ${_edgeInsetsLiteral(node, 'margin')},\n',
        output,
        wrapperIndent,
      );
      wrapperIndent -= 4;
    }
    if (hasVisibility) {
      output = _wrapWidget(
        'Visibility',
        '${_spaces(wrapperIndent + 2)}visible: ${_propertyExpression(node, 'visible', node.properties['visible'] == false ? 'false' : 'true', 'boolean')},\n',
        output,
        wrapperIndent,
      );
    }
    return output;
  }

  String _wrapResponsiveSize(String child, BuilderNode node, int indent) {
    final double? widthFactor = _sizeFactor(node.properties['widthMode']);
    final double? heightFactor = _sizeFactor(node.properties['heightMode']);
    final String width =
        widthFactor == null
            ? 'null'
            : '(constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width) * $widthFactor';
    final String height =
        heightFactor == null
            ? 'null'
            : '(constraints.maxHeight.isFinite ? constraints.maxHeight : MediaQuery.sizeOf(context).height) * $heightFactor';
    final String pad = _spaces(indent);
    final String inner = _spaces(indent + 4);
    return 'LayoutBuilder(\n'
        '${_spaces(indent + 2)}builder: (BuildContext context, BoxConstraints constraints) {\n'
        '${_spaces(indent + 4)}return SizedBox(\n'
        '$inner width: $width,\n'
        '$inner height: $height,\n'
        '$inner child: $child,\n'
        '${_spaces(indent + 4)});\n'
        '${_spaces(indent + 2)}},\n'
        '$pad)';
  }

  double? _sizeFactor(Object? value) => switch (value) {
    'max' => 1,
    'quarter' => 0.25,
    'half' => 0.5,
    'threeQuarter' => 0.75,
    _ => null,
  };

  String _emitRawNode(BuilderNode node, int indent) {
    final String pad = _spaces(indent);
    final String inner = _spaces(indent + 2);
    switch (node.type) {
      case 'scaffold':
        final BuilderNode? appBar = _firstChildOfType(node, 'appBar');
        final BuilderNode? floatingActionButton =
            _firstChildOfType(node, 'floatingActionButton') ??
            _firstChildOfType(node, 'extendedFloatingActionButton');
        final BuilderNode? bottomAppBar = _firstChildOfType(
          node,
          'bottomAppBar',
        );
        final BuilderNode? navigationBar = _firstChildOfType(
          node,
          'navigationBar',
        );
        final BuilderNode? bottomSheet = _firstChildOfType(node, 'bottomSheet');
        final BuilderNode? drawer = _firstChildOfType(node, 'navigationDrawer');
        final BuilderNode? bottomNavigation = bottomAppBar ?? navigationBar;
        final Set<String> scaffoldSlotIds = <String>{
          if (appBar != null) appBar.id,
          if (floatingActionButton != null) floatingActionButton.id,
          if (bottomNavigation != null) bottomNavigation.id,
          if (bottomSheet != null) bottomSheet.id,
          if (drawer != null) drawer.id,
        };
        final List<BuilderNode> bodyChildren =
            node.children
                .where(
                  (BuilderNode child) => !scaffoldSlotIds.contains(child.id),
                )
                .toList();
        final String appBarSource =
            appBar == null
                ? ''
                : '$inner appBar: ${_emitRawNode(appBar, indent + 4)},\n';
        final String floatingButtonSource =
            floatingActionButton == null
                ? ''
                : '$inner floatingActionButton: ${_emitRawNode(floatingActionButton, indent + 4)},\n';
        final String bottomNavigationSource =
            bottomNavigation == null
                ? ''
                : '$inner bottomNavigationBar: ${_emitRawNode(bottomNavigation, indent + 4)},\n';
        final String bottomSheetSource =
            bottomSheet == null
                ? ''
                : '$inner bottomSheet: ${_emitRawNode(bottomSheet, indent + 4)},\n';
        final String drawerSource =
            drawer == null
                ? ''
                : '$inner drawer: ${_emitRawNode(drawer, indent + 4)},\n';
        return 'Scaffold(\n'
            '$appBarSource'
            '$inner body: ${_emitChildren(bodyChildren, indent + 4)},\n'
            '$floatingButtonSource'
            '$bottomNavigationSource'
            '$bottomSheetSource'
            '$drawerSource'
            '$pad)';
      case 'column':
      case 'row':
        final String constructor = node.type == 'row' ? 'Row' : 'Column';
        final String children = _emitWidgetList(node.children, indent + 6);
        return '$constructor(\n'
            '$inner mainAxisAlignment: ${_mainAxis(node.properties['mainAxisAlignment'])},\n'
            '$inner crossAxisAlignment: ${_crossAxis(node.properties['crossAxisAlignment'])},\n'
            '$inner children: <Widget>[\n'
            '$children'
            '$inner ],\n'
            '$pad)';
      case 'expanded':
        final int flex = _integer(node.properties['flex'], 1).clamp(1, 100);
        return 'Expanded(\n'
            '$inner flex: $flex,\n'
            '$inner child: ${_emitChildren(node.children, indent + 4)},\n'
            '$pad)';
      case 'safeArea':
        final bool top = node.properties['top'] != false;
        final bool bottom = node.properties['bottom'] != false;
        final bool left = node.properties['left'] != false;
        final bool right = node.properties['right'] != false;
        final double minimum = _number(node.properties['minimum'], 0, 0, 1200);
        return 'SafeArea(\n'
            '$inner top: $top,\n'
            '$inner bottom: $bottom,\n'
            '$inner left: $left,\n'
            '$inner right: $right,\n'
            '$inner minimum: const EdgeInsets.all($minimum),\n'
            '$inner child: ${_emitChildren(node.children, indent + 4)},\n'
            '$pad)';
      case 'container':
        final double width = _number(node.properties['width'], 220, 0, 1200);
        final double height = _number(node.properties['height'], 100, 0, 1200);
        final double padding = _number(node.properties['padding'], 12, 0, 1200);
        final double radius = _number(
          node.properties['borderRadius'],
          12,
          0,
          100,
        );
        final int color = _integer(
          node.properties['backgroundColor'],
          0xFFF1EFF8,
        );
        final String alignment =
            node.properties['alignment'] is String
                ? '$inner alignment: ${_alignmentLiteral(node.properties['alignment'])},\n'
                : '';
        return 'Container(\n'
            '$inner width: $width,\n'
            '$inner height: $height,\n'
            '$inner padding: const ${_edgeInsetsLiteral(node, 'padding', fallback: padding)},\n'
            '$alignment'
            '$inner decoration: BoxDecoration(\n'
            '${_spaces(indent + 4)}color: const Color(${_colorLiteral(color)}),\n'
            '${_spaces(indent + 4)}borderRadius: BorderRadius.circular($radius),\n'
            '$inner ),\n'
            '$inner child: ${_emitChildren(node.children, indent + 4)},\n'
            '$pad)';
      case 'padding':
        return 'Padding(\n'
            '$inner padding: const ${_edgeInsetsLiteral(node, 'padding', fallback: 16)},\n'
            '$inner child: ${_emitChildren(node.children, indent + 4)},\n'
            '$pad)';
      case 'componentGroup':
        return _emitChildren(node.children, indent);
      case 'card':
        final double width = _number(node.properties['width'], 240, 0, 1200);
        final double height = _number(node.properties['height'], 140, 0, 1200);
        final double radius = _number(
          node.properties['borderRadius'],
          12,
          0,
          100,
        );
        final double elevation = _number(
          node.properties['elevation'],
          2,
          0,
          24,
        );
        final int cardColor = _integer(
          node.properties['backgroundColor'],
          0xFFFFFFFF,
        );
        return 'SizedBox(width: $width, height: $height, child: Card(\n'
            '$inner color: const Color(${_colorLiteral(cardColor)}),\n'
            '$inner elevation: $elevation,\n'
            '$inner shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular($radius)),\n'
            '$inner child: Padding(padding: const ${_edgeInsetsLiteral(node, 'padding', fallback: 12)}, child: ${_emitChildren(node.children, indent + 4)}),\n'
            '$pad))';
      case 'stack':
        final double width = _number(node.properties['width'], 260, 0, 1200);
        final double height = _number(node.properties['height'], 160, 0, 1200);
        final String children = _emitWidgetList(node.children, indent + 6);
        return 'SizedBox(width: $width, height: $height, child: Stack(\n'
            '$inner alignment: ${_alignmentLiteral(node.properties['alignment'])},\n'
            '$inner fit: ${node.properties['fit'] == 'expand' ? 'StackFit.expand' : 'StackFit.loose'},\n'
            '$inner children: <Widget>[\n'
            '$children'
            '$inner ],\n'
            '$pad))';
      case 'listView':
      case 'gridView':
      case 'pageView':
        return _emitCollectionNode(node, indent);
      case 'swipeableStack':
        return _emitSwipeableStack(node, indent);
      case 'appBar':
        final String title = _dartString(
          node.properties['title'] as String? ?? 'App Bar',
        );
        final int background = _integer(
          node.properties['backgroundColor'],
          0xFF6750A4,
        );
        final int foreground = _integer(
          node.properties['foregroundColor'],
          0xFFFFFFFF,
        );
        final double elevation = _number(
          node.properties['elevation'],
          2,
          0,
          24,
        );
        return 'AppBar(title: Text($title), backgroundColor: const Color(${_colorLiteral(background)}), foregroundColor: const Color(${_colorLiteral(foreground)}), elevation: $elevation)';
      case 'floatingActionButton':
        final int background = _integer(
          node.properties['backgroundColor'],
          0xFF6750A4,
        );
        final int foreground = _integer(
          node.properties['foregroundColor'],
          0xFFFFFFFF,
        );
        return 'FloatingActionButton(onPressed: ${_actionHandler(node, indent)}, backgroundColor: const Color(${_colorLiteral(background)}), foregroundColor: const Color(${_colorLiteral(foreground)}), child: Icon(${_iconLiteral(node.properties['iconName'])}))';
      case 'extendedFloatingActionButton':
        return 'FloatingActionButton.extended(onPressed: ${_actionHandler(node, indent)}, icon: Icon(${_iconLiteral(node.properties['iconName'])}), label: Text(${_dartString(node.properties['label'] as String? ?? 'Create')}), backgroundColor: const Color(${_colorLiteral(_integer(node.properties['backgroundColor'], 0xFF6750A4))}), foregroundColor: const Color(${_colorLiteral(_integer(node.properties['foregroundColor'], 0xFFFFFFFF))}))';
      case 'iconButton':
        final String tooltip = _dartString(
          node.properties['tooltip'] as String? ?? '',
        );
        final String constructor = switch (node.properties['style']) {
          'filled' => 'IconButton.filled',
          'filledTonal' => 'IconButton.filledTonal',
          'outlined' => 'IconButton.outlined',
          _ => 'IconButton',
        };
        return '$constructor(tooltip: $tooltip, icon: Icon(${_iconLiteral(node.properties['iconName'])}), onPressed: ${_actionHandler(node, indent)})';
      case 'segmentedButton':
        final List<String> options = _commaSeparated(
          node.properties['options'],
          'Day,Week,Month',
        );
        final String segments = options
            .map(
              (String option) =>
                  'ButtonSegment<String>(value: ${_dartString(option)}, label: Text(${_dartString(option)}))',
            )
            .join(', ');
        final String key = _dartString('${_currentPageId}::${node.id}');
        final int selected = _integer(
          node.properties['selectedIndex'],
          0,
        ).clamp(0, options.length - 1);
        final bool multiSelect = node.properties['multiSelect'] == true;
        final List<String> selectedOptions =
            _commaSeparated(
              node.properties['selectedOptions'],
              options[selected],
            ).where(options.contains).toList();
        final String actionCall = _actionInvocation(node, indent + 2);
        if (multiSelect) {
          if (selectedOptions.isEmpty) selectedOptions.add(options[selected]);
          final String initialSelection = selectedOptions
              .map(_dartString)
              .join(', ');
          return 'SegmentedButton<String>(segments: <ButtonSegment<String>>[$segments], multiSelectionEnabled: true, selected: (_widgetState.putIfAbsent($key, () => <String>{$initialSelection}) as Set<String>), onSelectionChanged: (Set<String> selection) async { setState(() { _widgetState[$key] = selection; });$actionCall })';
        }
        final String initialSelection = _dartString(options[selected]);
        return 'SegmentedButton<String>(segments: <ButtonSegment<String>>[$segments], selected: <String>{(_widgetState.putIfAbsent($key, () => $initialSelection) as String)}, onSelectionChanged: (Set<String> selection) async { setState(() { _widgetState[$key] = selection.first; });$actionCall })';
      case 'badge':
        final String badgeChild =
            node.children.isEmpty
                ? 'Icon(${_iconLiteral(node.properties['iconName'])})'
                : _emitChildren(node.children, indent + 4);
        return 'Badge(label: Text(${_dartString(node.properties['label'] as String? ?? '3')}), child: $badgeChild)';
      case 'linearProgressIndicator':
        final double value = _number(node.properties['value'], 0.65, 0, 1);
        final double minHeight = _number(
          node.properties['minHeight'],
          4,
          0,
          100,
        );
        return 'LinearProgressIndicator(value: $value, minHeight: $minHeight)';
      case 'snackBar':
        final String actionLabel =
            (node.properties['actionLabel'] as String? ?? '').trim();
        final String actionHandler = _actionHandler(node, indent);
        final String actionCallback =
            actionHandler == 'null' ? '() {}' : actionHandler;
        final String action =
            actionLabel.isEmpty
                ? ''
                : ', action: SnackBarAction(label: ${_dartString(actionLabel)}, onPressed: $actionCallback)';
        return 'SnackBar(content: Text(${_dartString(node.properties['message'] as String? ?? 'Message')})$action)';
      case 'alertDialog':
        final String content =
            node.children.isEmpty
                ? 'Text(${_dartString(node.properties['message'] as String? ?? 'Message')})'
                : _emitChildren(node.children, indent + 4);
        final String cancel =
            (node.properties['cancelLabel'] as String? ?? '').trim();
        final String cancelAction =
            cancel.isEmpty
                ? ''
                : 'TextButton(onPressed: ${_actionHandler(node, indent)}, child: Text(${_dartString(cancel)})), ';
        return 'AlertDialog(title: Text(${_dartString(node.properties['title'] as String? ?? 'Dialog')}), content: $content, actions: <Widget>[$cancelAction FilledButton(onPressed: ${_actionHandler(node, indent)}, child: Text(${_dartString(node.properties['confirmLabel'] as String? ?? 'OK')}))])';
      case 'bottomSheet':
        final String sheetContent =
            node.children.isEmpty
                ? 'ListTile(title: Text(${_dartString(node.properties['title'] as String? ?? 'More options')}), subtitle: Text(${_dartString(node.properties['message'] as String? ?? '')}))'
                : _emitChildren(node.children, indent + 4);
        return 'BottomSheet(onClosing: () {}, builder: (BuildContext context) => Padding(padding: const EdgeInsets.all(16), child: $sheetContent))';
      case 'listTile':
        final String subtitle =
            (node.properties['subtitle'] as String? ?? '').trim();
        final String subtitleArg =
            subtitle.isEmpty
                ? ''
                : ', subtitle: Text(${_dartString(subtitle)})';
        return 'ListTile(leading: Icon(${_iconLiteral(node.properties['leadingIcon'])}), title: Text(${_dartString(node.properties['title'] as String? ?? 'List item')})$subtitleArg, trailing: Icon(${_iconLiteral(node.properties['trailingIcon'])}), onTap: ${_actionHandler(node, indent)})';
      case 'bottomAppBar':
        return 'BottomAppBar(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[Text(${_dartString(node.properties['label'] as String? ?? 'Bottom app bar')}), IconButton(tooltip: "Add", icon: const Icon(Icons.add), onPressed: ${_actionHandler(node, indent)})]))';
      case 'navigationBar':
      case 'navigationDrawer':
      case 'navigationRail':
        final List<String> destinations = _commaSeparated(
          node.properties['destinations'],
          'Home,Search,Settings',
        );
        final String key = _dartString('${_currentPageId}::${node.id}');
        final int selected = _integer(
          node.properties['selectedIndex'],
          0,
        ).clamp(0, destinations.length - 1);
        final String selectedIndex =
            '(_widgetState.putIfAbsent($key, () => $selected) as int).clamp(0, ${destinations.length - 1})';
        final String actionCall = _actionInvocation(node, indent + 2);
        if (node.type == 'navigationBar') {
          final String destinationWidgets = destinations
              .map(
                (String label) =>
                    'NavigationDestination(icon: const Icon(Icons.circle_outlined), selectedIcon: const Icon(Icons.circle), label: ${_dartString(label)})',
              )
              .join(', ');
          return 'NavigationBar(selectedIndex: $selectedIndex, onDestinationSelected: (int index) async { setState(() { _widgetState[$key] = index; });$actionCall }, destinations: <NavigationDestination>[$destinationWidgets])';
        }
        final String drawerRailDestinations = destinations
            .map(
              (String label) =>
                  node.type == 'navigationDrawer'
                      ? 'NavigationDrawerDestination(icon: const Icon(Icons.circle_outlined), selectedIcon: const Icon(Icons.circle), label: Text(${_dartString(label)}))'
                      : 'NavigationRailDestination(icon: const Icon(Icons.circle_outlined), selectedIcon: const Icon(Icons.circle), label: Text(${_dartString(label)}))',
            )
            .join(', ');
        final String typeName =
            node.type == 'navigationDrawer'
                ? 'NavigationDrawer'
                : 'NavigationRail';
        final String childrenName =
            node.type == 'navigationDrawer' ? 'children' : 'destinations';
        final String childrenType =
            node.type == 'navigationRail'
                ? 'NavigationRailDestination'
                : 'Widget';
        final String destinationsArg =
            node.type == 'navigationDrawer'
                ? 'Padding(padding: const EdgeInsets.fromLTRB(28, 16, 16, 10), child: Text("Navigation", style: Theme.of(context).textTheme.titleSmall)), '
                : '';
        return '$typeName(selectedIndex: $selectedIndex, onDestinationSelected: (int index) async { setState(() { _widgetState[$key] = index; });$actionCall }, $childrenName: <$childrenType>[$destinationsArg$drawerRailDestinations])';
      case 'tabBar':
        final List<String> tabs = _commaSeparated(
          node.properties['tabs'],
          'Overview,Details,Reviews',
        );
        final String tabWidgets = tabs
            .map((String tab) => 'Tab(text: ${_dartString(tab)})')
            .join(', ');
        final String actionCall = _actionInvocation(node, indent + 4);
        return 'DefaultTabController(length: ${tabs.length}, child: TabBar(onTap: (int index) async {$actionCall }, tabs: <Widget>[$tabWidgets]))';
      case 'chip':
        return 'ActionChip(label: Text(${_dartString(node.properties['label'] as String? ?? 'Chip')}), onPressed: ${_actionHandler(node, indent)})';
      case 'datePicker':
        final String key = _dartString('${_currentPageId}::${node.id}');
        final String actionCall = _actionInvocation(node, indent + 2);
        return 'TextButton.icon(onPressed: () async { final DateTime? value = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(1900), lastDate: DateTime(2100)); if (value != null && context.mounted) { setState(() { _widgetState[$key] = value; });$actionCall } }, icon: const Icon(Icons.calendar_month), label: Text(_widgetState[$key] is DateTime ? (_widgetState[$key] as DateTime).toString().split(" ").first : ${_dartString(node.properties['label'] as String? ?? 'Select date')}))';
      case 'menu':
        final List<String> options = _commaSeparated(
          node.properties['options'],
          'Edit,Copy,Delete',
        );
        final String key = _dartString('${_currentPageId}::${node.id}');
        final String actionCall = _actionInvocation(node, indent + 4);
        final String menuItems = options
            .map(
              (String option) =>
                  'MenuItemButton(onPressed: () async { setState(() { _widgetState[$key] = ${_dartString(option)}; });$actionCall }, child: Text(${_dartString(option)}))',
            )
            .join(', ');
        return 'MenuAnchor(menuChildren: <Widget>[$menuItems], builder: (BuildContext context, MenuController controller, Widget? child) => FilledButton.tonal(onPressed: () { if (controller.isOpen) { controller.close(); } else { controller.open(); } }, child: Text(${_dartString(node.properties['label'] as String? ?? 'Open menu')})))';
      case 'radio':
        final List<String> options = _commaSeparated(
          node.properties['options'],
          'Option one,Option two',
        );
        final String requestedSelection =
            node.properties['selectedOption'] as String? ?? options.first;
        final String selectedOption =
            options.contains(requestedSelection)
                ? requestedSelection
                : options.first;
        final String key = _dartString('${_currentPageId}::${node.id}');
        final String initialSelection = _dartString(selectedOption);
        final String radioRows = options
            .map(
              (String option) =>
                  'Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Radio<String>(value: ${_dartString(option)}), Text(${_dartString(option)})])',
            )
            .join(', ');
        final String actionCall = _actionInvocation(node, indent + 4);
        return 'RadioGroup<String>(groupValue: (_widgetState.putIfAbsent($key, () => $initialSelection) as String), onChanged: (String? value) async { if (value != null) { setState(() { _widgetState[$key] = value; });$actionCall } }, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[$radioRows]))';
      case 'slider':
        final double min = _number(node.properties['min'], 0, -100000, 99999);
        final double max = _number(
          node.properties['max'],
          100,
          min + 0.0001,
          100000,
        );
        final double value = _number(node.properties['value'], 50, min, max);
        final String key = _dartString('${_currentPageId}::${node.id}');
        final String actionCall = _actionInvocation(node, indent + 4);
        return 'Slider(min: $min, max: $max, value: (_widgetState.putIfAbsent($key, () => $value) as double).clamp($min, $max).toDouble(), onChanged: (double value) async { setState(() { _widgetState[$key] = value; });$actionCall })';
      case 'timePicker':
        final String key = _dartString('${_currentPageId}::${node.id}');
        final String actionCall = _actionInvocation(node, indent + 2);
        return 'TextButton.icon(onPressed: () async { final TimeOfDay? value = await showTimePicker(context: context, initialTime: TimeOfDay.now()); if (value != null && context.mounted) { setState(() { _widgetState[$key] = value; });$actionCall } }, icon: const Icon(Icons.access_time), label: Text(_widgetState[$key] is TimeOfDay ? (_widgetState[$key] as TimeOfDay).format(context) : ${_dartString(node.properties['label'] as String? ?? 'Select time')}))';
      case 'text':
        final String text = _textPropertyExpression(
          node,
          'text',
          node.properties['text'] as String? ?? 'Text',
        );
        final double fontSize = _number(node.properties['fontSize'], 18, 8, 96);
        final String fontWeight =
            node.properties['fontWeight'] == 'bold'
                ? 'FontWeight.bold'
                : 'FontWeight.normal';
        final String color =
            node.properties['color'] is int
                ? 'const Color(${_colorLiteral(node.properties['color']! as int)})'
                : 'Theme.of(context).colorScheme.onSurface';
        return 'Text(\n'
            '$inner $text,\n'
            '$inner style: TextStyle(\n'
            '${_spaces(indent + 4)}fontSize: $fontSize,\n'
            '${_spaces(indent + 4)}fontWeight: $fontWeight,\n'
            '${_spaces(indent + 4)}color: $color,\n'
            '$inner ),\n'
            '$pad)';
      case 'button':
        final String label = _propertyExpression(
          node,
          'label',
          _dartString(node.properties['label'] as String? ?? 'Button'),
          'string',
        );
        final String style = node.properties['style'] as String? ?? 'filled';
        final String constructor = switch (style) {
          'elevated' => 'ElevatedButton',
          'outlined' => 'OutlinedButton',
          'text' => 'TextButton',
          _ => 'FilledButton',
        };
        return '$constructor(\n'
            '$inner onPressed: ${_actionHandler(node, indent + 2)},\n'
            '$inner child: Text($label),\n'
            '$pad)';
      case 'image':
        final String source =
            node.properties['source'] is String
                ? node.properties['source']! as String
                : '';
        final double width = _number(node.properties['width'], 180, 0, 1200);
        final double height = _number(node.properties['height'], 120, 0, 1200);
        if (source.isEmpty) {
          return 'SizedBox(width: $width, height: $height, child: const Icon(Icons.image_outlined))';
        }
        final String? asset =
            _imageAssets[_imageAssetKey(_currentPageId, node.id)] ??
            _imageAssets[node.id];
        if (asset != null) {
          return 'Image.asset(${_dartString(asset)}, width: $width, height: $height, fit: ${_boxFit(node.properties['fit'])}, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined))';
        }
        return 'Image.file(File(${_dartString(source)}), width: $width, height: $height, fit: ${_boxFit(node.properties['fit'])}, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined))';
      case 'icon':
        final double size = _number(node.properties['size'], 32, 8, 256);
        final int color = _integer(node.properties['color'], 0xFF6750A4);
        return 'Icon(${_iconLiteral(node.properties['iconName'])}, size: $size, color: const Color(${_colorLiteral(color)}))';
      case 'divider':
        final double dividerHeight = _number(
          node.properties['height'],
          24,
          0,
          1200,
        );
        final double thickness = _number(
          node.properties['thickness'],
          1,
          0.1,
          100,
        );
        final double indent = _number(node.properties['indent'], 0, 0, 1200);
        final double endIndent = _number(
          node.properties['endIndent'],
          0,
          0,
          1200,
        );
        final int color = _integer(node.properties['color'], 0xFFB8BEC9);
        return 'Divider(height: $dividerHeight, thickness: $thickness, indent: $indent, endIndent: $endIndent, color: const Color(${_colorLiteral(color)}))';
      case 'verticalDivider':
        final double width = _number(node.properties['width'], 24, 0, 1200);
        final double height = _number(node.properties['height'], 48, 0, 1200);
        final double thickness = _number(
          node.properties['thickness'],
          1,
          0.1,
          100,
        );
        final double indent = _number(node.properties['indent'], 0, 0, 1200);
        final double endIndent = _number(
          node.properties['endIndent'],
          0,
          0,
          1200,
        );
        final int color = _integer(node.properties['color'], 0xFFB8BEC9);
        return 'SizedBox(height: $height, child: VerticalDivider(width: $width, thickness: $thickness, indent: $indent, endIndent: $endIndent, color: const Color(${_colorLiteral(color)})))';
      case 'textField':
        final String initialValue = _textPropertyExpression(
          node,
          'initialValue',
          node.properties['initialValue'] as String? ?? '',
        );
        final String fieldLabel = _textPropertyExpression(
          node,
          'label',
          node.properties['label'] as String? ?? 'Text field',
        );
        final String hint = _textPropertyExpression(
          node,
          'hintText',
          node.properties['hintText'] as String? ?? 'Enter text',
        );
        final double width = _number(node.properties['width'], 240, 0, 1200);
        return 'SizedBox(width: $width, child: TextFormField(key: ValueKey<String>($initialValue), initialValue: $initialValue, decoration: InputDecoration(labelText: $fieldLabel, hintText: $hint, border: const OutlineInputBorder(), isDense: true)))';
      case 'checkbox':
        final String label = _propertyExpression(
          node,
          'label',
          _dartString(node.properties['label'] as String? ?? 'Checkbox'),
          'string',
        );
        final bool value = node.properties['value'] == true;
        final int color = _integer(node.properties['activeColor'], 0xFF6750A4);
        return 'Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Checkbox(value: $value, onChanged: null, activeColor: const Color(${_colorLiteral(color)})), Text($label)])';
      case 'switch':
        final String label = _propertyExpression(
          node,
          'label',
          _dartString(node.properties['label'] as String? ?? 'Switch'),
          'string',
        );
        final bool value = node.properties['value'] == true;
        final int color = _integer(node.properties['activeColor'], 0xFF6750A4);
        return 'Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Switch(value: $value, onChanged: null, activeColor: const Color(${_colorLiteral(color)})), Text($label)])';
      case 'signature':
        final double width = _number(node.properties['width'], 280, 40, 1200);
        final double height = _number(node.properties['height'], 160, 40, 1200);
        final double strokeWidth = _number(
          node.properties['strokeWidth'],
          2,
          0.5,
          20,
        );
        final int penColor = _integer(node.properties['penColor'], 0xFF20242C);
        final int backgroundColor = _integer(
          node.properties['backgroundColor'],
          0xFFFFFFFF,
        );
        return '_LocalSignaturePad(width: $width, height: $height, strokeWidth: $strokeWidth, penColor: const Color(${_colorLiteral(penColor)}), backgroundColor: const Color(${_colorLiteral(backgroundColor)}))';
      default:
        throw StateError('Unsupported widget type "${node.type}".');
    }
  }

  String _emitCollectionNode(BuilderNode node, int indent) {
    final String pad = _spaces(indent);
    final String inner = _spaces(indent + 2);
    final double width = _number(node.properties['width'], 300, 0, 1200);
    final double height = _number(node.properties['height'], 220, 0, 1200);
    final String indexedChildren = _emitIndexedChildren(
      node.children,
      indent + 8,
    );
    final String constructor;
    switch (node.type) {
      case 'listView':
        final double spacing = _number(
          node.properties['itemSpacing'],
          8,
          0,
          120,
        );
        final bool horizontal =
            node.properties['scrollDirection'] == 'horizontal';
        final String axis = horizontal ? 'horizontal' : 'vertical';
        constructor =
            'ListView.separated(scrollDirection: Axis.$axis, padding: EdgeInsets.zero, itemCount: ${node.children.length}, separatorBuilder: (BuildContext context, int index) => SizedBox(width: ${horizontal ? spacing : 0}, height: ${horizontal ? 0 : spacing}), itemBuilder: (BuildContext context, int index) {\n'
            '$indexedChildren${_spaces(indent + 4)}})';
      case 'gridView':
        final int count = _integer(
          node.properties['crossAxisCount'],
          2,
        ).clamp(1, 8);
        final double spacing = _number(
          node.properties['itemSpacing'],
          8,
          0,
          120,
        );
        constructor =
            'GridView.builder(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: $count, crossAxisSpacing: $spacing, mainAxisSpacing: $spacing), padding: EdgeInsets.zero, itemCount: ${node.children.length}, itemBuilder: (BuildContext context, int index) {\n'
            '$indexedChildren${_spaces(indent + 4)}})';
      case 'pageView' || 'swipeableStack':
        constructor =
            'PageView.builder(itemCount: ${node.children.length}, itemBuilder: (BuildContext context, int index) {\n'
            '$indexedChildren${_spaces(indent + 4)}})';
      default:
        throw StateError('Unsupported collection widget "${node.type}".');
    }
    return 'SizedBox(\n'
        '$inner width: $width,\n'
        '$inner height: $height,\n'
        '$inner child: $constructor,\n'
        '$pad)';
  }

  String _emitIndexedChildren(List<BuilderNode> children, int indent) {
    final String pad = _spaces(indent);
    final StringBuffer body = StringBuffer()..writeln('${pad}switch (index) {');
    for (int index = 0; index < children.length; index++) {
      body.writeln(
        '${pad}  case $index: return ${_emitNode(children[index], indent + 4)};',
      );
    }
    body
      ..writeln('${pad}  default: return const SizedBox.shrink();')
      ..writeln('$pad}');
    return body.toString();
  }

  String _emitSwipeableStack(BuilderNode node, int indent) {
    final double width = _number(node.properties['width'], 300, 0, 1200);
    final double height = _number(node.properties['height'], 220, 0, 1200);
    final int visibleCount = _integer(
      node.properties['visibleCount'],
      3,
    ).clamp(1, 5);
    final bool loop = node.properties['loop'] == true;
    final String children = _emitWidgetList(node.children, indent + 6);
    return 'SizedBox(\n'
        '${_spaces(indent + 2)}width: $width,\n'
        '${_spaces(indent + 2)}height: $height,\n'
        '${_spaces(indent + 2)}child: _LocalSwipeableStack(\n'
        '${_spaces(indent + 4)}visibleCount: $visibleCount,\n'
        '${_spaces(indent + 4)}loop: $loop,\n'
        '${_spaces(indent + 4)}cards: <Widget>[\n'
        '$children'
        '${_spaces(indent + 4)}],\n'
        '${_spaces(indent + 2)}),\n'
        '${_spaces(indent)})';
  }

  BuilderNode? _firstChildOfType(BuilderNode node, String type) {
    for (final BuilderNode child in node.children) {
      if (child.type == type) return child;
    }
    return null;
  }

  String _boxFit(Object? value) => switch (value) {
    'contain' => 'BoxFit.contain',
    'fill' => 'BoxFit.fill',
    'fitWidth' => 'BoxFit.fitWidth',
    'fitHeight' => 'BoxFit.fitHeight',
    'none' => 'BoxFit.none',
    'scaleDown' => 'BoxFit.scaleDown',
    _ => 'BoxFit.cover',
  };

  String _iconLiteral(Object? value) => switch (value) {
    'home' => 'Icons.home',
    'search' => 'Icons.search',
    'favorite' => 'Icons.favorite',
    'settings' => 'Icons.settings',
    'person' => 'Icons.person',
    'add' => 'Icons.add',
    'check' => 'Icons.check',
    'menu' => 'Icons.menu',
    'arrowForward' => 'Icons.arrow_forward',
    'notifications' => 'Icons.notifications_outlined',
    'calendar' => 'Icons.calendar_month',
    'clock' => 'Icons.access_time',
    _ => 'Icons.star',
  };

  List<String> _commaSeparated(Object? value, String fallback) {
    final String source =
        value is String && value.trim().isNotEmpty ? value : fallback;
    final List<String> items =
        source
            .split(',')
            .map((String item) => item.trim())
            .where((String item) => item.isNotEmpty)
            .toList();
    return items.isEmpty ? fallback.split(',') : items;
  }

  static const String _httpHelper = r'''
  Future<http.Response> _sendHttpRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    final http.Client client = http.Client();
    try {
      final http.Request request = http.Request(method, uri)
        ..headers.addAll(headers);
      if (body.isNotEmpty) request.body = body;
      final http.StreamedResponse streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }
''';

  static const String _signatureHelper = r'''
class _LocalSignaturePad extends StatefulWidget {
  const _LocalSignaturePad({required this.width, required this.height, required this.strokeWidth, required this.penColor, required this.backgroundColor});
  final double width;
  final double height;
  final double strokeWidth;
  final Color penColor;
  final Color backgroundColor;
  @override
  State<_LocalSignaturePad> createState() => _LocalSignaturePadState();
}

class _LocalSignaturePadState extends State<_LocalSignaturePad> {
  final List<List<Offset>> _strokes = <List<Offset>>[];
  @override
  Widget build(BuildContext context) => Container(
    width: widget.width,
    height: widget.height,
    decoration: BoxDecoration(color: widget.backgroundColor, border: Border.all(color: const Color(0xFFBBC2CE)), borderRadius: BorderRadius.circular(6)),
    child: Stack(children: <Widget>[
      Positioned.fill(child: GestureDetector(
        onPanStart: (details) => setState(() => _strokes.add(<Offset>[details.localPosition])),
        onPanUpdate: (details) => setState(() { if (_strokes.isNotEmpty) _strokes.last.add(details.localPosition); }),
        child: CustomPaint(painter: _LocalSignaturePainter(_strokes, widget.penColor, widget.strokeWidth), child: const SizedBox.expand()),
      )),
      Positioned(top: 0, right: 0, child: IconButton(tooltip: 'Clear signature', visualDensity: VisualDensity.compact, onPressed: () => setState(_strokes.clear), icon: const Icon(Icons.refresh, size: 16))),
    ]),
  );
}

class _LocalSignaturePainter extends CustomPainter {
  const _LocalSignaturePainter(this.strokes, this.color, this.width);
  final List<List<Offset>> strokes;
  final Color color;
  final double width;
  @override
  void paint(Canvas canvas, Size size) {
    final Paint pen = Paint()..color = color..strokeWidth = width..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke;
    for (final List<Offset> stroke in strokes) {
      if (stroke.isEmpty) continue;
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final Offset point in stroke.skip(1)) { path.lineTo(point.dx, point.dy); }
      canvas.drawPath(path, pen);
    }
  }
  @override
  bool shouldRepaint(covariant _LocalSignaturePainter oldDelegate) => true;
}
''';

  static const String _swipeableStackHelper = r'''
class _LocalSwipeableStack extends StatefulWidget {
  const _LocalSwipeableStack({required this.cards, required this.visibleCount, required this.loop});
  final List<Widget> cards;
  final int visibleCount;
  final bool loop;
  @override
  State<_LocalSwipeableStack> createState() => _LocalSwipeableStackState();
}

class _LocalSwipeableStackState extends State<_LocalSwipeableStack> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const Center(child: Text('Add cards to swipe'));
    final int active = _index % widget.cards.length;
    return Stack(alignment: Alignment.center, children: <Widget>[
      for (int depth = widget.visibleCount - 1; depth > 0; depth--)
        if (widget.cards.length > depth)
          Positioned.fill(top: depth * 9, bottom: 0, left: depth * 7, right: depth * 7,
            child: IgnorePointer(child: Card(color: const Color(0xFFE7EAF0), child: const SizedBox.expand()))),
      Positioned.fill(child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0).abs() < 80) return;
          if (_index + 1 < widget.cards.length || widget.loop) setState(() => _index++);
        },
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 180),
          child: Card(key: ValueKey<int>(active), clipBehavior: Clip.antiAlias,
            child: SizedBox.expand(child: widget.cards[active]))),
      )),
    ]);
  }
}
''';

  String _emitChildren(List<BuilderNode> children, int indent) {
    if (children.isEmpty) return 'const SizedBox.shrink()';
    if (children.length == 1) return _emitNode(children.first, indent);
    final String inner = _spaces(indent + 2);
    final String nodes = _emitWidgetList(children, indent + 4);
    return 'Column(\n'
        '$inner children: <Widget>[\n'
        '$nodes'
        '$inner ],\n'
        '${_spaces(indent)})';
  }

  String _wrapWidget(
    String constructor,
    String properties,
    String child,
    int indent,
  ) {
    final String inner = _spaces(indent + 2);
    return '$constructor(\n'
        '$properties'
        '$inner child: $child,\n'
        '${_spaces(indent)})';
  }

  String _edgeInsetsLiteral(
    BuilderNode node,
    String prefix, {
    double fallback = 0,
  }) {
    final double legacy = _number(node.properties[prefix], fallback, 0, 1200);
    double side(String name) => _number(
      node.properties['$prefix${_capitalized(name)}'],
      legacy,
      0,
      1200,
    );
    return 'EdgeInsets.fromLTRB(${side('left')}, ${side('top')}, ${side('right')}, ${side('bottom')})';
  }

  bool _hasInsets(BuilderNode node, String prefix) {
    final double legacy = _number(node.properties[prefix], 0, 0, 1200);
    for (final String side in <String>['Top', 'Right', 'Bottom', 'Left']) {
      if (_number(node.properties['$prefix$side'], legacy, 0, 1200) != 0) {
        return true;
      }
    }
    return false;
  }

  String _capitalized(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';

  String _alignmentLiteral(Object? value) => switch (value) {
    'topLeft' => 'Alignment.topLeft',
    'topCenter' => 'Alignment.topCenter',
    'topRight' => 'Alignment.topRight',
    'centerLeft' => 'Alignment.centerLeft',
    'center' => 'Alignment.center',
    'centerRight' => 'Alignment.centerRight',
    'bottomLeft' => 'Alignment.bottomLeft',
    'bottomCenter' => 'Alignment.bottomCenter',
    'bottomRight' => 'Alignment.bottomRight',
    _ => 'Alignment.topLeft',
  };

  String _propertyExpression(
    BuilderNode node,
    String property,
    String fallback,
    String type,
  ) {
    String expression = fallback;
    final Object? rawBindings = node.properties['bindings'];
    Object? variableId;
    if (rawBindings is Map) variableId = rawBindings[property];
    final BuilderVariable? variable =
        variableId is String ? _variablesById[variableId] : null;
    if (variable != null &&
        (variable.type == type ||
            type == 'string' ||
            (type == 'number' && _isNumericType(variable.type)))) {
      final String state = "_appState[${_dartString(variable.id)}]";
      expression = switch (type) {
        'boolean' => '(($state as bool?) ?? $fallback)',
        'number' => '(($state as num?)?.toDouble() ?? $fallback)',
        _ => '($state?.toString() ?? $fallback)',
      };
    }
    if (_hasWidgetAction(node, property)) {
      final String key = _dartString(
        '${_runtimeWidgetKey(_currentPageId, node.id)}.$property',
      );
      final String cast = switch (type) {
        'boolean' => 'bool?',
        'number' => 'num?',
        _ => 'String?',
      };
      final String stateValue = switch (type) {
        'number' => "(_widgetState[$key] as $cast)?.toDouble()",
        _ => '_widgetState[$key] as $cast',
      };
      expression = '($stateValue ?? $expression)';
    }
    return expression;
  }

  String _textPropertyExpression(
    BuilderNode node,
    String property,
    String fallback,
  ) {
    String expression = _templateExpression(fallback);
    final Object? rawBindings = node.properties['bindings'];
    final Object? variableId =
        rawBindings is Map ? rawBindings[property] : null;
    final BuilderVariable? variable =
        variableId is String ? _variablesById[variableId] : null;
    if (variable != null) {
      final String state = "_appState[${_dartString(variable.id)}]";
      expression = '($state?.toString() ?? $expression)';
    }
    if (_hasWidgetAction(node, property)) {
      final String key = _dartString(
        '${_runtimeWidgetKey(_currentPageId, node.id)}.$property',
      );
      expression = '((_widgetState[$key] as String?) ?? $expression)';
    }
    return expression;
  }

  String _templateExpression(String template) {
    final RegExp token = RegExp(r'\$\{([^}]+)\}|\$([A-Za-z_][A-Za-z0-9_]*)');
    final List<String> pieces = <String>[];
    int previousEnd = 0;
    for (final Match match in token.allMatches(template)) {
      final String key = (match[1] ?? match[2] ?? '').trim();
      BuilderVariable? variable;
      for (final BuilderVariable candidate in _variablesById.values) {
        if (candidate.id == key || candidate.name == key) {
          variable = candidate;
          break;
        }
      }
      if (variable == null) continue;
      if (match.start > previousEnd) {
        pieces.add(_dartString(template.substring(previousEnd, match.start)));
      }
      pieces.add('(_appState[${_dartString(variable.id)}]?.toString() ?? "")');
      previousEnd = match.end;
    }
    if (pieces.isEmpty) return _dartString(template);
    if (previousEnd < template.length) {
      pieces.add(_dartString(template.substring(previousEnd)));
    }
    return pieces.join(' + ');
  }

  bool _isNumericType(String type) =>
      <String>{'number', 'integer', 'double'}.contains(type);

  bool _hasDynamicProperty(BuilderNode node, String property) {
    final Object? rawBindings = node.properties['bindings'];
    if (rawBindings is Map) {
      final Object? variableId = rawBindings[property];
      if (variableId is String && _variablesById.containsKey(variableId)) {
        return true;
      }
    }
    return _hasWidgetAction(node, property);
  }

  bool _hasWidgetAction(BuilderNode node, String property) =>
      _widgetActionTargets[_runtimeWidgetKey(_currentPageId, node.id)]
          ?.contains(property) ??
      false;

  String _runtimeWidgetKey(String pageId, String nodeId) => '$pageId::$nodeId';

  Object _coerceActionValue(BuilderVariable variable, Object? value) {
    Object? normalized = value;
    if ((variable.type == 'json' || variable.type == 'stringList') &&
        value is String) {
      try {
        normalized = jsonDecode(value);
      } on FormatException {
        normalized = null;
      }
    }
    return switch (variable.type) {
      'number' || 'double' =>
        normalized is num
            ? normalized.toDouble()
            : double.tryParse(normalized?.toString() ?? '') ??
                variable.initialValue,
      'integer' =>
        normalized is num
            ? normalized.round()
            : int.tryParse(normalized?.toString() ?? '') ??
                double.tryParse(normalized?.toString() ?? '')?.round() ??
                variable.initialValue,
      'boolean' => normalized == true,
      'stringList' =>
        normalized is List
            ? normalized.map((Object? item) => item.toString()).toList()
            : variable.initialValue,
      'json' =>
        normalized is List ||
                normalized is Map ||
                normalized is num ||
                normalized is bool ||
                normalized is String
            ? normalized!
            : variable.initialValue,
      _ => normalized?.toString() ?? '',
    };
  }

  Object _coerceWidgetActionValue(String property, Object? value) =>
      switch (property) {
        'visible' => value == true,
        'opacity' => _number(value, 1, 0, 1),
        _ => value?.toString() ?? '',
      };

  String _dartValue(Object? value) => switch (value) {
    null => 'null',
    bool() => value ? 'true' : 'false',
    num() => value.toString(),
    List() => '<Object?>[${value.map(_dartValue).join(', ')}]',
    Map() =>
      '<String, Object?>{${value.entries.map((MapEntry<Object?, Object?> entry) => '${_dartString(entry.key.toString())}: ${_dartValue(entry.value)}').join(', ')}}',
    _ => _dartString(value.toString()),
  };

  String _emitWidgetList(List<BuilderNode> nodes, int indent) =>
      nodes
          .map(
            (BuilderNode child) =>
                '${_spaces(indent)}${_emitNode(child, indent)},\n',
          )
          .join();

  String _mainAxis(Object? value) => switch (value) {
    'center' => 'MainAxisAlignment.center',
    'end' => 'MainAxisAlignment.end',
    'spaceBetween' => 'MainAxisAlignment.spaceBetween',
    _ => 'MainAxisAlignment.start',
  };

  String _crossAxis(Object? value) => switch (value) {
    'center' => 'CrossAxisAlignment.center',
    'end' => 'CrossAxisAlignment.end',
    _ => 'CrossAxisAlignment.start',
  };

  double _number(Object? value, double fallback, double min, double max) {
    if (value is num && value.isFinite) {
      return value.toDouble().clamp(min, max).toDouble();
    }
    return fallback;
  }

  int _integer(Object? value, int fallback) =>
      value is num && value.isFinite ? value.round() : fallback;

  String _colorLiteral(int value) =>
      '0x${value.toUnsigned(32).toRadixString(16).padLeft(8, '0')}';

  String _dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');

  String _spaces(int count) => List<String>.filled(count, ' ').join();
}
