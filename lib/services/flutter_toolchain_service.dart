import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

class FlutterDevice {
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.isEmulator,
  });

  final String id;
  final String name;
  final String targetPlatform;
  final bool isEmulator;

  factory FlutterDevice.fromJson(Map<String, Object?> json) => FlutterDevice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Unnamed device',
    targetPlatform: json['targetPlatform'] as String? ?? '',
    isEmulator: json['emulator'] == true,
  );
}

class FlutterCommandResult {
  const FlutterCommandResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;

  bool get succeeded => exitCode == 0;
}

class FlutterToolchainService {
  Process? _activeProcess;

  static String findFlutterExecutable() {
    final Map<String, String> environment = Platform.environment;
    final String? flutterRoot = _environmentValue(environment, 'FLUTTER_ROOT');
    final String? userProfile = _environmentValue(environment, 'USERPROFILE');
    final String pathValue = _environmentValue(environment, 'PATH') ?? '';
    final List<String> searchDirectories = <String>[
      if (flutterRoot != null && flutterRoot.isNotEmpty)
        '${flutterRoot}${Platform.pathSeparator}bin',
      if (Platform.isWindows && userProfile != null && userProfile.isNotEmpty)
        '$userProfile${Platform.pathSeparator}flutter${Platform.pathSeparator}bin',
      ...pathValue.split(Platform.isWindows ? ';' : ':'),
    ];
    final String executableName =
        Platform.isWindows ? 'flutter.bat' : 'flutter';
    for (final String directory in searchDirectories) {
      final String candidate =
          '${directory.replaceAll('"', '')}${Platform.pathSeparator}$executableName';
      if (File(candidate).existsSync()) return candidate;
    }
    throw StateError(
      'Flutter was not found on PATH. Add Flutter’s bin folder to PATH '
      'and restart Local Flutter Builder.',
    );
  }

  static String? _environmentValue(Map<String, String> values, String key) {
    for (final MapEntry<String, String> entry in values.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) return entry.value;
    }
    return null;
  }

  Future<List<FlutterDevice>> devices({
    void Function(String line)? onOutput,
  }) async {
    final FlutterCommandResult result = await run(
      Directory.current.path,
      const <String>['devices', '--machine'],
      onOutput: onOutput,
    );
    if (!result.succeeded) {
      throw StateError('Flutter could not list devices.\n${result.output}');
    }
    final String output = result.output.trim();
    final int jsonStart = output.indexOf('[');
    final int jsonEnd = output.lastIndexOf(']');
    if (jsonStart < 0 || jsonEnd < jsonStart) return const <FlutterDevice>[];
    final Object? decoded = jsonDecode(
      output.substring(jsonStart, jsonEnd + 1),
    );
    if (decoded is! List) return const <FlutterDevice>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> item) =>
              FlutterDevice.fromJson(<String, Object?>{
                for (final MapEntry<Object?, Object?> entry in item.entries)
                  entry.key.toString(): entry.value,
              }),
        )
        .where((FlutterDevice device) => device.id.isNotEmpty)
        .toList();
  }

  Future<FlutterCommandResult> resolvePackages(
    String projectPath, {
    required bool offline,
    void Function(String line)? onOutput,
  }) => run(projectPath, <String>[
    'pub',
    'get',
    if (offline) '--offline',
  ], onOutput: onOutput);

  Future<FlutterCommandResult> run(
    String projectPath,
    List<String> arguments, {
    void Function(String line)? onOutput,
  }) async {
    if (_activeProcess != null) {
      throw StateError('A Flutter command is already running.');
    }
    final String executable = findFlutterExecutable();
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: Directory(projectPath).absolute.path,
      runInShell: Platform.isWindows,
    );
    _activeProcess = process;
    final Queue<String> output = Queue<String>();
    void captureLine(String line) {
      final String cleanLine = line.trimRight();
      if (cleanLine.isEmpty) return;
      if (output.length >= 1000) output.removeFirst();
      output.addLast(cleanLine);
      onOutput?.call(cleanLine);
    }

    final Future<void> stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(captureLine);
    final Future<void> stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(captureLine);
    try {
      final int exitCode = await process.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      return FlutterCommandResult(
        exitCode: exitCode,
        output: output.join('\n'),
      );
    } finally {
      if (identical(_activeProcess, process)) _activeProcess = null;
    }
  }

  void cancel() {
    final Process? process = _activeProcess;
    if (process == null) return;
    if (!Platform.isWindows) {
      process.kill();
      return;
    }
    // Flutter runs through a batch file on Windows. Stop its child process
    // as well so a temporary preview can be removed after the command exits.
    unawaited(
      Process.run('taskkill', <String>[
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ]).then<void>(
        (ProcessResult result) {
          if (result.exitCode != 0) process.kill();
        },
        onError: (Object _, StackTrace __) {
          process.kill();
        },
      ),
    );
  }
}
