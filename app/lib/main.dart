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
import 'lab/catalog.dart';
import 'lab/exports.dart';
import 'lab/folder_print_library.dart';
import 'lab/ffi_model.dart';
import 'lab/image_file.dart';
import 'lab/model.dart';
import 'lab/print.dart';
import 'lab/print_library.dart';
import 'lab/open_print_library.dart';
import 'lab/print_marker.dart';
import 'lab/print_meta.dart';
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
import 'widgets/folder_move_sheet.dart';
import 'widgets/import_progress_sheet.dart';

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
      title: 'Kallo',
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

  /// Whether the export folder has been read into [_prints].
  ///
  /// Entering the rack or the gallery used to read and decode every print
  /// again, which left a little more of the last set in the allocator each
  /// time. A print changes the list; walking into a room does not.
  bool _printsLoaded = false;
  List<PrintJob> _jobs = const <PrintJob>[];
  PrintLibrary? _library;
  int _missingPrints = 0;
  int _repairablePrints = 0;
  bool _repairing = false;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _watchDebounce;
  Settings _settings = const Settings();
  String? _exportPath;
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  /// A context below the Navigator and the app's scope, for dialogs opened by
  /// the state above both. The Navigator is the only one the app has.
  BuildContext get _dialogContext =>
      _navigator.currentState?.overlay?.context ?? context;

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
      _printsLoaded = true;
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
    _watchDebounce?.cancel();
    unawaited(_watch?.cancel());
    _library?.close();
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
  ///
  /// A phone chooses from Photos through the system picker; a desktop chooses
  /// a file. The rest of the darkroom does not know which happened.
  Future<void> _choosePhoto() async {
    final File? file = await _pickPhotograph();
    if (file == null || !mounted) {
      return;
    }
    try {
      final File kept = await StripStore.keep(file);
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

  Future<File?> _pickPhotograph() async {
    final PrintLibrary? library = _library;
    if (library != null && library.canPickImages) {
      try {
        final List<File> picked = await library.pickImages(limit: 1);
        return picked.isEmpty ? null : picked.first;
      } on Object catch (error) {
        debugPrint('no photograph picker: $error');
        return null;
      }
    }
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
    return file == null ? null : File(file.path);
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

  /// Change the developer's temperature.
  ///
  /// The temperature is part of the strip's development, so changing it starts
  /// a new strip: the old prints were made at a different temperature, and
  /// keeping them would be a strip that says two things at once.
  Future<void> _setTemperature(double tempC) async {
    final TestStrip? strip = _strip;
    if (strip == null || strip.tempC == tempC) {
      return;
    }
    await _replaceStrip(strip.withTemperature(tempC));
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
    final PrintLibrary? library = _library;
    if (strip == null || library == null || strip.photo == null) {
      return;
    }
    final Directory exports = library.workFolder;
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
      final String filmName =
          _catalogue?.film(strip.stockId)?.displayName ?? strip.stockLabel;
      final String paperName =
          _catalogue?.paper(strip.paperId ?? '')?.displayName ??
          strip.paperLabel ??
          Stocks.crystal.displayName;
      final File output = await printTest(
        model: Model.find(),
        strip: strip,
        minutes: request.minutes,
        exports: exports,
        width: request.width,
        format: request.format,
        printEv: request.printEv,
        filters: request.filters,
        heatGlass: request.heatGlass,
      );
      final DateTime now = DateTime.now().toUtc();
      final PrintMeta meta = PrintMeta(
        id: PrintMeta.newId(),
        title: _stem(output.path),
        kind: PrintKind.print,
        printed: now,
        added: now,
        updated: now,
        printNumber: 1,
        process: _catalogue?.film(strip.stockId)?.process,
        film: filmName,
        paper: paperName,
        minutes: request.minutes,
        tempC: strip.tempC,
      );
      await library.addFile(output, meta);
      if (library.folder == null) {
        try {
          if (await output.exists()) {
            await output.delete();
          }
        } on FileSystemException {
          // The temporary folder is cleaned by the system; the print is in
          // Photos or MediaStore already.
        }
      }
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
    final bool phone = Platform.isIOS || Platform.isAndroid;
    if (phone) {
      // The platform bridge tells Settings where the app's support folder is,
      // so the settings file is read after the library opens, not before.
      await _openLibrary();
      _settings = await Settings.read();
      _spectral = _settings.spectral;
    } else {
      _settings = await Settings.read();
      _exportPath = _settings.exportPath;
      _spectral = _settings.spectral;
      await _openLibrary();
    }
    await _reloadPrints();
    _startWatching();
  }

  /// Reload when the folder changes behind the app.
  ///
  /// The marker and the catalog are the truth, so a file dropped in Finder or
  /// removed by another app should reach the wall without a relaunch. Events
  /// are debounced: a copy is many writes, and one reload is enough.
  void _startWatching() {
    _watchDebounce?.cancel();
    unawaited(_watch?.cancel());
    _watch = null;
    final Directory? folder = _library?.folder ?? _folder;
    if (folder == null || !folder.existsSync()) {
      return;
    }
    try {
      _watch = folder
          .watch(
            events:
                FileSystemEvent.create |
                FileSystemEvent.modify |
                FileSystemEvent.delete |
                FileSystemEvent.move,
          )
          .listen(
            (FileSystemEvent event) {
              _watchDebounce?.cancel();
              _watchDebounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) {
                  unawaited(_reloadPrints());
                }
              });
            },
            onError: (Object error) {
              debugPrint('the folder could not be watched: $error');
            },
          );
    } on Object catch (error) {
      debugPrint('the folder could not be watched: $error');
    }
  }

  /// Open the catalog and let it adopt the old print store once.
  Future<void> _openLibrary() async {
    final Directory? folder = _folder;
    if (folder == null && !(Platform.isIOS || Platform.isAndroid)) {
      return;
    }
    try {
      final PrintLibrary library = await openPrintLibrary(folder: folder);
      if (library is FolderPrintLibrary) {
        try {
          await library.migrateLegacy();
        } on Object {
          library.close();
          rethrow;
        }
      }
      _library = library;
    } on Object catch (error) {
      debugPrint('the catalog could not be opened: $error');
      _library?.close();
      _library = null;
    }
  }

  /// The path a new strip is exposed through. It is a new strip's setting, not
  /// a switch on the strip in the darkroom: a strip is made one way.
  Future<void> _setSpectral(bool on) async {
    setState(() => _spectral = on);
    _settings = _settings.withSpectral(on);
    await _settings.write();
  }

  /// Read the export folder only when it has not been read yet.
  ///
  /// A room asks for the prints each time it is entered; the app already has
  /// them unless this is the first ask, or a print has just changed the list.
  Future<void> _ensurePrints() async {
    if (_printsLoaded) {
      return;
    }
    await _reloadPrints();
  }

  Future<void> _reloadPrints() async {
    _printsLoaded = true;
    final PrintLibrary? library = _library;
    final List<Print> prints = library == null
        ? const <Print>[]
        : await library.read();
    if (!mounted) {
      for (final Print print in prints) {
        print.dispose();
      }
      return;
    }
    final List<Print> previous = _prints;
    final (int missing, int repairable) = _issueCounts();
    setState(() {
      _prints = prints;
      _missingPrints = missing;
      _repairablePrints = repairable;
    });
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
    final FolderPrintLibrary? library = _library is FolderPrintLibrary
        ? _library as FolderPrintLibrary
        : null;
    if (library != null) {
      final int count = library.catalog
          .printsInLibrary(library.library.id)
          .length;
      if (count > 0) {
        final FolderMoveChoice? choice = await showFolderMoveSheet(
          _dialogContext,
          count: count,
          destination: Exports.display(chosen),
        );
        if (!mounted || choice == null || choice == FolderMoveChoice.cancel) {
          return;
        }
        if (choice == FolderMoveChoice.useNew) {
          _library = library.switchTo(Directory(chosen));
        } else {
          try {
            _library = await library.moveTo(Directory(chosen));
          } on Object catch (error) {
            debugPrint('the prints could not be moved: $error');
            return;
          }
        }
      } else {
        _library = library.switchTo(Directory(chosen));
      }
    }
    _exportPath = chosen;
    await _remember(chosen);
    await _reloadPrints();
    _startWatching();
  }

  Future<void> _resetExport() async {
    if (!mounted) {
      return;
    }
    final FolderPrintLibrary? library = _library is FolderPrintLibrary
        ? _library as FolderPrintLibrary
        : null;
    final Directory? target = Exports.defaultDirectory;
    if (library != null && target != null) {
      try {
        _library = await library.moveTo(target);
      } on Object catch (error) {
        debugPrint('the prints could not be moved back: $error');
        return;
      }
    }
    setState(() => _exportPath = null);
    await _remember(null);
    await _reloadPrints();
    _startWatching();
  }

  /// Copy selected pictures into the library. The source files never change.
  Future<void> _importImages() async {
    final PrintLibrary? library = _library;
    if (library == null) {
      return;
    }
    final List<File> files;
    try {
      if (library.canPickImages) {
        files = await library.pickImages();
      } else {
        final List<XFile> picked = await openFiles(
          acceptedTypeGroups: <XTypeGroup>[
            const XTypeGroup(
              label: 'Images',
              extensions: <String>['png', 'jpg', 'jpeg'],
            ),
          ],
          confirmButtonText: 'Import',
        );
        files = <File>[for (final XFile file in picked) File(file.path)];
      }
    } on Object catch (error) {
      debugPrint('no import panel: $error');
      return;
    }
    if (!mounted) {
      return;
    }
    final ImportProgress progress = showImportProgressSheet(
      _dialogContext,
      total: files.length,
    );
    await progress.ready;
    int done = 0;
    try {
      for (final File source in files) {
        if (progress.canceled) {
          break;
        }
        progress.current.value = _basename(source.path);
        File? target;
        try {
          final Directory? folder = library.folder;
          if (folder != null && source.parent.path == folder.path) {
            continue;
          }
          final ScannedPrint? scan = await PrintMarker.read(source);
          if (scan == null) {
            continue;
          }
          final PrintMeta? existing = scan.meta;
          if (existing != null &&
              library.catalog.printById(existing.id) != null) {
            continue;
          }
          final FileStat stat = await source.stat();
          target = File(_uniqueImportPath(library.workFolder, source.path));
          await source.copy(target.path);
          final DateTime now = DateTime.now().toUtc();
          final PrintMeta meta =
              existing ??
              PrintMeta(
                id: PrintMeta.newId(),
                title: _importTitle(source, stat),
                kind: PrintKind.import,
                printed: stat.modified.toUtc(),
                added: now,
                updated: now,
                sourceName: _basename(source.path),
              );
          await library.addFile(target, meta);
        } on Object catch (error) {
          debugPrint('the import of ${source.path} failed: $error');
        } finally {
          if (library.folder == null && target != null) {
            try {
              if (await target.exists()) {
                await target.delete();
              }
            } on FileSystemException {
              // A temporary import the system cleans up later is not a failure.
            }
          }
          if (library.canPickImages) {
            try {
              if (await source.exists()) {
                await source.delete();
              }
            } on FileSystemException {
              // The picker's own copy is a cache; losing it later is harmless.
            }
          }
        }
        progress.done.value = ++done;
      }
    } finally {
      progress.close();
    }
    await _reloadPrints();
  }

  (int, int) _issueCounts() {
    final PrintLibrary? library = _library;
    if (library == null) {
      return (0, 0);
    }
    int missing = 0;
    int repairable = 0;
    for (final CatalogPrint row in library.catalog.printsInLibrary(
      library.library.id,
      includeMissing: true,
    )) {
      if (row.missing) {
        missing++;
        continue;
      }
      if ((row.xmpState == XmpState.missing ||
              row.xmpState == XmpState.stale) &&
          File(row.locator).existsSync()) {
        repairable++;
      }
    }
    return (missing, repairable);
  }

  Future<void> _repairMarkers() async {
    final PrintLibrary? library = _library;
    if (library == null || _repairing) {
      return;
    }
    setState(() => _repairing = true);
    try {
      await library.repairMarkers();
      await _reloadPrints();
    } finally {
      if (mounted) {
        setState(() => _repairing = false);
      }
    }
  }

  Future<void> _remember(String? path) async {
    _settings = _settings.withExports(path);
    if (mounted) {
      setState(() {});
    }
    await _settings.write();
  }

  Directory? get _folder {
    if (Platform.isIOS || Platform.isAndroid) {
      return null;
    }
    return widget.exportsFolder ?? Exports.directoryFor(_exportPath);
  }

  String _uniqueImportPath(Directory folder, String sourcePath) {
    final String separator = Platform.pathSeparator;
    final String base = _basename(sourcePath);
    final String stem = _stem(sourcePath);
    final int dot = base.lastIndexOf('.');
    final String extension = dot < 0 ? '' : base.substring(dot);
    int index = 1;
    File candidate = File('${folder.path}$separator$base');
    while (candidate.existsSync()) {
      index++;
      candidate = File('${folder.path}$separator$stem-$index$extension');
    }
    return candidate.path;
  }

  static String _basename(String path) {
    final int slash = path.lastIndexOf(Platform.pathSeparator);
    return slash < 0 ? path : path.substring(slash + 1);
  }

  static String _stem(String path) {
    final String base = _basename(path);
    final int dot = base.lastIndexOf('.');
    return dot <= 0 ? base : base.substring(0, dot);
  }

  /// Android's system picker returns a media id, not the name of the file the
  /// person chose. A wall label of `1000043857` is not a title; the day the
  /// picture was taken is something a person can read.
  static String _importTitle(File source, FileStat stat) {
    final String stem = _stem(source.path);
    if (!RegExp(r'^\d+$').hasMatch(stem)) {
      return stem;
    }
    final DateTime at = stat.modified.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Kallo ${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}.${two(at.minute)}';
  }

  ExportSetting get _exportSetting {
    final PrintLibrary? library = _library;
    final bool canChoose = library?.canChooseFolder ?? Exports.canChoose;
    return ExportSetting(
      label: library?.locationLabel ?? Exports.display(_folder?.path),
      canChoose: canChoose,
      custom: canChoose && _exportPath != null,
      onChoose: canChoose ? _chooseExport : null,
      onReset: canChoose ? _resetExport : null,
      onImport: library == null ? null : _importImages,
      canListAll: library?.canListAll ?? true,
      missingPrints: _missingPrints,
      repairablePrints: _repairablePrints,
      onRepair: _repairing ? null : _repairMarkers,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Kallo',
      navigatorKey: _navigator,
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
          ? ColoredBox(color: KalloColors.light.ground)
          : Studio(
              strip: _strip!,
              photograph: _photograph,
              catalogue: _catalogue ?? Catalogue.carried,
              prints: _prints,
              exports: _library?.workFolder ?? _folder,
              jobs: _jobs,
              onChoosePhoto: () => unawaited(_choosePhoto()),
              onFilm: (Stock film) => unawaited(_chooseFilm(film)),
              onPaper: (Stock? paper) => unawaited(_choosePaper(paper)),
              onTemperature: (double tempC) =>
                  unawaited(_setTemperature(tempC)),
              onDevelop: _develop,
              onRemove: _remove,
              onClearStrip: () => unawaited(_clearStrip()),
              onPrint: _print,
              onEnterExports: widget.prints == null
                  ? () => unawaited(_ensurePrints())
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
