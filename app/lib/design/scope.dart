import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Carries the appearance of the window.
///
/// One set of colours, resolved: light or dark. The system decides unless the
/// user pinned one in the drawer, and the resolution happens once, at the top,
/// so that nothing below has to ask what time it is.
///
/// A room's lamp is not here. The gallery has one, and it dims the wall and the
/// work — not the window around them, which is why the light is passed to the
/// gallery and not to every plane.
class KalloScope extends InheritedWidget {
  const KalloScope({
    super.key,
    required this.colors,
    required this.pinned,
    required this.onPin,
    required super.child,
  });

  final KalloColors colors;

  /// What the user pinned, or null when the window follows the system.
  final Brightness? pinned;

  /// Pins an appearance, or hands it back to the system with null.
  final ValueChanged<Brightness?> onPin;

  Brightness get brightness => colors.brightness;

  static KalloScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KalloScope>();

  static KalloScope of(BuildContext context) {
    final KalloScope? scope = maybeOf(context);
    assert(scope != null, 'No KalloScope above this widget.');
    return scope!;
  }

  static KalloColors colorsOf(BuildContext context) => of(context).colors;

  @override
  bool updateShouldNotify(KalloScope oldWidget) =>
      !identical(oldWidget.colors, colors) || oldWidget.pinned != pinned;
}
