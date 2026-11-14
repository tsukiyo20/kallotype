import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';
import '../lab/print_out.dart';
import '../widgets/print_viewer.dart';
import '../widgets/wall.dart';

/// The drying rack: lines of prints, pegs, and the ones still wet.
///
/// A rack is a place in a room, not a filmstrip. The prints wrap into as many
/// columns as the window holds and the room scrolls down, because paper is read
/// by walking along a line and then down to the next one — not by dragging a
/// single row sideways off the screen.
///
/// The line is a wire with a little sag, the print hangs from a clip, and the
/// paper has a shadow because it is in the air. Clicking one takes it off the
/// rack and fills the window with it.
class Rack extends StatelessWidget {
  const Rack({
    super.key,
    required this.prints,
    required this.jobs,
    this.topInset = 0,
  });

  /// Everything exported, oldest first. The rack reads it backwards.
  final List<Print> prints;

  /// The prints being made. A print is a render, not a copy, so there is
  /// always something on the line before there is anything on it.
  final List<PrintJob> jobs;

  /// The transparent chrome over the room.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    final KalloRack rack = KalloRack.of(colors.brightness);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.62),
          radius: 1.08,
          colors: <Color>[rack.top, rack.base],
        ),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints room) {
          if (prints.isEmpty) {
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EmptyRackPainter(
                      wire: rack.wire,
                      clip: rack.clip,
                      topInset: topInset,
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          s.rackEmpty,
                          style: KalloType.title.copyWith(color: colors.ink),
                        ),
                        const SizedBox(height: KalloSpace.step1),
                        Text(
                          s.rackEmptyNote,
                          textAlign: TextAlign.center,
                          style: KalloType.small.copyWith(
                            color: colors.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          final List<Print> newest = prints.reversed.toList(growable: false);
          final double side = room.maxWidth >= 900 ? 48 : 28;
          final double available = math.max(220, room.maxWidth - side * 2);
          const double gap = 28;
          final int fit = math.max(
            1,
            ((available + gap) / (210 + gap)).floor(),
          );
          final int columns = math.max(1, math.min(newest.length, fit));
          final double width = math.min(
            260,
            (available - gap * (columns - 1)) / columns,
          );
          final List<List<Print>> lines = <List<Print>>[
            for (int i = 0; i < newest.length; i += columns)
              newest.sublist(i, math.min(i + columns, newest.length)),
          ];
          final double lineWidth = available;

          return Stack(
            children: <Widget>[
              // The frame the wires are tied to. It stays where it is while
              // the paper scrolls past it, because it is part of the room.
              Positioned(
                left: side,
                top: topInset + 8,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 1,
                    color: rack.wire.withValues(alpha: 0.30),
                  ),
                ),
              ),
              Positioned(
                right: side,
                top: topInset + 8,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 1,
                    color: rack.wire.withValues(alpha: 0.30),
                  ),
                ),
              ),
              SingleChildScrollView(
                key: const Key('rack-scroll'),
                padding: EdgeInsets.fromLTRB(
                  side,
                  topInset + KalloSpace.step4,
                  side,
                  40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int i = 0; i < lines.length; i++)
                      _Line(
                        key: ValueKey<String>('rack-line-$i'),
                        prints: lines[i],
                        width: width,
                        lineWidth: lineWidth,
                        gap: gap,
                        rack: rack,
                        first: i == 0,
                        startIndex: i * columns,
                      ),
                  ],
                ),
              ),
              if (jobs.isNotEmpty)
                Positioned(
                  top: topInset + KalloSpace.step3,
                  right: side,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      for (final PrintJob job in jobs)
                        _Running(job: job, s: s, colors: colors),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One line: a wire across the room and the prints clipped to it.
class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.prints,
    required this.width,
    required this.lineWidth,
    required this.gap,
    required this.rack,
    required this.first,
    required this.startIndex,
  });

  final List<Print> prints;
  final double width;
  final double lineWidth;
  final double gap;
  final KalloRack rack;
  final bool first;
  final int startIndex;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final double paper = prints
        .map((Print print) => PrintSheet.heightOf(width, aspect: print.aspect))
        .reduce(math.max);
    final double height = 28 + paper + 54;
    return Padding(
      padding: EdgeInsets.only(bottom: first ? KalloSpace.step5 : 18),
      child: SizedBox(
        width: lineWidth,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              top: _wireY,
              child: CustomPaint(
                size: Size(lineWidth, 6),
                painter: _WirePainter(rack.wire),
              ),
            ),
            for (int i = 0; i < prints.length; i++)
              Positioned(
                left: i * (width + gap),
                top: 0,
                child: _HangingPrint(
                  key: ValueKey<String>('rack-print-${startIndex + i}'),
                  print: prints[i],
                  width: width,
                  rack: rack,
                  colors: colors,
                  angle: ((startIndex + i) % 3 - 1) * 0.004,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const double _wireY = 16;
}

/// A print hanging from a clip, with the facts a printer needs under it.
class _HangingPrint extends StatefulWidget {
  const _HangingPrint({
    super.key,
    required this.print,
    required this.width,
    required this.rack,
    required this.colors,
    required this.angle,
  });

  final Print print;
  final double width;
  final KalloRack rack;
  final KalloColors colors;

  /// A rack is not a grid. A degree this shallow is enough to remember that
  /// the paper was hung by a hand.
  final double angle;

  @override
  State<_HangingPrint> createState() => _HangingPrintState();
}

class _HangingPrintState extends State<_HangingPrint> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Print print = widget.print;
    final String? at = print.at;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => unawaited(showPrintViewer(context, print: print)),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.width,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Transform.rotate(
                      angle: widget.angle,
                      alignment: Alignment.topCenter,
                      child: AnimatedPadding(
                        duration: KalloMotion.instant,
                        padding: EdgeInsets.only(top: _hover ? 0 : 2),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            boxShadow: _hover
                                ? const <BoxShadow>[
                                    BoxShadow(
                                      color: Color(0x2A000000),
                                      blurRadius: 24,
                                      offset: Offset(0, 12),
                                    ),
                                    BoxShadow(
                                      color: Color(0x0F000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ]
                                : KalloShadow.paper,
                          ),
                          child: PrintSheet(
                            width: widget.width,
                            aspect: print.aspect,
                            paper: widget.colors.print,
                            outline: widget.colors.hairline.withValues(
                              alpha: 0.35,
                            ),
                            light: 1,
                            child: RawImage(
                              image: print.image,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: <Widget>[
                        Text(
                          print.folio,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KalloType.folio.copyWith(
                            color: widget.rack.label,
                          ),
                        ),
                        const Spacer(),
                        if (at != null)
                          Text(
                            at,
                            style: KalloType.folio.copyWith(
                              color: widget.rack.label.withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      print.filmDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KalloType.small.copyWith(
                        color: widget.rack.label.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              // The clip is in front of the wire and the paper: it is what
              // holds the sheet to the line.
              Positioned(
                left: 0,
                right: 0,
                top: 3,
                child: Center(
                  child: CustomPaint(
                    size: const Size(22, 28),
                    painter: _ClipPainter(widget.rack.clip),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wire, with the sag a line under paper has.
class _WirePainter extends CustomPainter {
  const _WirePainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Path wire = Path()
      ..moveTo(0, 2)
      ..quadraticBezierTo(size.width / 2, 5.2, size.width, 2);
    // The wire is tied down at both ends; a line that stops in the air is a
    // rule, not a rack.
    canvas.drawLine(
      const Offset(0, 0),
      const Offset(0, 8),
      Paint()
        ..strokeWidth = 1.1
        ..color = colour,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, 8),
      Paint()
        ..strokeWidth = 1.1
        ..color = colour,
    );
    canvas.drawPath(
      wire,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = colour,
    );
    canvas.drawPath(
      wire,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..strokeCap = StrokeCap.round
        ..color = colour.withValues(alpha: 0.32),
    );
  }

  @override
  bool shouldRepaint(_WirePainter old) => old.colour != colour;
}

/// A binder clip: two black jaws and a silver handle.
class _ClipPainter extends CustomPainter {
  const _ClipPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint metal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = colour;
    // The two handles fold in toward each other above the jaw.
    canvas.drawLine(const Offset(5.5, 10), const Offset(9.5, 1.5), metal);
    canvas.drawLine(const Offset(16.5, 10), const Offset(12.5, 1.5), metal);
    canvas.drawLine(const Offset(9.5, 1.5), const Offset(12.5, 1.5), metal);
    // The jaw: a dark trapezoid that bites the paper.
    final Path jaw = Path()
      ..moveTo(4, 10)
      ..lineTo(18, 10)
      ..lineTo(16, 25)
      ..lineTo(6, 25)
      ..close();
    canvas.drawPath(jaw, Paint()..color = colour.withValues(alpha: 0.90));
    canvas.drawLine(
      const Offset(7, 13.5),
      const Offset(15, 13.5),
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ClipPainter old) => old.colour != colour;
}

/// A print being made, said quietly in the corner.
class _Running extends StatelessWidget {
  const _Running({required this.job, required this.s, required this.colors});

  final PrintJob job;
  final KalloStrings s;
  final KalloColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: KalloSpace.step2 - 2),
      padding: const EdgeInsets.symmetric(horizontal: KalloSpace.step3),
      height: 28,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(KalloRadius.pill),
        border: Border.all(color: colors.hairline.withValues(alpha: 0.65)),
        boxShadow: KalloShadow.control,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: KalloSpace.step2),
          Text(
            '${s.printing}   ·   ${job.frame.clock}',
            style: KalloType.small.copyWith(color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// The empty rack: three wires, every one of them empty.
class _EmptyRackPainter extends CustomPainter {
  const _EmptyRackPainter({
    required this.wire,
    required this.clip,
    required this.topInset,
  });

  final Color wire;
  final Color clip;
  final double topInset;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.width >= 900 ? 48 : 28;
    for (int i = 0; i < 3; i++) {
      final double y = topInset + 92 + i * 138;
      final Path path = Path()
        ..moveTo(side, y)
        ..quadraticBezierTo(size.width / 2, y + 4, size.width - side, y);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round
          ..color = wire.withValues(alpha: 0.75),
      );
      for (final double x in <double>[0.34, 0.50, 0.66]) {
        final Offset at = Offset(side + (size.width - side * 2) * x, y + 1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: at, width: 15, height: 19),
            const Radius.circular(2.2),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = clip.withValues(alpha: 0.48),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EmptyRackPainter old) =>
      old.wire != wire || old.clip != clip || old.topInset != topInset;
}
