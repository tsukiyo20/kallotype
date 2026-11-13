import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/clock.dart';

/// The development time, as a ruler.
///
/// A darkroom's timer is a dial, not a form field: the time is one continuous
/// variable and the machine accepts any value, so the five ladder marks are
/// ticks under a ruler rather than five buttons. The handle is the safelight's
/// colour because it is the time being chosen.
class TimeSlider extends StatefulWidget {
  const TimeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onSettled,
    this.min = 1,
    this.max = 20,
    this.step = 0.5,
    this.ticks = const <double>[3, 6, 9, 12, 15],
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onSettled;
  final double min;
  final double max;
  final double step;
  final List<double> ticks;

  @override
  State<TimeSlider> createState() => _TimeSliderState();
}

class _TimeSliderState extends State<TimeSlider> {
  bool _hover = false;
  bool _focus = false;
  bool _dragging = false;
  double? _hoverValue;

  double _quantise(double raw) {
    final double clamped = raw.clamp(widget.min, widget.max);
    final double steps = ((clamped - widget.min) / widget.step).roundToDouble();
    return (widget.min + steps * widget.step).clamp(widget.min, widget.max);
  }

  void _set(double raw) {
    final double value = _quantise(raw);
    if (value != widget.value) {
      widget.onChanged(value);
    }
  }

  double _valueAt(double dx, double width) {
    final double t = width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);
    return widget.min + t * (widget.max - widget.min);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      widget.onChanged(_quantise(widget.value - widget.step));
      widget.onSettled?.call(_quantise(widget.value - widget.step));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      widget.onChanged(_quantise(widget.value + widget.step));
      widget.onSettled?.call(_quantise(widget.value + widget.step));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final bool lit = _hover || _focus || _dragging;
    return Focus(
      onKeyEvent: _key,
      onFocusChange: (bool focus) => setState(() => _focus = focus),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          return Semantics(
            slider: true,
            label: 'development',
            value: darkroomClock(widget.value),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              onHover: (PointerHoverEvent event) => setState(
                () => _hoverValue = _quantise(
                  _valueAt(event.localPosition.dx, width),
                ),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails details) {
                  final double value = _quantise(
                    _valueAt(details.localPosition.dx, width),
                  );
                  widget.onChanged(value);
                  widget.onSettled?.call(value);
                },
                onHorizontalDragStart: (DragStartDetails details) {
                  setState(() => _dragging = true);
                  _set(_valueAt(details.localPosition.dx, width));
                },
                onHorizontalDragUpdate: (DragUpdateDetails details) =>
                    _set(_valueAt(details.localPosition.dx, width)),
                onHorizontalDragEnd: (_) {
                  setState(() => _dragging = false);
                  widget.onSettled?.call(widget.value);
                },
                onHorizontalDragCancel: () {
                  setState(() => _dragging = false);
                  widget.onSettled?.call(widget.value);
                },
                child: CustomPaint(
                  size: Size(width, 58),
                  painter: _RulerPainter(
                    value: widget.value,
                    min: widget.min,
                    max: widget.max,
                    ticks: widget.ticks,
                    hover: _hoverValue,
                    lit: lit,
                    ink: colors.ink,
                    muted: colors.inkFaint,
                    accent: colors.accent,
                    hairline: colors.hairline,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.ticks,
    required this.hover,
    required this.lit,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.hairline,
  });

  final double value;
  final double min;
  final double max;
  final List<double> ticks;
  final double? hover;
  final bool lit;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color hairline;

  double _x(double minutes, double width) =>
      (minutes - min) / (max - min) * width;

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double y = 18;
    final Paint hair = Paint()
      ..color = hairline
      ..strokeWidth = 1;
    final Paint accentPaint = Paint()..color = accent;

    canvas.drawLine(Offset(0, y + 0.5), Offset(width, y + 0.5), hair);
    // The five ladder marks: a tick, and its clock underneath.
    for (final double minutes in ticks) {
      final double x = _x(minutes, width);
      canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), hair);
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: darkroomClock(minutes),
          style: KalloType.folio.copyWith(
            color: minutes == value ? ink : muted,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x - label.width / 2, y + 10));
    }
    // Where the pointer is, before it commits: a hairline that says the time
    // the click would choose.
    final double? hover = this.hover;
    if (lit && hover != null && hover != value) {
      final double hx = _x(hover, width);
      canvas.drawLine(
        Offset(hx, y - 9),
        Offset(hx, y + 7),
        Paint()
          ..color = muted.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
    final double x = _x(value, width);
    // The travelled part of the ruler is the safelight's; the rest is a ruler.
    canvas.drawLine(
      Offset(0, y + 0.5),
      Offset(x, y + 0.5),
      Paint()
        ..color = accent
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(x, y - 10),
      Offset(x, y + 9),
      Paint()
        ..color = ink
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(Offset(x, y + 0.5), 3, accentPaint);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.value != value ||
      old.hover != hover ||
      old.lit != lit ||
      old.min != min ||
      old.max != max;
}
