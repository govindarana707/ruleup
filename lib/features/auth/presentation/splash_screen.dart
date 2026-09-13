import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The branded surface shown only while RuleUp restores the current session.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SplashColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _LeafBackdrop())),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 20, 24, 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 650;
                return Column(
                  children: [
                    const Spacer(flex: 3),
                    _BrandLockup(compact: compact),
                    SizedBox(height: compact ? 26 : 42),
                    _LoadingStatus(animation: _progressController),
                    const Spacer(flex: 4),
                    const _Footer(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _SplashColors {
  static const background = Color(0xFF061416);
  static const mint = Color(0xFF45EDC3);
  static const muted = Color(0xFFA4B0B3);
  static const track = Color(0xFF193033);
  static const leaf = Color(0xFF0A3A35);
  static const arc = Color(0xFF0B5045);
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 108.0 : 132.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'RuleUp logo',
          image: true,
          child: SizedBox.square(
            dimension: iconSize,
            child: CustomPaint(painter: const _AppIconPainter()),
          ),
        ),
        SizedBox(height: compact ? 12 : 18),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            const TextSpan(
              children: [
                TextSpan(text: 'Rule'),
                TextSpan(
                  text: 'Up',
                  style: TextStyle(color: _SplashColors.mint),
                ),
              ],
            ),
            style: TextStyle(
              fontFamily: 'RuleUpSans',
              color: Colors.white,
              fontSize: compact ? 54 : 64,
              height: 0.98,
              fontWeight: FontWeight.w500,
              letterSpacing: -3.4,
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 20),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'BUILD A BETTER YOU',
            style: TextStyle(
              fontFamily: 'RuleUpSans',
              color: _SplashColors.muted,
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w400,
              letterSpacing: compact ? 5 : 7,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingStatus extends StatelessWidget {
  const _LoadingStatus({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Getting things ready',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 142,
            height: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) =>
                    CustomPaint(painter: _ProgressPainter(animation.value)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Getting things ready...',
            style: TextStyle(
              fontFamily: 'RuleUpSans',
              color: _SplashColors.muted,
              fontSize: 16,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          const Align(alignment: Alignment.bottomLeft, child: _SmallSteps()),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 250),
              child: Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFF536265))),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Developed by',
                        style: TextStyle(
                          fontFamily: 'RuleUpSans',
                          color: _SplashColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Govinda Rana',
                        style: TextStyle(
                          fontFamily: 'RuleUpSans',
                          color: Color(0xFFE9EFF0),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Divider(color: Color(0xFF536265))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallSteps extends StatelessWidget {
  const _SmallSteps();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SMALL STEPS\nBIG CHANGES',
          style: TextStyle(
            fontFamily: 'RuleUpSans',
            color: Color(0xFFD1D9DA),
            fontSize: 10,
            height: 1.55,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: 38,
          height: 2,
          decoration: BoxDecoration(
            color: _SplashColors.mint,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = _SplashColors.track,
    );
    final segmentWidth = size.width * 0.48;
    final left = (size.width + segmentWidth) * progress - segmentWidth;
    final segment = Rect.fromLTWH(left, 0, segmentWidth, size.height);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, radius));
    canvas.drawRRect(
      RRect.fromRectAndRadius(segment, radius),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF20CDA7), Color(0xFF5CFFD5)],
        ).createShader(segment),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _AppIconPainter extends CustomPainter {
  const _AppIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(size.width * 0.26)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5BFFD6), Color(0xFF35DFAF)],
        ).createShader(bounds),
    );

    final leaf = Path()
      ..moveTo(size.width * 0.35, size.height * 0.68)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.43,
        size.width * 0.45,
        size.height * 0.29,
        size.width * 0.76,
        size.height * 0.28,
      )
      ..cubicTo(
        size.width * 0.75,
        size.height * 0.61,
        size.width * 0.62,
        size.height * 0.78,
        size.width * 0.43,
        size.height * 0.72,
      )
      ..cubicTo(
        size.width * 0.48,
        size.height * 0.57,
        size.width * 0.56,
        size.height * 0.47,
        size.width * 0.62,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.50,
        size.height * 0.49,
        size.width * 0.41,
        size.height * 0.58,
        size.width * 0.35,
        size.height * 0.68,
      )
      ..close();
    canvas.drawPath(leaf, Paint()..color = _SplashColors.background);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LeafBackdrop extends CustomPainter {
  const _LeafBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = _SplashColors.arc.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(-size.width * 0.26, -size.width * 0.18),
        radius: size.width * 0.67,
      ),
      0.05,
      math.pi * 0.67,
      false,
      linePaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 1.32, size.height * 1.08),
        radius: size.width * 0.72,
      ),
      math.pi,
      math.pi * 0.72,
      false,
      linePaint,
    );

    _drawLeaf(
      canvas,
      center: Offset(size.width * 0.06, size.height * 0.09),
      leafSize: size.width * 0.25,
      rotation: -0.76,
    );
    _drawLeaf(
      canvas,
      center: Offset(size.width * 0.92, size.height * 0.89),
      leafSize: size.width * 0.28,
      rotation: 0.72,
    );
  }

  void _drawLeaf(
    Canvas canvas, {
    required Offset center,
    required double leafSize,
    required double rotation,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final path = Path()
      ..moveTo(-leafSize * 0.56, 0)
      ..quadraticBezierTo(0, -leafSize * 0.56, leafSize * 0.56, 0)
      ..quadraticBezierTo(0, leafSize * 0.56, -leafSize * 0.56, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = _SplashColors.leaf.withValues(alpha: 0.62)
        ..style = PaintingStyle.fill,
    );
    canvas.drawLine(
      Offset(-leafSize * 0.46, 0),
      Offset(leafSize * 0.43, 0),
      Paint()
        ..color = _SplashColors.background.withValues(alpha: 0.72)
        ..strokeWidth = leafSize * 0.1
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
