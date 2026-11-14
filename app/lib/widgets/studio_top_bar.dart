import 'package:flutter/widgets.dart';

import '../design/strings.dart';
import '../design/tokens.dart';
import 'pane_button.dart';

/// The window's one piece of chrome.
///
/// It is not a toolbar: there is no bar, no fill and no rule under it. The pane
/// controls and, in the darkroom, the step capsule float over the work, which
/// runs to the top edge of the window. The buttons are glass because they sit
/// on whatever is underneath — a white bench, a black wall, a photograph. The
/// sidebar's switch lives with the sidebar while it is open, so only the
/// inspector's remains here at that edge.
class StudioTopBar extends StatelessWidget {
  const StudioTopBar({
    super.key,
    required this.sidebarOpen,
    required this.onSidebar,
    required this.mac,
    this.showSidebar = true,
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

  /// Whether this window has a sidebar at all. A phone keeps its places in a
  /// bottom bar, so the pane switch would have nothing to put away.
  final bool showSidebar;

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
    // The open sidebar carries its own switch. With it shut, the content
    // starts at the window's edge, where the traffic lights live: the one
    // control steps over them rather than sitting underneath.
    final double left = mac ? 84 : 16;
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
            if (showSidebar && !sidebarOpen)
              AnimatedPositioned(
                duration: KalloMotion.settle,
                curve: KalloMotion.enter,
                left: left,
                top: (height - 34) / 2,
                child: PaneButton(
                  key: const Key('sidebar-toggle'),
                  side: PaneSide.left,
                  open: false,
                  label: s.showSidebar,
                  onTap: onSidebar,
                ),
              ),
            if (trailing != null)
              Positioned(right: 16, top: (height - 30) / 2, child: trailing!)
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
