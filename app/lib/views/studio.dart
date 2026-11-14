import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/chrome.dart';
import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/exports.dart';
import '../lab/print.dart';
import '../lab/print_out.dart';
import '../lab/print_request.dart';
import '../lab/stock.dart';
import '../lab/strip.dart';
import '../widgets/stage_tabs.dart';
import '../widgets/studio_sidebar.dart';
import 'chambers.dart';
import 'develop_stage.dart';
import 'drawer.dart';
import 'gallery.dart';
import 'line.dart';
import 'print_stage.dart';
import 'select_stage.dart';
import 'steps.dart';

/// The window: two rooms, and the steps of the one that makes the work.
///
/// The sidebar is a place. The darkroom has four steps, and they sit on the
/// top edge of the work as edge codes rather than in a second navigation: the
/// bench does not move, it changes what is on it. The gallery has no steps —
/// a wall is looked at, not operated.
class Studio extends StatefulWidget {
  const Studio({
    super.key,
    required this.strip,
    required this.photograph,
    required this.catalogue,
    required this.prints,
    required this.exports,
    required this.jobs,
    required this.onChoosePhoto,
    required this.onFilm,
    required this.onPaper,
    required this.onTemperature,
    required this.onDevelop,
    required this.onRemove,
    required this.onClearStrip,
    required this.onPrint,
    required this.onEnterExports,
    required this.export,
    required this.locale,
    required this.onLocale,
    required this.spectral,
    required this.onSpectral,
    this.initiallyOpen = false,
    this.initialChamber = Chamber.darkroom,
    this.initialStep = DarkroomStep.select,
    this.chrome = WindowChrome.plain,
    this.onDragWindow,
  });

  final TestStrip strip;

  /// The original photograph, decoded for the light table. Null before a
  /// photograph has been chosen, which is a state the first step shows.
  final ui.Image? photograph;

  final Catalogue catalogue;
  final List<Print> prints;
  final Directory? exports;
  final List<PrintJob> jobs;

  final VoidCallback onChoosePhoto;
  final ValueChanged<Stock> onFilm;
  final ValueChanged<Stock?> onPaper;
  final ValueChanged<double> onTemperature;
  final Future<void> Function(double minutes) onDevelop;
  final Future<void> Function(double minutes) onRemove;
  final VoidCallback onClearStrip;
  final Future<void> Function(PrintRequest request) onPrint;
  final VoidCallback? onEnterExports;

  final ExportSetting export;
  final Locale? locale;
  final ValueChanged<Locale?> onLocale;
  final bool spectral;
  final ValueChanged<bool> onSpectral;

  final bool initiallyOpen;
  final Chamber initialChamber;
  final DarkroomStep initialStep;
  final WindowChrome chrome;
  final VoidCallback? onDragWindow;

  @override
  State<Studio> createState() => _StudioState();
}

class _StudioState extends State<Studio> {
  late Chamber _chamber = widget.initialChamber;
  late DarkroomStep _step = widget.initialStep;
  late bool _open = widget.initiallyOpen;

  /// The gallery's lamp. The room remembers it; the window does not go dark.
  bool _lit = true;

  void _room(Chamber chamber) {
    setState(() {
      _chamber = chamber;
      _open = false;
    });
    if (chamber == Chamber.gallery) {
      widget.onEnterExports?.call();
    }
  }

  void _stage(DarkroomStep step) {
    if (widget.strip.photo == null && step != DarkroomStep.select) {
      return;
    }
    setState(() => _step = step);
    if (step == DarkroomStep.dry) {
      widget.onEnterExports?.call();
    }
  }

  void _closeDrawer() => setState(() => _open = false);

  void _toggleLight() => setState(() => _lit = !_lit);

