import 'package:flutter/material.dart';

enum ColorInputFormat { hex, rgb, hsl }

String formatColorInput(Color color, ColorInputFormat format) {
  final int argb = color.toARGB32();
  final int alpha = (argb >> 24) & 0xFF;
  final int red = (argb >> 16) & 0xFF;
  final int green = (argb >> 8) & 0xFF;
  final int blue = argb & 0xFF;
  return switch (format) {
    ColorInputFormat.hex =>
      '#${alpha == 0xFF ? '' : _twoDigits(alpha)}${_twoDigits(red)}${_twoDigits(green)}${_twoDigits(blue)}',
    ColorInputFormat.rgb => '$red, $green, $blue',
    ColorInputFormat.hsl => _formatHsl(color),
  };
}

Color? parseColorInput(String value, ColorInputFormat format) {
  final String input = value.trim();
  if (input.isEmpty) return null;
  return switch (format) {
    ColorInputFormat.hex => _parseHex(input),
    ColorInputFormat.rgb => _parseRgb(input),
    ColorInputFormat.hsl => _parseHsl(input),
  };
}

class ColorPickerField extends StatelessWidget {
  const ColorPickerField({
    required this.color,
    required this.onChanged,
    super.key,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: () async {
          final Color? result = await showLocalColorPicker(context, color);
          if (result != null) onChanged(result);
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD3D6DF)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                formatColorInput(color, ColorInputFormat.hex),
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const Icon(Icons.colorize, size: 16),
          ],
        ),
      ),
    );
  }
}

Future<Color?> showLocalColorPicker(BuildContext context, Color initialColor) {
  return showDialog<Color>(
    context: context,
    builder:
        (BuildContext context) =>
            _LocalColorPickerDialog(initialColor: initialColor),
  );
}

class _LocalColorPickerDialog extends StatefulWidget {
  const _LocalColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_LocalColorPickerDialog> createState() =>
      _LocalColorPickerDialogState();
}

