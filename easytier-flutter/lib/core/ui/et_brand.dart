import 'package:flutter/material.dart';

/// EasyTier brand mark: an M3-blue rounded tile with a white three-node mesh.
/// One `const`-only drawing so the launcher icon, splash, rail and hero orb all
/// share the exact same geometry (see android/ios/macos/windows assets).
class EtBrandMark extends StatelessWidget {
  const EtBrandMark({super.key, this.size = 36, this.radius});

  /// Google-blue launcher background (matches the generated PNG/vector icons).
  static const Color brandBlue = Color(0xFF1A73E8);

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brandBlue,
        borderRadius: BorderRadius.circular(radius ?? size * 0.28),
      ),
      child: CustomPaint(painter: const _MeshMarkPainter()),
    );
  }
}

class _MeshMarkPainter extends CustomPainter {
  const _MeshMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Normalised from the 1024 master: top (0.5, 0.328), legs (0.301, 0.633)
    // and (0.699, 0.633); node radius 0.078, connector width 0.041.
    Offset p(double x, double y) => Offset(size.width * x, size.height * y);
    final top = p(0.5, 0.328);
    final left = p(0.301, 0.633);
    final right = p(0.699, 0.633);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.041
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(top, left, stroke);
    canvas.drawLine(top, right, stroke);
    canvas.drawLine(left, right, stroke);
    final node = Paint()..color = Colors.white;
    final radius = size.width * 0.078;
    canvas.drawCircle(top, radius, node);
    canvas.drawCircle(left, radius, node);
    canvas.drawCircle(right, radius, node);
  }

  @override
  bool shouldRepaint(_MeshMarkPainter oldDelegate) => false;
}
