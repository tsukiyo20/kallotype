import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

// ---------------------------------------------------------------------------
// Geometry — 35 mm film, in millimetres, scaled to whatever height you ask for.
// ---------------------------------------------------------------------------

const double kFilmWidthMm = 35;
const double kFrameHeightMm = 24;
const double kFrameWidthMm = 36;
const double kGapMm = 2;
const double kPitchMm = kFrameWidthMm + kGapMm;
const double kRebateMm = (kFilmWidthMm - kFrameHeightMm) / 2;

@immutable
class FilmMetrics {
  const FilmMetrics({
    required this.scale,
    required this.height,
    required this.width,
    required this.frameWidth,
    required this.frameHeight,
    required this.gap,
    required this.pitch,
    required this.rebate,
  });

  factory FilmMetrics.forHeight(double height, int frameCount) {
    final double scale = height / kFilmWidthMm;
    final double pitch = kPitchMm * scale;
    return FilmMetrics(
      scale: scale,
      height: height,
      width: frameCount <= 0 ? 0 : frameCount * pitch - kGapMm * scale,
      frameWidth: kFrameWidthMm * scale,
      frameHeight: kFrameHeightMm * scale,
      gap: kGapMm * scale,
      pitch: pitch,
      rebate: kRebateMm * scale,
    );
  }

  final double scale;
  final double height;
  final double width;
  final double frameWidth;
  final double frameHeight;
  final double gap;
  final double pitch;
  final double rebate;
}

// ---------------------------------------------------------------------------
// A stand-in for kallotype-view.
//
// This is NOT the model. It is a shape close enough to draw a strip with, so
// that the interface can be judged before the renderer exists. The real
// numbers come from Rust; nothing here may grow into a second implementation.
// ---------------------------------------------------------------------------

/// Contrast as a function of development time, in the shape the core uses:
/// `gamma(t) = gamma_inf - (gamma_inf - gamma_0) * exp(-t / tau)`.
double gammaAt(double minutes) {
  const double gammaInf = 1.85;
  const double gamma0 = 0.30;
  const double tau = 6.5;
  return gammaInf - (gammaInf - gamma0) * math.exp(-minutes / tau);
}

/// The H&D curve: a toe, a straight line, a shoulder.
double negativeDensity(double logE, double gamma) {
  const double a = 4;
  const double toe = -1.55;
  const double shoulder = 1.05;
  const double dMin = 0.17;

  double softplus(double x) {
    if (x > 18) return x;
    if (x < -18) return 0;
    return math.log(1 + math.exp(x));
  }

  return dMin +
      (gamma / a) * (softplus(a * (logE - toe)) - softplus(a * (logE - shoulder)));
}

/// One frame, and how it was developed.
@immutable
class FilmFrame {
  const FilmFrame({
    required this.gamma,
    required this.number,
    required this.minutes,
  });

  final double gamma;

  /// What is printed on the rebate: `12A`.
  final String number;

  /// How long it was in the developer.
  final double minutes;
}

/// `09:00`, because a development time is a duration and not a number.
String formatMinutes(double minutes) {
  final int total = (minutes * 60).round();
  final String whole = (total ~/ 60).toString().padLeft(2, '0');
  final String rest = (total % 60).toString().padLeft(2, '0');
  return '$whole:$rest';
}

// ---------------------------------------------------------------------------
// The strip.
// ---------------------------------------------------------------------------

/// A strip of developed film, lit by the room it is in.
///
/// In the darkroom it is an object, dim, lit by one safelight. On the light
/// table it is a source: the base glows, the sprocket holes go bright, and the
/// emulsion is the brightest thing on the screen.
class FilmStrip extends StatelessWidget {
  const FilmStrip({
    super.key,
    required this.frames,
    required this.height,
    this.selected = 0,
    this.onSelect,
  });

  final List<FilmFrame> frames;
  final double height;
  final int selected;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;
    final FilmMetrics m = FilmMetrics.forHeight(height, frames.length);

