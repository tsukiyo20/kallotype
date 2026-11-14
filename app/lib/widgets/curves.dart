import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';

/// The roll's tone: density against patch.
///
/// Forty lines is a moiré, so the roll is drawn as an envelope — the thinnest
/// and densest development at each patch, filled — and the selected frame is
/// drawn on top. The point of the product is the difference between the two.
///
/// With no frame selected, every line is drawn at the same weight and there is
/// no envelope: that is the curve as a record rather than as a comparison, and
/// it is what the binder shows.
class KalloCurves extends StatelessWidget {
  const KalloCurves({
    super.key,
    required this.series,
    this.selected,
    this.height = 108,
    this.xs,
  });

  final List<List<double>> series;
  final int? selected;
  final double height;

  /// The x value of each point, when the curve is a function rather than a
  /// strip of patches. The film chart's x is log exposure, and so is the
  /// paper's; a curve drawn against its index would be a curve of the sampling.
  final List<double>? xs;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: _CurvePainter(
        series,
        selected,
        xs,
        KalloScope.colorsOf(context).hairline,
        KalloScope.colorsOf(context).accent,
      ),
    ),
  );
}

class _CurvePainter extends CustomPainter {
  const _CurvePainter(
    this.series,
    this.selected,
    this.xs,
    this.hairline,
    this.accent,
  );

  final List<List<double>> series;
  final int? selected;
  final List<double>? xs;
  final Color hairline;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) {
      return;
    }
    double top = 0;
    double floor = double.infinity;
    for (final List<double> values in series) {
      top = math.max(top, values.reduce(math.max));
      floor = math.min(floor, values.reduce(math.min));
    }
    final double span = math.max(top - floor, 1e-6);
    final int patches = series.first.length;
    final List<double>? xs = this.xs;
    final double xMin = xs == null ? 0 : xs.reduce(math.min);
    final double xMax = xs == null ? 0 : xs.reduce(math.max);
    final double xSpan = math.max(xMax - xMin, 1e-9);
    double x(int i) => xs == null
        ? (patches == 1 ? 0 : i / (patches - 1) * size.width)
        : (xs[i] - xMin) / xSpan * size.width;
    double y(double v) =>
        size.height - (v - floor) / span * (size.height - 10) - 4;

    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = hairline
        ..strokeWidth = 1,
    );

    final int? selected = this.selected;
    if (selected == null) {
      for (final List<double> values in series) {
        canvas.drawPath(
          _path(values, x, y),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..strokeJoin = StrokeJoin.round
            ..color = accent.withValues(alpha: 0.55),
        );
      }
      return;
    }

    final Path envelope = Path();
    for (int i = 0; i < patches; i++) {
      final double v = series
          .map((List<double> s) => s[i])
          .reduce((double a, double b) => math.max(a, b));
      if (i == 0) {
        envelope.moveTo(x(i), y(v));
      } else {
        envelope.lineTo(x(i), y(v));
      }
    }
    for (int i = patches - 1; i >= 0; i--) {
      final double v = series
          .map((List<double> s) => s[i])
          .reduce((double a, double b) => math.min(a, b));
      envelope.lineTo(x(i), y(v));
    }
    envelope.close();
    canvas.drawPath(envelope, Paint()..color = accent.withValues(alpha: 0.10));

    canvas.drawPath(
      _path(series[selected], x, y),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = accent,
    );
  }

  Path _path(
    List<double> values,
    double Function(int) x,
    double Function(double) y,
  ) {
    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      if (i == 0) {
        path.moveTo(x(i), y(values[i]));
      } else {
        path.lineTo(x(i), y(values[i]));
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.selected != selected || old.series != series || old.xs != xs;
}
