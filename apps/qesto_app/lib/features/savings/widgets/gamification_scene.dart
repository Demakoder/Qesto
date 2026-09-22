import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/qesto_theme.dart';

class GamificationScene extends StatelessWidget {
  const GamificationScene({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label:
          'Игровая сцена цели, выполнено ${(progress * 100).round()} процентов',
      child: ClipRRect(
        borderRadius: QestoGeometry.control,
        child: AspectRatio(
          aspectRatio: 1.42,
          child: CustomPaint(
            painter: _GamificationPainter(progress.clamp(0, 1)),
          ),
        ),
      ),
    );
  }
}

class _GamificationPainter extends CustomPainter {
  const _GamificationPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFDFF6FF), Color(0xFFF3FCF6)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    _drawCloud(
      canvas,
      Offset(size.width * 0.16, size.height * 0.18),
      size.width * 0.19,
    );
    _drawCloud(
      canvas,
      Offset(size.width * 0.82, size.height * 0.20),
      size.width * 0.16,
    );

    final farHill = Path()
      ..moveTo(0, size.height * 0.64)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.48,
        size.width * 0.43,
        size.height * 0.62,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        size.height * 0.45,
        size.width,
        size.height * 0.59,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(farHill, Paint()..color = const Color(0xFFBEEB94));

    final grass = Path()
      ..moveTo(0, size.height * 0.69)
      ..quadraticBezierTo(
        size.width * 0.24,
        size.height * 0.59,
        size.width * 0.48,
        size.height * 0.72,
      )
      ..quadraticBezierTo(
        size.width * 0.77,
        size.height * 0.61,
        size.width,
        size.height * 0.68,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(grass, Paint()..color = const Color(0xFF75D263));

    _drawPath(canvas, size);
    _drawTree(
      canvas,
      Offset(size.width * 0.12, size.height * 0.61),
      size.height * 0.36,
    );
    if (progress > 0.32) {
      _drawHouse(
        canvas,
        Offset(size.width * 0.68, size.height * 0.61),
        size.width * 0.32,
      );
    }
    if (progress > 0.08) {
      _drawCreature(
        canvas,
        Offset(size.width * 0.36, size.height * 0.66),
        size.width * 0.25,
      );
    }

    final flowerCount = math.max(1, (progress * 7).round());
    for (var index = 0; index < flowerCount; index++) {
      final x = size.width * (0.55 + (index * 0.067) % 0.4);
      final y = size.height * (0.79 + (index.isEven ? 0.06 : 0.01));
      _drawFlower(canvas, Offset(x, y), size.width * 0.018);
    }

    if (progress > 0.62) {
      final leafPaint = Paint()..color = const Color(0xFF54B93D);
      canvas.save();
      canvas.translate(size.width * 0.48, size.height * 0.25);
      canvas.rotate(-0.5);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 12, height: 6),
        leafPaint,
      );
      canvas.restore();
    }
  }

  void _drawCloud(Canvas canvas, Offset center, double width) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: width * 0.28),
      paint,
    );
    canvas.drawCircle(
      center.translate(-width * 0.21, -width * 0.09),
      width * 0.13,
      paint,
    );
    canvas.drawCircle(
      center.translate(width * 0.02, -width * 0.14),
      width * 0.18,
      paint,
    );
  }

  void _drawTree(Canvas canvas, Offset base, double height) {
    final trunk = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: base.translate(0, -height * 0.25),
        width: height * 0.12,
        height: height * 0.52,
      ),
      Radius.circular(height * 0.04),
    );
    canvas.drawRRect(trunk, Paint()..color = const Color(0xFF8E6944));
    final crownPaint = Paint()..color = const Color(0xFF4EB45C);
    final top = base.translate(0, -height * 0.7);
    final crown = Path()
      ..moveTo(top.dx, top.dy - height * 0.23)
      ..lineTo(top.dx - height * 0.23, top.dy + height * 0.16)
      ..lineTo(top.dx + height * 0.23, top.dy + height * 0.16)
      ..close();
    canvas.drawPath(crown, crownPaint);
    final crownTwo = Path()
      ..moveTo(top.dx, top.dy - height * 0.04)
      ..lineTo(top.dx - height * 0.29, top.dy + height * 0.34)
      ..lineTo(top.dx + height * 0.29, top.dy + height * 0.34)
      ..close();
    canvas.drawPath(crownTwo, Paint()..color = const Color(0xFF3FA952));
  }

  void _drawHouse(Canvas canvas, Offset base, double width) {
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        base.dx - width / 2,
        base.dy - width * 0.48,
        width,
        width * 0.54,
      ),
      Radius.circular(width * 0.05),
    );
    canvas.drawRRect(bodyRect, Paint()..color = const Color(0xFFFFF9E9));

    final roof = Path()
      ..moveTo(base.dx - width * 0.59, base.dy - width * 0.45)
      ..lineTo(base.dx, base.dy - width * 0.80)
      ..lineTo(base.dx + width * 0.59, base.dy - width * 0.45)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFF4BA64D));
    canvas.drawPath(
      roof,
      Paint()
        ..color = const Color(0xFF3D8D43)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.035,
    );

    final door = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        base.dx - width * 0.11,
        base.dy - width * 0.29,
        width * 0.22,
        width * 0.35,
      ),
      Radius.circular(width * 0.1),
    );
    canvas.drawRRect(door, Paint()..color = const Color(0xFF9B7048));
    canvas.drawCircle(
      Offset(base.dx + width * 0.055, base.dy - width * 0.11),
      width * 0.018,
      Paint()..color = const Color(0xFFFFD16A),
    );

    final windowRect = Rect.fromLTWH(
      base.dx + width * 0.24,
      base.dy - width * 0.31,
      width * 0.20,
      width * 0.18,
    );
    final window = RRect.fromRectAndRadius(
      windowRect,
      Radius.circular(width * 0.025),
    );
    canvas.drawRRect(window, Paint()..color = const Color(0xFF9BE2E7));
    canvas.drawLine(
      windowRect.centerLeft,
      windowRect.centerRight,
      Paint()
        ..color = const Color(0xFF4EA7A9)
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      windowRect.topCenter,
      windowRect.bottomCenter,
      Paint()
        ..color = const Color(0xFF4EA7A9)
        ..strokeWidth = 2,
    );
  }

  void _drawPath(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.73, size.height)
      ..quadraticBezierTo(
        size.width * 0.56,
        size.height * 0.79,
        size.width * 0.69,
        size.height * 0.65,
      )
      ..lineTo(size.width * 0.76, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.65,
        size.height * 0.82,
        size.width * 0.87,
        size.height,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFE7A2));
  }

  void _drawCreature(Canvas canvas, Offset center, double width) {
    final bodyPaint = Paint()..color = const Color(0xFF8FD64F);
    final shadowPaint = Paint()..color = const Color(0x22000000);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, width * 0.34),
        width: width * 0.74,
        height: width * 0.18,
      ),
      shadowPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: width * 1.08),
      bodyPaint,
    );

    for (final offset in [-0.28, -0.09, 0.11, 0.29]) {
      final spike = Path()
        ..moveTo(
          center.dx + width * offset - width * 0.08,
          center.dy - width * 0.43,
        )
        ..lineTo(center.dx + width * offset, center.dy - width * 0.67)
        ..lineTo(
          center.dx + width * offset + width * 0.08,
          center.dy - width * 0.43,
        )
        ..close();
      canvas.drawPath(spike, bodyPaint);
    }

    final eyePaint = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = const Color(0xFF203221);
    for (final dx in [-0.19, 0.19]) {
      final eyeCenter = center.translate(width * dx, -width * 0.10);
      canvas.drawCircle(eyeCenter, width * 0.11, eyePaint);
      canvas.drawCircle(
        eyeCenter.translate(width * 0.018, width * 0.018),
        width * 0.047,
        pupilPaint,
      );
    }

    final mouth = Path()
      ..moveTo(center.dx - width * 0.13, center.dy + width * 0.10)
      ..quadraticBezierTo(
        center.dx,
        center.dy + width * 0.25,
        center.dx + width * 0.13,
        center.dy + width * 0.10,
      );
    canvas.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFF244029)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.04
        ..strokeCap = StrokeCap.round,
    );

    final coinCenter = center.translate(0, width * 0.34);
    canvas.drawCircle(
      coinCenter,
      width * 0.18,
      Paint()..color = QestoColors.orange,
    );
    canvas.drawCircle(
      coinCenter,
      width * 0.18,
      Paint()
        ..color = const Color(0xFFFFD36D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.025,
    );
    final ruble = TextPainter(
      text: TextSpan(
        text: '₽',
        style: TextStyle(
          color: Colors.white,
          fontSize: width * 0.20,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ruble.paint(canvas, coinCenter - Offset(ruble.width / 2, ruble.height / 2));
  }

  void _drawFlower(Canvas canvas, Offset center, double radius) {
    final stem = Paint()
      ..color = const Color(0xFF2A9B45)
      ..strokeWidth = 2;
    canvas.drawLine(center, center.translate(0, radius * 3.5), stem);
    final petal = Paint()..color = Colors.white;
    for (var index = 0; index < 5; index++) {
      final angle = index / 5 * math.pi * 2;
      canvas.drawCircle(
        center.translate(math.cos(angle) * radius, math.sin(angle) * radius),
        radius * 0.76,
        petal,
      );
    }
    canvas.drawCircle(
      center,
      radius * 0.62,
      Paint()..color = QestoColors.orange,
    );
  }

  @override
  bool shouldRepaint(covariant _GamificationPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
