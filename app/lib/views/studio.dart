import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/chrome.dart';
import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/exports.dart';
import '../lab/print.dart';
import '../lab/print_out.dart';
import '../lab/print_request.dart';
import '../lab/stock.dart';
import '../lab/strip.dart';
import '../widgets/stage_tabs.dart';
import '../widgets/switch.dart';
import '../widgets/studio_top_bar.dart';
import '../widgets/studio_sidebar.dart';
import 'chambers.dart';
import 'develop_stage.dart';
import 'drawer.dart';
import 'gallery.dart';
import 'rack.dart';
import 'print_stage.dart';
import 'select_stage.dart';
import 'steps.dart';

/// The window: two rooms, a rack between them, and the steps of the room that
/// makes the work.
///
/// The sidebar is a place. The darkroom has three steps, and they sit on the
/// top edge of the work as edge codes rather than in a second navigation: the
/// bench does not move, it changes what is on it. The rack and the gallery have
/// no steps — a line is hung, a wall is looked at, neither is operated.
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

  /// The two sides of the window. Hiding them is about the work and not a
  /// preference, so neither is written to disk: the next visit opens on the
  /// room, not on the last arrangement of the furniture.
  bool _sidebar = true;
  bool _inspector = true;

  /// The gallery's lamp. The room remembers it; the window does not go dark.
  bool _lit = true;

  /// The gallery's loupe. It starts put away: the wall is for looking at, and
  /// glass is a tool a person takes up on purpose.
  bool _loupe = false;

  /// Whether one print has left the wall to fill the window. The loupe is a
  /// wall tool, so its switch goes with the wall.
  bool _galleryNear = false;

  void _room(Chamber chamber) {
    setState(() {
      _chamber = chamber;
      _open = false;
      if (chamber != Chamber.gallery) {
        _galleryNear = false;
      }
    });
    if (chamber != Chamber.darkroom) {
      widget.onEnterExports?.call();
    }
  }

  void _stage(DarkroomStep step) {
    if (widget.strip.photo == null && step != DarkroomStep.select) {
      return;
    }
    setState(() => _step = step);
  }

  void _closeDrawer() => setState(() => _open = false);

  void _toggleLight() => setState(() => _lit = !_lit);

  void _toggleLoupe() => setState(() => _loupe = !_loupe);

  @override
  Widget build(BuildContext context) {
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
        },
        const SingleActivator(LogicalKeyboardKey.keyD): () =>
            _room(Chamber.darkroom),
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            _room(Chamber.rack),
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
                  AnimatedSize(
                    duration: KalloMotion.settle,
                    curve: KalloMotion.enter,
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.hardEdge,
                    child: _sidebar
                        ? SizedBox(
                            key: const Key('studio-sidebar'),
                            width: 232,
                            child: StudioSidebar(
                              chamber: _chamber,
                              onChamber: _room,
                              galleryCount: widget.prints.length,
                              onSettings: () => setState(() => _open = true),
                              onSidebar: () =>
                                  setState(() => _sidebar = !_sidebar),
                            ),
                          )
                        : const SizedBox(width: 0),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(child: _body()),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: _topBar(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.chrome == WindowChrome.mac &&
                  widget.onDragWindow != null &&
                  _sidebar)
                Positioned(
                  left: 0,
                  top: 0,
                  // Leave the sidebar's own switch hittable. The rest of the
                  // strip above the traffic lights still drags the window.
                  width: 232 - 16 - 34 - 12,
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
                        color: KalloScope.colorsOf(context).scrim,
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

  Widget _body() {
    if (_chamber == Chamber.gallery) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _lit ? 1 : 0),
        duration: _lit ? KalloMotion.settle : KalloMotion.slow,
        curve: _lit ? KalloMotion.enter : KalloMotion.settleCurve,
        builder: (BuildContext context, double light, Widget? child) => Gallery(
          // A wall reads newest first, like the rack: the print just made is
          // the one worth seeing.
          prints: widget.prints.reversed.toList(growable: false),
          light: light,
          loupe: _loupe,
          onNear: (bool near) {
            if (_galleryNear != near) {
              setState(() => _galleryNear = near);
            }
          },
          topInset: _topBarHeight,
        ),
      );
    }
    if (_chamber == Chamber.rack) {
      return Rack(
        prints: widget.prints,
        jobs: widget.jobs,
        topInset: _topBarHeight,
      );
    }
    return _darkroom();
  }

  static const double _topBarHeight = 56;

  /// The inspector exists only where a step has a panel. The print step with
  /// nothing to print has no panel, and a control that toggles nothing is a
  /// control that lies.
  bool get _hasInspector =>
      _chamber == Chamber.darkroom &&
      !(_step == DarkroomStep.print && widget.strip.prints.isEmpty);

  Widget _topBar() {
    final KalloStrings s = KalloStrings.of(context);
    final Widget center = _chamber == Chamber.darkroom
        ? StageTabs(current: _step, onSelect: _stage)
        : _RoomPill(
            label: _chamber == Chamber.rack ? s.rack : s.galleryRoom,
            trailing: _chamber == Chamber.rack && widget.prints.isNotEmpty
                ? '${widget.prints.length}'
                : null,
          );
    final KalloColors colors = KalloScope.colorsOf(context);
    return StudioTopBar(
      sidebarOpen: _sidebar,
      onSidebar: () => setState(() => _sidebar = !_sidebar),
      mac: widget.chrome == WindowChrome.mac,
      inspectorOpen: _hasInspector ? _inspector : null,
      onInspector: _hasInspector
          ? () => setState(() => _inspector = !_inspector)
          : null,
      trailing: _chamber == Chamber.gallery
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (!_galleryNear) ...<Widget>[
                  KalloSwitch(
                    key: const Key('loupe'),
                    label: s.loupe,
                    control: colors.inkMuted,
                    on: _loupe,
                    onTap: _toggleLoupe,
                  ),
                  const SizedBox(width: KalloSpace.step2),
                ],
                KalloSwitch(
                  key: const Key('light'),
                  label: s.roomLight,
                  control: colors.inkMuted,
                  on: _lit,
                  onTap: _toggleLight,
                ),
              ],
            )
          : null,
      center: center,
      onDragWindow: widget.onDragWindow,
      height: _topBarHeight,
      rightInset: _hasInspector && _inspector ? 304 : 0,
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
        showInspector: _inspector,
        topInset: _topBarHeight,
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
        showInspector: _inspector,
        topInset: _topBarHeight,
      ),
      DarkroomStep.print => PrintStage(
        key: ValueKey<String>(
          'print-${widget.strip.photo}-${widget.strip.stockId}-'
          '${widget.strip.paperId}-${widget.strip.tempC}',
        ),
        strip: widget.strip,
        paperName:
            widget.catalogue.paper(widget.strip.paperId ?? '')?.displayName ??
            widget.strip.paperLabel ??
            '',
        exports: widget.exports,
        onPrint: widget.onPrint,
        onGoDevelop: () => _stage(DarkroomStep.develop),
        onGoRack: () => _room(Chamber.rack),
        showInspector: _inspector,
        topInset: _topBarHeight,
      ),
    };
  }
}

/// A room's name in the top bar, when the room has no steps.
class _RoomPill extends StatelessWidget {
  const _RoomPill({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(KalloRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: KalloType.body.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w500,
              fontSize: 12.5,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: KalloSpace.step2),
            Text(
              trailing!,
              style: KalloType.folio.copyWith(color: colors.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}
