import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'design/chrome.dart';
import 'design/scope.dart';
import 'design/strings.dart';
import 'design/tokens.dart';
import 'film/strip_data.dart';
import 'lab/exports.dart';
import 'lab/settings.dart';
import 'lab/fixture.dart';
import 'lab/print.dart';
import 'lab/print_out.dart';
import 'lab/model.dart';
import 'lab/roll.dart';
import 'lab/roll_store.dart';
import 'lab/stock.dart';
import 'views/places.dart';
import 'views/room.dart';

/// Whether the app opens the forty-frame layout fixture instead of the roll the
/// model drew. `fvm flutter run --dart-define=fixture`.
const bool _fixture = bool.fromEnvironment('fixture');

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
    this.catalogue,
    this.prints,
    this.jobs,
    this.exportsFolder,
    this.rollFolder,
    this.locale,
    this.appearance,
    this.spectral = false,
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

  /// Every stock the model carries. The tests pin it, so that a golden is a
  /// picture of the app rather than of the model binary on this machine; the app
  /// asks `kalo stocks --json` once, at the start.
  final Catalogue? catalogue;

  /// Prints to hang. The tests pass them; the app reads the export folder,
  /// which is empty until something has been printed.
  final List<Print>? prints;

  /// Prints in progress. The tests pin them; the app makes them.
  final List<PrintJob>? jobs;

  /// Where prints come from. The tests pin it, so that a golden does not show
  /// the folder of whoever ran it.
  final Directory? exportsFolder;

  /// Where the roll lives. Pinned by the tests for the same reason.
  final Directory? rollFolder;

  /// Pins the human language. Null follows the device, which is also what the
  /// drawer's first option does.
  final Locale? locale;

  /// Pins the appearance. Null follows the system.
  final Brightness? appearance;

  /// Whether a new roll is developed through the spectral path. The drawer's
  /// colour card sets it; the settings file remembers it.
  final bool spectral;

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
  late bool _spectral = widget.spectral;
  Roll? _roll;
  Catalogue? _catalogue;
  List<Print> _prints = const <Print>[];
  List<PrintJob> _jobs = const <PrintJob>[];
  Settings _settings = const Settings();
  String? _exportPath;

  @override
  void initState() {
    super.initState();
    _locale = widget.locale;
    _pinned = widget.appearance;
    _roll = widget.roll;
    _catalogue = widget.catalogue;
    if (_catalogue == null) {
      unawaited(_openCatalogue());
    }
    final List<Print>? prints = widget.prints;
    _jobs = widget.jobs ?? const <PrintJob>[];
    if (prints != null) {
      _prints = prints;
    } else {
      unawaited(_openExports());
    }
    if (_roll == null) {
      unawaited(_openRoll());
    }
  }

  /// What the model carries: one call, and the shelf is a shelf.
  ///
  /// It is asked once and held. The catalogue is the model's, not the app's, so
  /// it cannot be a constant in this file — and it is not worth re-reading,
  /// because it changes when the model is rebuilt, which is when the app is
  /// restarted.
  Future<void> _openCatalogue() async {
    final Catalogue catalogue = await Catalogue.load(Model.find());
    if (mounted) {
      setState(() => _catalogue = catalogue);
    }
  }

  /// The roll you were carrying, or the model's own chart when there is none.
  ///
  /// A roll that has been developed is on disk, and it is the one place the app
  /// is allowed to be full on purpose: a darkroom holds the roll you left in it.
  Future<void> _openRoll() async {
    final Roll? stored = await RollStore.load();
    if (stored != null) {
      if (mounted) {
        setState(() => _roll = stored);
      }
      return;
    }
    final StripData strip = await StripData.load();
    if (!mounted) {
      return;
    }
    setState(
      () => _roll = _fixture ? interpolatedRoll(strip) : Roll.fromStrip(strip),
    );
  }

  /// Make a print: render the frame at the size a print is, then hang it.
  ///
  /// The job goes on the list before the render starts, because a print that
  /// takes eight seconds is a print that is not finished, and the line is where
  /// a darkroom says so.
  Future<void> _print(Frame frame) async {
    final Roll? roll = _roll;
    final Directory? exports = _folder;
    if (roll == null || exports == null) {
      return;
    }
    final PrintJob job = PrintJob(frame: frame, exports: exports);
    setState(() => _jobs = <PrintJob>[job, ..._jobs]);
    try {
      await printFrame(
        roll: roll,
        frame: frame,
        exports: exports,
        paperName: roll.paperName(_catalogue ?? Catalogue.carried),
        stock: _catalogue?.film(roll.stockId),
      );
      await _reloadPrints();
    } finally {
      if (mounted) {
        setState(() => _jobs = <PrintJob>[
              for (final PrintJob other in _jobs)
                if (!identical(other, job)) other,
            ]);
      }
    }
  }

  void _developed(Roll roll) {
    final Roll? previous = _roll;
    setState(() => _roll = roll);
    if (previous == null || identical(previous, roll)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final Frame frame in previous.frames) {
        frame.image?.dispose();
      }
    });
  }

  /// Read the folder the person chose, and the prints in it.
  ///
  /// One after the other rather than together: where the prints are is the
  /// first question, and asking it twice at once would be two answers.
  Future<void> _openExports() async {
    _settings = await Settings.read();
    _exportPath = _settings.exportPath;
    _spectral = _settings.spectral;
    await _reloadPrints();
  }

  /// The path a roll is developed through. It is a new roll's setting, not a
  /// switch on the roll in the table: a roll is made one way.
  Future<void> _setSpectral(bool on) async {
    setState(() => _spectral = on);
    _settings = _settings.withSpectral(on);
    await _settings.write();
  }

  Future<void> _reloadPrints() async {
    final List<Print> prints = await Exports.read(folder: _folder);
    if (!mounted) {
      for (final Print print in prints) {
        print.dispose();
      }
      return;
    }
    final List<Print> previous = _prints;
    setState(() => _prints = prints);
    if (identical(previous, prints) || previous.isEmpty) {
      return;
    }
    // The frame that shows the new prints has to be drawn before the old
    // textures are freed: a picture that is disposed while it is on screen is
    // a picture that draws as nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final Print print in previous) {
        print.dispose();
      }
    });
  }

  Future<void> _chooseExport() async {
    final String? chosen;
    try {
      chosen = await Exports.choose();
    } on Exception catch (error) {
      // A panel that cannot open is a setting that cannot change. It is not
      // worth taking the window down for.
      debugPrint('no folder panel: $error');
      return;
    }
    if (chosen == null || !mounted) {
      return;
    }
    _exportPath = chosen;
    await _remember(chosen);
    await _reloadPrints();
  }

  Future<void> _resetExport() async {
    if (!mounted) {
      return;
    }
    setState(() => _exportPath = null);
    await _remember(null);
    await _reloadPrints();
  }

  Future<void> _remember(String? path) async {
    _settings = _settings.withExports(path);
    if (mounted) {
      setState(() {});
    }
    await _settings.write();
  }

  /// The folder prints come from, resolved once: the one the person chose, or
  /// the platform's own.
  Directory? get _folder =>
      widget.exportsFolder ?? Exports.directoryFor(_exportPath);

  /// What the drawer says about it.
  ExportSetting get _exportSetting => ExportSetting(
        label: Exports.display(_folder?.path),
        canChoose: Exports.canChoose,
        custom: _exportPath != null,
        onChoose: _chooseExport,
        onReset: _resetExport,
      );

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
              catalogue: _catalogue ?? Catalogue.carried,
              prints: _prints,
              exports: _folder,
              rollFolder: widget.rollFolder ?? RollStore.folder,
              onDeveloped: _developed,
              jobs: _jobs,
              onPrint: _print,
              onEnterExports:
                  widget.prints == null ? () => unawaited(_reloadPrints()) : null,
              export: _exportSetting,
              locale: _locale,
              onLocale: (Locale? next) => setState(() => _locale = next),
              spectral: _spectral,
              onSpectral: _setSpectral,
              initiallyOpen: widget.drawerOpen,
              initialPlace: widget.initialPlace,
              chrome: widget.chrome,
              onDragWindow: widget.onDragWindow,
            ),
    );
  }
}
