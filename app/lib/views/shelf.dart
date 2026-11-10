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
class Shelf extends StatefulWidget {
  const Shelf({
    super.key,
    required this.roll,
    required this.onDeveloped,
    required this.onOpen,
  });

  /// The roll already on the shelf, if there is one.
  final Roll? roll;

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
    if (photo == null || _developing) {
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
        stock: Stocks.vision,
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
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
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
                Text(
                  Stocks.vision.label,
                  style: KalloType.data.copyWith(color: colors.ink),
                ),
                const SizedBox(height: KalloSpace.step4),
                _label(s.developments, colors),
                const SizedBox(height: KalloSpace.step1),
                Text(
                  <String>[for (final double minutes in ladder) darkroomClock(minutes)].join('   ·   '),
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
