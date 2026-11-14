import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// Which edge of the window a pane control belongs to.
enum PaneSide { left, right }

/// A pane's switch: a small glass capsule with a split-pane mark.
class PaneButton extends StatefulWidget {
  const PaneButton({
    super.key,
    required this.side,
    required this.open,
    required this.label,
    required this.onTap,
  });

  final PaneSide side;
  final bool open;
  final String label;
  final VoidCallback onTap;

  @override
  State<PaneButton> createState() => _PaneButtonState();
}

class _PaneButtonState extends State<PaneButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final Color ink = _hover ? colors.ink : colors.inkMuted;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: KalloMotion.instant,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _hover
                  ? colors.fillStrong.withValues(alpha: 0.92)
                  : colors.fill.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(KalloRadius.pill),
              border: Border.all(
                color: colors.hairline.withValues(alpha: _hover ? 0.9 : 0.55),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KalloRadius.pill),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Center(
                  child: CustomPaint(
                    size: const Size(18, 18),
                    painter: _PanePainter(
                      side: widget.side,
                      open: widget.open,
                      ink: ink,
                      accent: colors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanePainter extends CustomPainter {
  const _PanePainter({
    required this.side,
    required this.open,
    required this.ink,
    required this.accent,
  });

  final PaneSide side;
  final bool open;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(1.5, 3.5, 15, 11),
      const Radius.circular(2.6),
    );
    if (open) {
      final Rect pane = side == PaneSide.left
          ? const Rect.fromLTRB(1.5, 3.5, 7.0, 14.5)
          : const Rect.fromLTRB(11.0, 3.5, 16.5, 14.5);
      canvas.save();
      canvas.clipRRect(frame);
      canvas.drawRect(pane, Paint()..color = accent.withValues(alpha: 0.30));
      canvas.restore();
    }
    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = ink,
    );
    final double divider = side == PaneSide.left ? 7.0 : 11.0;
    canvas.drawLine(
      Offset(divider, 3.5),
      Offset(divider, 14.5),
      Paint()
        ..strokeWidth = 1.2
        ..color = open ? accent : ink.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_PanePainter old) =>
      old.side != side ||
      old.open != open ||
      old.ink != ink ||
      old.accent != accent;
}
