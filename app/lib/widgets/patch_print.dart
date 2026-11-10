import 'package:flutter/widgets.dart';

/// The wedge on paper: nine patches of dye, side by side.
///
/// The colours arrive already printed — `Frame.printColours` has subtracted the
/// frame's own base and multiplied by the paper. Nothing is decided here, which
/// is why this is a painter and not a picture: there is nothing to draw but the
/// colours the model produced.
class PatchPrint extends StatelessWidget {
  const PatchPrint({super.key, required this.patches});

  final List<Color> patches;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _PatchPainter(patches),
      );
}

class _PatchPainter extends CustomPainter {
  const _PatchPainter(this.patches);

  final List<Color> patches;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width / patches.length;
    final Paint fill = Paint();
    for (int i = 0; i < patches.length; i++) {
      fill.color = patches[i];
      // Half a pixel of overlap, so that no seam shows at a fraction width.
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w + 0.5, size.height), fill);
    }
  }

  @override
  bool shouldRepaint(_PatchPainter old) => old.patches != patches;
}
