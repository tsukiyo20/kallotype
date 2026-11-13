import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'design/chrome.dart';
import 'design/scope.dart';
import 'design/strings.dart';
import 'design/tokens.dart';
import 'lab/exports.dart';
import 'lab/ffi_model.dart';
import 'lab/image_file.dart';
import 'lab/model.dart';
import 'lab/print.dart';
import 'lab/print_out.dart';
import 'lab/print_request.dart';
import 'lab/roll.dart';
import 'lab/roll_store.dart';
import 'lab/settings.dart';
import 'lab/stock.dart';
import 'lab/strip.dart';
import 'lab/strip_develop.dart';
import 'lab/strip_store.dart';
import 'views/chambers.dart';
import 'views/steps.dart';
import 'views/studio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The model is a library the app carries; if it cannot load, the subprocess
  // path is still there and the app says so in the console.
  await loadLinkedModel();
  final bool desktop =
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  if (desktop) {
    await windowManager.ensureInitialized();
    // A window that is wider than the screen loses its instrument panel off
    // the right edge. 1280 by 820 is the size the design is drawn at; it is
    // capped to the display it actually opens on.
    Size size = const Size(1280, 820);
    try {
      final Display display = await screenRetriever.getPrimaryDisplay();
      final Size visible = display.visibleSize ?? display.size;
      size = Size(
        math.max(960, math.min(1280, visible.width - 64)),
        math.max(600, math.min(820, visible.height - 120)),
      );
    } on Object catch (error) {
      debugPrint('no display size: $error');
    }
    final WindowOptions options = WindowOptions(
      size: size,
      minimumSize: Size(960, 600),
      center: true,
      title: 'Kallotype',
      // The Mac keeps its traffic lights and loses its bar; the other two keep
      // their frames until they have controls of their own, because a window
      // with no way to close it is a bug, not a style.
      titleBarStyle: Platform.isMacOS
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
    );
    unawaited(
      windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
      }),
    );
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
    this.strip,
    this.photograph,
    this.catalogue,
    this.prints,
    this.jobs,
    this.exportsFolder,
    this.locale,
    this.appearance,
    this.spectral = false,
    this.drawerOpen = false,
    this.initialChamber = Chamber.darkroom,
    this.initialStep = DarkroomStep.select,
    this.chrome = WindowChrome.plain,
    this.onDragWindow,
  });

  /// What the window looks like around the app.
  final WindowChrome chrome;

  /// Moves the window, when the chrome has no title bar of its own.
  final VoidCallback? onDragWindow;

  /// A strip to open directly. The tests pass one; the app reads the strip on
  /// disk, which is the one in the darkroom.
  final TestStrip? strip;

  /// The original photograph, already decoded. The tests pass it; the app
  /// decodes the photograph the strip keeps.
  final ui.Image? photograph;

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

  /// Pins the human language. Null follows the device, which is also what the
  /// drawer's first option does.
  final Locale? locale;

  /// Pins the appearance. Null follows the system.
  final Brightness? appearance;

  /// Whether a new strip is exposed through the spectral path. The drawer's
  /// colour card sets it; the settings file remembers it.
  final bool spectral;

  /// Opens the drawer on the first frame, for the golden that shows it.
  final bool drawerOpen;

  final Chamber initialChamber;
  final DarkroomStep initialStep;

  @override
  State<KalloApp> createState() => _KalloAppState();
}

