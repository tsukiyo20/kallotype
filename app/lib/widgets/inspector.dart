import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// The instrument panel, when it is there.
///
/// A side pane is furniture: it slides away and the work keeps the width it
/// gives back. The child stays laid out at its own width while the frame
/// closes, so the controls do not reflow through every intermediate width on
/// their way out.
class InspectorPane extends StatelessWidget {
  const InspectorPane({
    super.key,
    required this.open,
    required this.child,
    this.width = 304,
  });

  final bool open;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: open ? width : 0),
      duration: KalloMotion.settle,
      curve: KalloMotion.enter,
      builder: (BuildContext context, double value, Widget? child) {
        if (value <= 0.001) {
          return const SizedBox(width: 0);
        }
        return SizedBox(
          width: value,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: width,
              maxWidth: width,
              child: SizedBox(width: width, child: child),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
