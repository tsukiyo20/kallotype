import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/clock.dart';
import '../lab/model.dart';
import '../lab/print_request.dart';
import '../lab/strip.dart';
import '../lab/strip_develop.dart';
import '../widgets/button.dart';
import '../widgets/chip.dart';
import '../widgets/stepper.dart';
import '../widgets/wall.dart';

/// The third step: the negative chosen on the strip, printed as a picture.
///
/// The test strip is one exposure; this is the enlarger dialled. The timer, the
/// colour pack and the heat glass are the three things a printer actually
/// changes, so they are the three controls — and the paper underneath them is
/// the print they make, at the size a print is.
class PrintStage extends StatefulWidget {
  const PrintStage({
    super.key,
    required this.strip,
    required this.paperName,
    required this.exports,
    required this.onPrint,
    required this.onGoDevelop,
  });

  final TestStrip strip;
  final String paperName;
  final Directory? exports;
  final Future<void> Function(PrintRequest request) onPrint;
  final VoidCallback onGoDevelop;

  @override
  State<PrintStage> createState() => _PrintStageState();
}

class _PrintStageState extends State<PrintStage> {
  late double _minutes;
  double _printEv = 0;
  int _yellow = 0;
  int _magenta = 0;
  int _cyan = 0;
  String? _glass;

  ui.Image? _preview;
  bool _busy = false;
  bool _printed = false;
  String? _error;

