import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/contact.dart';
import '../lab/roll.dart';
import '../widgets/patch_print.dart';

/// The roll, unrolled: the contact proof on the table.
///
/// A contact proof is a print — the film laid on paper, exposed once, developed
/// — so the table shows the model's print of it: one sheet, five strips, the
/// clear rebate printed black and the edge codes printed light. The app adds
/// only what a person adds to a print: a pencil box around the development
/// being considered, and the paper's name in the sheet's own margin.
///
/// The proof is not drawn here and cannot be. Its one exposure is the thing it
/// has to say, and a frame at a time — each at its own exposure, which is what
/// the drawings and the exports are — would say the opposite. The model prints
/// it; the record beside the print says where the frames are, so the app scales
/// a print instead of laying one out.
///
/// A roll the model drew has no negative, and a roll developed before the proof
/// existed has no sheet: those fall back to the chart, frames on paper in a
/// grid. A grid is the right arrangement for a chart — five rows of numbers say
/// nothing about which one is the good one — and the wrong one for a proof.
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
    final ContactProof? proof = roll.contact;
    if (proof != null) {
      return _ProofSheet(
        proof: proof,
        roll: roll,
        selected: selected,
        onSelect: onSelect,
        paperName: paperName,
      );
    }
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

/// The model's proof, on the table.
///
/// A contact proof is one sheet of paper, exposed once under the whole ladder.
/// The table shows the print itself — not a redrawing of it — so the only thing
/// the app adds is what a person adds to a print: a pencil box around the
/// development being considered, and the paper's name in its own margin.
class _ProofSheet extends StatelessWidget {
  const _ProofSheet({
    required this.proof,
    required this.roll,
    required this.selected,
    required this.onSelect,
    this.paperName,
  });

  final ContactProof proof;
  final Roll roll;
  final int selected;
  final ValueChanged<int> onSelect;

  /// The paper the proof was made on, written in its margin.
  final String? paperName;

  /// What the page leaves around the sheet, which is what makes it a sheet.
  static const double _page = 20;

  /// The box's clearance and weight: a pencil does not touch the picture it is
  /// choosing.
  static const double _clearance = 4;
  static const double _mark = 1.5;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return ColoredBox(
      color: colors.content,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double available =
              math.max(240, constraints.maxWidth - _page * 2);
          final double scale = available / proof.pixels.width;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(_page),
            child: Center(
              child: SizedBox(
                width: proof.pixels.width * scale,
                height: proof.pixels.height * scale,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (TapUpDetails details) => _choose(details, scale),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: RawImage(
                          image: proof.image,
                          fit: BoxFit.fill,
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: colors.hairline),
                            ),
                          ),
                        ),
                      ),
                      for (final ContactFrame frame in proof.frames)
                        if (roll.frames.length > selected &&
                            roll.frames[selected].number == frame.number)
                          Positioned.fromRect(
                            rect: Rect.fromLTWH(
                              frame.rect.left * scale - _clearance,
                              frame.rect.top * scale - _clearance,
                              frame.rect.width * scale + _clearance * 2,
                              frame.rect.height * scale + _clearance * 2,
                            ),
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: KalloInk.accent, width: _mark),
                                ),
                              ),
                            ),
                          ),
                      if (paperName != null)
                        Positioned(
                          right: proof.paperMargin * scale * 0.5,
                          bottom: proof.paperMargin * scale * 0.45,
                          child: IgnorePointer(
                            child: Text(
                              paperName!,
                              style: KalloType.caption.copyWith(
                                color: KalloInk.faint,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// A tap picks the development it landed on, if it landed on one.
  void _choose(TapUpDetails details, double scale) {
    final Offset at = details.localPosition / scale;
    for (final ContactFrame frame in proof.frames) {
      if (!frame.rect.contains(at)) {
        continue;
      }
      final int index =
          roll.frames.indexWhere((Frame candidate) => candidate.number == frame.number);
      if (index >= 0) {
        onSelect(index);
      }
      return;
    }
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
