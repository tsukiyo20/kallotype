import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';

/// The gallery: the last place. One wall, one print, one light.
///
/// A print is not a picture, it is a sheet of paper reflecting whatever light
/// falls on it. So the room is built the way that physics is built: every
/// surface is a reflectance, the lamp is a single number, and the number is
/// multiplied into each of them.
///
/// Which is what makes the switch worth having. Turn the lamp off and the wall
/// goes to black, the label goes with it, the chrome goes down — and the print
/// does not go out, it stays at a tenth. That is not a filter: it is the eye
/// adapting, and it is the one moment in this app where you are meant to see
/// nothing and then see something.
class Gallery extends StatelessWidget {
  const Gallery({super.key, required this.prints, required this.onLight});

  /// Everything exported, oldest first. The last one hangs: a gallery shows
  /// the work there is, and there is one wall in this one.
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

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final double light = KalloScope.lightOf(context);
    // The paper holds its light better than the room does, for the same reason
    // everything else does not: the eye is the instrument here, not the lamp.
    final double printed = _darkAdaptation + (1 - _darkAdaptation) * light;
    final Print? hanging = prints.isEmpty ? null : prints.last;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints room) {
        final double width = math.max(
          160,
          math.min(room.maxWidth * 0.62, (room.maxHeight - 110) / 0.72),
        );
        final double border = width * 0.030;
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
            Center(
              child: hanging == null
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _Sheet(
                          width: width,
                          border: border,
                          print: hanging,
                          light: printed,
                        ),
                        if (hanging.label.isNotEmpty) ...<Widget>[
                          const SizedBox(height: KalloSpace.step4),
                          Text(
                            hanging.label,
                            style: KalloType.small.copyWith(
                              color: KalloColors.under(_label, light),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ],
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

/// The print: the image the model printed, on paper, with the paper's margin
/// showing.
///
/// A fine print leaves more paper at the bottom than at the top. It costs one
/// number and it is the difference between a print and a screenshot.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.width,
    required this.border,
    required this.print,
    required this.light,
  });

  final double width;
  final double border;
  final Print print;

  /// The light on the print, from a tenth to all of it.
  final double light;

  @override
  Widget build(BuildContext context) {
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
