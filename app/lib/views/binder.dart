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
    required this.catalogue,
    required this.exports,
    required this.rollFolder,
  });

  final Roll roll;

  /// Every stock the model carries: this roll's film is on it, with the sheet
  /// its numbers came from and what each field admits to.
  final Catalogue catalogue;

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
    final Stock? stock = catalogue.film(roll.stockId);
    // A reversal is its own picture: there is no print stage, so there is no
    // paper to record and no paper record to show.
    final bool prints = stock?.process != FilmProcess.reversal;
    final Stock? paper = prints ? catalogue.paper(roll.paper) : null;

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
                        (s.film, stock?.short ?? roll.stockLabel),
                        if (prints) (s.paper, roll.paperName(catalogue)),
                      ],
                    ),
                  ],
                ),
                if (stock != null && stock.measured.isNotEmpty) ...<Widget>[
                  const SizedBox(height: KalloSpace.step6),
                  _stock(stock, s.theFilm, colors, s),
                ],
                if (paper != null && paper.measured.isNotEmpty) ...<Widget>[
                  const SizedBox(height: KalloSpace.step6),
                  _stock(paper, s.thePaper, colors, s),
                ],
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

  /// The film's own record: what it is, what sheet it was read from, and one
  /// line per field saying whether that field was measured or borrowed.
  ///
  /// This is the section the product is named after. A stock that borrowed its
  /// dyes is a different claim from one that measured them, and the difference
  /// belongs on the page a person keeps, not in a note nobody opens.
  Widget _stock(
    Stock stock,
    String title,
    KalloColors colors,
    KalloStrings s,
  ) {
    final Provenance provenance = stock.provenance;
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              stock.short,
              style: KalloType.title.copyWith(color: colors.ink),
            ),
            const SizedBox(width: KalloSpace.step2),
            Expanded(
              child: Text(
                stock.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KalloType.small.copyWith(color: colors.inkFaint),
              ),
            ),
          ],
        ),
        if (stock.process != null) ...<Widget>[
          const SizedBox(height: KalloSpace.step1),
          Text(
            s.processNote(stock.process!),
            style: KalloType.body.copyWith(color: colors.inkMuted),
          ),
        ],
        const SizedBox(height: KalloSpace.step3),
        RecordGroup(
          rows: <(String, String)>[
            if (stock.referenceMinutes > 0)
              (
                s.reference,
                '${stock.referenceMinutes.toStringAsFixed(1)} min'
                    '   ·   ${stock.referenceTempC.toStringAsFixed(1)} °C',
              ),
            if (!provenance.isEmpty)
              (s.source, _provenance(provenance, s)),
          ],
        ),
        const SizedBox(height: KalloSpace.step4),
        Text(
          s.measuredAndBorrowed,
          style: KalloType.caption.copyWith(
            color: colors.inkFaint,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: KalloSpace.step2),
        for (final Measured measured in stock.measured)
          _field(measured, colors, s),
      ],
    );
  }

  /// `E-4050 · page 4 · read 2026-11-08`, with whatever the file has.
  String _provenance(Provenance provenance, KalloStrings s) {
    return <String>[
      provenance.publication,
      if (provenance.page.isNotEmpty) s.page(provenance.page),
      if (provenance.retrieved.isNotEmpty) s.readOn(provenance.retrieved),
    ].join('   ·   ');
  }

  /// One field of the record: the name on the left, the verdict on the right,
  /// and the file's sentence under both when it said more than one word.
  ///
  /// Every verdict is set the same. A borrowed line is not marked in a different
  /// colour or a lighter weight, because the word is the mark: `borrowed` is not
  /// a warning about the film, it is a fact about the number, and a page that
  /// made it look like a defect would be editorialising on the model's behalf.
  Widget _field(Measured measured, KalloColors colors, KalloStrings s) {
    final String verdict = s.claim(measured.claim);
    return Padding(
      padding: const EdgeInsets.only(bottom: KalloSpace.step2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                s.field(measured.field).toUpperCase(),
                style: KalloType.caption.copyWith(
                  color: colors.inkFaint,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (verdict.isNotEmpty)
                Text(
                  verdict,
                  style: KalloType.small.copyWith(color: colors.ink),
                ),
            ],
          ),
          if (measured.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 1),
            Text(
              measured.detail,
              style: KalloType.small.copyWith(color: colors.inkMuted),
            ),
          ],
        ],
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
