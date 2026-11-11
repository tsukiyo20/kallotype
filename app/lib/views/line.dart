import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';

/// The line: prints drying.
///
/// A string across the room and the work hanging from it, newest first, because
/// the line is what happened and the gallery is what it looked like. Nothing
/// here is a queue yet — a print is a file copied into the export folder, which
/// takes no time — so what hangs is what has been done, not what is running.
class Line extends StatelessWidget {
  const Line({super.key, required this.prints});

  /// Everything exported, oldest first. The line reads it backwards.
  final List<Print> prints;

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
                s.lineEmpty,
                style: KalloType.title.copyWith(color: colors.ink),
              ),
              const SizedBox(height: KalloSpace.step1),
              Text(
                s.lineEmptyNote,
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
          final double width = math.min(240, math.max(160, room.maxHeight * 0.36));
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
                        _Pegged(print: print, width: width),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 40,
                top: KalloSpace.step5,
                child: Text(
                  s.printCount(prints.length),
                  style: KalloType.caption.copyWith(
                    color: colors.inkFaint,
                    letterSpacing: 1.4,
                  ),
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
                padding: EdgeInsets.fromLTRB(border, border, border, border * 2.2),
                child: SizedBox(
                  width: image,
                  height: image / 1.5,
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
              Text(
                at,
                style: KalloType.folio.copyWith(color: colors.inkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
