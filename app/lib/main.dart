import 'package:flutter/widgets.dart';

import 'design/scope.dart';
import 'design/strings.dart';
import 'design/tokens.dart';
import 'film/strip_data.dart';
import 'lab/fixture.dart';
import 'lab/roll.dart';
import 'views/room.dart';

/// Whether the app opens the forty-frame layout fixture instead of the roll the
/// model drew. `fvm flutter run --dart-define=roll=36`.
const bool _fixture = bool.fromEnvironment('roll36');

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
    this.appearance,
    this.technicalTerms = false,
    this.drawerOpen = false,
  });

  /// A roll to open directly. The tests pass one; the app loads the committed
  /// strip, which is the only roll there is until the model is behind an FFI.
  final Roll? roll;

  /// Pins the human language. Null follows the device, which is also what the
  /// drawer's first option does.
  final Locale? locale;

  /// Pins the appearance. Null follows the system.
  final Brightness? appearance;

  final bool technicalTerms;

  /// Opens the drawer on the first frame, for the golden that shows it.
  final bool drawerOpen;

  @override
  State<KalloApp> createState() => _KalloAppState();
}

class _KalloAppState extends State<KalloApp> {
  Locale? _locale;
  Brightness? _pinned;
  late bool _technical = widget.technicalTerms;
  Roll? _roll;

  @override
  void initState() {
    super.initState();
    _locale = widget.locale;
    _pinned = widget.appearance;
    _roll = widget.roll;
    if (_roll == null) {
      StripData.load().then((StripData strip) {
        if (!mounted) {
          return;
        }
        setState(() => _roll = _fixture ? interpolatedRoll(strip) : Roll.fromStrip(strip));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Kallotype',
      color: KalloColors.light.ground,
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
      builder: (BuildContext context, Widget? child) {
        // Following the system is read here and nowhere else: `MediaQuery`
        // rebuilds when the platform changes its appearance, so pinning one in
        // the drawer is the only other input.
        final Brightness resolved =
            _pinned ?? MediaQuery.platformBrightnessOf(context);
        final KalloColors colors = KalloColors.of(resolved);
        return KalloScope(
          colors: colors,
          pinned: _pinned,
          onPin: (Brightness? next) => setState(() => _pinned = next),
          child: DefaultTextStyle(
            style: KalloType.body.copyWith(color: colors.ink),
            child: child!,
          ),
        );
      },
      home: _roll == null
          ? const ColoredBox(color: Color(0xFFF6F5F2))
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
