import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';

/// The gallery: the last place. One wall, every print, one light.
///
/// A print is not a picture, it is a sheet of paper reflecting whatever light
/// falls on it. So the room is built the way that physics is built: every
/// surface is a reflectance, the lamp is a single number, and the number is
/// multiplied into each of them.
///
/// Which is what makes the switch worth having. Turn the lamp off and the wall
/// goes to black, the labels go with it, the chrome goes down — and the prints
/// do not go out, they stay at a tenth. That is not a filter: it is the eye
/// adapting, and it is the one moment in this app where you are meant to see
/// nothing and then see something.
///
/// Everything exported hangs here, because a gallery shows the work there is.
/// The wall is arranged in a grid and not hung like a salon, because a grid is
/// the only arrangement that says nothing about the pictures: five developments
/// of one negative are five equal things, and the wall should not pretend to
/// prefer one.
class Gallery extends StatelessWidget {
  const Gallery({super.key, required this.prints, required this.onLight});

  /// Everything exported, oldest first.
  final List<Print> prints;

  /// The switch belongs to the room, not to the wall.
  final VoidCallback onLight;

  /// The wall: warm, and never neutral, so that the paper reads as paper.
  static const Color _wallTop = Color(0xFF262119);
  static const Color _wallBase = Color(0xFF090807);

  /// The paper the print is on. Warmer and duller than the screen's white,
  /// because it is the one surface here that is a material.
  static const Color _paper = Color(0xFFFFFBF2);

  /// The graphite of a wall label.
  static const Color _label = Color(0xFF9A9387);

  /// In a dark room an eye keeps about this much. Not a fade to nothing: a print
  /// you can still find, and only just.
  static const double _darkAdaptation = 0.10;

