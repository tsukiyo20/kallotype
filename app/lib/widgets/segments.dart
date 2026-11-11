import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// Choices laid on a track, one of them lifted.
///
/// The Apple control, at this product's size: a recessed track, a raised
/// segment, and no other ornament. It is used where the options are a fact
/// rather than a menu — an appearance, a language, a development.
class KalloSegments extends StatelessWidget {
  const KalloSegments({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.quiet = false,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Quiet segments do not lift: they are a scale with a mark on it, not a
  /// control with a chosen value.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: BorderRadius.circular(KalloRadius.control + 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: KalloMotion.quick,
                curve: KalloMotion.enter,
                padding: const EdgeInsets.symmetric(
                  horizontal: KalloSpace.step3 + 2,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  // A selected segment has to lift off its track in both
                  // appearances: white on light, a lit grey on dark.
                  color: i == selected && !quiet
                      ? Color.lerp(colors.surface, colors.ink, 0.09)
                      : null,
                  borderRadius: BorderRadius.circular(KalloRadius.control),
                  boxShadow: i == selected && !quiet
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  options[i],
                  style: KalloType.body.copyWith(
                    fontSize: 12.5,
                    fontWeight:
                        i == selected ? FontWeight.w500 : FontWeight.w400,
                    color: i == selected ? colors.ink : colors.inkMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
