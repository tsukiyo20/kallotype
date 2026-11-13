import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../views/steps.dart';

/// The darkroom's four steps, as edge codes rather than a tab bar.
///
/// The marks are the film's: a number and two letters, tabular, spaced like a
/// rebate. They sit on the top edge of the work and they do not push a page —
/// the room changes what is on the bench, not where the bench is.
class StageTabs extends StatelessWidget {
  const StageTabs({super.key, required this.current, required this.onSelect});

  final DarkroomStep current;
  final ValueChanged<DarkroomStep> onSelect;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.content,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: KalloSpace.step5),
          for (final DarkroomStep step in DarkroomStep.values)
            _StepMark(
              step: step,
              label: switch (step) {
                DarkroomStep.select => s.selectStep,
                DarkroomStep.develop => s.developStep,
                DarkroomStep.print => s.printStep,
                DarkroomStep.dry => s.dryStep,
              },
              selected: step == current,
              onTap: () => onSelect(step),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _StepMark extends StatefulWidget {
  const _StepMark({
    required this.step,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final DarkroomStep step;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_StepMark> createState() => _StepMarkState();
}

class _StepMarkState extends State<_StepMark> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final Color code = widget.selected
        ? colors.accent
        : _hover
        ? colors.inkMuted
        : colors.inkFaint;
    final Color label = widget.selected
        ? colors.ink
        : _hover
        ? colors.ink
        : colors.inkMuted;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${widget.step.code} ${widget.step.mark} ${widget.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: KalloMotion.quick,
            curve: KalloMotion.enter,
            margin: const EdgeInsets.only(right: KalloSpace.step1),
            padding: const EdgeInsets.symmetric(horizontal: KalloSpace.step3),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: widget.selected ? colors.accent : colors.content,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${widget.step.code}  ${widget.step.mark}',
                  style: KalloType.caption.copyWith(
                    color: code,
                    letterSpacing: 1.1,
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  style: KalloType.body.copyWith(
                    color: label,
                    fontWeight: widget.selected
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
