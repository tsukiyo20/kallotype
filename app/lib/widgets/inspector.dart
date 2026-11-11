import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/roll.dart';
import 'record.dart';

/// The frame's record, on the right.
///
/// Apple's information panel is the model: a caption, a big number, a group of
/// rows with the label on the left and the figure on the right, and one action
/// at the bottom that is a button and looks like one.
class Inspector extends StatelessWidget {
  const Inspector({
    super.key,
    required this.roll,
    required this.selected,
    required this.onEnlarge,
  });

  final Roll roll;
  final int selected;

  /// Take this frame to the bench, where it is one frame rather than one of
  /// forty.
  final VoidCallback onEnlarge;

  Frame get frame => roll.frames[selected];
  int get total => roll.frames.length;

  /// Whether the roll has a chart in it. A roll the app developed has prints
  /// and no curves: the model's command line writes pixels, not densities, and
  /// a chart with invented rows would be worse than no chart.
  bool get charted => roll.frames.every((Frame frame) => frame.isMeasured);

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RecordHeader(number: frame.number, total: total),
            const SizedBox(height: 16),
            RecordGroup(
              rows: <(String, String)>[
                (s.time, frame.clock),
                (s.temperature, '${frame.tempC.toStringAsFixed(1)} °C'),
                if (frame.gamma != null) (s.gamma, _triple(frame.gamma!)),
                if (frame.dMax != null) (s.dMax, _triple(frame.dMax!)),
              ],
            ),
            if (!charted) const Spacer(),
            if (charted) ...<Widget>[
              const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Text(
                  s.tone,
                  style: KalloType.caption.copyWith(color: colors.inkFaint),
                ),
                const Spacer(),
                Text(
                  s.frames(total),
                  style: KalloType.small.copyWith(color: colors.inkFaint),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 108,
              child: CustomPaint(
                painter: _CurvePainter(
                  <List<double>>[
                    for (final Frame f in roll.frames) f.toneCurve!,
                  ],
                  selected,
                  colors.hairline,
                  colors.accent,
                ),
              ),
            ),
            const Spacer(),
            ],
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onEnlarge,
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.ink,
                    borderRadius: BorderRadius.circular(KalloRadius.control),
                  ),
                  child: Text(
                    s.develop,
                    style: KalloType.body.copyWith(
                      color: colors.content,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Three figures, tabular, never rounded to fewer than they were measured.
  static String _triple(List<double> values) =>
      values.map((double v) => v.toStringAsFixed(2)).join('  ');
}

/// The wedge's tone: density against patch.
/// The roll's tone, and the frame's place in it.
///
/// Forty lines is a moiré, so the roll is drawn as an envelope — the thinnest
/// and densest development at each patch, filled — and the selected frame is
/// drawn on top. The point of the product is the difference between the two.
class _CurvePainter extends CustomPainter {
  const _CurvePainter(this.series, this.selected, this.hairline, this.accent);

  final List<List<double>> series;
  final int selected;
  final Color hairline;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    double top = 0;
    double floor = double.infinity;
    for (final List<double> values in series) {
      top = math.max(top, values.reduce(math.max));
      floor = math.min(floor, values.reduce(math.min));
    }
    final double span = math.max(top - floor, 1e-6);
    final int patches = series.first.length;
    double x(int i) => patches == 1 ? 0 : i / (patches - 1) * size.width;
    double y(double v) => size.height - (v - floor) / span * (size.height - 10) - 4;

    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = hairline
        ..strokeWidth = 1,
    );

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

    final List<double> values = series[selected];
    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      if (i == 0) {
        path.moveTo(x(i), y(values[i]));
      } else {
        path.lineTo(x(i), y(values[i]));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.selected != selected || old.series != series;
}
