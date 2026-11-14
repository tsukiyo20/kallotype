import 'package:flutter/widgets.dart';

/// The two shadows the product draws, as pre-rendered nine-patches.
///
/// A [BoxShadow] is a blur: the engine allocates window-sized offscreen
/// surfaces for it, even when the box is small. These assets are the same
/// shadow baked once, so a room of paper and a sheet over the window cost a
/// texture instead of a blur pass.
enum KalloShadowKind { paper, sheet }

@immutable
class _KalloShadow {
  const _KalloShadow({
    required this.asset,
    required this.pad,
    required this.centerSlice,
  });

  final String asset;

  /// The transparent margin around the child's rectangle.
  final double pad;

  /// The part of the image that may stretch. The corners keep the blur.
  final Rect centerSlice;

  static const _KalloShadow paper = _KalloShadow(
    asset: 'assets/shadow-paper.png',
    pad: 64,
    centerSlice: Rect.fromLTRB(64, 64, 320, 320),
  );

  static const _KalloShadow sheet = _KalloShadow(
    asset: 'assets/shadow-sheet.png',
    pad: 96,
    centerSlice: Rect.fromLTRB(96, 96, 416, 416),
  );

  static _KalloShadow of(KalloShadowKind kind) =>
      kind == KalloShadowKind.paper ? paper : sheet;
}

/// Puts a baked shadow behind [child].
///
/// The child is the sheet itself; the shadow extends [pad] beyond it. The
/// stack is not clipped, so a sheet at the edge of a room can still cast its
/// shadow into the room.
class KalloShadowBox extends StatelessWidget {
  const KalloShadowBox({super.key, required this.kind, required this.child});

  final KalloShadowKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _KalloShadow shadow = _KalloShadow.of(kind);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          left: -shadow.pad,
          top: -shadow.pad,
          right: -shadow.pad,
          bottom: -shadow.pad,
          child: IgnorePointer(
            child: Image.asset(
              shadow.asset,
              fit: BoxFit.fill,
              centerSlice: shadow.centerSlice,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
