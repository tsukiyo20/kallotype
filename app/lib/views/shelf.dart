import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/clock.dart';
import '../lab/develop.dart';
import '../lab/model.dart';
import '../lab/roll.dart';
import '../lab/stock.dart';
import '../widgets/button.dart';

/// The shelf: stock, and a new roll.
///
/// The first place, and the only one where a photograph enters the product. It
/// goes in whole — one picture, five trips through the developer — because the
/// roll this product is about is not a set of photographs but one frame at
/// several times, and the sheet is a comparison rather than a collection.
///
/// The shelf is a shelf and not a drop-down. Every film the model carries is on
/// it, grouped by chemistry, and a roll is developed as the box you took off
/// it: choosing a stock is not configuration, it is the first decision of the
/// work, and it changes what the five frames are made of.
class Shelf extends StatefulWidget {
  const Shelf({
    super.key,
    required this.roll,
    required this.catalogue,
    required this.onDeveloped,
    required this.onOpen,
  });

  /// The roll already on the shelf, if there is one.
  final Roll? roll;

  /// Every film the model carries. One, when the model did not answer.
  final Catalogue catalogue;

  final ValueChanged<Roll> onDeveloped;
  final VoidCallback onOpen;

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  File? _photo;
  bool _developing = false;
  int _done = 0;
  int _total = ladder.length;
  String? _error;

  /// The box last taken off the shelf, if any.
  String? _taken;

  /// The film the next roll is developed as.
  ///
  /// The last box taken, or the stock with nothing borrowed in it, or whatever
  /// the first box is — in that order, because a shelf whose first answer is
  /// "EKTACHROME E100" would make a reversal the default and there would be no
  /// print at the end of the roll.
  Stock? get _stock {
    final Catalogue catalogue = widget.catalogue;
    return catalogue.film(_taken ?? Stocks.defaultId) ??
        catalogue.film(widget.roll?.stockId ?? '') ??
        (catalogue.films.isEmpty ? Stocks.vision : catalogue.films.first);
  }

