import 'package:flutter/material.dart';
import 'dart:ui' show PointMode;

class LocalSignaturePad extends StatefulWidget {
  const LocalSignaturePad({
    required this.width,
    required this.height,
    required this.strokeWidth,
    required this.penColor,
    required this.backgroundColor,
    super.key,
  });

  final double width;
  final double height;
  final double strokeWidth;
  final Color penColor;
  final Color backgroundColor;

  @override
  State<LocalSignaturePad> createState() => _LocalSignaturePadState();
}

class _LocalSignaturePadState extends State<LocalSignaturePad> {
  final List<List<Offset>> _strokes = <List<Offset>>[];

  @override
  Widget build(BuildContext context) => Container(
    width: widget.width,
    height: widget.height,
    decoration: BoxDecoration(
      color: widget.backgroundColor,
      border: Border.all(color: const Color(0xFFBBC2CE)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart:
                  (DragStartDetails details) => setState(() {
                    _strokes.add(<Offset>[details.localPosition]);
                  }),
              onPanUpdate:
                  (DragUpdateDetails details) => setState(() {
                    if (_strokes.isNotEmpty)
                      _strokes.last.add(details.localPosition);
                  }),
              child: CustomPaint(
                painter: _SignaturePainter(
                  strokes: _strokes,
                  color: widget.penColor,
                  strokeWidth: widget.strokeWidth,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Clear signature',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () => setState(_strokes.clear),
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint pen =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
    for (final List<Offset> stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawPoints(PointMode.points, stroke, pen);
        continue;
      }
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final Offset point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
