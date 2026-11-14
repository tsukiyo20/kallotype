import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../views/steps.dart';

/// The darkroom's three steps, as one small capsule.
///
/// The steps used to be edge codes on a bar across the window. A bar is a
/// second navigation and a line under it is a second edge; both pulled the eye
/// off the work. This is the Apple control at the top of the room: a recessive
/// track, a raised segment, and the edge code still sitting inside the word.
/// No rule, no full-width background.
class StageTabs extends StatelessWidget {
  const StageTabs({super.key, required this.current, required this.onSelect});

  final DarkroomStep current;
  final ValueChanged<DarkroomStep> onSelect;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return Semantics(
      container: true,
      label: s.darkroom,
      child: Container(
        key: const Key('stage-tabs'),
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(KalloRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final DarkroomStep step in DarkroomStep.values)
              _StepMark(
                step: step,
                label: switch (step) {
                  DarkroomStep.select => s.selectStep,
                  DarkroomStep.develop => s.developStep,
                  DarkroomStep.print => s.printStep,
                },
                selected: step == current,
                onTap: () => onSelect(step),
              ),
          ],
        ),
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
    final bool lifted = widget.selected;
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
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: lifted
                  ? colors.elevated
                  : _hover
                  ? colors.fillStrong
                  : colors.fill,
              borderRadius: BorderRadius.circular(KalloRadius.pill),
              boxShadow: lifted ? KalloShadow.control : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.step.code,
                  style: KalloType.folio.copyWith(
                    color: lifted ? colors.accent : colors.inkFaint,
                    fontSize: 9.5,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: KalloType.body.copyWith(
                    fontSize: 12.5,
                    color: lifted
                        ? colors.ink
                        : _hover
                        ? colors.ink
                        : colors.inkMuted,
                    fontWeight: lifted ? FontWeight.w600 : FontWeight.w400,
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
