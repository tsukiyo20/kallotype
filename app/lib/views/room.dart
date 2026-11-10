import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/chrome.dart';
import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';
import '../lab/roll.dart';
import '../sheets/contact_sheet.dart';
import '../widgets/inspector.dart';
import '../widgets/sidebar.dart';
import 'drawer.dart';
import 'gallery.dart';
import 'places.dart';

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
    this.prints = const <Print>[],
    required this.locale,
    required this.onLocale,
    required this.technicalTerms,
    required this.onTechnicalTerms,
    this.initiallyOpen = false,
    this.initialPlace = Place.table,
    this.chrome = WindowChrome.plain,
    this.onDragWindow,
  });

  final WindowChrome chrome;
  final VoidCallback? onDragWindow;

  final Roll roll;

  /// What has been exported, in the order it was printed. Nothing is a state
  /// the room can show: the gallery is a wall, and a wall can be empty.
  final List<Print> prints;

  final Locale? locale;
  final ValueChanged<Locale?> onLocale;
  final bool technicalTerms;
  final ValueChanged<bool> onTechnicalTerms;

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
    final Frame frame = widget.roll.frames[_selected];
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
                onSelect: (Place place) => setState(() {
                  _place = place;
                  _open = false;
                }),
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
                        '${s.frames(widget.roll.frames.length)}   ·   ${widget.roll.stockLabel}',
                    onSettings: () => setState(() => _open = true),
                  ),
                  Expanded(
                    child: _place == Place.gallery
                        ? Gallery(prints: widget.prints, onLight: _toggleLight)
                        : _bench(frame, s),
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
                        locale: widget.locale,
                        onLocale: widget.onLocale,
                        technicalTerms: widget.technicalTerms,
                        onTechnicalTerms: widget.onTechnicalTerms,
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

  /// The bench: the field on the left, the record on the right, the status
  /// under it. Everything that is not the gallery.
  Widget _bench(Frame frame, KalloStrings s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: switch (_place) {
                  Place.table => ContactSheet(
                      roll: widget.roll,
                      selected: _selected,
                      onSelect: (int index) =>
                          setState(() => _selected = index),
                    ),
                  _ => _Unbuilt(place: _place),
                },
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
          child: Inspector(roll: widget.roll, selected: _selected),
        ),
      ],
    );
  }
}

/// A place on the map with nothing in it yet.
///
/// It says what it is for rather than that it is missing: a place that has not
/// been filled is a room, and a blank field is a bug.
class _Unbuilt extends StatelessWidget {
  const _Unbuilt({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return ColoredBox(
      color: colors.content,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              s.placeLabel(place.name),
              style: KalloType.title.copyWith(color: colors.ink),
            ),
            const SizedBox(height: KalloSpace.step1),
            Text(
              s.placeNote(place.name),
              style: KalloType.small.copyWith(color: colors.inkFaint),
            ),
          ],
        ),
      ),
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
