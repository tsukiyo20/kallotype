import 'dart:io';

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/exports.dart';
import '../lab/roll.dart';
import '../lab/stock.dart';
import '../widgets/curves.dart';
import '../widgets/record.dart';

/// The binder: where this roll came from, in the paper voice.
///
/// Reference and not a step: nothing here changes anything. It is the record a
/// darkroom keeps — which photograph, which film, which paper, which five
/// times — and it is the one place in the product where a path belongs, because
/// a record that cannot say where a file is is a memory.
class Binder extends StatelessWidget {
  const Binder({
    super.key,
    required this.roll,
    required this.exports,
    required this.rollFolder,
  });

  final Roll roll;

  /// Where the prints are, and where the roll is, resolved at the top of the
  /// app: a record that cannot say where a file is is a memory.
  final Directory? exports;
  final Directory? rollFolder;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    final bool charted = roll.frames.every((Frame frame) => frame.isMeasured);
    final String? photo = roll.photo;

    return ColoredBox(
      color: colors.content,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 48),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  s.placeLabel('binder'),
                  style: KalloType.title.copyWith(fontSize: 26, color: colors.ink),
                ),
                const SizedBox(height: KalloSpace.step2),
                Text(
                  s.binderNote,
                  style: KalloType.body.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: KalloSpace.step6),
                _section(
                  s.theRoll,
                  colors,
                  children: <Widget>[
                    RecordGroup(
                      rows: <(String, String)>[
                        (s.rollName(roll.number), s.frames(roll.frames.length)),
                        if (photo != null)
                          (s.photograph, photo.split(Platform.pathSeparator).last),
                        (s.film, roll.stockLabel),
                        (s.paper, Stocks.paperShort),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: KalloSpace.step6),
                _section(
                  s.theLadder,
                  colors,
                  children: <Widget>[
                    RecordGroup(
                      rows: <(String, String)>[
                        for (final Frame frame in roll.frames)
                          (
                            '${frame.number.toString().padLeft(2, '0')}   ·   ${frame.clock}',
                            <String>[
                              '${frame.tempC.toStringAsFixed(1)} °C',
                              if (frame.gamma != null)
                                frame.gamma!
                                    .map((double v) => v.toStringAsFixed(2))
                                    .join('  '),
                            ].join('   ·   '),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: KalloSpace.step6),
                _section(
                  s.theCurves,
                  colors,
                  children: <Widget>[
                    if (charted)
                      KalloCurves(
                        series: <List<double>>[
                          for (final Frame frame in roll.frames)
                            frame.toneCurve!,
                        ],
                        height: 140,
                      )
                    else
                      Text(
                        s.noCurve,
                        style: KalloType.body.copyWith(color: colors.inkMuted),
                      ),
                  ],
                ),
                const SizedBox(height: KalloSpace.step6),
                _section(
                  s.theFiles,
                  colors,
                  children: <Widget>[
                    RecordGroup(
                      rows: <(String, String)>[
                        (s.rollFolder, Exports.display(rollFolder?.path)),
                        (s.printsFolder, Exports.display(exports?.path)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    String title,
    KalloColors colors, {
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: KalloType.caption.copyWith(
            color: colors.inkFaint,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: KalloSpace.step2),
        ...children,
      ],
    );
  }
}
