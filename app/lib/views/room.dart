import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/chrome.dart';
import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/exports.dart';
import '../lab/print.dart';
import '../lab/print_out.dart';
import '../lab/roll.dart';
import '../lab/stock.dart';
import '../sheets/contact_sheet.dart';
import '../widgets/inspector.dart';
import '../widgets/sidebar.dart';
import 'drawer.dart';
import 'binder.dart';
import 'gallery.dart';
import 'line.dart';
import 'places.dart';
import 'shelf.dart';
import 'workbench.dart';

/// The window.
///
/// Four planes: a column of places, a toolbar, the field, and the inspector.
/// The drawer slides over all of them and puts itself away.
///
/// The field is a function of the place, and the room's light is a function of
/// the place too: the gallery has a lamp, and everything else is always lit.
class Room extends StatefulWidget {
  const Room({
    super.key,
    required this.roll,
    required this.catalogue,
    this.prints = const <Print>[],
    this.onEnterExports,
    required this.onDeveloped,
    required this.exports,
    required this.rollFolder,
    required this.jobs,
    required this.onPrint,
    required this.export,
    required this.locale,
    required this.onLocale,
    required this.technicalTerms,
    required this.onTechnicalTerms,
    required this.spectral,
    required this.onSpectral,
    this.initiallyOpen = false,
    this.initialPlace = Place.table,
    this.chrome = WindowChrome.plain,
    this.onDragWindow,
  });

  final WindowChrome chrome;
  final VoidCallback? onDragWindow;

  final Roll roll;

  /// Every film and paper the model carries. The shelf is a shelf because of
  /// it, and the binder shows a roll's own film out of it.
  final Catalogue catalogue;

  /// What has been exported, in the order it was printed. Nothing is a state
  /// the room can show: the gallery is a wall, and a wall can be empty.
  final List<Print> prints;

  /// Where a print goes, and where the roll lives, resolved once at the top.
  final Directory? exports;
  final Directory? rollFolder;

  /// The prints being made, and the way to make one.
  final List<PrintJob> jobs;
  final Future<void> Function(Frame frame) onPrint;

  /// Walking into a room that shows exports is what makes it look again: the
  /// folder is not watched, and a room that shows yesterday's work is a room
  /// with the lights off.
  final VoidCallback? onEnterExports;

  /// A roll that has just come off the shelf: one photograph, developed.
  final ValueChanged<Roll> onDeveloped;

  /// Where prints come from, and whether this platform lets a person say.
  final ExportSetting export;

  final Locale? locale;
  final ValueChanged<Locale?> onLocale;
  final bool technicalTerms;
  final ValueChanged<bool> onTechnicalTerms;

  /// The path a new roll is developed through, and the way to change it.
  final bool spectral;
  final ValueChanged<bool> onSpectral;

  /// Opened on the first frame. The golden test uses it; the app does not.
  final bool initiallyOpen;

  /// The place the window opens on. The goldens use it; the app opens on the
  /// table, which is where a roll of film is.
  final Place initialPlace;

  @override
  State<Room> createState() => _RoomState();
}

class _RoomState extends State<Room> {
  late Place _place = widget.initialPlace;
  int _selected = 2;
  late bool _open = widget.initiallyOpen;

  /// The lamp. It belongs to the room and it is remembered by it: leaving the
  /// gallery with the light off and coming back finds the room still dark.
  bool _lit = true;

  void _closeDrawer() => setState(() => _open = false);

  /// The selected frame, held inside the roll: developing a new roll can leave
  /// the old selection past its end.
  int get _index => math.min(_selected, widget.roll.frames.length - 1);

  void _toggleLight() => setState(() => _lit = !_lit);