  @override
  Widget build(BuildContext context) {
    final Stock? film = widget.catalogue.film(widget.strip.stockId);
    final Stock? paper = widget.strip.paperId == null
        ? null
        : widget.catalogue.paper(widget.strip.paperId!);
    final String filmShort = film?.short ?? widget.strip.stockLabel;
    final String paperShort = paper?.short ?? widget.strip.paperLabel ?? '';
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _closeDrawer,
        if (_chamber == Chamber.darkroom) ...<ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.digit1): () =>
              _stage(DarkroomStep.select),
          const SingleActivator(LogicalKeyboardKey.digit2): () =>
              _stage(DarkroomStep.develop),
          const SingleActivator(LogicalKeyboardKey.digit3): () =>
              _stage(DarkroomStep.print),
          const SingleActivator(LogicalKeyboardKey.digit4): () =>
              _stage(DarkroomStep.dry),
        },
        const SingleActivator(LogicalKeyboardKey.keyD): () =>
            _room(Chamber.darkroom),
        const SingleActivator(LogicalKeyboardKey.keyG): () =>
            _room(Chamber.gallery),
        if (_chamber == Chamber.gallery)
          const SingleActivator(LogicalKeyboardKey.keyL): _toggleLight,
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: KalloScope.colorsOf(context).ground,
          child: Stack(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 232,
                    child: StudioSidebar(
                      topInset: widget.chrome == WindowChrome.mac ? 44 : 12,
                      chamber: _chamber,
                      onChamber: _room,
                      strip: widget.strip,
                      filmShort: filmShort,
                      paperShort: paperShort,
                      galleryCount: widget.prints.length,
                      testCount: widget.strip.prints.length,
                      onSettings: () => setState(() => _open = true),
                    ),
                  ),
                  Expanded(
                    child: _chamber == Chamber.gallery
                        ? TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: _lit ? 1 : 0),
                            duration: _lit
                                ? KalloMotion.settle
                                : KalloMotion.slow,
                            curve: _lit
                                ? KalloMotion.enter
                                : KalloMotion.settleCurve,
                            builder:
                                (
                                  BuildContext context,
                                  double light,
                                  Widget? child,
                                ) => Gallery(
                                  // A wall reads newest first, like the line:
                                  // the print just made is the one worth seeing.
                                  prints: widget.prints.reversed.toList(
                                    growable: false,
                                  ),
                                  light: light,
                                  onLight: _toggleLight,
                                ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart:
                                    widget.chrome == WindowChrome.mac &&
                                        widget.onDragWindow != null
                                    ? (_) => widget.onDragWindow!()
                                    : null,
                                child: StageTabs(
                                  current: _step,
                                  onSelect: _stage,
                                ),
                              ),
                              Expanded(child: _darkroom()),
                            ],
                          ),
                  ),
                ],
              ),
              if (widget.chrome == WindowChrome.mac &&
                  widget.onDragWindow != null)
                Positioned(
                  left: 0,
                  top: 0,
                  width: 232,
                  height: 44,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => widget.onDragWindow!(),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_open,
                  child: GestureDetector(
                    onTap: _closeDrawer,
                    child: AnimatedOpacity(
                      duration: KalloMotion.settle,
                      curve: KalloMotion.enter,
                      opacity: _open ? 1 : 0,
                      child: ColoredBox(
                        color: KalloScope.colorsOf(context).ink
                            .withValues(alpha: 0.16),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSlide(
                  duration: KalloMotion.settle,
                  curve: KalloMotion.enter,
                  offset: Offset(0, _open ? 0 : 1),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          return SizedBox(
                            height: math.min(600, constraints.maxHeight * 0.9),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(KalloRadius.sheet),
                              ),
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  boxShadow: KalloShadow.sheet,
                                ),
                                child: SettingsDrawer(
                                  export: widget.export,
                                  locale: widget.locale,
                                  onLocale: widget.onLocale,
                                  spectral: widget.spectral,
                                  onSpectral: widget.onSpectral,
                                  onClose: _closeDrawer,
                                ),
                              ),
                            ),
                          );
                        },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _darkroom() {
    return switch (_step) {
      DarkroomStep.select => SelectStage(
        strip: widget.strip,
        photograph: widget.photograph,
        catalogue: widget.catalogue,
        onChoosePhoto: widget.onChoosePhoto,
        onFilm: widget.onFilm,
        onPaper: widget.onPaper,
        onGoDevelop: () => _stage(DarkroomStep.develop),
        onClear: widget.onClearStrip,
      ),
      DarkroomStep.develop => DevelopStage(
        key: ValueKey<String>(
          'develop-${widget.strip.photo}-${widget.strip.stockId}-'
          '${widget.strip.paperId}-${widget.strip.tempC}',
        ),
        strip: widget.strip,
        onTemperature: widget.onTemperature,
        onDevelop: widget.onDevelop,
        onRemove: widget.onRemove,
      ),
      DarkroomStep.print => PrintStage(
        key: ValueKey<String>(
          'print-${widget.strip.photo}-${widget.strip.stockId}-'
          '${widget.strip.paperId}-${widget.strip.tempC}',
        ),
        strip: widget.strip,
        paperName:
            widget.catalogue.paper(widget.strip.paperId ?? '')?.short ??
            widget.strip.paperLabel ??
            '',
        exports: widget.exports,
        onPrint: widget.onPrint,
        onGoDevelop: () => _stage(DarkroomStep.develop),
      ),
      DarkroomStep.dry => Line(prints: widget.prints, jobs: widget.jobs),
    };
  }
}