class _LocalColorPickerDialogState extends State<_LocalColorPickerDialog> {
  late Color _color;
  late HSVColor _hsv;
  late TextEditingController _inputController;
  ColorInputFormat _inputFormat = ColorInputFormat.hex;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
    _hsv = HSVColor.fromColor(_color);
    _inputController = TextEditingController(
      text: formatColorInput(_color, _inputFormat),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose color'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SaturationValuePicker(
                hsv: _hsv,
                onChanged: (HSVColor value) => _setColor(value.toColor()),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 55,
                    child: Text('Hue', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: _HueSlider(
                      value: _hsv.hue,
                      onChanged:
                          (double hue) =>
                              _setColor(_hsv.withHue(hue).toColor()),
                    ),
                  ),
                  SizedBox(
                    width: 39,
                    child: Text(
                      '${_hsv.hue.round()}°',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 55,
                    child: Text('Opacity', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: Slider(
                      value: _hsv.alpha.clamp(0, 1).toDouble(),
                      onChanged:
                          (double alpha) =>
                              _setColor(_hsv.withAlpha(alpha).toColor()),
                    ),
                  ),
                  SizedBox(
                    width: 39,
                    child: Text(
                      '${(_hsv.alpha * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              SegmentedButton<ColorInputFormat>(
                segments: const <ButtonSegment<ColorInputFormat>>[
                  ButtonSegment<ColorInputFormat>(
                    value: ColorInputFormat.hex,
                    label: Text('HEX'),
                  ),
                  ButtonSegment<ColorInputFormat>(
                    value: ColorInputFormat.rgb,
                    label: Text('RGB'),
                  ),
                  ButtonSegment<ColorInputFormat>(
                    value: ColorInputFormat.hsl,
                    label: Text('HSL'),
                  ),
                ],
                selected: <ColorInputFormat>{_inputFormat},
                onSelectionChanged: (Set<ColorInputFormat> selected) {
                  _setInputFormat(selected.first);
                },
              ),
              const SizedBox(height: 11),
              TextField(
                key: const ValueKey<String>('color-picker-input'),
                controller: _inputController,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _parseCurrentInput,
                onSubmitted: _parseCurrentInput,
                decoration: InputDecoration(
                  labelText: switch (_inputFormat) {
                    ColorInputFormat.hex => 'Hex color',
                    ColorInputFormat.rgb => 'RGB channels',
                    ColorInputFormat.hsl => 'HSL channels',
                  },
                  hintText: switch (_inputFormat) {
                    ColorInputFormat.hex => '#RRGGBB or #AARRGGBB',
                    ColorInputFormat.rgb => '255, 99, 71 or rgb(255, 99, 71)',
                    ColorInputFormat.hsl =>
                      '210, 50%, 40% or hsl(210, 50%, 40%)',
                  },
                  errorText: _inputError,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text('Preview', style: TextStyle(fontSize: 12)),
                  const Spacer(),
                  Container(
                    width: 34,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _color,
                      border: Border.all(color: const Color(0xFFD3D6DF)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    formatColorInput(_color, ColorInputFormat.hex),
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('Use color'),
        ),
      ],
    );
  }

  void _setColor(Color color, {bool updateInput = true}) {
    setState(() {
      _color = color;
      _hsv = HSVColor.fromColor(color);
      _inputError = null;
      if (updateInput) _replaceInput(formatColorInput(color, _inputFormat));
    });
  }

  void _setInputFormat(ColorInputFormat format) {
    setState(() {
      _inputFormat = format;
      _inputError = null;
      _replaceInput(formatColorInput(_color, format));
    });
  }

  void _replaceInput(String value) {
    if (_inputController.text == value) return;
    _inputController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _parseCurrentInput(String value) {
    final Color? parsed = parseColorInput(value, _inputFormat);
    if (parsed == null) {
      setState(() => _inputError = _inputErrorFor(_inputFormat));
      return;
    }
    _setColor(parsed, updateInput: false);
  }

  String _inputErrorFor(ColorInputFormat format) => switch (format) {
    ColorInputFormat.hex => 'Enter 6 or 8 hexadecimal digits.',
    ColorInputFormat.rgb => 'Enter three channels from 0 to 255.',
    ColorInputFormat.hsl => 'Enter hue 0–360 and saturation/lightness 0–100%.',
  };
}

class _SaturationValuePicker extends StatelessWidget {
  const _SaturationValuePicker({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, 180);
        void update(Offset position) {
          final double saturation = (position.dx / size.width).clamp(0, 1);
          final double value = 1 - (position.dy / size.height).clamp(0, 1);
          onChanged(hsv.withSaturation(saturation).withValue(value));
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown:
                (TapDownDetails details) => update(details.localPosition),
            onPanStart:
                (DragStartDetails details) => update(details.localPosition),
            onPanUpdate:
                (DragUpdateDetails details) => update(details.localPosition),
            child: CustomPaint(
              size: size,
              painter: _SaturationValuePainter(hsv: hsv),
            ),
          ),
        );
      },
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final Color hueColor = hsv.withSaturation(1).withValue(1).toColor();
    canvas.drawRect(bounds, Paint()..color = hueColor);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Colors.white, Color(0x00FFFFFF)],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x00000000), Colors.black],
        ).createShader(bounds),
    );

    final Offset handle = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      handle,
      8,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      handle,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          void update(Offset position) {
            onChanged((position.dx / constraints.maxWidth).clamp(0, 1) * 360);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown:
                (TapDownDetails details) => update(details.localPosition),
            onPanStart:
                (DragStartDetails details) => update(details.localPosition),
            onPanUpdate:
                (DragUpdateDetails details) => update(details.localPosition),
            child: CustomPaint(
              size: Size(constraints.maxWidth, 28),
              painter: _HueSliderPainter(value: value),
            ),
          );
        },
      ),
    );
  }
}

