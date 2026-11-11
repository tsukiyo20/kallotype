import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';

/// The head of a frame's record: what it is, and which one of how many.
class RecordHeader extends StatelessWidget {
  const RecordHeader({super.key, required this.number, required this.total});

  final int number;
  final int total;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          s.frame,
          style: KalloType.caption.copyWith(color: colors.inkFaint),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              number.toString().padLeft(2, '0'),
              style: KalloType.plate.copyWith(color: colors.ink),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                s.ofFrames(total),
                style: KalloType.small.copyWith(color: colors.inkFaint),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rows of a record: the label on the left, the figure on the right, a
/// hairline between. Anything measured goes here, and nowhere else.
class RecordGroup extends StatelessWidget {
  const RecordGroup({super.key, required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
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
