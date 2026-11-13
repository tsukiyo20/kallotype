import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// One choice, as a box on a shelf.
///
/// A film, a paper, a glass: a thing you can take. Taken, it is the dark one —
/// filled with ink rather than outlined, because the accent is the safelight's
/// and a material is not a selection of a frame.
class KalloChip extends StatelessWidget {
  const KalloChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.enabled = true,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  /// A chip in a row of controls rather than a chip on a shelf.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final bool live = enabled && onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: MouseRegion(
        cursor: live ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: live ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 7 : 10,
              vertical: compact ? 3 : 6,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? colors.ink
                  : enabled
                  ? colors.ground
                  : colors.ground.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(KalloRadius.film),
              border: Border.all(
                color: selected
                    ? colors.ink
                    : enabled
                    ? colors.hairline
                    : colors.hairline.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              label,
              style: (compact ? KalloType.small : KalloType.data).copyWith(
                color: selected
                    ? colors.content
                    : enabled
                    ? colors.ink
                    : colors.inkFaint,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
