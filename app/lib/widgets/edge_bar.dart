import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// The five places in the room.
///
/// Navigation is not a tab bar. It is edge printing: the codes a lab would
/// stamp on the rebate, so that where you are reads as part of the film rather
/// than as a control.
enum Place { shelf, table, binder, line, drawer }

extension PlaceWords on Place {
  /// The code printed on the rebate.
  String get code => switch (this) {
        Place.shelf => 'SH',
        Place.table => 'TA',
        Place.binder => 'BI',
        Place.line => 'LI',
        Place.drawer => 'DR',
      };

  String get label => switch (this) {
        Place.shelf => 'SHELF',
        Place.table => 'TABLE',
        Place.binder => 'BINDER',
        Place.line => 'LINE',
        Place.drawer => 'DRAWER',
      };

  /// What the place is for, in the room's own words.
  String get note => switch (this) {
        Place.shelf => 'stock, and a new roll',
        Place.table => 'the roll, rolled or unrolled',
        Place.binder => 'curves and provenance',
        Place.line => 'prints, and the queue',
        Place.drawer => 'language, colour, sound',
      };
}

/// The five places, printed along the bottom edge.
class EdgeBar extends StatelessWidget {
  const EdgeBar({super.key, required this.current});

  final Place current;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(height: 1, color: colors.hairline),
        const SizedBox(height: KalloSpace.step3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final Place place in Place.values)
              Expanded(
                child: _PlaceCode(place: place, here: place == current),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlaceCode extends StatelessWidget {
  const _PlaceCode({required this.place, required this.here});

  final Place place;
  final bool here;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final Color ink = here ? colors.accent : colors.inkMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: colors.hairline)),
          child: Text(place.code, style: KalloType.folio.copyWith(color: ink)),
        ),
        const SizedBox(width: KalloSpace.step2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(place.label, style: KalloType.caption.copyWith(color: ink)),
            const SizedBox(height: 3),
            Text(
              place.note,
              style: KalloType.body
                  .copyWith(fontSize: 10.5, color: colors.inkFaint),
            ),
          ],
        ),
      ],
    );
  }
}