  /// The largest a print gets on this wall. One print alone should not become a
  /// billboard, and five in a row should not become stamps.
  static const double _largest = 660;

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final double light = KalloScope.lightOf(context);
    // The paper holds its light better than the room does, for the same reason
    // everything else does not: the eye is the instrument here, not the lamp.
    final double printed = _darkAdaptation + (1 - _darkAdaptation) * light;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints room) {
        const double gap = 28;
        const double margin = 40;
        // The switch floats over the wall, so the wall fades under it rather
        // than putting a panel in front of the work.
        const double floor = 120;
        final double available = math.max(200, room.maxWidth - margin * 2);
        // Three prints across a 1280 window, four across a wide one, and never
        // fewer columns than there are prints to put in them.
        final int fitting =
            math.max(1, math.min(5, ((available + gap) / 328).floor()));
        final int columns = math.max(1, math.min(prints.length, fitting));
        final double paper = math.min(
          math.min(
            (available - gap * (columns - 1)) / columns,
            (room.maxHeight - floor - 40) / 0.74,
          ),
          _largest,
        );
        final int rows = (prints.length / columns).ceil();
        final double height = paper * 0.74 + 30;
        final double content =
            rows * height + math.max(0, rows - 1) * gap;
        final double top = math.max(margin, (room.maxHeight - content) / 2);

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.10),
                  radius: 0.85,
                  colors: <Color>[
                    KalloColors.under(_wallTop, light),
                    KalloColors.under(_wallBase, light),
                  ],
                ),
              ),
            ),
            if (prints.isNotEmpty)
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(margin, top, margin, floor),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    for (final Print print in prints)
                      _Hung(
                        print: print,
                        width: paper,
                        light: light,
                        printed: printed,
                      ),
                  ],
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: floor,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        KalloColors.under(_wallBase, light).withValues(alpha: 0),
                        KalloColors.under(_wallBase, light),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: KalloSpace.step6,
              child: Center(
                child: _LightSwitch(
                  label: s.roomLight,
                  on: light > 0.5,
                  onTap: onLight,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One print on the wall, with the label under it.
class _Hung extends StatelessWidget {
  const _Hung({
    required this.print,
    required this.width,
    required this.light,
    required this.printed,
  });

  final Print print;
  final double width;

  /// The light on the wall, which the label is on.
  final double light;

  /// The light on the print, which holds a little longer.
  final double printed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Sheet(print: print, width: width, light: printed),
          const SizedBox(height: KalloSpace.step3 - 2),
          Text.rich(
            TextSpan(children: _wallLabel(print, light)),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KalloType.caption.copyWith(
              letterSpacing: 0.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// The wall label: what a person would read beside the work.
///
/// The film and the paper are set quiet and the development is set loud,
/// because on a wall of the same negative at five times the only word that
/// differs is the one worth finding. A print whose record was lost is called
/// what its file is called — it is still a print, and it is still here.
List<InlineSpan> _wallLabel(Print print, double light) {
  final Color quiet =
      KalloColors.under(Gallery._label, light).withValues(alpha: 0.60);
  final Color loud = KalloColors.under(Gallery._label, light);
  final List<InlineSpan> spans = <InlineSpan>[];
  void add(String? text, Color colour) {
    if (text == null || text.isEmpty) {
      return;
    }
    if (spans.isNotEmpty) {
      spans.add(TextSpan(text: '   ·   ', style: TextStyle(color: quiet)));
    }
    spans.add(TextSpan(text: text, style: TextStyle(color: colour)));
  }

  add(print.film, quiet);
  add(print.clock, loud);
  add(print.paper, quiet);
  if (spans.isEmpty) {
    spans.add(TextSpan(text: print.name, style: TextStyle(color: quiet)));
  }
  return spans;
}

/// The print: the image the model printed, on paper, with the paper's margin
/// showing.
///
/// A fine print leaves more paper at the bottom than at the top. It costs one
/// number and it is the difference between a print and a screenshot.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.print,
    required this.width,
    required this.light,
  });

  final Print print;
  final double width;

  /// The light on the print, from a tenth to all of it.
  final double light;

  @override
  Widget build(BuildContext context) {
    final double border = width * 0.030;
    final double image = width - border * 2;
    final Widget pixels = RawImage(
      image: print.image,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KalloColors.under(Gallery._paper, light),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(border, border, border, border * 2.2),
        child: SizedBox(
          width: image,
          height: image / 1.5,
          child: light >= 1
              ? pixels
              : ColorFiltered(
                  // A print under less light is the same print with every
                  // channel multiplied, which is what the matrix is and what
                  // opacity would not be: fading to the wall is not dimming.
                  colorFilter: ColorFilter.matrix(<double>[
                    light, 0, 0, 0, 0, //
                    0, light, 0, 0, 0, //
                    0, 0, light, 0, 0, //
                    0, 0, 0, 1, 0, //
                  ]),
                  child: pixels,
                ),
        ),
      ),
    );
  }
}

/// The switch on the wall, and the only thing in this room that is its own
/// light: it does not dim, because a control you cannot find in the dark is a
/// control that has been taken away.
class _LightSwitch extends StatefulWidget {
  const _LightSwitch({
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  State<_LightSwitch> createState() => _LightSwitchState();
}

class _LightSwitchState extends State<_LightSwitch> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const Color slate = Color(0xFFF4EFE6);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const Key('light'),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: KalloMotion.instant,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: KalloSpace.step3),
          decoration: BoxDecoration(
            color: slate.withValues(alpha: _hover ? 0.10 : 0.04),
            borderRadius: BorderRadius.circular(KalloRadius.control),
            border: Border.all(
              color: slate.withValues(alpha: _hover ? 0.28 : 0.16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: KalloMotion.instant,
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.on ? slate : null,
                  border: widget.on
                      ? null
                      : Border.all(color: slate.withValues(alpha: 0.45)),
                ),
              ),
              const SizedBox(width: KalloSpace.step2),
              Text(
                widget.label,
                style: KalloType.small.copyWith(
                  color: slate.withValues(alpha: _hover ? 0.92 : 0.70),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
