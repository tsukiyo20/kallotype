import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// One choice, as a box on a shelf.
///
/// A film, a paper, a glass: a thing you can take. Taken, it is the one tinted
/// control on the page. Unselected, it is the window's recessed fill — not a
/// box of its own, because the shelf already has a surface.
class KalloChip extends StatefulWidget {
  const KalloChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.enabled = true,
    this.compact = false,
    this.semanticLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  /// A chip in a row of controls rather than a chip on a shelf.
  final bool compact;

  /// What a screen reader says. A chip under a maker's heading can say the
  /// product alone; the manufacturing is in the heading.
  final String? semanticLabel;

  @override
  State<KalloChip> createState() => _KalloChipState();
}

class _KalloChipState extends State<KalloChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final bool live = widget.enabled && widget.onTap != null;
    final Color background = !widget.enabled
        ? colors.fill.withValues(alpha: 0.45)
        : widget.selected
        ? colors.accent
        : _hover
        ? colors.fillStrong
        : colors.fill;
    final Color foreground = !widget.enabled
        ? colors.inkFaint
        : widget.selected
        ? colors.onAccent
        : colors.ink;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.semanticLabel ?? widget.label,
      child: MouseRegion(
        cursor: live ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: live ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: KalloMotion.instant,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 8 : 10,
              vertical: widget.compact ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(
                widget.compact ? KalloRadius.control - 1 : KalloRadius.control,
              ),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (widget.compact ? KalloType.small : KalloType.data)
                  .copyWith(
                    color: foreground,
                    fontWeight: widget.selected
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
