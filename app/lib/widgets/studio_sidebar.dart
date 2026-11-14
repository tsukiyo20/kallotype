import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../views/chambers.dart';

/// The three places, and the one setting.
///
/// The sidebar is a source list, not a dashboard. It says where a person can
/// go and nothing about the strip they are working on: the work belongs to the
/// room, and a title and a material line do not become global facts because
/// they fit in a column.
class StudioSidebar extends StatelessWidget {
  const StudioSidebar({
    super.key,
    required this.chamber,
    required this.onChamber,
    required this.galleryCount,
    required this.onSettings,
    this.topInset = 12,
  });

  final Chamber chamber;
  final ValueChanged<Chamber> onChamber;

  /// The prints hanging in the gallery: the room's count.
  final int galleryCount;

  final VoidCallback onSettings;

  /// Room for the traffic lights when the title bar is hidden.
  final double topInset;

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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 16, 18),
            child: Text(
              'KALLOTYPE',
              style: KalloType.caption.copyWith(
                color: colors.inkFaint,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _Room(
            label: s.darkroom,
            mark: _DarkroomMark(),
            selected: chamber == Chamber.darkroom,
            onTap: () => onChamber(Chamber.darkroom),
          ),
          _Room(
            label: s.rack,
            mark: _RackMark(),
            selected: chamber == Chamber.rack,
            onTap: () => onChamber(Chamber.rack),
          ),
          _Room(
            label: s.galleryRoom,
            mark: _GalleryMark(),
            selected: chamber == Chamber.gallery,
            trailing: galleryCount > 0 ? '$galleryCount' : null,
            onTap: () => onChamber(Chamber.gallery),
          ),
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
    final Color ink = widget.selected
        ? colors.ink
        : _hover
        ? colors.ink
        : colors.inkMuted;
    final Color mark = widget.selected
        ? colors.accent
        : _hover
        ? colors.ink
        : colors.inkMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: KalloMotion.quick,
            curve: KalloMotion.enter,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.fillStrong
                  : _hover
                  ? colors.fill
                  : null,
              borderRadius: BorderRadius.circular(KalloRadius.control),
            ),
            child: Row(
              children: <Widget>[
                ColorFiltered(
                  colorFilter: ColorFilter.mode(mark, BlendMode.srcIn),
                  child: widget.mark,
                ),
                const SizedBox(width: KalloSpace.step3),
                Expanded(
                  child: Text(
                    widget.label,
                    style: KalloType.body.copyWith(
                      color: ink,
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
          child: AnimatedContainer(
            duration: KalloMotion.quick,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: _hover ? colors.fill : null,
              borderRadius: BorderRadius.circular(KalloRadius.control),
            ),
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
                  style: KalloType.body.copyWith(
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

/// The rack's mark: a line, two pegs, two sheets.
class _RackMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(16, 16),
    painter: _RackPainter(KalloScope.colorsOf(context).inkMuted),
  );
}

class _RackPainter extends CustomPainter {
  const _RackPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = colour;
    canvas.drawLine(const Offset(1.5, 4), const Offset(14.5, 4), stroke);
    for (final double x in <double>[4.5, 11.5]) {
      canvas.drawLine(Offset(x, 4), Offset(x, 6), stroke);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 2, 6, 4, 6),
          const Radius.circular(0.8),
        ),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_RackPainter old) => old.colour != colour;
}

/// The gallery's mark: a print on a wire.
class _GalleryMark extends StatelessWidget {
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
