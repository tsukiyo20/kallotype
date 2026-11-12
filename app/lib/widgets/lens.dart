import 'package:flutter/widgets.dart';

/// A loupe: a lens with a rim, held over the material.
///
/// It is a physical object and it is drawn as one: a turned metal bezel whose
/// sheen runs round it, a glass that darkens and softens at its edge, and the
/// room reflected as one arc across the top left. There is no shadow under it —
/// the app has no shadows for depth — but there is a rim, because a loupe is
/// held, and a circle of nothing is not held.
///
/// The glass is its own material: the colours below belong to the object and
/// not to the wall or the paper it is held over.
class KalloLens extends StatelessWidget {
  const KalloLens({
    super.key,
    required this.at,
    required this.radius,
    required this.child,
  });

  /// The centre, in the parent's coordinates.
  final Offset at;

  /// The glass's radius. The bezel sits outside it.
  final double radius;

  /// The magnified material, clipped to the glass.
  final Widget child;

  /// The bezel's width: a rim, not a hairline.
  static const double bezel = 5.0;

  /// The bezel: graphite, turning to silver where the light catches it.
  static const Color _dark = Color(0xFF211E1B);
  static const Color _light = Color(0xFF958F86);

  @override
  Widget build(BuildContext context) {
    final double outer = radius + bezel;
    final double glass = radius * 2;
    return Positioned(
      left: at.dx - outer,
      top: at.dy - outer,
      child: IgnorePointer(
        child: SizedBox(
          width: outer * 2,
          height: outer * 2,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: bezel,
                top: bezel,
                width: glass,
                height: glass,
                child: ClipOval(child: child),
              ),
              // A lens is dimmer and softer at its edge, and that falloff is
              // half of what tells the eye it is looking through glass.
              Positioned(
                left: bezel,
                top: bezel,
                width: glass,
                height: glass,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[Color(0x00000000), Color(0x1F000000)],
                      stops: <double>[0.64, 1],
                    ),
                  ),
                ),
              ),
              // The room, reflected: one soft arc across the top left.
              Positioned(
                left: bezel,
                top: bezel,
                width: glass,
                height: glass,
                child: const CustomPaint(painter: _Glint()),
              ),
              // The rim.
              Positioned.fill(child: const CustomPaint(painter: _Bezel())),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bezel: a band with a sheen that turns with the light, and two edges.
class _Bezel extends CustomPainter {
  const _Bezel();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = size.center(Offset.zero);
    final double outer = size.shortestSide / 2;
    final Rect box = Offset.zero & size;
    final Paint band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = KalloLens.bezel
      ..shader = const SweepGradient(
        colors: <Color>[
          KalloLens._dark,
          KalloLens._light,
          Color(0xFF3A3631),
          Color(0xFF857F76),
          KalloLens._dark,
        ],
        transform: GradientRotation(-0.8),
      ).createShader(box);
    canvas.drawCircle(centre, outer - KalloLens.bezel / 2, band);
    // An outer edge that catches the light and an inner one that does not: two
    // rings are what make a band read as a solid rim rather than a line.
    canvas.drawCircle(
      centre,
      outer - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x40FFFFFF),
    );
    canvas.drawCircle(
      centre,
      outer - KalloLens.bezel + 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(_Bezel oldDelegate) => false;
}

/// The reflection: one blurred arc, as a window would sit in the glass.
class _Glint extends CustomPainter {
  const _Glint();

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.shortestSide / 2;
    final Paint glint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * 0.08
      ..color = const Color(0x1FFFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: radius * 0.74),
      -2.8,
      1.2,
      false,
      glint,
    );
  }

  @override
  bool shouldRepaint(_Glint oldDelegate) => false;
}
