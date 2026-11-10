import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// A button.
///
/// Two of them, and they are the same shape: one sits on a field and one is the
/// action at the bottom of a column. Nothing else in the product is a button,
/// which is why this can be a hundred lines and not a system.
class KalloButton extends StatelessWidget {
  const KalloButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.height = 26,
  });

  final String label;
  final VoidCallback? onTap;

  /// Filled is the one action on a screen; bordered is everything else.
  final bool filled;

  final double height;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final bool enabled = onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: filled ? KalloSpace.step5 : KalloSpace.step3,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? colors.ink : colors.surface,
            borderRadius: BorderRadius.circular(
              filled ? KalloRadius.control : KalloRadius.control - 1,
            ),
            border: filled ? null : Border.all(color: colors.hairline),
          ),
          child: Text(
            label,
            style: KalloType.body.copyWith(
              fontSize: filled ? 12.5 : 12,
              fontWeight: filled ? FontWeight.w500 : FontWeight.w400,
              color: enabled
                  ? (filled ? colors.content : colors.ink)
                  : colors.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}
