import 'package:flutter/widgets.dart';

/// The four places you can be.
///
/// Settings is not one of them: it is a drawer in the bench, opened from the
/// toolbar, and it slides over wherever you already are.
enum Place { shelf, table, binder, line }

extension PlaceWords on Place {
  /// The code printed on the rebate. It does not translate: it is the film's.
  String get code => switch (this) {
        Place.shelf => 'SH',
        Place.table => 'TA',
        Place.binder => 'BI',
        Place.line => 'LI',
      };

  String get label => switch (this) {
        Place.shelf => 'Shelf',
        Place.table => 'Table',
        Place.binder => 'Binder',
        Place.line => 'Line',
      };

  /// What the place is for, in the room's own words.
  String get note => switch (this) {
        Place.shelf => 'stock, and a new roll',
        Place.table => 'the roll, rolled or unrolled',
        Place.binder => 'curves and provenance',
        Place.line => 'prints, and the queue',
      };
}

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
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.place != place || old.colour != colour;
}
