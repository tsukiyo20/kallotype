import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Carries the colours of wherever we currently are.
///
/// It carries [KalloColors] rather than a [KalloEnvironment] because the app
/// animates between the two environments, and an enum cannot be half way
/// between two rooms.
class KalloScope extends InheritedWidget {
  const KalloScope({
    super.key,
    required this.colors,
    required this.environment,
    required super.child,
  });

  final KalloColors colors;

  /// Where we are heading. During the transition the colours are between the
  /// two, and this says which of the two they are being asked about.
  final KalloEnvironment environment;

  bool get isLit => environment == KalloEnvironment.lightTable;

  static KalloScope of(BuildContext context) {
    final KalloScope? scope =
        context.dependOnInheritedWidgetOfExactType<KalloScope>();
    assert(scope != null, 'No KalloScope above this widget.');
    return scope!;
  }

  static KalloColors colorsOf(BuildContext context) => of(context).colors;

  @override
  bool updateShouldNotify(KalloScope oldWidget) =>
      !identical(oldWidget.colors, colors) ||
      oldWidget.environment != environment;
}
