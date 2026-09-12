import 'package:flutter/material.dart';

/// A compact three-coin stack used wherever RuleUp shows its point currency.
class PointCoinsIcon extends StatelessWidget {
  const PointCoinsIcon({
    super.key,
    this.size = 24,
    required this.color,
    this.semanticLabel = 'Points',
  });

  final double size;
  final Color color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _PointCoinsPainter(color),
      ),
    ),
  );
}

class _PointCoinsPainter extends CustomPainter {
  const _PointCoinsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale, scale);

    _coin(canvas, const Offset(13, 5), 7.5);
    _coin(canvas, const Offset(11, 10), 8.5);
    _coin(canvas, const Offset(9, 15), 9.5);
  }

  void _coin(Canvas canvas, Offset center, double width) {
    final top = Rect.fromCenter(center: center, width: width, height: 4.8);
    final side = Rect.fromLTWH(center.dx - width / 2, center.dy, width, 3.1);
    final sidePaint = Paint()..color = color.withValues(alpha: .55);
    canvas.drawRect(side, sidePaint);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + side.height),
        width: width,
        height: 4.8,
      ),
      sidePaint,
    );
    canvas.drawOval(top, Paint()..color = color);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - width * .12, center.dy - .35),
        width: width * .55,
        height: 1.35,
      ),
      Paint()..color = Colors.white.withValues(alpha: .38),
    );
  }

  @override
  bool shouldRepaint(_PointCoinsPainter oldDelegate) =>
      oldDelegate.color != color;
}