class _HueSliderPainter extends CustomPainter {
  const _HueSliderPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect track = Rect.fromLTWH(0, 9, size.width, 10);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(5)),
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[
            Colors.red,
            Colors.yellow,
            Colors.lime,
            Colors.cyan,
            Colors.blue,
            Color(0xFFFF00FF),
            Colors.red,
          ],
        ).createShader(track),
    );
    final Offset handle = Offset((value / 360) * size.width, size.height / 2);
    canvas.drawCircle(handle, 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      handle,
      7,
      Paint()
        ..color = const Color(0xFF4A4E57)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _HueSliderPainter oldDelegate) =>
      oldDelegate.value != value;
}

String _formatHsl(Color color) {
  final HSLColor hsl = HSLColor.fromColor(color);
  return '${hsl.hue.round()}, ${(hsl.saturation * 100).round()}%, ${(hsl.lightness * 100).round()}%';
}

Color? _parseHex(String input) {
  String value = input.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.toLowerCase().startsWith('0x')) value = value.substring(2);
  if (value.length != 6 && value.length != 8) return null;
  final int? parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return Color(value.length == 6 ? 0xFF000000 | parsed : parsed);
}

Color? _parseRgb(String input) {
  final List<String>? parts = _colorChannels(input, 'rgba?');
  if (parts == null || parts.length < 3 || parts.length > 4) return null;
  final int? red = _parseRgbChannel(parts[0]);
  final int? green = _parseRgbChannel(parts[1]);
  final int? blue = _parseRgbChannel(parts[2]);
  final double? alpha = parts.length == 4 ? _parseAlpha(parts[3]) : 1;
  if (red == null || green == null || blue == null || alpha == null)
    return null;
  return Color.fromARGB((alpha * 255).round(), red, green, blue);
}

Color? _parseHsl(String input) {
  final List<String>? parts = _colorChannels(input, 'hsla?');
  if (parts == null || parts.length < 3 || parts.length > 4) return null;
  final double? hue = double.tryParse(parts[0].replaceAll('°', '').trim());
  final double? saturation = _parsePercent(parts[1]);
  final double? lightness = _parsePercent(parts[2]);
  final double? alpha = parts.length == 4 ? _parseAlpha(parts[3]) : 1;
  if (hue == null || hue < 0 || hue > 360) return null;
  if (saturation == null || lightness == null || alpha == null) return null;
  return HSLColor.fromAHSL(alpha, hue, saturation, lightness).toColor();
}

List<String>? _colorChannels(String input, String functionPattern) {
  String channels = input.trim();
  final RegExp function = RegExp(
    '^${functionPattern}\\((.*)\\)\$',
    caseSensitive: false,
  );
  final RegExpMatch? match = function.firstMatch(channels);
  if (match != null) channels = match.group(1)!;
  channels = channels.replaceAll('/', ' ').replaceAll(',', ' ');
  final List<String> parts =
      channels
          .split(RegExp(r'\s+'))
          .where((String part) => part.isNotEmpty)
          .toList();
  return parts.length >= 3 && parts.length <= 4 ? parts : null;
}

int? _parseRgbChannel(String value) {
  final String channel = value.trim();
  if (channel.endsWith('%')) {
    final double? percent = double.tryParse(
      channel.substring(0, channel.length - 1),
    );
    if (percent == null || percent < 0 || percent > 100) return null;
    return (percent * 2.55).round();
  }
  final double? number = double.tryParse(channel);
  if (number == null || number < 0 || number > 255) return null;
  return number.round();
}

double? _parsePercent(String value) {
  final String channel = value.trim();
  if (channel.endsWith('%')) {
    final double? percent = double.tryParse(
      channel.substring(0, channel.length - 1),
    );
    if (percent == null || percent < 0 || percent > 100) return null;
    return percent / 100;
  }
  final double? number = double.tryParse(channel);
  if (number == null || number < 0 || number > 100) return null;
  return number <= 1 ? number : number / 100;
}

double? _parseAlpha(String value) {
  final String channel = value.trim();
  if (channel.endsWith('%')) {
    final double? percent = double.tryParse(
      channel.substring(0, channel.length - 1),
    );
    if (percent == null || percent < 0 || percent > 100) return null;
    return percent / 100;
  }
  final double? number = double.tryParse(channel);
  if (number == null || number < 0 || number > 1) return null;
  return number;
}

String _twoDigits(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
