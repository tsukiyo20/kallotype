import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/clock.dart';
import '../lab/strip.dart';
import '../views/chambers.dart';

/// The two rooms, and the one strip in the darkroom.
///
/// The sidebar is a place, not a menu: the darkroom and the gallery are the
/// only two things it can make current, and the work underneath is the strip
/// that is on the bench. It says what the strip is made of, not how to operate
/// it — the steps belong to the room.
class StudioSidebar extends StatelessWidget {
  const StudioSidebar({
    super.key,
    required this.chamber,
    required this.onChamber,
    required this.strip,
    required this.filmShort,
    required this.paperShort,
    required this.galleryCount,
    required this.testCount,
    required this.onSettings,
    this.topInset = 12,
  });

  final Chamber chamber;
  final ValueChanged<Chamber> onChamber;

  final TestStrip strip;
  final String filmShort;
  final String paperShort;

  /// The prints hanging in the gallery: the room's count.
  final int galleryCount;

  /// The prints on the strip: the work's count.
  final int testCount;

  final VoidCallback onSettings;

  /// Room for the traffic lights when the title bar is hidden.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    final String? name = strip.name;
    final double? first = strip.balanceFrom;
    return ColoredBox(
      color: colors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(height: topInset),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 16, 16),
            child: Text(
              'KALLOTYPE',
              style: KalloType.caption.copyWith(
                color: colors.inkFaint,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _Room(
            label: s.darkroom,
            mark: const _DarkroomMark(),
            selected: chamber == Chamber.darkroom,
            onTap: () => onChamber(Chamber.darkroom),
          ),
          _Room(
            label: s.galleryRoom,
            mark: const _GalleryMark(),
            selected: chamber == Chamber.gallery,
            trailing: galleryCount > 0 ? '$galleryCount' : null,
            onTap: () => onChamber(Chamber.gallery),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(height: 1, color: colors.hairline),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              s.thisStrip,
              style: KalloType.caption.copyWith(
                color: colors.inkFaint,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              name ?? s.noPhotographChosen,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KalloType.title.copyWith(
                color: name == null ? colors.inkFaint : colors.ink,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              strip.photo == null
                  ? s.darkroomNote
                  : '$filmShort   ·   $paperShort',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: KalloType.small.copyWith(color: colors.inkMuted),
            ),
          ),
          if (strip.photo != null) ...<Widget>[
            const SizedBox(height: 14),
            _Fact(label: s.testStrip, value: s.stripCount(testCount)),
            if (first != null)
              _Fact(label: s.sameExposure, value: darkroomClock(first)),
          ],
          const Spacer(),
          _SettingsItem(onTap: onSettings),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Room extends StatefulWidget {
  const _Room({
    required this.label,
    required this.mark,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final Widget mark;
  final bool selected;
  final VoidCallback onTap;
  final String? trailing;

  @override
  State<_Room> createState() => _RoomState();
}

class _RoomState extends State<_Room> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final bool lit = widget.selected || _hover;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: widget.selected ? colors.accent : colors.sidebar,
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: Row(
              children: <Widget>[
                widget.mark,
                const SizedBox(width: KalloSpace.step3),
                Expanded(
                  child: Text(
                    widget.label,
                    style: KalloType.body.copyWith(
                      color: lit ? colors.ink : colors.inkMuted,
                      fontWeight: widget.selected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (widget.trailing != null)
                  Text(
                    widget.trailing!,
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

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 3, 20, 3),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KalloType.small.copyWith(color: colors.inkFaint),
            ),
          ),
          const SizedBox(width: KalloSpace.step2),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: KalloType.data.copyWith(color: colors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatefulWidget {
  const _SettingsItem({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SettingsItem> createState() => _SettingsItemState();
}

class _SettingsItemState extends State<_SettingsItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CustomPaint(
                    painter: _SlidersMark(
                      _hover ? colors.ink : colors.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: KalloSpace.step3),
                Text(
                  s.settings,
                  style: KalloType.small.copyWith(
                    color: _hover ? colors.ink : colors.inkMuted,
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

/// The darkroom's mark: a safelight, its shade and the light under it.
class _DarkroomMark extends StatelessWidget {
  const _DarkroomMark();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(16, 16),
    painter: _DarkroomPainter(KalloScope.colorsOf(context).inkMuted),
  );
}

class _DarkroomPainter extends CustomPainter {
  const _DarkroomPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = colour;
    final Path shade = Path()
      ..moveTo(4.5, 3)
      ..lineTo(11.5, 3)
      ..lineTo(13.5, 8)
      ..lineTo(2.5, 8)
      ..close();
    canvas.drawPath(shade, stroke);
    canvas.drawLine(const Offset(8, 8), const Offset(8, 9.4), stroke);
    canvas.drawCircle(const Offset(8, 11), 1.6, Paint()..color = colour);
    canvas.drawLine(const Offset(2, 13.5), const Offset(5, 13.5), stroke);
    canvas.drawLine(const Offset(11, 13.5), const Offset(14, 13.5), stroke);
  }

  @override
  bool shouldRepaint(_DarkroomPainter old) => old.colour != colour;
}

/// The gallery's mark: a print on a wire.
class _GalleryMark extends StatelessWidget {
  const _GalleryMark();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(16, 16),
    painter: _GalleryPainter(KalloScope.colorsOf(context).inkMuted),
  );
}

class _GalleryPainter extends CustomPainter {
  const _GalleryPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = colour;
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

  @override
  bool shouldRepaint(_GalleryPainter old) => old.colour != colour;
}

class _SlidersMark extends CustomPainter {
  const _SlidersMark(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = colour;
    final Paint dot = Paint()..color = colour;
    canvas.drawLine(const Offset(1, 4.5), const Offset(15, 4.5), line);
    canvas.drawLine(const Offset(1, 11.5), const Offset(15, 11.5), line);
    canvas.drawCircle(const Offset(11, 4.5), 1.6, dot);
    canvas.drawCircle(const Offset(5, 11.5), 1.6, dot);
  }

  @override
  bool shouldRepaint(_SlidersMark old) => old.colour != colour;
}