class _KalloAppState extends State<KalloApp> {
  Locale? _locale;
  Brightness? _pinned;
  late bool _spectral = widget.spectral;
  TestStrip? _strip;
  ui.Image? _photograph;
  bool _ownsPhotograph = false;
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
    _strip = widget.strip;
    _photograph = widget.photograph;
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
    if (_strip == null) {
      unawaited(_openStrip());
    } else if (_photograph == null) {
      unawaited(_openPhotograph(_strip!));
    }
  }

  @override
  void dispose() {
    if (_ownsPhotograph) {
      _photograph?.dispose();
    }
    super.dispose();
  }

  /// What the model carries: one call, and the shelf is a shelf.
  Future<void> _openCatalogue() async {
    final Catalogue catalogue = await Catalogue.load(Model.find());
    if (mounted) {
      setState(() => _catalogue = catalogue);
    }
  }

  /// The strip you were making, or the photograph the last roll kept.
  Future<void> _openStrip() async {
    TestStrip? stored;
    try {
      stored = await StripStore.load();
    } on Object catch (error) {
      Model.log('the strip could not be read: $error');
    }
    if (stored == null) {
      final Roll? roll = await RollStore.load();
      if (roll != null) {
        stored = TestStrip(
          photo: roll.photo,
          stockId: roll.stockId,
          stockLabel: roll.stockLabel,
          paperId: roll.paperId,
          paperLabel: roll.paperLabel,
          spectral: roll.spectral,
        );
        await StripStore.save(stored);
      }
    }
    stored ??= const TestStrip();
    if (!mounted) {
      return;
    }
    setState(() => _strip = stored);
    await _openPhotograph(stored);
  }

  Future<void> _openPhotograph(TestStrip strip) async {
    final String? path = strip.photo;
    if (path == null) {
      return;
    }
    final File file = File(path);
    if (!file.existsSync()) {
      return;
    }
    try {
      final ui.Image image = await decode(file, width: 1600);
      if (!mounted) {
        image.dispose();
        return;
      }
      final ui.Image? old = _ownsPhotograph ? _photograph : null;
      setState(() {
        _photograph = image;
        _ownsPhotograph = true;
      });
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } on Object catch (error) {
      Model.log('the photograph could not be read: $error');
    }
  }

  /// Choose a photograph: copy it into the strip's folder, decode it, and
  /// start a strip on it. A different photograph is a different strip.
  Future<void> _choosePhoto() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'photographs',
          extensions: <String>[
            'jpg',
            'jpeg',
            'png',
            'tif',
            'tiff',
            'arw',
            'cr2',
            'cr3',
            'nef',
            'raf',
            'rw2',
            'orf',
            'dng',
            'pef',
            'srw',
            'nrw',
            'x3f',
            'iiq',
            '3fr',
          ],
        ),
      ],
    );
    if (file == null || !mounted) {
      return;
    }
    try {
      final File kept = await StripStore.keep(File(file.path));
      final TestStrip current = _strip ?? const TestStrip();
      if (current.photo == kept.path) {
        return;
      }
      final ui.Image image = await decode(kept, width: 1600);
      if (!mounted) {
        image.dispose();
        return;
      }
      final TestStrip next = current.withPhoto(kept.path);
      final ui.Image? oldPhoto = _ownsPhotograph ? _photograph : null;
      final List<TestPrint> oldPrints = current.prints;
      setState(() {
        _strip = next;
        _photograph = image;
        _ownsPhotograph = true;
      });
      for (final TestPrint print in oldPrints) {
        final ui.Image? picture = print.image;
        if (picture != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => picture.dispose(),
          );
        }
      }
      if (oldPhoto != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => oldPhoto.dispose());
      }
      await StripStore.clear();
      await StripStore.save(next);
    } on Object catch (error) {
      Model.log('the photograph could not be kept: $error');
    }
  }

  /// Replace the strip and forget the prints the old one had.
  Future<void> _replaceStrip(TestStrip next) async {
    final TestStrip? old = _strip;
    setState(() => _strip = next);
    for (final TestPrint print in old?.prints ?? const <TestPrint>[]) {
      final ui.Image? picture = print.image;
      if (picture != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => picture.dispose());
      }
    }
    await StripStore.clear();
    await StripStore.save(next);
  }

  Future<void> _chooseFilm(Stock film) async {
    final Catalogue catalogue = _catalogue ?? Catalogue.carried;
    final TestStrip strip = _strip ?? const TestStrip();
    final List<Stock> papers = catalogue.papersFor(film.process);
    Stock? paper;
    for (final Stock candidate in papers) {
      if (candidate.id == strip.paperId) {
        paper = candidate;
        break;
      }
    }
    paper ??= papers.isEmpty ? null : papers.first;
    await _replaceStrip(
      TestStrip(
        photo: strip.photo,
        stockId: film.id,
        stockLabel: film.label,
        paperId: paper?.id,
        paperLabel: paper?.label,
        spectral: strip.spectral,
        tempC: strip.tempC,
      ),
    );
  }

  Future<void> _choosePaper(Stock? paper) async {
    final TestStrip strip = _strip ?? const TestStrip();
    await _replaceStrip(
      TestStrip(
        photo: strip.photo,
        stockId: strip.stockId,
        stockLabel: strip.stockLabel,
        paperId: paper?.id,
        paperLabel: paper?.label,
        spectral: strip.spectral,
        tempC: strip.tempC,
      ),
    );
  }

  /// Forget the prints and keep the photograph and the materials.
  Future<void> _clearStrip() async {
    final TestStrip? strip = _strip;
    if (strip == null) {
      return;
    }
    await _replaceStrip(strip.withoutPrints());
  }

  /// Develop one print and add it to the strip.
  Future<void> _develop(double minutes) async {
    final TestStrip? strip = _strip;
    if (strip == null || strip.photo == null) {
      return;
    }
    TestPrint? replaced;
    for (final TestPrint print in strip.prints) {
      if (print.minutes == minutes) {
        replaced = print;
        break;
      }
    }
    final TestStrip next = await developTestPrint(
      model: Model.find(),
      strip: strip,
      minutes: minutes,
    );
    if (!mounted) {
      return;
    }
    setState(() => _strip = next);
    final ui.Image? picture = replaced?.image;
    if (picture != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => picture.dispose());
    }
  }

  /// Take one print off the strip.
  Future<void> _remove(double minutes) async {
    final TestStrip? strip = _strip;
    if (strip == null) {
      return;
    }
    TestPrint? removed;
    for (final TestPrint print in strip.prints) {
      if (print.minutes == minutes) {
        removed = print;
        break;
      }
    }
    if (removed == null) {
      return;
    }
    final TestStrip next = strip.without(minutes);
    setState(() => _strip = next);
    await StripStore.save(next);
    final File? file = removed.file;
    if (file != null && file.existsSync()) {
      await file.delete();
    }
    final ui.Image? picture = removed.image;
    if (picture != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => picture.dispose());
    }
  }

  /// Make a finished print and hang it.
  Future<void> _print(PrintRequest request) async {
    final TestStrip? strip = _strip;
    final Directory? exports = _folder;
    if (strip == null || exports == null || strip.photo == null) {
      return;
    }
    int number = 0;
    for (int i = 0; i < strip.prints.length; i++) {
      if (strip.prints[i].minutes == request.minutes) {
        number = i + 1;
        break;
      }
    }
    final PrintJob job = PrintJob(
      frame: Frame(
        number: number == 0 ? 1 : number,
        minutes: request.minutes,
        tempC: strip.tempC,
      ),
      exports: exports,
    );
    setState(() => _jobs = <PrintJob>[job, ..._jobs]);
    try {
      await printTest(
        model: Model.find(),
        strip: strip,
        minutes: request.minutes,
        exports: exports,
        paperName:
            _catalogue?.paper(strip.paperId ?? '')?.short ??
            strip.paperLabel ??
            Stocks.paperShort,
        printEv: request.printEv,
        filters: request.filters,
        heatGlass: request.heatGlass,
      );
      await _reloadPrints();
    } finally {
      if (mounted) {
        setState(
          () => _jobs = <PrintJob>[
            for (final PrintJob other in _jobs)
              if (!identical(other, job)) other,
          ],
        );
      }
    }
  }

  /// Read the folder the person chose, and the prints in it.
  Future<void> _openExports() async {
    _settings = await Settings.read();
    _exportPath = _settings.exportPath;
    _spectral = _settings.spectral;
    await _reloadPrints();
  }

  /// The path a new strip is exposed through. It is a new strip's setting, not
  /// a switch on the strip in the darkroom: a strip is made one way.
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

  Directory? get _folder =>
      widget.exportsFolder ?? Exports.directoryFor(_exportPath);

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
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
            settings: settings,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondary,
            ) => builder(context),
          ),
      builder: (BuildContext context, Widget? child) {
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
      home: _strip == null
          ? const ColoredBox(color: Color(0xFFF6F5F2))
          : Studio(
              strip: _strip!,
              photograph: _photograph,
              catalogue: _catalogue ?? Catalogue.carried,
              prints: _prints,
              exports: _folder,
              jobs: _jobs,
              onChoosePhoto: () => unawaited(_choosePhoto()),
              onFilm: (Stock film) => unawaited(_chooseFilm(film)),
              onPaper: (Stock? paper) => unawaited(_choosePaper(paper)),
              onDevelop: _develop,
              onRemove: _remove,
              onClearStrip: () => unawaited(_clearStrip()),
              onPrint: _print,
              onEnterExports: widget.prints == null
                  ? () => unawaited(_reloadPrints())
                  : null,
              export: _exportSetting,
              locale: _locale,
              onLocale: (Locale? next) => setState(() => _locale = next),
              spectral: _spectral,
              onSpectral: _setSpectral,
              initiallyOpen: widget.drawerOpen,
              initialChamber: widget.initialChamber,
              initialStep: widget.initialStep,
              chrome: widget.chrome,
              onDragWindow: widget.onDragWindow,
            ),
    );
  }
}