  Future<void> _choose() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'photographs',
          extensions: <String>['jpg', 'jpeg', 'png', 'tif', 'tiff'],
        ),
      ],
    );
    if (file == null || !mounted) {
      return;
    }
    setState(() {
      _photo = File(file.path);
      _error = null;
    });
  }

  Future<void> _develop() async {
    final File? photo = _photo;
    final Stock? stock = _stock;
    if (photo == null || stock == null || _developing) {
      return;
    }
    final KalloStrings s = KalloStrings.of(context);
    final Model model = Model.find();
    if (!model.available) {
      setState(() => _error = s.noModel);
      return;
    }
    setState(() {
      _developing = true;
      _done = 0;
      _total = ladder.length;
      _error = null;
    });
    try {
      final Roll roll = await develop(
        model: model,
        photograph: photo,
        stock: stock,
        onProgress: (int done, int total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
      );
      if (!mounted) {
        return;
      }
      widget.onDeveloped(roll);
      widget.onOpen();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _developing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return ColoredBox(
      color: colors.content,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 36, 40, 40),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget form = _form(colors, s);
            final Widget shelf = _shelf(colors, s);
            // The stock stands beside the bench while there is room for both,
            // and under it when there is not: a shelf pushed to a third of its
            // width stops being a shelf and becomes a list of two boxes.
            if (constraints.maxWidth < 940) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  form,
                  const SizedBox(height: KalloSpace.step6),
                  shelf,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(width: 520, child: form),
                const SizedBox(width: KalloSpace.step6),
                Expanded(child: shelf),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _form(KalloColors colors, KalloStrings s) {
    final Stock? stock = _stock;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            s.newRoll,
            style: KalloType.title.copyWith(fontSize: 26, color: colors.ink),
          ),
          const SizedBox(height: KalloSpace.step2),
          Text(
            s.newRollNote,
            style: KalloType.body.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: KalloSpace.step6),
          _label(s.photograph, colors),
          const SizedBox(height: KalloSpace.step2),
          _field(colors, s),
          const SizedBox(height: KalloSpace.step4),
          _label(s.film, colors),
          const SizedBox(height: KalloSpace.step1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                stock?.short ?? Stocks.vision.short,
                style: KalloType.data.copyWith(color: colors.ink),
              ),
              if (stock != null) ...<Widget>[
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
            ],
          ),
          const SizedBox(height: KalloSpace.step4),
          _label(s.developments, colors),
          const SizedBox(height: KalloSpace.step1),
          Text(
            <String>[
              for (final double minutes in ladder) darkroomClock(minutes),
            ].join('   ·   '),
            style: KalloType.data.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: KalloSpace.step6),
          _action(colors, s),
          if (widget.roll != null) ...<Widget>[
            const SizedBox(height: KalloSpace.step6),
            Container(height: 1, color: colors.hairline),
            const SizedBox(height: KalloSpace.step4),
            _roll(widget.roll!, colors, s),
          ],
        ],
      ),
    );
  }

  /// Every film the model carries, as boxes on shelves.
  Widget _shelf(KalloColors colors, KalloStrings s) {
    final Catalogue catalogue = widget.catalogue;
    final List<FilmProcess> processes = FilmProcess.values
        .where((FilmProcess process) => catalogue.of(process).isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              s.theShelf,
              style: KalloType.caption.copyWith(
                color: colors.inkFaint,
                letterSpacing: 1.6,
              ),
            ),
            const Spacer(),
            Text(
              s.shelfCount(catalogue.films.length),
              style: KalloType.small.copyWith(color: colors.inkFaint),
            ),
          ],
        ),
        if (catalogue.films.length <= 1) ...<Widget>[
          const SizedBox(height: KalloSpace.step2),
          Text(
            s.shelfAlone,
            style: KalloType.small.copyWith(color: colors.inkFaint),
          ),
        ],
        for (final FilmProcess process in processes) ...<Widget>[
          const SizedBox(height: KalloSpace.step4),
          Text(
            s.processName(process),
            style: KalloType.caption.copyWith(
              color: colors.inkFaint,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: KalloSpace.step2),
          Wrap(
            spacing: KalloSpace.step1 + 2,
            runSpacing: KalloSpace.step1 + 2,
            children: <Widget>[
              for (final Stock stock in catalogue.of(process))
                _box(stock, colors),
            ],
          ),
        ],
      ],
    );
  }

  /// One film, as a box on the shelf. Taken, it is the dark one: filled with
  /// ink rather than outlined, the way the one action on a screen is.
  Widget _box(Stock stock, KalloColors colors) {
    final bool taken = stock.id == _stock?.id;
    return Semantics(
      button: true,
      selected: taken,
      label: stock.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() {
            _taken = stock.id;
            _error = null;
          }),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: taken ? colors.ink : colors.ground,
              borderRadius: BorderRadius.circular(KalloRadius.film),
              border: Border.all(
                color: taken ? colors.ink : colors.hairline,
              ),
            ),
            child: Text(
              stock.short,
              style: KalloType.data.copyWith(
                color: taken ? colors.content : colors.ink,
                fontWeight: taken ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, KalloColors colors) => Text(
        text.toUpperCase(),
        style: KalloType.caption.copyWith(color: colors.inkFaint),
      );

  Widget _field(KalloColors colors, KalloStrings s) {
    final File? photo = _photo;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: KalloSpace.step3, right: 3),
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: BorderRadius.circular(KalloRadius.control),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              photo == null
                  ? s.noPhotograph
                  : photo.path.split(Platform.pathSeparator).last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KalloType.data.copyWith(
                color: photo == null ? colors.inkFaint : colors.ink,
              ),
            ),
          ),
          KalloButton(label: s.choosePhoto, onTap: _choose),
        ],
      ),
    );
  }

  Widget _action(KalloColors colors, KalloStrings s) {
    if (_developing) {
      final double progress = _total == 0 ? 0 : _done / _total;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            s.developingOf(_done, _total),
            style: KalloType.small.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: KalloSpace.step2),
          Container(
            height: 2,
            alignment: Alignment.centerLeft,
            color: colors.hairline,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: ColoredBox(
                color: colors.accent,
                child: const SizedBox(height: 2),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        KalloButton(
          label: s.develop,
          onTap: _photo == null ? null : _develop,
          filled: true,
          height: 32,
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: KalloSpace.step3),
          Text(
            _error!,
            style: KalloType.small.copyWith(color: colors.accent),
          ),
        ],
      ],
    );
  }

  Widget _roll(Roll roll, KalloColors colors, KalloStrings s) {
    return Row(
      children: <Widget>[
        Text(
          s.rollName(roll.number),
          style: KalloType.title.copyWith(color: colors.ink),
        ),
        const SizedBox(width: KalloSpace.step3),
        Text(
          '${s.frames(roll.frames.length)}   ·   ${s.onTheTable}',
          style: KalloType.small.copyWith(color: colors.inkFaint),
        ),
        const Spacer(),
        KalloButton(label: s.openRoll, onTap: widget.onOpen),
      ],
    );
  }
}
