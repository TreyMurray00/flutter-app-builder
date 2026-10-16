import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/flutter_toolchain_service.dart';

class FlutterToolchainDialog extends StatefulWidget {
  const FlutterToolchainDialog({
    required this.projectPath,
    required this.service,
    this.previewMode = false,
    super.key,
  });

  final String projectPath;
  final FlutterToolchainService service;
  final bool previewMode;

  @override
  State<FlutterToolchainDialog> createState() => _FlutterToolchainDialogState();
}

class _FlutterToolchainDialogState extends State<FlutterToolchainDialog> {
  static const Map<String, String> _buildTargets = <String, String>{
    'web': 'Web',
    'apk': 'Android APK',
    'windows': 'Windows desktop',
    'macos': 'macOS desktop',
    'linux': 'Linux desktop',
    'ios': 'iOS device',
  };

  Iterable<MapEntry<String, String>> get _supportedBuildTargets =>
      _buildTargets.entries.where((MapEntry<String, String> target) {
        return switch (target.key) {
          'windows' => Platform.isWindows,
          'macos' || 'ios' => Platform.isMacOS,
          'linux' => Platform.isLinux,
          _ => true,
        };
      });

  final ScrollController _logScrollController = ScrollController();
  final List<String> _outputLines = <String>[];
  List<FlutterDevice> _devices = const <FlutterDevice>[];
  String? _selectedDeviceId;
  String _buildTarget = 'web';
  String? _error;
  int? _exitCode;
  bool _loadingDevices = true;
  bool _working = false;
  bool _offline = true;
  bool _autoRunAttempted = false;

  @override
  void initState() {
    super.initState();
    if (widget.previewMode) _offline = false;
    unawaited(_refreshDevices());
  }

  @override
  void dispose() {
    if (_working) widget.service.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshDevices() async {
    setState(() {
      _loadingDevices = true;
      _error = null;
    });
    try {
      final List<FlutterDevice> devices = await widget.service.devices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _selectedDeviceId =
            devices.any((FlutterDevice item) => item.id == _selectedDeviceId)
                ? _selectedDeviceId
                : devices.isEmpty
                ? null
                : devices
                        .where((FlutterDevice item) => item.id == _hostDeviceId)
                        .firstOrNull
                        ?.id ??
                    devices.first.id;
      });
      if (widget.previewMode &&
          !_autoRunAttempted &&
          _selectedDeviceId != null) {
        _autoRunAttempted = true;
        unawaited(
          _execute(<String>['run', '-d', _selectedDeviceId!, '--no-pub']),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  String get _hostDeviceId =>
      Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
          ? 'macos'
          : 'linux';

  void _appendOutput(String line) {
    if (!mounted) return;
    setState(() {
      _outputLines.add(line);
      if (_outputLines.length > 1000) _outputLines.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  Future<void> _execute(List<String> command) async {
    if (_working) return;
    setState(() {
      _working = true;
      _exitCode = null;
      _error = null;
      _outputLines.clear();
    });
    try {
      _appendOutput('Resolving project packages${_offline ? ' offline' : ''}…');
      final FlutterCommandResult packages = await widget.service
          .resolvePackages(
            widget.projectPath,
            offline: _offline,
            onOutput: _appendOutput,
          );
      if (!packages.succeeded) {
        if (mounted) setState(() => _exitCode = packages.exitCode);
        return;
      }
      _appendOutput('Running: flutter ${command.join(' ')}');
      final FlutterCommandResult result = await widget.service.run(
        widget.projectPath,
        command,
        onOutput: _appendOutput,
      );
      if (mounted) setState(() => _exitCode = result.exitCode);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.previewMode || !_working,
    child: AlertDialog(
      title: Text(
        widget.previewMode
            ? 'Flutter runtime preview'
            : 'Run and build exported app',
      ),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedDeviceId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Run on device',
                      isDense: true,
                    ),
                    hint: Text(
                      _loadingDevices ? 'Finding devices…' : 'No device',
                    ),
                    items:
                        _devices
                            .map(
                              (
                                FlutterDevice device,
                              ) => DropdownMenuItem<String>(
                                value: device.id,
                                child: Text(
                                  '${device.name} · ${device.targetPlatform}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    onChanged:
                        _working
                            ? null
                            : (String? value) =>
                                setState(() => _selectedDeviceId = value),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh connected devices',
                  onPressed:
                      _working || _loadingDevices ? null : _refreshDevices,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: <Widget>[
                if (!widget.previewMode)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _buildTarget,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Build target',
                        isDense: true,
                      ),
                      items:
                          _supportedBuildTargets
                              .map(
                                (MapEntry<String, String> target) =>
                                    DropdownMenuItem<String>(
                                      value: target.key,
                                      child: Text(target.value),
                                    ),
                              )
                              .toList(),
                      onChanged:
                          _working
                              ? null
                              : (String? value) =>
                                  setState(() => _buildTarget = value ?? 'web'),
                    ),
                  ),
                if (!widget.previewMode) const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile.adaptive(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Resolve packages offline'),
                    subtitle: const Text('Turn off to allow pub.dev access'),
                    value: _offline,
                    onChanged:
                        _working
                            ? null
                            : (bool value) => setState(() => _offline = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                      _working || _selectedDeviceId == null
                          ? null
                          : () => _execute(<String>[
                            'run',
                            '-d',
                            _selectedDeviceId!,
                            '--no-pub',
                          ]),
                  icon: const Icon(Icons.play_arrow, size: 17),
                  label: const Text('Run'),
                ),
                if (!widget.previewMode)
                  OutlinedButton.icon(
                    onPressed:
                        _working
                            ? null
                            : () =>
                                _execute(const <String>['analyze', '--no-pub']),
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: const Text('Analyze'),
                  ),
                if (!widget.previewMode)
                  OutlinedButton.icon(
                    onPressed:
                        _working
                            ? null
                            : () => _execute(<String>[
                              'build',
                              _buildTarget,
                              '--no-pub',
                              if (_buildTarget == 'ios') '--no-codesign',
                            ]),
                    icon: const Icon(Icons.build_outlined, size: 16),
                    label: const Text('Build'),
                  ),
                if (_working)
                  TextButton.icon(
                    onPressed: widget.service.cancel,
                    icon: const Icon(Icons.stop_circle_outlined, size: 16),
                    label: const Text('Stop'),
                  ),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFB3261E), fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  controller: _logScrollController,
                  child: ListView(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(10),
                    children: <Widget>[
                      if (_outputLines.isEmpty)
                        const Text(
                          'Flutter command output will appear here.',
                          style: TextStyle(fontSize: 11),
                        )
                      else
                        SelectableText(
                          _outputLines.join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_exitCode != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _exitCode == 0
                    ? 'Command completed successfully.'
                    : 'Command exited with code $_exitCode.',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      _exitCode == 0
                          ? const Color(0xFF217346)
                          : const Color(0xFFB3261E),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed:
              _working && widget.previewMode
                  ? null
                  : () {
                    if (_working) widget.service.cancel();
                    Navigator.pop(context);
                  },
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
