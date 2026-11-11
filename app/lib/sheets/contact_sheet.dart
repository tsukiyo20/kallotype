import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/roll.dart';
import '../widgets/patch_print.dart';

/// The roll, unrolled: a contact proof on the table.
///
/// A contact sheet is a print — the negative laid on paper, exposed, developed
/// — so the roll is one sheet and not a grid of cards: the frames sit on the
/// paper, their numbers and times are written on it, and the margin carries the
/// paper it was made on. That margin is the difference between a preview of the
/// prints and a proof of them. What the frames look like is the model's work;
/// that they are on this sheet, on this paper, is the thing the table could not
/// say before, and the reason a proof is worth making before a print.
///
/// The frames are a grid and not a strip. The roll is one frame at five times,
/// and a grid is the only arrangement that says nothing about which development
/// is the good one — a strip would impose an order the work does not have.
class ContactSheet extends StatelessWidget {
  const ContactSheet({
    super.key,
    required this.roll,
    required this.selected,
    required this.onSelect,
    this.paperName,
  });

  final Roll roll;
  final int selected;
  final ValueChanged<int> onSelect;

  /// The paper this sheet is, when the roll was printed on a known one.
  ///
  /// Null for a reversal, which has no print stage and so no paper: the margin
  /// then says nothing rather than naming a stock the roll was never printed
  /// on. A roll the model drew keeps the app's own paper, which is the paper
  /// its wedge was printed on.
  final String? paperName;

  /// The sheet's margin: the paper left around the frames.
  static const double _margin = 24;

  /// What the page leaves around the sheet, which is what makes it a sheet.
  static const double _page = 20;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return ColoredBox(
      color: colors.content,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          const double gap = 14;
          final double content =
              math.max(120, constraints.maxWidth - _page * 2 - _margin * 2);
          final int columns = switch (content) {
            > 950 => 4,
            > 430 => 3,
            _ => 2,
          };
          final double width = (content - gap * (columns - 1)) / columns;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(_page),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.print,
                border: Border.all(color: colors.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(_margin),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Wrap(
                      spacing: gap,
                      runSpacing: 18,
                      children: <Widget>[
                        for (int i = 0; i < roll.frames.length; i++)
                          _FrameTile(
                            frame: roll.frames[i],
                            width: width,
                            selected: i == selected,
                            onTap: () => onSelect(i),
                            paper: colors.print,
                          ),
                      ],
                    ),
                    if (paperName != null) ...<Widget>[
                      const SizedBox(height: KalloSpace.step5),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          paperName!,
                          style: KalloType.caption.copyWith(
                            color: KalloInk.faint,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One frame printed on the sheet.
///
/// There is no card and no corner: a frame on a contact print is a rectangle of
/// image on paper, and the only mark is the one a person would make — a box
/// around the development being considered, in the safelight's own colour.
class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.frame,
    required this.width,
    required this.selected,
    required this.onTap,
    required this.paper,
  });

  final Frame frame;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  /// The sheet's paper: what the model's wedge was printed on, when the frame
  /// has no image of its own.
  final Color paper;

  /// The gap between the mark and the frame, and the mark's own weight. A
  /// pencil does not touch the picture it is choosing.
  static const double _clearance = 3;
  static const double _mark = 1.5;

  @override
  Widget build(BuildContext context) {
    final double image = width - (_clearance + _mark) * 2;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(_clearance),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? KalloInk.accent : const Color(0x00000000),
                    width: _mark,
                  ),
                ),
                child: SizedBox(
                  width: image,
                  height: image / 1.5,
                  // A frame the app developed has a print; a frame the model
                  // drew has a chart. The sheet draws whichever it was given.
                  child: frame.image != null
                      ? RawImage(
                          image: frame.image,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        )
                      : PatchPrint(patches: frame.printColours(paper)!),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: <Widget>[
                Text(
                  frame.number.toString().padLeft(2, '0'),
                  style: KalloType.folio.copyWith(
                    color: selected ? KalloInk.accent : KalloInk.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  frame.clock,
                  style: KalloType.folio.copyWith(color: KalloInk.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
