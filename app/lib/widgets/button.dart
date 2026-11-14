import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// A button.
///
/// Two of them, and they are the same shape: one action on a page, filled with
/// the safelight; everything else, filled with the window's own grey. No
/// outline, no ripple: a mac button changes its fill under the pointer.
class KalloButton extends StatelessWidget {
  const KalloButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.height = 30,
  });

  final String label;
  final VoidCallback? onTap;

  /// Filled is the one action on a screen; quiet is everything else.
  final bool filled;

  final double height;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final bool enabled = onTap != null;
    return _ButtonBody(
      label: label,
      onTap: onTap,
      filled: filled,
      height: height,
      enabled: enabled,
      colors: colors,
    );
  }
}

class _ButtonBody extends StatefulWidget {
  const _ButtonBody({
    required this.label,
    required this.onTap,
    required this.filled,
    required this.height,
    required this.enabled,
    required this.colors,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final double height;
  final bool enabled;
  final KalloColors colors;

  @override
  State<_ButtonBody> createState() => _ButtonBodyState();
}

class _ButtonBodyState extends State<_ButtonBody> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = widget.colors;
    final Color background = !widget.enabled
        ? (widget.filled ? colors.fill : colors.fill.withValues(alpha: 0.55))
        : widget.filled
        ? colors.accent
        : _hover
        ? colors.fillStrong
        : colors.fill;
    final Color foreground = !widget.enabled
        ? colors.inkFaint
        : widget.filled
        ? colors.onAccent
        : colors.ink;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: KalloMotion.instant,
          height: widget.height,
          padding: EdgeInsets.symmetric(
            horizontal: widget.filled ? KalloSpace.step5 : KalloSpace.step4,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(KalloRadius.control),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KalloType.body.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
