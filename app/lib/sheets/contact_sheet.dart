import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/roll.dart';
import '../widgets/edge_bar.dart';

/// The table, with the roll unrolled on it.
///
/// A contact sheet is a print: the negative laid on paper, exposed, developed.
/// What it shows is positives, and what you do on it is choose. It is the
/// default place in the product, because it is both the library and the bench.
class SheetScreen extends StatelessWidget {
  const SheetScreen({super.key, required this.roll, this.selected = 2});

  final Roll roll;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return ColoredBox(
      color: colors.ground,
      child: Padding(
        padding: const EdgeInsets.all(KalloSpace.step5 - 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(roll: roll),
            const SizedBox(height: KalloSpace.step4),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: _Sheet(roll: roll, selected: selected)),
                  const SizedBox(width: KalloSpace.step4),
                  SizedBox(
                    width: 300,
                    child: _Card(
                      frame: roll.frames[selected],
                      total: roll.frames.length,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KalloSpace.step4 - 8),
            const EdgeBar(current: Place.table),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.roll});

  final Roll roll;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'KALLOTYPE',
              style: KalloType.caption.copyWith(
                color: colors.inkFaint,
                letterSpacing: 2.6,
              ),
            ),
            const SizedBox(height: KalloSpace.step2 - 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  roll.id,
                  style: KalloType.plate.copyWith(color: colors.ink),
                ),
                const SizedBox(width: KalloSpace.step3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${roll.stockLabel}   ·   ${roll.frames.length} FRAMES',
                    style: KalloType.data.copyWith(color: colors.inkMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
        const Spacer(),
        Text(
          'SHEET 01',
          style: KalloType.folio.copyWith(color: colors.inkFaint),
        ),
      ],
    );
  }
}

/// The frames, on the paper.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.roll, required this.selected});

  final Roll roll;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth > 720 ? 3 : 2;
        const double gap = KalloSpace.step3;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return SingleChildScrollView(
          child: Wrap(
            spacing: gap,
            runSpacing: KalloSpace.step4 - 4,
            children: <Widget>[
              for (int i = 0; i < roll.frames.length; i++)
                _FrameTile(
                  frame: roll.frames[i],
                  width: width,
                  marked: i == selected,
                  paper: colors.surfaceRaised,
                  hairline: colors.hairline,
                  ink: colors.ink,
                  inkFaint: colors.inkFaint,
                  accent: colors.accent,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.frame,
    required this.width,
    required this.marked,
    required this.paper,
    required this.hairline,
    required this.ink,
    required this.inkFaint,
    required this.accent,
  });

  final Frame frame;
  final double width;
  final bool marked;
  final Color paper;
  final Color hairline;
  final Color ink;
  final Color inkFaint;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 3 / 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PrintPainter(
                      frame.printColours(paper),
                      hairline,
                    ),
                  ),
                ),
                if (marked)
                  Positioned.fill(
                    child: CustomPaint(painter: _GreasePainter(accent)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: KalloSpace.step2 - 2),
          Row(
            children: <Widget>[
              Text(
                frame.number.toString().padLeft(2, '0'),
                style: KalloType.folio.copyWith(color: inkFaint),
              ),
              const Spacer(),
              Text(
                frame.clock,
                style: KalloType.folio.copyWith(color: inkFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nine patches of dye, laid on paper.
class _PrintPainter extends CustomPainter {
  const _PrintPainter(this.patches, this.hairline);

  final List<Color> patches;
  final Color hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width / patches.length;
    final Paint fill = Paint();
    for (int i = 0; i < patches.length; i++) {
      fill.color = patches[i];
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w + 0.5, size.height), fill);
    }
    canvas.drawRect(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hairline,
    );
  }

  @override
  bool shouldRepaint(_PrintPainter old) =>
      old.patches != patches || old.hairline != hairline;
}

/// A grease pencil, not a selection rectangle.
class _GreasePainter extends CustomPainter {
  const _GreasePainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = Rect.fromLTWH(0, 0, size.width, size.height).deflate(9);
    final Path path = Path();
    const int steps = 96;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps * 2 * math.pi;
      // A hand is not a compass: the radius wobbles as it goes round.
      final double wobble =
          1 + 0.016 * math.sin(t * 7 + 1.3) + 0.009 * math.sin(t * 13 + 4.1);
      final double x = box.center.dx + math.cos(t) * box.width / 2 * wobble;
      final double y = box.center.dy + math.sin(t) * box.height / 2 * wobble;
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
        ..strokeWidth = 1.7
        ..strokeJoin = StrokeJoin.round
        ..color = colour,
    );
  }

  @override
  bool shouldRepaint(_GreasePainter old) => old.colour != colour;
}

/// The card: the frame's record, on paper.
class _Card extends StatelessWidget {
  const _Card({required this.frame, required this.total});

  final Frame frame;
  final int total;

  static String _triple(List<double> values) =>
      values.map((double v) => v.toStringAsFixed(2)).join('  /  ');

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(KalloSpace.step3 + 4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'FRAME',
            style: KalloType.caption.copyWith(color: colors.inkFaint),
          ),
          const SizedBox(height: KalloSpace.step1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                frame.number.toString().padLeft(2, '0'),
                style: KalloType.plate.copyWith(
                  fontSize: 46,
                  color: colors.ink,
                ),
              ),
              const SizedBox(width: KalloSpace.step2),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '/ ${total.toString().padLeft(2, '0')}',
                  style: KalloType.folio.copyWith(color: colors.inkFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: KalloSpace.step3),
          Container(height: 1, color: colors.hairline),
          const SizedBox(height: KalloSpace.step3),
          _Row('Time', frame.clock, colors),
          _Row('Temp', '${frame.tempC.toStringAsFixed(1)} °C', colors),
          _Row('Gamma', _triple(frame.gamma), colors),
          _Row('D max', _triple(frame.dMax), colors),
          Text(
            'DENSITY',
            style: KalloType.caption.copyWith(color: colors.inkFaint),
          ),
          const SizedBox(height: KalloSpace.step1),
          SizedBox(
            height: 86,
            width: double.infinity,
            child: CustomPaint(
              painter: _CurvePainter(
                frame.toneCurve,
                colors.hairline,
                colors.accent,
              ),
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'DEVELOP',
              style: KalloType.caption.copyWith(color: colors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// The wedge's tone, as a curve: density against patch.
class _CurvePainter extends CustomPainter {
  const _CurvePainter(this.values, this.hairline, this.accent);

  final List<double> values;
  final Color hairline;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final double top = values.reduce(math.max);
    final double floor = values.reduce(math.min);
    final double span = math.max(top - floor, 1e-6);
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = hairline
        ..strokeWidth = 1,
    );
    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = values.length == 1
          ? 0
          : i / (values.length - 1) * size.width;
      final double y =
          size.height - (values[i] - floor) / span * (size.height - 6) - 3;
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
        ..strokeWidth = 1.4
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.values != values;
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, this.colors);

  final String label;
  final String value;
  final KalloColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KalloSpace.step3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: KalloType.caption.copyWith(color: colors.inkFaint),
          ),
          const SizedBox(height: 3),
          Text(value, style: KalloType.data.copyWith(color: colors.ink)),
        ],
      ),
    );
  }
}
