import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/clock.dart';
import '../lab/roll.dart';
import '../lab/stock.dart';
import '../widgets/button.dart';
import '../widgets/patch_print.dart';
import '../widgets/record.dart';
import '../widgets/segments.dart';
import '../widgets/wall.dart';

/// The workbench: one frame, enlarged.
///
/// The enlarger is the instrument and the easel is the surface, so the room is
/// lit — the opposite of the gallery, which is a wall in the dark. The control
/// is the development: the roll's ladder laid under the print, one segment per
/// time, and the picture changing as you move along it. Every step is a real
/// print the model made at that time, which is the only honest way to show a
/// ladder: nothing here interpolates.
///
/// The bench also has the one lamp that makes the easel a proof. A print is
/// judged on a wall, against dark, with its paper as the brightest thing in
/// view — which is the gallery's condition and not the bench's. So the proof
/// takes the frame out of the room and hangs it: the same sheet, the same
/// label, the same wall the gallery builds, at the size the gallery hangs it.
/// The panel stays lit and the ladder stays under the wall, because the point
/// is still to choose a time, and you choose it by looking at the print.
class Workbench extends StatefulWidget {
  const Workbench({
    super.key,
    required this.roll,
    required this.selected,
    required this.onSelect,
    required this.exports,
    required this.paperName,
    required this.film,
    required this.onPrint,
  });

  final Roll roll;

  /// What the print's paper is called, resolved at the top of the app.
  final String paperName;

  /// The film this roll was made of, when the shelf knows it.
  final Stock? film;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Where a print goes. Null when this platform has no folder, and then the
  /// bench can look but not print.
  final Directory? exports;

  /// Make the print. It is a render and not a copy, so it takes time, and the
  /// app owns the job: the line has to know about it.
  final Future<void> Function(Frame frame) onPrint;

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  bool _busy = false;
  bool _printed = false;
  String? _error;

  /// Whether the frame is being looked at as the wall will show it.
  ///
  /// It belongs to the bench and not to the frame: it is a way of looking, and
  /// moving along the ladder keeps it — the whole point of a proof is to see
  /// the same wall change.
  bool _proof = false;

  Frame get _frame => widget.roll.frames[widget.selected];

  /// A reversal is developed to a positive and scanned: there is no print stage
  /// between the film and the picture, so there is no sheet to hang.
  bool get _printable =>
      widget.film?.process != FilmProcess.reversal;

  @override
  void didUpdateWidget(Workbench old) {
    super.didUpdateWidget(old);
    // A print belongs to the frame it was made from. Changing the frame is
    // starting again, and the notice goes with it.
    if (old.selected != widget.selected) {
      _printed = false;
      _error = null;
    }
  }