  @override
  Widget build(BuildContext context) {
    final KalloScope scope = KalloScope.of(context);
    final KalloStrings s = KalloStrings.of(context);
    final bool gallery = _place == Place.gallery;
    // The lamp is on everywhere except in the gallery with the switch off, so
    // leaving a dark room brings the lights up on the way out.
    final double target = gallery && !_lit ? 0.0 : 1.0;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _closeDrawer,
        if (gallery)
          const SingleActivator(LogicalKeyboardKey.keyL): _toggleLight,
      },
      child: Focus(
        autofocus: true,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: target),
          // A lamp comes up faster than a room goes dark. The one direction is
          // the filament, the other is the eye.
          duration: target >= 1 ? KalloMotion.settle : KalloMotion.slow,
          curve: target >= 1 ? KalloMotion.enter : KalloMotion.settleCurve,
          child: _window(s),
          builder: (BuildContext context, double light, Widget? child) {
            return KalloScope(
              colors: scope.colors.toward(KalloColors.night, 1 - light),
              light: light,
              pinned: scope.pinned,
              onPin: scope.onPin,
              child: child!,
            );
          },
        ),
      ),
    );
  }

  Widget _window(KalloStrings s) {
    final Frame frame = widget.roll.frames[_index];
    return Stack(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 216,
              child: Sidebar(
                topInset: widget.chrome == WindowChrome.mac ? 44 : 12,
                current: _place,
                onSelect: (Place place) {
                  setState(() {
                    _place = place;
                    _open = false;
                  });
                  if (place == Place.gallery || place == Place.line) {
                    widget.onEnterExports?.call();
                  }
                },
                rolls: 1,
                rollName: s.rollName(widget.roll.number),
                frameCount: widget.roll.frames.length,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Toolbar(
                    draggable: widget.chrome == WindowChrome.mac,
                    onDrag: widget.onDragWindow,
                    title: s.rollName(widget.roll.number),
                    subtitle:
                        '${s.frames(widget.roll.frames.length)}   ·   '
                        '${widget.catalogue.film(widget.roll.stockId)?.short ?? widget.roll.stockLabel}',
                    onSettings: () => setState(() => _open = true),
                  ),
                  Expanded(
                    child: switch (_place) {
                      // Two rooms and a bench: the shelf and the gallery are
                      // whole fields, and the record on the right belongs to a
                      // frame, which is a thing only the bench has.
                      Place.shelf => Shelf(
                          roll: widget.roll,
                          catalogue: widget.catalogue,
                          spectral: widget.spectral,
                          onDeveloped: widget.onDeveloped,
                          onOpen: () => setState(() => _place = Place.table),
                        ),
                      Place.workbench => Workbench(
                          roll: widget.roll,
                          selected: _index,
                          onSelect: (int index) =>
                              setState(() => _selected = index),
                          exports: widget.exports,
                          paperName: widget.roll.paperName(widget.catalogue),
                          film: widget.catalogue.film(widget.roll.stockId),
                          onPrint: widget.onPrint,
                        ),
                      Place.binder => Binder(
                          roll: widget.roll,
                          catalogue: widget.catalogue,
                          exports: widget.exports,
                          rollFolder: widget.rollFolder,
                        ),
                      Place.line => Line(
                          prints: widget.prints,
                          jobs: widget.jobs,
                        ),
                      Place.gallery => Gallery(
                          prints: widget.prints,
                          onLight: _toggleLight,
                        ),
                      _ => _bench(frame, s),
                    },
                  ),
                ],
              ),
            ),
          ],
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
                  color: KalloScope.colorsOf(context).ink.withValues(alpha: 0.16),
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
              builder: (BuildContext context, BoxConstraints constraints) {
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
                        technicalTerms: widget.technicalTerms,
                        onTechnicalTerms: widget.onTechnicalTerms,
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
    );
  }

  /// The bench: the sheet on the left, the record on the right, the status
  /// under it. The table's layout, and the only place that has one.
  Widget _bench(Frame frame, KalloStrings s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: ContactSheet(
                  roll: widget.roll,
                  selected: _index,
                  onSelect: (int index) => setState(() => _selected = index),
                ),
              ),
              _Status(
                left: s.statusBar(
                  frame.number,
                  frame.clock,
                  '${frame.tempC.toStringAsFixed(1)} °C',
                ),
                right: 'sRGB',
              ),
            ],
          ),
        ),
        SizedBox(
          width: 280,
          child: Inspector(
            roll: widget.roll,
            selected: _index,
            onEnlarge: () => setState(() => _place = Place.workbench),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.title,
    required this.subtitle,
    required this.onSettings,
    this.draggable = false,
    this.onDrag,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSettings;

  /// The toolbar is the window's handle when there is no title bar.
  final bool draggable;
  final VoidCallback? onDrag;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.content,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: draggable && onDrag != null ? (_) => onDrag!() : null,
          child: Row(
            children: <Widget>[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: KalloType.title.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: KalloType.small.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
              const Spacer(),
              _IconButton(onTap: onSettings, colours: colors),
            ],
          ),
        ),
    );
  }
}

/// Sliders, drawn: the settings mark, at one weight.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.onTap, required this.colours});

  final VoidCallback onTap;
  final KalloColors colours;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KalloRadius.control),
          ),
          child: CustomPaint(
            size: const Size(16, 16),
            painter: _SlidersPainter(colours.inkMuted),
          ),
        ),
      ),
    );
  }
}

class _SlidersPainter extends CustomPainter {
  const _SlidersPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = colour;
    final Paint dot = Paint()..color = colour;
    canvas.drawLine(const Offset(2, 4.5), const Offset(14, 4.5), line);
    canvas.drawLine(const Offset(2, 11.5), const Offset(14, 11.5), line);
    canvas.drawCircle(const Offset(10.5, 4.5), 1.7, dot);
    canvas.drawCircle(const Offset(5.5, 11.5), 1.7, dot);
  }

  @override
  bool shouldRepaint(_SlidersPainter old) => old.colour != colour;
}

class _Status extends StatelessWidget {
  const _Status({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Text(left, style: KalloType.small.copyWith(color: colors.inkFaint)),
          const Spacer(),
          Text(right, style: KalloType.small.copyWith(color: colors.inkFaint)),
        ],
      ),
    );
  }
}
