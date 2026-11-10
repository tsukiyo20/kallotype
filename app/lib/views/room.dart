import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/chrome.dart';
import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/roll.dart';
import '../sheets/contact_sheet.dart';
import '../widgets/inspector.dart';
import '../widgets/sidebar.dart';
import 'drawer.dart';
import 'places.dart';

/// The window.
///
/// Four planes: a column of places, a toolbar, the sheet, and the inspector.
/// The drawer slides over all of them and puts itself away.
class Room extends StatefulWidget {
  const Room({
    super.key,
    required this.roll,
    required this.locale,
    required this.onLocale,
    required this.technicalTerms,
    required this.onTechnicalTerms,
    this.initiallyOpen = false,
    this.chrome = WindowChrome.plain,
    this.onDragWindow,
  });

  final WindowChrome chrome;
  final VoidCallback? onDragWindow;

  final Roll roll;
  final Locale? locale;
  final ValueChanged<Locale?> onLocale;
  final bool technicalTerms;
  final ValueChanged<bool> onTechnicalTerms;

  /// Opened on the first frame. The golden test uses it; the app does not.
  final bool initiallyOpen;

  @override
  State<Room> createState() => _RoomState();
}

class _RoomState extends State<Room> {
  Place _place = Place.table;
  int _selected = 2;
  late bool _open = widget.initiallyOpen;

  void _closeDrawer() => setState(() => _open = false);

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final Frame frame = widget.roll.frames[_selected];
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _closeDrawer,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
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
                    rollName: widget.roll.id,
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
                        title: widget.roll.id,
                        subtitle:
                            '${widget.roll.frames.length} frames   ·   ${widget.roll.stockLabel}',
                        onSettings: () => setState(() => _open = true),
                      ),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Expanded(
                                    child: ContactSheet(
                                      roll: widget.roll,
                                      selected: _selected,
                                      onSelect: (int index) =>
                                          setState(() => _selected = index),
                                    ),
                                  ),
                                  _Status(
                                    left:
                                        'Frame ${frame.number.toString().padLeft(2, '0')}   ·   ${frame.clock}   ·   ${frame.tempC.toStringAsFixed(1)} °C',
                                    right: 'sRGB',
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 280,
                              child: Inspector(
                                roll: widget.roll,
                                selected: _selected,
                              ),
                            ),
                          ],
                        ),
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
                      color: colors.ink.withValues(alpha: 0.16),
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
