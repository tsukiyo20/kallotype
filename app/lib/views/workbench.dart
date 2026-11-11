import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/clock.dart';
import '../lab/roll.dart';
import '../widgets/button.dart';
import '../widgets/patch_print.dart';
import '../widgets/record.dart';
import '../widgets/segments.dart';

/// The workbench: one frame, enlarged.
///
/// The enlarger is the instrument and the easel is the surface, so the room is
/// lit — the opposite of the gallery, which is a wall in the dark. The control
/// is the development: the roll's ladder laid under the print, one segment per
/// time, and the picture changing as you move along it. Every step is a real
/// print the model made at that time, which is the only honest way to show a
/// ladder: nothing here interpolates.
class Workbench extends StatefulWidget {
  const Workbench({
    super.key,
    required this.roll,
    required this.selected,
    required this.onSelect,
    required this.exports,
    required this.paperName,
    required this.onPrint,
  });

  final Roll roll;

  /// What the print's paper is called, resolved at the top of the app.
  final String paperName;
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

  Frame get _frame => widget.roll.frames[widget.selected];

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
                  (room.maxHeight - 150) / 0.72,
                );
                return Column(
                  children: <Widget>[
                    Expanded(
                      child: Center(
                        child: _easel(width, colors),
                      ),
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
  Widget _easel(double width, KalloColors colors) {
    final double border = width * 0.030;
    final double image = width - border * 2;
    final Frame frame = _frame;
    final Widget picture = frame.image != null
        ? RawImage(
            image: frame.image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          )
        : PatchPrint(patches: frame.printColours(colors.print)!);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.print,
        border: Border.all(color: colors.hairline),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(border, border, border, border * 2.2),
        child: SizedBox(width: image, height: image / 1.5, child: picture),
      ),
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
    final bool printable = frame.image != null && widget.exports != null;
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
            const Spacer(),
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
