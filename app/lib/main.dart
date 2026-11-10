import 'package:flutter/widgets.dart';

import 'design/scope.dart';
import 'design/tokens.dart';
import 'film/strip_data.dart';
import 'lab/roll.dart';
import 'sheets/contact_sheet.dart';

void main() => runApp(const KalloApp());

/// The app.
///
/// `WidgetsApp`, not `MaterialApp`: text direction, focus, overlay, semantics
/// and routing come from it, and nothing else does. Everything visible is the
/// product's own vocabulary.
class KalloApp extends StatelessWidget {
  const KalloApp({super.key, this.roll});

  /// A roll to open directly. The tests pass one; the app loads the committed
  /// strip, which is the only roll there is until the model is behind an FFI.
  final Roll? roll;

  @override
  Widget build(BuildContext context) {
    const KalloColors colors = KalloColors.lightTable;
    return WidgetsApp(
      title: 'Kallotype',
      color: colors.ground,
      debugShowCheckedModeBanner: false,
      builder: (BuildContext context, Widget? child) => KalloScope(
        colors: colors,
        environment: KalloEnvironment.lightTable,
        child: DefaultTextStyle(
          style: KalloType.body.copyWith(color: colors.ink),
          child: child!,
        ),
      ),
      // There are no page transitions in this product: you move between
      // places by changing the light and moving the camera, never by pushing
      // a route. The one route that exists comes and goes in no time.
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (BuildContext context, Animation<double> animation,
                Animation<double> secondary) =>
            builder(context),
      ),
      home: roll == null ? const _Opening() : SheetScreen(roll: roll!),
    );
  }
}

/// The table, before the roll is on it.
class _Opening extends StatefulWidget {
  const _Opening();

  @override
  State<_Opening> createState() => _OpeningState();
}

class _OpeningState extends State<_Opening> {
  late final Future<Roll> _roll = StripData.load().then(
    (StripData strip) => Roll.fromStrip(strip),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Roll>(
      future: _roll,
      builder: (BuildContext context, AsyncSnapshot<Roll> snapshot) {
        if (snapshot.hasError) {
          return ColoredBox(
            color: KalloScope.colorsOf(context).ground,
            child: Center(
              child: Text(
                'The strip did not load: ${snapshot.error}',
                style: KalloType.body.copyWith(
                  color: KalloScope.colorsOf(context).inkMuted,
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return ColoredBox(color: KalloScope.colorsOf(context).ground);
        }
        return SheetScreen(roll: snapshot.data!);
      },
    );
  }
}
