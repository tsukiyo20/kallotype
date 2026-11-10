import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/roll.dart';

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
  });

  final Roll roll;
  final int selected;

  Frame get frame => roll.frames[selected];
  int get total => roll.frames.length;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
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
            Text(
              'FRAME',
              style: KalloType.caption.copyWith(color: colors.inkFaint),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  frame.number.toString().padLeft(2, '0'),
                  style: KalloType.plate.copyWith(color: colors.ink),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'of $total',
                    style: KalloType.small.copyWith(color: colors.inkFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Group(
              rows: <(String, String)>[
                ('Time', frame.clock),
                ('Temperature', '${frame.tempC.toStringAsFixed(1)} °C'),
                ('Gamma', _triple(frame.gamma)),
                ('D max', _triple(frame.dMax)),
              ],
              colors: colors,
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Text(
                  'TONE',
                  style: KalloType.caption.copyWith(color: colors.inkFaint),
                ),
                const Spacer(),
                Text(
                  '$total frames',
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
                    for (final Frame f in roll.frames) f.toneCurve,
                  ],
                  selected,
                  colors.hairline,
                  colors.accent,
                  colors.inkFaint,
                ),
              ),
            ),
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(KalloRadius.control),
                  ),
                  child: Text(
                    'Develop',
                    style: KalloType.body.copyWith(
                      color: const Color(0xFFFFFFFF),
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

  static String _triple(List<double> values) =>
      values.map((double v) => v.toStringAsFixed(2)).join('  ');
}

class _Group extends StatelessWidget {
  const _Group({required this.rows, required this.colors});

  final List<(String, String)> rows;
  final KalloColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < rows.length; i++)
          Container(
            height: 30,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: i == rows.length - 1
                      ? const Color(0x00000000)
                      : colors.hairline,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  rows[i].$1,
                  style: KalloType.small.copyWith(color: colors.inkMuted),
                ),
                const Spacer(),
                Text(
                  rows[i].$2,
                  style: KalloType.data.copyWith(color: colors.ink),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The wedge's tone: density against patch.
/// Every frame's tone, on one pair of axes.
///
/// The point of the product is on this chart: five frames, one wedge, five
/// developments. The selected one is drawn in the accent and the rest are
/// faint, so the difference between them is the picture rather than a caption.
class _CurvePainter extends CustomPainter {
  const _CurvePainter(
    this.series,
    this.selected,
    this.hairline,
    this.accent,
    this.faint,
  );

  final List<List<double>> series;
  final int selected;
  final Color hairline;
  final Color accent;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    double top = 0;
    double floor = double.infinity;
    for (final List<double> values in series) {
      top = math.max(top, values.reduce(math.max));
      floor = math.min(floor, values.reduce(math.min));
    }
    final double span = math.max(top - floor, 1e-6);
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = hairline
        ..strokeWidth = 1,
    );
    for (int s = 0; s < series.length; s++) {
      final List<double> values = series[s];
      final Path path = Path();
      for (int i = 0; i < values.length; i++) {
        final double x =
            values.length == 1 ? 0 : i / (values.length - 1) * size.width;
        final double y =
            size.height - (values[i] - floor) / span * (size.height - 10) - 4;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s == selected ? 1.6 : 1
          ..strokeJoin = StrokeJoin.round
          ..color = s == selected ? accent : faint,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.selected != selected || old.series != series;
}
