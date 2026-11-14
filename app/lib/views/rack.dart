import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';
import '../lab/print_out.dart';

/// The drying rack: prints hanging on a line, and the ones still wet.
///
/// A string across the room and the work hanging from it, newest first. This is
/// the paper as it came out of the enlarger: no frame, no wall, no lamp. The
/// gallery is the same work framed; the rack is where it dries. A print is a
/// render and not a copy, so there is also a corner that says what is being
/// made — the one thing on this string that does not exist yet.
class Rack extends StatelessWidget {
  const Rack({super.key, required this.prints, required this.jobs});

  /// Everything exported, oldest first. The line reads it backwards.
  final List<Print> prints;

  /// The prints being made. A print is a render, not a copy, so there is
  /// always something on the line before there is anything on it.
  final List<PrintJob> jobs;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    if (prints.isEmpty) {
      return ColoredBox(
        color: colors.content,
        child: Center(
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
                style: KalloType.small.copyWith(color: colors.inkFaint),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: colors.content,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints room) {
          final List<Print> newest = prints.reversed.toList();
          // The line hangs the wall's paper: the same area for every print, so
          // a vertical frame is the same print turned and not a bigger one.
          final double base = math.min(
            240,
            math.max(160, room.maxHeight * 0.36),
          );
          final double area = base * base / 1.5;
          double widthOf(Print print) => math.sqrt(area * print.aspect);
          return Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                top: _string,
                child: Container(height: 1, color: colors.hairline),
              ),
              Positioned.fill(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // The peg's top is the string: the print hangs from it, and
                  // a gap there would be a print nailed to the wall.
                  padding: const EdgeInsets.fromLTRB(40, _string, 40, 40),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final Print print in newest)
                        _Pegged(print: print, width: widthOf(print)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 40,
                top: KalloSpace.step5,
                child: Row(
                  children: <Widget>[
                    Text(
                      s.rack,
                      style: KalloType.caption.copyWith(
                        color: colors.inkFaint,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(width: KalloSpace.step3),
                    Text(
                      s.printCount(prints.length),
                      style: KalloType.folio.copyWith(color: colors.inkFaint),
                    ),
                  ],
                ),
              ),
              if (jobs.isNotEmpty)
                Positioned(
                  top: KalloSpace.step4,
                  right: 40,
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

  /// Where the string is. One number, because the line is a line.
  static const double _string = 96;
}

/// A print being made, said quietly in the corner: the frame, its time, and the
/// one thing a rendering cannot tell you, which is how long it will take.
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
      height: 26,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(KalloRadius.control),
        border: Border.all(color: colors.hairline),
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
            '${s.printing}   ${job.frame.number.toString().padLeft(2, '0')}   ·   ${job.frame.clock}',
            style: KalloType.small.copyWith(color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// One print on the string: a peg, the paper, and the two facts worth reading.
class _Pegged extends StatelessWidget {
  const _Pegged({required this.print, required this.width});

  final Print print;
  final double width;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final double border = width * 0.035;
    final double image = width - border * 2;
    // The sheet is the picture's shape: a vertical frame hangs as a tall sheet,
    // not as a landscape one with the middle of the photograph in it.
    final double aspect = print.aspect;
    final String? at = print.at;
    return Padding(
      padding: const EdgeInsets.only(right: KalloSpace.step5),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The peg: the print hangs from the string, so its mark is above
            // it and the paper starts under it.
            Center(
              child: Container(width: 1, height: 36, color: colors.hairline),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.print,
                border: Border.all(color: colors.hairline),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  border,
                  border,
                  border,
                  border * 2.2,
                ),
                child: SizedBox(
                  width: image,
                  height: image / aspect,
                  child: RawImage(
                    image: print.image,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
            const SizedBox(height: KalloSpace.step2),
            Text(
              print.folio,
              style: KalloType.folio.copyWith(color: colors.ink),
            ),
            if (at != null) ...<Widget>[
              const SizedBox(height: 1),
              Text(at, style: KalloType.folio.copyWith(color: colors.inkFaint)),
            ],
          ],
        ),
      ),
    );
  }
}
