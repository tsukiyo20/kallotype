import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';

/// Which edge of the window a pane control belongs to.
enum PaneSide { left, right }

/// The window's one piece of chrome.
///
/// It is not a toolbar: there is no bar, no fill and no rule under it. Two
/// controls and, in the darkroom, the step capsule float over the work, which
/// runs to the top edge of the window. The buttons are glass because they sit
/// on whatever is underneath — a white bench, a black wall, a photograph.
class StudioTopBar extends StatelessWidget {
  const StudioTopBar({
    super.key,
    required this.sidebarOpen,
    required this.onSidebar,
    required this.mac,
    this.inspectorOpen,
    this.onInspector,
    this.trailing,
    this.center,
    this.onDragWindow,
    this.height = 56,
    this.rightInset = 0,
  });

  final bool sidebarOpen;
  final VoidCallback onSidebar;

  /// Whether the window has traffic lights over its top-left corner.
  final bool mac;

  /// The inspector, when the room has one.
  final bool? inspectorOpen;
  final VoidCallback? onInspector;

  /// A room's own control at the right edge, where there is no inspector. The
  /// gallery puts its lamp here.
  final Widget? trailing;

  /// The capsule in the middle of the bar: the darkroom's steps, or a room's
  /// name.
  final Widget? center;

  final VoidCallback? onDragWindow;
  final double height;

  /// The width the inspector takes. The capsule centres over the bench, not
  /// over the inspector that belongs to it.
  final double rightInset;

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    // With the sidebar shut the content starts at the window's edge, where the
    // traffic lights live. The one control steps over them; it does not sit
    // underneath them.
    final double left = mac && !sidebarOpen ? 84 : 16;
    return SizedBox(
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: onDragWindow == null ? null : (_) => onDragWindow!(),
        child: Stack(
          children: <Widget>[
            if (center != null)
              AnimatedPositioned(
                duration: KalloMotion.settle,
                curve: KalloMotion.enter,
                left: 0,
                right: rightInset,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: center,
                  ),
                ),
              ),
            AnimatedPositioned(
              duration: KalloMotion.settle,
              curve: KalloMotion.enter,
              left: left,
              top: (height - 34) / 2,
              child: PaneButton(
                key: const Key('sidebar-toggle'),
                side: PaneSide.left,
                open: sidebarOpen,
                label: sidebarOpen ? s.hideSidebar : s.showSidebar,
                onTap: onSidebar,
              ),
            ),
            if (trailing != null)
              Positioned(
                right: 16,
                top: (height - 30) / 2,
                child: trailing!,
              )
            else if (onInspector != null)
              Positioned(
                right: 16,
                top: (height - 34) / 2,
                child: PaneButton(
                  key: const Key('inspector-toggle'),
                  side: PaneSide.right,
                  open: inspectorOpen ?? true,
                  label: (inspectorOpen ?? true)
                      ? s.hideInspector
                      : s.showInspector,
                  onTap: onInspector!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
