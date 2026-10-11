import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_flutter_builder/editor/color_picker_dialog.dart';

void main() {
  group('color input formats', () {
    test('parses HEX, RGB, HSL, and alpha values', () {
      expect(
        parseColorInput('#336699', ColorInputFormat.hex)?.toARGB32(),
        0xFF336699,
      );
      expect(
        parseColorInput('#80336699', ColorInputFormat.hex)?.toARGB32(),
        0x80336699,
      );
      expect(
        parseColorInput('rgb(255, 0, 128)', ColorInputFormat.rgb)?.toARGB32(),
        0xFFFF0080,
      );
      expect(
        parseColorInput('255, 0, 128, 50%', ColorInputFormat.rgb)?.toARGB32(),
        0x80FF0080,
      );
      expect(
        parseColorInput('hsl(0, 100%, 50%)', ColorInputFormat.hsl)?.toARGB32(),
        0xFFFF0000,
      );
      expect(parseColorInput('not a color', ColorInputFormat.hex), isNull);
    });

    test('formats alpha colors as eight-digit HEX', () {
      const Color color = Color(0x80336699);

      expect(formatColorInput(color, ColorInputFormat.hex), '#80336699');
      expect(
        parseColorInput(
          formatColorInput(color, ColorInputFormat.hex),
          ColorInputFormat.hex,
        )?.toARGB32(),
        color.toARGB32(),
      );
    });
  });

  testWidgets('HEX and RGB controls update the selected color', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Color? selectedColor;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (BuildContext context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      selectedColor = await showLocalColorPicker(
                        context,
                        const Color(0xFF6750A4),
                      );
                    },
                    child: const Text('Open picker'),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('RGB'));
    await tester.pumpAndSettle();
    final Finder input = find.byKey(
      const ValueKey<String>('color-picker-input'),
    );
    await tester.enterText(input, '255, 0, 0');
    await tester.pumpAndSettle();
    expect(find.text('#FF0000'), findsOneWidget);

    await tester.tap(find.text('Use color'));
    await tester.pumpAndSettle();
    expect(selectedColor?.toARGB32(), 0xFFFF0000);
  });
}