  Future<void> _print() async {
    if (widget.exports == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _printed = false;
    });
    try {
      await widget.onPrint(_frame);
      if (mounted) {
        setState(() => _printed = true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    // The paper is the picture's shape: a vertical frame is a tall sheet, not a
    // landscape one with the photograph cropped into its middle.
    final ui.Image? image = _frame.image;
    final double aspect = image == null ? 1.5 : image.width / image.height;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ColoredBox(
            color: colors.content,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints room) {
                final double width = math.min(
                  math.max(240, room.maxWidth - 80),
                  (room.maxHeight - 150) /
                      PrintSheet.heightPerWidth(aspect: aspect),
                );
                return Column(
                  children: <Widget>[
                    Expanded(
                      child: _proof && _printable
                          ? _wall(s, KalloWall.of(colors.brightness), aspect)
                          : Center(child: _easel(width, colors, aspect)),
                    ),
                    KalloSegments(
                      options: <String>[
                        for (final Frame frame in widget.roll.frames)
                          darkroomClock(frame.minutes),
                      ],
                      selected: widget.selected,
                      onSelect: widget.onSelect,
                      quiet: true,
                    ),
                    SizedBox(
                      height: 34,
                      child: Center(child: _notice(colors, s)),
                    ),
                    const SizedBox(height: KalloSpace.step2),
                  ],
                );
              },
            ),
          ),
        ),
        SizedBox(width: 280, child: _record(colors, s)),
      ],
    );
  }

  /// The print on the easel: paper, a margin, and the frame the model made.
  ///
  /// The easel's paper is the window's, because the easel sits on a page that
  /// belongs to the room. The wall's is a constant; see [`PrintSheet`].
  Widget _easel(double width, KalloColors colors, double aspect) {
    return PrintSheet(
      width: width,
      aspect: aspect,
      paper: colors.print,
      outline: colors.hairline,
      child: _picture(colors.print),
    );
  }

  /// The frame, as the model printed it — or the chart, when there are no
  /// pixels.
  Widget _picture(Color paper) {
    final ui.Image? image = _frame.image;
    if (image != null) {
      return RawImage(
        image: image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
    }
    return PatchPrint(patches: _frame.printColours(paper)!);
  }

  /// The frame hung the way the gallery hangs a print.
  ///
  /// The sheet is the wall's paper and the wall's size — the same 3 % margin,
  /// the same label, the same ground — so that what the bench shows is not a
  /// smaller gallery but the gallery's condition brought to the bench. The
  /// ladder stays under it: the time is still being chosen, and the label's
  /// loud word is the one it is being chosen at.
  Widget _wall(KalloStrings s, KalloWall wall, double aspect) {
    // The sheet's height over its width, from `PrintSheet`'s arithmetic: the
    // wall piece is the one place that has to know it before it builds the
    // sheet, because the sheet is centred in whatever height there is.
    final double perWidth = PrintSheet.heightPerWidth(aspect: aspect);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints band) {
        final double sheet = math.max(
          160,
          math.min(
            math.min(band.maxWidth - 112, (band.maxHeight - 72) / perWidth),
            KalloWall.largest,
          ),
        );
        return Wall(
          wall: wall,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                PrintSheet(
                  width: sheet,
                  aspect: aspect,
                  paper: wall.paper,
                  child: _picture(wall.paper),
                ),
                const SizedBox(height: KalloSpace.step3 + 2),
                Text.rich(
                  TextSpan(
                    children: wallLabel(
                      light: 1,
                      wall: wall,
                      film: widget.film?.short ?? widget.roll.stockLabel,
                      clock: _frame.clock,
                      paper: widget.paperName,
                    ),
                  ),
                  key: const Key('proof-label'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KalloType.caption.copyWith(
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _notice(KalloColors colors, KalloStrings s) {
    if (_error != null) {
      return Text(
        _error!,
        style: KalloType.small.copyWith(color: colors.accent),
      );
    }
    if (_printed) {
      return Text(
        '${s.printedOut}   ·   ${s.onTheLine}',
        style: KalloType.small.copyWith(color: colors.inkFaint),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _record(KalloColors colors, KalloStrings s) {
    final Frame frame = _frame;
    // A reversal is developed to a positive and scanned: there is no print
    // stage between the film and the picture, so there is nothing to make here.
    final bool reversal = widget.film?.process == FilmProcess.reversal;
    final bool printable =
        frame.image != null && widget.exports != null && !reversal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RecordHeader(
              number: frame.number,
              total: widget.roll.frames.length,
            ),
            const SizedBox(height: 16),
            RecordGroup(
              rows: <(String, String)>[
                (s.time, frame.clock),
                (s.temperature, '${frame.tempC.toStringAsFixed(1)} °C'),
                if (frame.gamma != null)
                  (s.gamma, frame.gamma!.map((double v) => v.toStringAsFixed(2)).join('  ')),
                if (frame.dMax != null)
                  (s.dMax, frame.dMax!.map((double v) => v.toStringAsFixed(2)).join('  ')),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              s.paper,
              style: KalloType.caption.copyWith(color: colors.inkFaint),
            ),
            const SizedBox(height: KalloSpace.step1),
            Text(
              widget.paperName,
              style: KalloType.data.copyWith(color: colors.ink),
            ),
            if (!reversal) ...<Widget>[
              const SizedBox(height: KalloSpace.step4),
              Align(
                alignment: Alignment.centerLeft,
                child: _ProofSwitch(
                  label: s.proof,
                  on: _proof,
                  onTap: () => setState(() => _proof = !_proof),
                ),
              ),
            ],
            const Spacer(),
            if (reversal)
              Text(
                s.noPrintStage,
                style: KalloType.small.copyWith(color: colors.inkMuted),
              )
            else
              KalloButton(
                label: _busy ? s.printing : s.printOut,
                onTap: printable && !_busy ? _print : null,
                filled: true,
                height: 32,
              ),
          ],
        ),
      ),
    );
  }
}

/// The bench's lamp: the proof is on or off, and the dot says which.
///
/// It is the gallery's switch brought to a light surface — a room's lamp, not
/// an appearance — and it is quiet, because it is a way of looking and not a
/// decision about the work. The dot is not the accent: the accent marks the
/// frame that was chosen, and this switch chooses nothing.
class _ProofSwitch extends StatefulWidget {
  const _ProofSwitch({
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  State<_ProofSwitch> createState() => _ProofSwitchState();
}

class _ProofSwitchState extends State<_ProofSwitch> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const Key('proof'),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: KalloSpace.step3),
          decoration: BoxDecoration(
            color: _hover ? colors.ground : null,
            borderRadius: BorderRadius.circular(KalloRadius.control),
            border: Border.all(
              color: _hover ? colors.inkFaint : colors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.on ? colors.ink : null,
                  border: widget.on
                      ? null
                      : Border.all(color: colors.inkFaint),
                ),
              ),
              const SizedBox(width: KalloSpace.step2),
              Text(
                widget.label,
                style: KalloType.small.copyWith(
                  color: widget.on ? colors.ink : colors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
