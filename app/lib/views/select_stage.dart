import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/stock.dart';
import '../lab/strip.dart';
import '../widgets/button.dart';
import '../widgets/chip.dart';

/// The first step: the photograph, before the developer.
///
/// The original is the thing being worked on, so it is what the page is about;
/// the materials are a column beside it, the way a darkroom has the enlarger in
/// front of the paper shelves. Choosing a film or a paper is taking a box off
/// the shelf, not setting a preference — a new box starts a new strip.
class SelectStage extends StatelessWidget {
  const SelectStage({
    super.key,
    required this.strip,
    required this.photograph,
    required this.catalogue,
    required this.onChoosePhoto,
    required this.onFilm,
    required this.onPaper,
    required this.onGoDevelop,
    required this.onClear,
  });

  final TestStrip strip;
  final ui.Image? photograph;
  final Catalogue catalogue;

  final VoidCallback onChoosePhoto;
  final ValueChanged<Stock> onFilm;
  final ValueChanged<Stock?> onPaper;
  final VoidCallback onGoDevelop;
  final VoidCallback onClear;

  Stock? get _film => catalogue.film(strip.stockId);
  Stock? get _paper =>
      strip.paperId == null ? null : catalogue.paper(strip.paperId!);

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ColoredBox(
            color: colors.ground,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 22, 32, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        s.theOriginal,
                        style: KalloType.caption.copyWith(
                          color: colors.inkFaint,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(width: KalloSpace.step3),
                      Expanded(
                        child: Text(
                          strip.name ?? s.noPhotographChosen,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KalloType.small.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                      ),
                      _Quiet(
                        label: photograph == null
                            ? s.choosePhoto
                            : s.changePhoto,
                        onTap: onChoosePhoto,
                      ),
                    ],
                  ),
                  const SizedBox(height: KalloSpace.step4),
                  Expanded(child: _photograph(colors, s)),
                  const SizedBox(height: KalloSpace.step3),
                  Text(
                    photograph == null ? s.choosePhotoNote : '${strip.photo}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KalloType.small.copyWith(color: colors.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 304, child: _materials(colors, s)),
      ],
    );
  }

  Widget _photograph(KalloColors colors, KalloStrings s) {
    final ui.Image? photograph = this.photograph;
    if (photograph == null) {
      return Center(
        child: Column(
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
            const SizedBox(height: KalloSpace.step4),
            Text(
              s.choosePhotoNote,
              textAlign: TextAlign.center,
              style: KalloType.body.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: KalloSpace.step5),
            KalloButton(
              label: s.choosePhoto,
              onTap: onChoosePhoto,
              filled: true,
              height: 34,
            ),
          ],
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: photograph.width / photograph.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.print,
            border: Border.all(color: colors.hairline),
          ),
          child: RawImage(
            image: photograph,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }

  Widget _materials(KalloColors colors, KalloStrings s) {
    final Stock? film = _film;
    final Stock? paper = _paper;
    final List<Stock> papers = catalogue.papersFor(film?.process);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.film,
                    style: KalloType.caption.copyWith(
                      color: colors.inkFaint,
                      letterSpacing: 1.4,
                    ),
                  ),
                  for (final FilmProcess process in FilmProcess.values)
                    if (catalogue.of(process).isNotEmpty) ...<Widget>[
                      const SizedBox(height: KalloSpace.step3),
                      Text(
                        s.processName(process),
                        style: KalloType.small.copyWith(color: colors.inkMuted),
                      ),
                      const SizedBox(height: KalloSpace.step1 + 2),
                      Wrap(
                        spacing: KalloSpace.step1 + 2,
                        runSpacing: KalloSpace.step1 + 2,
                        children: <Widget>[
                          for (final Stock stock in catalogue.of(process))
                            KalloChip(
                              label: stock.short,
                              selected: stock.id == film?.id,
                              compact: true,
                              onTap: () => onFilm(stock),
                            ),
                        ],
                      ),
                    ],
                  if (film != null) ...<Widget>[
                    const SizedBox(height: KalloSpace.step2),
                    Text(
                      film.label,
                      style: KalloType.small.copyWith(color: colors.inkFaint),
                    ),
                  ],
                  if (strip.hasPrints) ...<Widget>[
                    const SizedBox(height: KalloSpace.step4),
                    Text(
                      s.materialsNote,
                      style: KalloType.small.copyWith(color: colors.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.hairline)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  s.paper,
                  style: KalloType.caption.copyWith(
                    color: colors.inkFaint,
                    letterSpacing: 1.4,
                  ),
                ),
                if (papers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: KalloSpace.step2),
                    child: Text(
                      s.noPaper,
                      style: KalloType.small.copyWith(color: colors.inkFaint),
                    ),
                  )
                else
                  for (final PaperEmulsion emulsion in PaperEmulsion.values)
                    if (papers.any(
                      (Stock p) =>
                          (p.emulsion ?? PaperEmulsion.colour) == emulsion,
                    )) ...<Widget>[
                      const SizedBox(height: KalloSpace.step2),
                      Text(
                        emulsion == PaperEmulsion.silver
                            ? s.silverPaper
                            : s.colourPaper,
                        style: KalloType.small.copyWith(color: colors.inkMuted),
                      ),
                      const SizedBox(height: KalloSpace.step1),
                      Wrap(
                        spacing: KalloSpace.step1 + 2,
                        runSpacing: KalloSpace.step1 + 2,
                        children: <Widget>[
                          for (final Stock p in papers)
                            if ((p.emulsion ?? PaperEmulsion.colour) ==
                                emulsion)
                              KalloChip(
                                label: p.short,
                                selected: p.id == paper?.id,
                                compact: true,
                                onTap: () => onPaper(p),
                              ),
                        ],
                      ),
                    ],
                if (paper != null) ...<Widget>[
                  const SizedBox(height: KalloSpace.step1),
                  Text(
                    paper.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KalloType.small.copyWith(color: colors.inkFaint),
                  ),
                ],
                const SizedBox(height: KalloSpace.step3),
                Row(
                  children: <Widget>[
                    Text(
                      s.exposure,
                      style: KalloType.caption.copyWith(
                        color: colors.inkFaint,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        '${s.metered}   0.0 EV',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: KalloType.data.copyWith(color: colors.inkMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KalloSpace.step3),
                KalloButton(
                  label: s.goDevelop,
                  onTap: photograph == null ? null : onGoDevelop,
                  filled: true,
                  height: 34,
                ),
                if (strip.hasPrints) ...<Widget>[
                  const SizedBox(height: KalloSpace.step2),
                  Align(
                    alignment: Alignment.center,
                    child: _Quiet(label: s.newStrip, onTap: onClear),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet action: a word that is a button because it is where the hand goes.
class _Quiet extends StatelessWidget {
  const _Quiet({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(
          label,
          style: KalloType.small.copyWith(
            color: colors.inkMuted,
            decoration: TextDecoration.underline,
            decorationColor: colors.hairline,
          ),
        ),
      ),
    );
  }
}
