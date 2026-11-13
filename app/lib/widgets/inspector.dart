import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/roll.dart';
import 'curves.dart';
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

  /// Whether the roll has a chart in it.
  ///
  /// A drawn chart and a measured one both belong on the panel: the committed
  /// strip is the model's drawing, and a roll the library developed carries a
  /// densitometer reading. The subprocess fallback writes pixels and no
  /// densities, and a chart with invented rows would be worse than no chart.
  bool get charted => roll.frames.every((Frame frame) => frame.hasChart);

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
            KalloCurves(
              series: <List<double>>[
                for (final Frame f in roll.frames) f.toneCurve!,
              ],
              selected: selected,
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
                    s.enlarge,
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
