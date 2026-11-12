import 'package:flutter/widgets.dart';

/// A loupe: a circle of material, magnified.
///
/// The same glass does the same job on a wall and on a table — a rim, a circle
/// cut out of the material, and the material drawn larger underneath. What the
/// caller puts under it is what differs, and the caller also places it: this
/// widget only knows where its centre is, in its parent's coordinates.
class KalloLens extends StatelessWidget {
  const KalloLens({
    super.key,
    required this.at,
    required this.radius,
    required this.rim,
    required this.child,
  });

  /// The centre, in the parent's coordinates.
  final Offset at;

  /// The circle's radius.
  final double radius;

  /// The rim's colour: a hairline, not a frame.
  final Color rim;

  /// The magnified material, already sized and offset inside the circle.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: at.dx - radius,
      top: at.dy - radius,
      child: IgnorePointer(
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: rim),
          ),
          child: ClipOval(child: child),
        ),
      ),
    );
  }
}
