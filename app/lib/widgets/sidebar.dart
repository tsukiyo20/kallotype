import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../views/places.dart';

/// The column of places, and the rolls under them.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.current,
    required this.onSelect,
    required this.rolls,
    required this.rollName,
    required this.frameCount,
    this.topInset = 12,
  });

  /// Room for the traffic lights when the title bar is hidden.
  final double topInset;

  final Place current;
  final ValueChanged<Place> onSelect;

  /// How many rolls there are. One, until the model is behind an FFI.
  final int rolls;
  final String rollName;
  final int frameCount;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return ColoredBox(
      color: colors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: topInset),
          _Header(s.library, colors),
          for (final Place place in Place.values)
            _Item(
              selected: place == current,
              label: s.placeLabel(place.name),
              icon: PlaceIcon(
                place: place,
                colour: place == current ? colors.accent : colors.inkMuted,
              ),
              onTap: () => onSelect(place),
            ),
          const SizedBox(height: 18),
          _Header(s.rolls, colors),
          _Item(
            selected: current == Place.table,
            label: rollName,
            trailing: '$frameCount',
            icon: CustomPaint(
              size: const Size(16, 16),
              painter: _RollPainter(
                current == Place.table ? colors.accent : colors.inkMuted,
              ),
            ),
            onTap: () => onSelect(Place.table),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// A roll: a frame with its perforations.
class _RollPainter extends CustomPainter {
  const _RollPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = colour;
    final Paint dot = Paint()..color = colour;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 4.5, 12, 7),
        const Radius.circular(1.5),
      ),
      stroke,
    );
    for (final double x in <double>[4.2, 8, 11.8]) {
      canvas.drawCircle(Offset(x, 2.6), 0.8, dot);
      canvas.drawCircle(Offset(x, 13.4), 0.8, dot);
    }
  }

  @override
  bool shouldRepaint(_RollPainter old) => old.colour != colour;
}

class _Header extends StatelessWidget {
  const _Header(this.text, this.colors);

  final String text;
  final KalloColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: KalloType.caption.copyWith(color: colors.inkFaint),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  final bool selected;
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? colors.accent.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: <Widget>[
                icon,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: KalloType.body.copyWith(
                      fontWeight:
                          selected ? FontWeight.w500 : FontWeight.w400,
                      color: colors.ink,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: KalloType.folio.copyWith(color: colors.inkFaint),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