  Timer? _timer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _minutes = widget.strip.latest?.minutes ?? 9;
    if (widget.strip.hasPrints) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _previewNow());
    }
  }

  @override
  void didUpdateWidget(PrintStage old) {
    super.didUpdateWidget(old);
    if (old.strip != widget.strip) {
      if (!widget.strip.hasPrints) {
        _preview?.dispose();
        _preview = null;
        return;
      }
      if (!widget.strip.prints.any((TestPrint p) => p.minutes == _minutes)) {
        _minutes = widget.strip.latest!.minutes;
      }
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    _preview?.dispose();
    super.dispose();
  }

  String get _filters => <String>[
    if (_yellow > 0) '${_yellow}Y',
    if (_magenta > 0) '${_magenta}M',
    if (_cyan > 0) '${_cyan}C',
  ].join('+');

  void _changed() {
    setState(() {
      _printed = false;
      _error = null;
    });
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 120), _previewNow);
  }

  Future<void> _previewNow() async {
    if (!widget.strip.hasPrints) {
      return;
    }
    final Model model = Model.find();
    final int generation = ++_generation;
    if (!model.available) {
      if (mounted) {
        setState(() => _error = KalloStrings.of(context).noModel);
      }
      return;
    }
    try {
      final ui.Image image = await previewFinalPrint(
        model: model,
        strip: widget.strip,
        minutes: _minutes,
        printEv: _printEv,
        filters: _filters,
        heatGlass: _glass,
      );
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      final ui.Image? old = _preview;
      setState(() => _preview = image);
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _print() async {
    if (_busy || widget.exports == null || !widget.strip.hasPrints) {
      return;
    }
    setState(() {
      _busy = true;
      _printed = false;
      _error = null;
    });
    try {
      await widget.onPrint(
        PrintRequest(
          minutes: _minutes,
          printEv: _printEv,
          filters: _filters,
          heatGlass: _glass,
        ),
      );
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
    if (!widget.strip.hasPrints) {
      return ColoredBox(
        color: colors.content,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                s.chooseFirstPrint,
                style: KalloType.body.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: KalloSpace.step4),
              KalloButton(
                label: s.goDevelop,
                onTap: widget.onGoDevelop,
                filled: true,
                height: 34,
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: _bench(colors, s)),
        SizedBox(width: 304, child: _panel(colors, s)),
      ],
    );
  }

  Widget _bench(KalloColors colors, KalloStrings s) {
    final ui.Image? image = _preview;
    final double aspect = image == null ? 1.5 : image.width / image.height;
    return ColoredBox(
      color: colors.content,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints room) {
          final double width = math.max(
            220,
            math.min(
              math.max(240, room.maxWidth - 140),
              (room.maxHeight - 150) /
                  PrintSheet.heightPerWidth(aspect: aspect),
            ),
          );
          return Column(
            children: <Widget>[
              Expanded(
                child: Center(
                  child: PrintSheet(
                    width: width,
                    aspect: aspect,
                    paper: colors.print,
                    outline: colors.hairline,
                    child: image == null
                        ? Center(
                            child: Text(
                              _busy ? s.printing : s.printNote,
                              textAlign: TextAlign.center,
                              style: KalloType.small.copyWith(
                                color: KalloInk.muted,
                              ),
                            ),
                          )
                        : RawImage(
                            image: image,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 24),
                child: Text(
                  '${darkroomClock(_minutes)}   ·   '
                  '${_printEv >= 0 ? '+' : ''}${_printEv.toStringAsFixed(1)} EV'
                  '${_filters.isEmpty ? '' : '   ·   $_filters'}'
                  '${_glass == null ? '' : '   ·   ${_glass!.toUpperCase()}'}',
                  style: KalloType.data.copyWith(color: colors.inkMuted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _panel(KalloColors colors, KalloStrings s) {
    final bool printable = widget.exports != null;
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.time,
                    style: KalloType.caption.copyWith(
                      color: colors.inkFaint,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: KalloSpace.step2),
                  Wrap(
                    spacing: KalloSpace.step1 + 2,
                    runSpacing: KalloSpace.step1 + 2,
                    children: <Widget>[
                      for (final TestPrint print in widget.strip.prints)
                        KalloChip(
                          label: print.clock,
                          selected: (print.minutes - _minutes).abs() < 1e-9,
                          onTap: () {
                            setState(() => _minutes = print.minutes);
                            _changed();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: KalloSpace.step5),
                  Container(height: 1, color: colors.hairline),
                  const SizedBox(height: KalloSpace.step4),
                  Text(
                    '${s.printExposure}  ·  EV',
                    style: KalloType.caption.copyWith(
                      color: colors.inkFaint,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: KalloSpace.step2),
                  KalloStepper(
                    label: s.exposure,
                    value:
                        '${_printEv >= 0 ? '+' : ''}${_printEv.toStringAsFixed(1)}',
                    width: 264,
                    onMinus: _printEv <= -2
                        ? null
                        : () {
                            setState(
                              () => _printEv = double.parse(
                                (_printEv - 0.1).toStringAsFixed(1),
                              ),
                            );
                            _changed();
                          },
                    onPlus: _printEv >= 2
                        ? null
                        : () {
                            setState(
                              () => _printEv = double.parse(
                                (_printEv + 0.1).toStringAsFixed(1),
                              ),
                            );
                            _changed();
                          },
                  ),
                  const SizedBox(height: KalloSpace.step4),
                  Text(
                    '${s.filters}  ·  CC',
                    style: KalloType.caption.copyWith(
                      color: colors.inkFaint,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: KalloSpace.step2),
                  _colour('Y', _yellow, (int next) {
                    setState(() => _yellow = next);
                    _changed();
                  }),
                  _colour('M', _magenta, (int next) {
                    setState(() => _magenta = next);
                    _changed();
                  }),
                  _colour('C', _cyan, (int next) {
                    setState(() => _cyan = next);
                    _changed();
                  }),
                  const SizedBox(height: KalloSpace.step4),
                  Text(
                    s.heatGlass,
                    style: KalloType.caption.copyWith(
                      color: colors.inkFaint,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: KalloSpace.step2),
                  Wrap(
                    spacing: KalloSpace.step1 + 2,
                    runSpacing: KalloSpace.step1 + 2,
                    children: <Widget>[
                      KalloChip(
                        label: s.noGlass,
                        selected: _glass == null,
                        compact: true,
                        onTap: () {
                          setState(() => _glass = null);
                          _changed();
                        },
                      ),
                      for (final String glass in <String>[
                        'kg1',
                        'kg2',
                        'kg3',
                        'kg5',
                      ])
                        KalloChip(
                          label: glass.toUpperCase(),
                          selected: _glass == glass,
                          compact: true,
                          onTap: () {
                            setState(() => _glass = glass);
                            _changed();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: KalloSpace.step5),
                  Text(
                    s.printNote,
                    style: KalloType.small.copyWith(color: colors.inkFaint),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.hairline)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!printable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: KalloSpace.step2),
                    child: Text(
                      s.noFolder,
                      style: KalloType.small.copyWith(color: colors.inkFaint),
                    ),
                  ),
                KalloButton(
                  label: _busy ? s.printing : s.printAction,
                  onTap: printable && !_busy ? _print : null,
                  filled: true,
                  height: 36,
                ),
                if (_printed) ...<Widget>[
                  const SizedBox(height: KalloSpace.step2),
                  Text(
                    s.printQueued,
                    style: KalloType.small.copyWith(color: colors.inkMuted),
                  ),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: KalloSpace.step2),
                  Text(
                    _error!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: KalloType.small.copyWith(color: colors.accent),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colour(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: KalloStepper(
        label: label,
        value: '$value',
        width: 264,
        onMinus: value <= 0 ? null : () => onChanged(value - 5),
        onPlus: value >= 100 ? null : () => onChanged(value + 5),
      ),
    );
  }
}
