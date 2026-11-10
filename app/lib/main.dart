import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'design/chrome.dart';
import 'design/scope.dart';
import 'design/strings.dart';
import 'design/tokens.dart';
import 'film/strip_data.dart';
import 'lab/fixture.dart';
import 'lab/print.dart';
import 'lab/roll.dart';
import 'views/places.dart';
import 'views/room.dart';

/// Whether the app opens the forty-frame layout fixture instead of the roll the
/// model drew. `fvm flutter run --dart-define=roll=36`.
const bool _fixture = bool.fromEnvironment('roll36');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bool desktop =
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  if (desktop) {
    await windowManager.ensureInitialized();
    final WindowOptions options = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(960, 600),
      center: true,
      title: 'Kallotype',
      // The Mac keeps its traffic lights and loses its bar; the other two keep
      // their frames until they have controls of their own, because a window
      // with no way to close it is a bug, not a style.
      titleBarStyle:
          Platform.isMacOS ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );
    unawaited(windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    }));
  }
  runApp(
    KalloApp(
      chrome: Platform.isMacOS ? WindowChrome.mac : WindowChrome.plain,
      onDragWindow: desktop ? windowManager.startDragging : null,
    ),
  );
}

/// The app.
///
/// `WidgetsApp`, not `MaterialApp`: text direction, focus, overlay, semantics
/// and routing come from it, and nothing else does. Everything visible is the
/// product's own vocabulary.
class KalloApp extends StatefulWidget {
  const KalloApp({
    super.key,
    this.roll,
    this.print,
    this.locale,
    this.appearance,
    this.technicalTerms = false,
    this.drawerOpen = false,
    this.initialPlace = Place.table,
    this.chrome = WindowChrome.plain,
    this.onDragWindow,
  });

  /// What the window looks like around the app.
  final WindowChrome chrome;

  /// Moves the window, when the chrome has no title bar of its own.
  final VoidCallback? onDragWindow;

  /// A roll to open directly. The tests pass one; the app loads the committed
  /// strip, which is the only roll there is until the model is behind an FFI.
  final Roll? roll;

  /// A print to hang. The tests pass one; the app loads the committed print,
  /// which is the only one there is until the model is behind an FFI.
  final Print? print;

  /// Pins the human language. Null follows the device, which is also what the
  /// drawer's first option does.
  final Locale? locale;

  /// Pins the appearance. Null follows the system.
  final Brightness? appearance;

  final bool technicalTerms;

  /// Opens the drawer on the first frame, for the golden that shows it.
  final bool drawerOpen;

  /// The place to open on. The app opens on the table; the goldens ask.
  final Place initialPlace;

  @override
  State<KalloApp> createState() => _KalloAppState();
}

class _KalloAppState extends State<KalloApp> {
  Locale? _locale;
  Brightness? _pinned;
  late bool _technical = widget.technicalTerms;
  Roll? _roll;
  Print? _print;

  @override
  void initState() {
    super.initState();
    _locale = widget.locale;
    _pinned = widget.appearance;
    _roll = widget.roll;
    _print = widget.print;
    if (_print == null) {
      Print.load(rootBundle).then(
        (Print print) {
          if (mounted) {
            setState(() => _print = print);
          }
        },
        // A missing print is an empty wall, not a broken window: the gallery is
        // a place you can be in with nothing hung in it.
        onError: (Object error) => debugPrint('no print to hang: $error'),
      );
    }
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
              print: _print,
              locale: _locale,
              onLocale: (Locale? next) => setState(() => _locale = next),
              technicalTerms: _technical,
              onTechnicalTerms: (bool next) =>
                  setState(() => _technical = next),
              initiallyOpen: widget.drawerOpen,
              initialPlace: widget.initialPlace,
              chrome: widget.chrome,
              onDragWindow: widget.onDragWindow,
            ),
    );
  }
}
