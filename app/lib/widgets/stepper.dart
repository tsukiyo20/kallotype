import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// A number a hand can move: the enlarger's timer, or one colour's pack.
///
/// It is a stepper and not a text field because it is a dial in a darkroom:
/// the value goes up and down in known steps, and a keyboard is not the thing
/// on the bench.
class KalloStepper extends StatelessWidget {
  const KalloStepper({
    super.key,
    required this.label,
    required this.value,
    this.onMinus,
    this.onPlus,
    this.width = 132,
  });

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final double width;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return SizedBox(
      width: width,
      child: Row(
        children: <Widget>[
          Text(label, style: KalloType.small.copyWith(color: colors.inkMuted)),
          const Spacer(),
          Container(
            height: 24,
            decoration: BoxDecoration(
              border: Border.all(color: colors.hairline),
              borderRadius: BorderRadius.circular(KalloRadius.control - 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Step(mark: '−', onTap: onMinus, colour: colors.inkMuted),
                SizedBox(
                  width: 42,
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: KalloType.data.copyWith(color: colors.ink),
                  ),
                ),
                _Step(mark: '+', onTap: onPlus, colour: colors.inkMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatefulWidget {
  const _Step({required this.mark, required this.onTap, required this.colour});

  final String mark;
  final VoidCallback? onTap;
  final Color colour;

  @override
  State<_Step> createState() => _StepState();
}

class _StepState extends State<_Step> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool live = widget.onTap != null;
    return MouseRegion(
      cursor: live ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          color: _hover && live ? KalloScope.colorsOf(context).ground : null,
          child: Text(
            widget.mark,
            style: KalloType.body.copyWith(
              color: live
                  ? widget.colour
                  : widget.colour.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
