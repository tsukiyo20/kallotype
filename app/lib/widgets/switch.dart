import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// A switch: a dot and a label, the one control in the app that is a state.
///
/// It is the lamp on the wall and the loupe on the table — the same object,
/// because both answer "is this on?" and the answer is a dot and a word.
class KalloSwitch extends StatefulWidget {
  const KalloSwitch({
    super.key,
    required this.label,
    required this.control,
    required this.on,
    required this.onTap,
  });

  final String label;

  /// What the control is made of: the wall's own light, or the table's ink.
  final Color control;

  final bool on;
  final VoidCallback onTap;

  @override
  State<KalloSwitch> createState() => _KalloSwitchState();
}

class _KalloSwitchState extends State<KalloSwitch> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color control = widget.control;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: KalloMotion.instant,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: KalloSpace.step3),
          decoration: BoxDecoration(
            color: control.withValues(alpha: _hover ? 0.10 : 0.04),
            borderRadius: BorderRadius.circular(KalloRadius.control),
            border: Border.all(
              color: control.withValues(alpha: _hover ? 0.28 : 0.16),
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
                  color: widget.on ? control : null,
                  border: widget.on
                      ? null
                      : Border.all(color: control.withValues(alpha: 0.45)),
                ),
              ),
              const SizedBox(width: KalloSpace.step2),
              Text(
                widget.label,
                style: KalloType.small.copyWith(
                  color: control.withValues(alpha: _hover ? 0.92 : 0.70),
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