    return SizedBox(
      width: m.width,
      height: m.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // The one shadow in the product, and it is light: a light table
          // spills onto the surface it is standing on.
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.accent.withValues(alpha: 0.12 * colors.emissive),
              blurRadius: 56,
              spreadRadius: 2,
            ),
          ],
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSelect == null
              ? null
              : (TapDownDetails details) {
                  final int index =
                      (details.localPosition.dx / m.pitch).floor();
                  if (index >= 0 && index < frames.length) {
                    onSelect!(index);
                  }
                },
          child: CustomPaint(
            painter: _FilmStripPainter(
              frames: frames,
              colors: colors,
              selected: selected,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilmStripPainter extends CustomPainter {
  _FilmStripPainter({
    required this.frames,
    required this.colors,
    required this.selected,
  });

  final List<FilmFrame> frames;
  final KalloColors colors;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty || size.isEmpty) {
      return;
    }

    final FilmMetrics m = FilmMetrics.forHeight(size.height, frames.length);
    final Rect strip = Offset.zero & size;

    // The rebate is clear film with the mask in it. On the light table it is
    // the brightest thing on the screen, because nothing in the emulsion is
    // holding any light back.
    final Color base = colors.filmClear;
    final Color shade = Color.lerp(base, const Color(0xFF0A0704), 0.42)!;

    canvas.drawRect(
      strip,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[shade, base, shade],
          stops: const <double>[0.0, 0.52, 1.0],
        ).createShader(strip),
    );

    // A perforation is a hole. Unlit, it is a hole in a dark object; on the
    // light table it is the light itself, and nothing else in the app changes
    // this much between the two rooms.
    final Color edgeHole = Color.lerp(
      const Color(0xFF080706),
      const Color(0xFFFFF6E6),
      colors.emissive,
    )!;

    // Sprocket holes: dark when the film is an object, bright when it is a
    // light source. Nothing else in the app changes this much between rooms.
    final double holeW = 2.8 * m.scale;
    final double holeH = 1.98 * m.scale;
    final double holePitch = 4.75 * m.scale;
    final double holeY = m.rebate * 0.44;
    final Paint holePaint = Paint()..color = edgeHole;

    for (double x = holePitch * 0.55; x < size.width; x += holePitch) {
      for (final double cy in <double>[holeY, size.height - holeY]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(x, cy),
              width: holeW,
              height: holeH,
            ),
            Radius.circular(0.5 * m.scale),
          ),
          holePaint,
        );
      }
    }

    for (int i = 0; i < frames.length; i++) {
      _paintFrame(
        canvas,
        Rect.fromLTWH(
          i * m.pitch,
          m.rebate,
          m.frameWidth,
          m.frameHeight,
        ),
        frames[i],
        base,
        i == selected,
      );
    }
  }

  void _paintFrame(
    Canvas canvas,
    Rect rect,
    FilmFrame frame,
    Color base,
    bool selected,
  ) {
    // Transmission, drawn. Patches sit on the straight line, where development
    // time is a slope rather than a shape, so five frames read as five
    // different contrasts instead of five copies of the same brown.
    const int patches = 9;
    final double w = rect.width / patches;
    final Paint paint = Paint();

    canvas.save();
    canvas.clipRect(rect);
    for (int i = 0; i < patches; i++) {
      // Two and a bit stops either side of the toe: wide enough that a longer
      // development visibly blocks the ends up and steepens the middle, which
      // is what the whole screen is here to show.
      final double logE = -2.0 + (i / (patches - 1)) * 2.8;
      final double density = negativeDensity(logE, frame.gamma);
      final double transmission = math.pow(10, -density).toDouble();
      final double value =
          math.pow(transmission, 0.55).toDouble().clamp(0.0, 1.0).toDouble();
      paint.color = Color.lerp(colors.filmDense, colors.filmClear, value)!;
      canvas.drawRect(
        Rect.fromLTWH(rect.left + i * w, rect.top, w + 0.5, rect.height),
        paint,
      );
    }
    canvas.restore();

    // A frame is a cut edge in the emulsion, not a card.
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.alphaBlend(colors.ground.withValues(alpha: 0.55), base),
    );

    if (selected) {
      canvas.drawRect(
        rect.deflate(1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = colors.accent,
      );
    }
  }

  @override
  bool shouldRepaint(_FilmStripPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      !identical(oldDelegate.colors, colors) ||
      !identical(oldDelegate.frames, frames);
}
