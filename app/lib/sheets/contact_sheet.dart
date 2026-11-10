import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/roll.dart';
import '../widgets/patch_print.dart';

/// The roll, unrolled: a contact sheet on the table.
///
/// A contact sheet is a print — the negative laid on paper, exposed, developed
/// — so every frame here is a positive, printed for its own highlights.
class ContactSheet extends StatelessWidget {
  const ContactSheet({
    super.key,
    required this.roll,
    required this.selected,
    required this.onSelect,
  });

  final Roll roll;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return ColoredBox(
      color: colors.content,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = switch (constraints.maxWidth) {
            > 1000 => 4,
            > 480 => 3,
            _ => 2,
          };
          const double gap = 14;
          final double width =
              (constraints.maxWidth - 40 - gap * (columns - 1)) / columns;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Wrap(
              spacing: gap,
              runSpacing: 18,
              children: <Widget>[
                for (int i = 0; i < roll.frames.length; i++)
                  _FrameTile(
                    frame: roll.frames[i],
                    width: width,
                    selected: i == selected,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.frame,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final Frame frame;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
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
              child: AnimatedContainer(
                duration: KalloMotion.instant,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.print,
                  borderRadius: BorderRadius.circular(KalloRadius.film + 1),
                  border: Border.all(
                    color: selected ? colors.accent : colors.hairline,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(KalloRadius.film),
                  child: AspectRatio(
                    aspectRatio: 3 / 2,
                    child: PatchPrint(patches: frame.printColours(colors.print)),
                  ),
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
                    color: selected ? colors.accent : colors.inkMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  frame.clock,
                  style: KalloType.folio.copyWith(color: colors.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


