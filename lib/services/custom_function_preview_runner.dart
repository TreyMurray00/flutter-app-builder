import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dart_eval/dart_eval.dart';
import 'package:flutter/foundation.dart';

import '../models/builder_document.dart';
import 'custom_function_source.dart';

class CustomFunctionPreviewResult {
  const CustomFunctionPreviewResult({
    required this.appState,
    required this.effects,
  });

  final Map<String, Object?> appState;
  final List<Map<String, Object?>> effects;
}

class CustomFunctionPreviewRunner {
  const CustomFunctionPreviewRunner._();

  static const Duration _executionLimit = Duration(seconds: 10);

  static Future<CustomFunctionPreviewResult> run({
    required String body,
    required List<BuilderVariable> variables,
    required Map<String, Object?> appState,
    List<BuilderCustomDataStructure> dataStructures =
        const <BuilderCustomDataStructure>[],
  }) async {
    final Map<String, String> variableIds = <String, String>{
      for (final BuilderVariable variable in variables) ...<String, String>{
        variable.id: variable.id,
        variable.name: variable.id,
      },
    };
    final String inputJson = jsonEncode(<String, Object?>{
      'appState': appState,
      'variableIds': variableIds,
    });
    final String inputLiteral = jsonEncode(inputJson).replaceAll(r'$', r'\$');
    final String source = _buildSource(body, inputLiteral, dataStructures);
    final String resultJson;

    if (kIsWeb) {
      resultJson = await _evaluate(source);
    } else {
      final ReceivePort receivePort = ReceivePort();
      final Isolate isolate = await Isolate.spawn<List<Object?>>(
        _runInIsolate,
        <Object?>[receivePort.sendPort, source],
        onError: receivePort.sendPort,
        errorsAreFatal: false,
      );
      try {
        final Object? message = await receivePort.first.timeout(
          _executionLimit,
          onTimeout:
              () =>
                  throw TimeoutException(
                    'Custom function preview exceeded ${_executionLimit.inSeconds} seconds.',
                  ),
        );
        if (message is Map<Object?, Object?> && message['ok'] == true) {
          resultJson = message['result']! as String;
        } else if (message is Map<Object?, Object?>) {
          throw FormatException(
            message['error']?.toString() ?? 'Dart evaluation failed.',
          );
        } else if (message is List<Object?> && message.length >= 2) {
          throw FormatException(message.first.toString());
        } else {
          throw const FormatException(
            'Dart evaluation returned an invalid result.',
          );
        }
      } finally {
        isolate.kill(priority: Isolate.immediate);
        receivePort.close();
      }
    }

    final Object? decoded = jsonDecode(resultJson);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException(
        'Dart evaluation returned an invalid result.',
      );
    }
    final Object? rawAppState = decoded['appState'];
    final Object? rawEffects = decoded['effects'];
    if (rawAppState is! Map<Object?, Object?> || rawEffects is! List) {
      throw const FormatException(
        'Dart evaluation returned invalid app state.',
      );
    }
    return CustomFunctionPreviewResult(
      appState: <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in rawAppState.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      },
      effects: <Map<String, Object?>>[
        for (final Object? effect in rawEffects)
          if (effect is Map<Object?, Object?>)
            <String, Object?>{
              for (final MapEntry<Object?, Object?> entry in effect.entries)
                if (entry.key is String) entry.key! as String: entry.value,
            },
      ],
    );
  }

  static String _buildSource(
    String body,
    String inputLiteral,
    List<BuilderCustomDataStructure> dataStructures,
  ) {
    final StringBuffer source =
        StringBuffer()
          ..writeln("import 'dart:convert';")
          ..writeln("import 'dart:math' as math;")
          ..writeln();
    for (final BuilderCustomDataStructure structure in dataStructures) {
      source
        ..writeln(structure.body)
        ..writeln();
    }
    source
      ..writeln('Future<String> main() async {')
      ..writeln(
        '  final Map<String, Object?> _input = Map<String, Object?>.from('
        'jsonDecode($inputLiteral) as Map);',
      )
      ..writeln(
        "  final Map<String, Object?> _appState = Map<String, Object?>.from(_input['appState'] as Map);",
      )
      ..writeln(
        "  final Map<String, String> _variableIds = Map<String, String>.from(_input['variableIds'] as Map);",
      )
      ..writeln(
        '  final List<Map<String, Object?>> _effects = <Map<String, Object?>>[];',
      )
      ..writeln()
      ..writeln('  Object? getVariable(String nameOrId) {')
      ..writeln('    final String? id = _variableIds[nameOrId];')
      ..writeln('    return _appState[id ?? nameOrId];')
      ..writeln('  }')
      ..writeln()
      ..writeln('  void setVariable(String nameOrId, Object? value) {')
      ..writeln('    final String? id = _variableIds[nameOrId];')
      ..writeln('    if (id != null) _appState[id] = value;')
      ..writeln('  }')
      ..writeln()
      ..writeln('  void setState(Function update) {')
      ..writeln('    update();')
      ..writeln('  }')
      ..writeln()
      ..writeln('  void showMessage(String message) {')
      ..writeln(
        "    _effects.add(<String, Object?>{'type': 'message', 'value': message});",
      )
      ..writeln('  }')
      ..writeln()
      ..writeln('  void navigateTo(String route) {')
      ..writeln(
        "    _effects.add(<String, Object?>{'type': 'navigate', 'value': route});",
      )
      ..writeln('  }')
      ..writeln()
      ..writeln('  void back() {')
      ..writeln("    _effects.add(<String, Object?>{'type': 'back'});")
      ..writeln('  }')
      ..writeln()
      ..writeln('  void print(Object? value) {')
      ..writeln(
        "    _effects.add(<String, Object?>{'type': 'log', 'value': value?.toString() ?? 'null'});",
      )
      ..writeln('  }')
      ..writeln()
      ..writeln('  Future<void> _runCustomFunctionBody() async {');
    source
      ..write(_indentBody(CustomFunctionSource.parse(body).body))
      ..writeln('  }')
      ..writeln()
      ..writeln('  await _runCustomFunctionBody();')
      ..writeln(
        "  return jsonEncode(<String, Object?>{'appState': _appState, 'effects': _effects});",
      )
      ..writeln('}');
    return source.toString();
  }

  static String _indentBody(String body) {
    final List<String> lines = body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines.map((String line) => '    $line\n').join();
  }

  static void _runInIsolate(List<Object?> message) {
    final SendPort reply = message[0]! as SendPort;
    final String source = message[1]! as String;
    _evaluateAndReply(source, reply);
  }

  static Future<void> _evaluateAndReply(String source, SendPort reply) async {
    try {
      reply.send(<String, Object?>{
        'ok': true,
        'result': await _evaluate(source),
      });
    } catch (error) {
      reply.send(<String, Object?>{'ok': false, 'error': error.toString()});
    }
  }

  static Future<String> _evaluate(String source) async {
    Object? result = eval(source, function: 'main');
    if (result is Future<Object?>) result = await result;
    if (result is! String) {
      throw FormatException(
        'Dart evaluation returned ${result.runtimeType} instead of text.',
      );
    }
    return result;
  }
}
