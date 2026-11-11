import 'package:flutter/widgets.dart';

/// The places you can be.
///
/// Settings is not one of them: it is a drawer in the bench, opened from the
/// toolbar, and it slides over wherever you already are.
///
/// The order is the work's order — what you have, what you look at it with,
/// what you judge one frame on, what you keep, what you print, and finally
/// where it hangs.
enum Place { shelf, table, workbench, binder, line, gallery }

/// A place's mark: geometric, one weight, drawn rather than imported.
class PlaceIcon extends StatelessWidget {
  const PlaceIcon({super.key, required this.place, required this.colour});

  final Place place;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(16, 16),
      painter: _IconPainter(place, colour),
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.place, this.colour);

  final Place place;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = colour;
    final Rect box = Rect.fromLTWH(2, 3, 12, 10);
    switch (place) {
      case Place.shelf:
        for (final double y in <double>[4.5, 8, 11.5]) {
          canvas.drawLine(Offset(2, y), Offset(14, y), stroke);
        }
      case Place.table:
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(2)),
          stroke,
        );
        canvas.drawLine(const Offset(2, 7), const Offset(14, 7), stroke);
      case Place.workbench:
        // An enlarger: a head, a column, and the easel it throws onto.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 2.5, 8, 3.6),
            const Radius.circular(1),
          ),
          stroke,
        );
        canvas.drawLine(const Offset(8, 6.1), const Offset(8, 11.4), stroke);
        canvas.drawLine(const Offset(3.2, 13), const Offset(12.8, 13), stroke);
      case Place.binder:
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(2)),
          stroke,
        );
        canvas.drawLine(const Offset(6, 3), const Offset(6, 13), stroke);
      case Place.line:
        canvas.drawLine(const Offset(2, 6), const Offset(14, 6), stroke);
        for (final double x in <double>[4, 9, 13]) {
          canvas.drawLine(Offset(x, 6), Offset(x, 11), stroke);
        }
      case Place.gallery:
        // A picture on a wire: the lowest rectangle in the set, and the only
        // one that hangs.
        canvas.drawLine(const Offset(3.2, 5.5), const Offset(8, 2.6), stroke);
        canvas.drawLine(const Offset(12.8, 5.5), const Offset(8, 2.6), stroke);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2.8, 5.5, 10.4, 8),
            const Radius.circular(1),
          ),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.place != place || old.colour != colour;
}
