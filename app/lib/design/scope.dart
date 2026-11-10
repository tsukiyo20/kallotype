import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Carries the appearance of the window, and how much light is on it.
///
/// One set of colours, resolved: light or dark. The system decides unless the
/// user pinned one in the drawer, and the resolution happens once, at the top,
/// so that nothing below has to ask what time it is.
///
/// The light is a second, smaller fact: a room can have its lamp off without
/// changing its appearance. The gallery is the room that does, and it is why
/// this is a number and not a flag — a light comes up, it does not switch.
class KalloScope extends InheritedWidget {
  const KalloScope({
    super.key,
    required this.colors,
    required this.pinned,
    required this.onPin,
    this.light = 1,
    required super.child,
  });

  final KalloColors colors;

  /// What the user pinned, or null when the window follows the system.
  final Brightness? pinned;

  /// Pins an appearance, or hands it back to the system with null.
  final ValueChanged<Brightness?> onPin;

  /// How much light is on the room, from none to all of it. The colour set has
  /// already been dimmed by it; this is for what is not a plane — a print, a
  /// notice on the wall.
  final double light;

  Brightness get brightness => colors.brightness;

  static KalloScope of(BuildContext context) {
    final KalloScope? scope =
        context.dependOnInheritedWidgetOfExactType<KalloScope>();
    assert(scope != null, 'No KalloScope above this widget.');
    return scope!;
  }

  static KalloColors colorsOf(BuildContext context) => of(context).colors;

  static double lightOf(BuildContext context) => of(context).light;

  @override
  bool updateShouldNotify(KalloScope oldWidget) =>
      !identical(oldWidget.colors, colors) ||
      oldWidget.pinned != pinned ||
      oldWidget.light != light;
}
