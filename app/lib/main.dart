import 'package:flutter/widgets.dart';

import 'design/strings.dart';
import 'design/scope.dart';
import 'design/tokens.dart';
import 'film/strip_data.dart';
import 'lab/roll.dart';
import 'views/room.dart';

void main() => runApp(const KalloApp());

/// The app.
///
/// `WidgetsApp`, not `MaterialApp`: text direction, focus, overlay, semantics
/// and routing come from it, and nothing else does. Everything visible is the
/// product's own vocabulary.
class KalloApp extends StatefulWidget {
  const KalloApp({
    super.key,
    this.roll,
    this.locale,
    this.technicalTerms = false,
    this.drawerOpen = false,
  });

  /// A roll to open directly. The tests pass one; the app loads the committed
  /// strip, which is the only roll there is until the model is behind an FFI.
  final Roll? roll;

  /// Pins the human language. Null follows the device, which is also what the
  /// drawer's first option does.
  final Locale? locale;

  final bool technicalTerms;

  /// Opens the drawer on the first frame, for the golden that shows it.
  final bool drawerOpen;

  @override
  State<KalloApp> createState() => _KalloAppState();
}

class _KalloAppState extends State<KalloApp> {
  Locale? _locale;
  late bool _technical = widget.technicalTerms;
  Roll? _roll;

  @override
  void initState() {
    super.initState();
    _locale = widget.locale;
    _roll = widget.roll;
    if (_roll == null) {
      StripData.load().then((StripData strip) {
        if (!mounted) {
          return;
        }
        setState(() => _roll = Roll.fromStrip(strip));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const KalloColors colors = KalloColors.lightTable;
    return WidgetsApp(
      title: 'Kallotype',
      color: colors.ground,
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: KalloStrings.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        KalloStrings.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      // There are no page transitions in this product: you move between places
      // by changing the light and moving the camera, never by pushing a route.
      // The one route that exists comes and goes in no time.
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (BuildContext context, Animation<double> animation,
                Animation<double> secondary) =>
            builder(context),
      ),
      builder: (BuildContext context, Widget? child) => KalloScope(
        colors: colors,
        environment: KalloEnvironment.lightTable,
        child: DefaultTextStyle(
          style: KalloType.body.copyWith(color: colors.ink),
          child: child!,
        ),
      ),
      home: _roll == null
          ? const ColoredBox(color: Color(0xFFF5F1E9))
          : Room(
              roll: _roll!,
              locale: _locale,
              onLocale: (Locale? next) => setState(() => _locale = next),
              technicalTerms: _technical,
              onTechnicalTerms: (bool next) =>
                  setState(() => _technical = next),
              initiallyOpen: widget.drawerOpen,
            ),
    );
  }
}
