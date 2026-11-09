import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import 'strip_data.dart';

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

/// `09:00`, because a development time is a duration and not a number.
String formatMinutes(double minutes) {
  final int total = (minutes * 60).round();
  final String whole = (total ~/ 60).toString().padLeft(2, '0');
  final String rest = (total % 60).toString().padLeft(2, '0');
  return '$whole:$rest';
}

// ---------------------------------------------------------------------------
// What a density looks like.
// ---------------------------------------------------------------------------

/// What a status density transmits, lit or unlit.
///
/// The base, the fog and the orange mask are added to the dye because that is
/// what a densitometer reads. The mask's coupling to the cyan dye is a
/// print-stage effect and is not shown here: this is the film, not the print.
Color _transmission(
  List<double> base,
  List<double> dye,
  KalloColors colors,
) {
  final Color lit = Color.from(
    alpha: 1,
    red: _lift(base[0] + dye[0]),
    green: _lift(base[1] + dye[1]),
    blue: _lift(base[2] + dye[2]),
  );
  // Unlit, the film is an object in a dark room and not a source of light.
  return Color.lerp(
    Color.lerp(colors.ground, lit, 0.30)!,
    lit,
    colors.emissive,
  )!;
}

/// Density to light, with the lift a light table's brightness gives it. A
/// density of 1.0 transmits a tenth of the light; the exponent is the display
/// transfer, and 0.70 is where the base stays the colour of the mask instead of
/// washing out to pink.
double _lift(double density) {
  final double transmitted = math.pow(10, -density).toDouble();
  return math.pow(transmitted, 0.70).toDouble().clamp(0.0, 1.0).toDouble();
}

// ---------------------------------------------------------------------------
// The strip.
// ---------------------------------------------------------------------------

/// A strip of developed film, lit by the room it is in.
///
/// The frames and the base come from the model, through `just view`; nothing
/// here decides what a density is.
class FilmStrip extends StatelessWidget {
  const FilmStrip({
    super.key,
    required this.frames,
    required this.baseDensity,
    required this.height,
    this.selected = 0,
    this.onSelect,
  });

  final List<StripFrame> frames;
  final List<double> baseDensity;
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
              baseDensity: baseDensity,
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
    required this.baseDensity,
    required this.colors,
    required this.selected,
  });

  final List<StripFrame> frames;
  final List<double> baseDensity;
  final KalloColors colors;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty || size.isEmpty) {
      return;
    }

    final FilmMetrics m = FilmMetrics.forHeight(size.height, frames.length);
    final Rect strip = Offset.zero & size;

    // The rebate is clear film: the base with no dye in it. On the light table
    // it is the brightest thing on the screen.
    final Color base = _transmission(baseDensity, const <double>[0, 0, 0], colors);
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
        Rect.fromLTWH(i * m.pitch, m.rebate, m.frameWidth, m.frameHeight),
        frames[i],
        base,
        i == selected,
      );
    }
  }

  void _paintFrame(
    Canvas canvas,
    Rect rect,
    StripFrame frame,
    Color base,
    bool selected,
  ) {
    final List<List<double>> patches = frame.patches;
    if (patches.isEmpty) {
      return;
    }

    final double w = rect.width / patches.length;
    final Paint paint = Paint();

    canvas.save();
    canvas.clipRect(rect);
    for (int i = 0; i < patches.length; i++) {
      paint.color = _transmission(baseDensity, patches[i], colors);
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
