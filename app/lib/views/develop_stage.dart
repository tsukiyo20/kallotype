import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/chart.dart';
import '../lab/clock.dart';
import '../lab/model.dart';
import '../lab/stock.dart';
import '../lab/strip.dart';
import '../lab/strip_develop.dart';
import '../widgets/button.dart';
import '../widgets/curves.dart';
import '../widgets/time_slider.dart';
import '../widgets/wall.dart';

/// The second step: one photograph, one time, one print at a time.
///
/// The print on the easel is the time in hand; the ruler under it moves the
/// time; the strip below it is what has been printed. A print is only added
/// when the button is pressed — dragging the ruler changes what the print
/// *would* be, it does not develop anything.
class DevelopStage extends StatefulWidget {
  const DevelopStage({
    super.key,
    required this.strip,
    required this.onDevelop,
    required this.onRemove,
  });

  final TestStrip strip;

  /// Develop one print at a time and add it to the strip.
  final Future<void> Function(double minutes) onDevelop;

  /// Take one print off the strip.
  final Future<void> Function(double minutes) onRemove;

  @override
  State<DevelopStage> createState() => _DevelopStageState();
}

class _DevelopStageState extends State<DevelopStage> {
  static const List<double> _ladder = <double>[3, 6, 9, 12, 15];

  late double _minutes;
  ui.Image? _preview;
  bool _ownsPreview = false;
  FilmChart? _chart;
  final Map<double, FilmCurve> _curves = <double, FilmCurve>{};
  PaperCurve? _paper;

  bool _busy = false;
  String? _error;

  Timer? _timer;
  int _generation = 0;
  final Map<double, GlobalKey> _stripKeys = <double, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _minutes = widget.strip.latest?.minutes ?? 9;
    _showPrint(_minutes);
    if (_preview == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _previewNow());
    }
    _loadPaper();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFilmCurves();
      _revealSelected();
    });
  }

  @override
  void didUpdateWidget(DevelopStage old) {
    super.didUpdateWidget(old);
    final TestPrint? print = _printAt(_minutes);
    if (print != null) {
      if (!identical(print.image, _preview)) {
        final ui.Image? oldImage = _preview;
        final bool owned = _ownsPreview;
        setState(() {
          _preview = print.image;
          _ownsPreview = false;
          _chart = print.chart ?? _chart;
        });
        if (owned) {
          _disposeAfterFrame(oldImage);
        }
      }
    } else if (!_ownsPreview &&
        _preview != null &&
        !widget.strip.prints.any(
          (TestPrint p) => identical(p.image, _preview),
        )) {
      // The print that was on the easel was removed: the image belonged to the
      // strip, and the strip no longer holds it.
      setState(() {
        _preview = null;
        _chart = null;
      });
      _schedule();
    }
    if (old.strip.paperId != widget.strip.paperId) {
      _loadPaper();
    }
    if (old.strip.photo != widget.strip.photo) {
      _generation++;
      _preview = null;
      _chart = null;
      _curves.clear();
      _minutes = widget.strip.latest?.minutes ?? 9;
      _showPrint(_minutes);
      _schedule();
    }
    unawaited(_loadFilmCurves());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    if (_ownsPreview) {
      _preview?.dispose();
    }
    super.dispose();
  }

  TestPrint? _printAt(double minutes) {
    for (final TestPrint print in widget.strip.prints) {
      if ((print.minutes - minutes).abs() < 1e-9) {
        return print;
      }
    }
    return null;
  }

  void _showPrint(double minutes) {
    final TestPrint? print = _printAt(minutes);
    if (print == null) {
      return;
    }
    final ui.Image? old = _preview;
    final bool owned = _ownsPreview;
    _preview = print.image;
    _ownsPreview = false;
    _chart = print.chart ?? _chart;
    if (owned) {
      _disposeAfterFrame(old);
    }
  }

  void _disposeAfterFrame(ui.Image? image) {
    if (image == null) {
      return;
    }
    // The picture on screen has to be replaced by the next one before its
    // texture is freed.
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  GlobalKey _stripKey(double minutes) =>
      _stripKeys.putIfAbsent(minutes, () => GlobalKey());

  /// Put the selected print in the middle of the strip, so a strip longer than
  /// the window does not hide the print the time is showing.
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? context = _stripKeys[_minutes]?.currentContext;
      if (context == null) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: KalloMotion.settle,
        curve: KalloMotion.enter,
      );
    });
  }

  void _setPreview(ui.Image image, {required bool owned}) {
    final ui.Image? old = _preview;
    final bool wasOwned = _ownsPreview;
    setState(() {
      _preview = image;
      _ownsPreview = owned;
    });
    if (wasOwned && !identical(old, image)) {
      _disposeAfterFrame(old);
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 110), _previewNow);
  }

  Future<void> _loadPaper() async {
    final Model model = Model.find();
    if (!model.available) {
      return;
    }
    try {
      final PaperCurve? curve = await model.paperCurve(
        paper: widget.strip.paperId ?? Stocks.paper,
      );
      if (mounted && curve != null) {
        setState(() => _paper = curve);
      }
    } on Object catch (error) {
      Model.log('the paper curve could not be read: $error');
    }
  }

  /// The full developed curves of the strip's times, and of the time in hand.
  ///
  /// The time in hand is not on the strip yet, so it is fetched too; the other
  /// times are pruned as the ruler moves, because a curve the person dragged
  /// past is not a print.
  Future<void> _loadFilmCurves() async {
    final Model model = Model.find();
    if (!model.available) {
      return;
    }
    final Set<double> wanted = <double>{
      _minutes,
      for (final TestPrint print in widget.strip.prints) print.minutes,
    };
    _curves.removeWhere((double time, FilmCurve _) => !wanted.contains(time));
    for (final double time in wanted) {
      if (_curves.containsKey(time)) {
        continue;
      }
      try {
        final FilmCurve? curve = await model.filmCurve(
          film: widget.strip.stockId,
          minutes: time,
          tempC: widget.strip.tempC,
        );
        if (!mounted) {
          return;
        }
        if (curve != null) {
          setState(() => _curves[time] = curve);
        }
      } on Object catch (error) {
        Model.log('the film curve could not be read: $error');
      }
    }
  }

  Future<FilmChart?> _readChart(double minutes) async {
    try {
      final List<FilmChart>? charts = await Model.find().chart(
        stock: widget.strip.stockId,
        times: <double>[minutes],
        tempC: widget.strip.tempC,
      );
      return charts == null || charts.isEmpty ? null : charts.first;
    } on Object catch (error) {
      Model.log('the strip could not be charted: $error');
      return null;
    }
  }

  Future<void> _previewNow() async {
    final TestPrint? print = _printAt(_minutes);
    if (print != null) {
      if (mounted) {
        setState(() {
          _showPrint(_minutes);
        });
        _revealSelected();
      }
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
      final ui.Image image = await previewTestPrint(
        model: model,
        strip: widget.strip,
        minutes: _minutes,
      );
      final FilmChart? chart = await _readChart(_minutes);
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      _setPreview(image, owned: true);
      setState(() {
        _chart = chart ?? _chart;
        _error = null;
      });
      await _loadFilmCurves();
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    }
  }

  void _changed(double minutes) {
    setState(() => _minutes = minutes);
    final TestPrint? print = _printAt(minutes);
    if (print != null) {
      _timer?.cancel();
      _generation++;
      setState(() => _showPrint(minutes));
      _revealSelected();
      return;
    }
    _schedule();
  }

  void _settled(double minutes) {
    _timer?.cancel();
    if (_printAt(minutes) == null) {
      _previewNow();
    }
  }

  Future<void> _develop() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDevelop(_minutes);
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

  Future<void> _remove() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onRemove(_minutes);
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

  List<FilmChart> get _charts => <FilmChart>[
    for (final TestPrint print in widget.strip.prints)
      if (print.chart != null) print.chart!,
    if (_chart != null &&
        !widget.strip.prints.any(
          (TestPrint p) => p.chart?.minutes == _chart!.minutes,
        ))
      _chart!,
  ];

  List<double> get _curveTimes => _curves.keys.toList()..sort();

  List<List<double>> get _series {
    if (_curves.isNotEmpty) {
      return <List<double>>[
        for (final double time in _curveTimes) _curves[time]!.tone,
      ];
    }
    return <List<double>>[for (final FilmChart chart in _charts) _tone(chart)];
  }

  List<double>? get _xs {
    if (_curves.isNotEmpty) {
      return _curves[_curveTimes.first]!.logE;
    }
    final List<FilmChart> charts = _charts;
    if (charts.isEmpty) {
      return null;
    }
    FilmChart? selected;
    for (final FilmChart chart in charts) {
      if (chart.minutes == _minutes) {
        selected = chart;
        break;
      }
    }
    return (selected ?? charts.last).logE;
  }

  int? get _selectedCurve {
    if (_curves.isNotEmpty) {
      final int index = _curveTimes.indexWhere(
        (double time) => time == _minutes,
      );
      return index < 0 ? null : index;
    }
    final List<FilmChart> charts = _charts;
    final int index = charts.indexWhere(
      (FilmChart chart) => chart.minutes == _minutes,
    );
    return index < 0 ? null : index;
  }

  static List<double> _tone(FilmChart chart) => <double>[
    for (final List<double> patch in chart.patches)
      (patch[0] + patch[1] + patch[2]) / 3,
  ];

  FilmCurve? get _currentCurve => _curves[_minutes];

  FilmChart? get _currentChart {
    for (final FilmChart chart in _charts) {
      if (chart.minutes == _minutes) {
        return chart;
      }
    }
    return _chart;
  }

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
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
    final bool hasPrints = widget.strip.prints.isNotEmpty;
    return ColoredBox(
      color: colors.content,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints room) {
          // The print and its controls are one object on the bench. They are
          // laid together and centred, so a tall window puts the ruler under
          // the picture instead of at the bottom of an empty field.
          final double reserve = hasPrints ? 248 : 174;
          final double width = math.max(
            220,
            math.min(
              math.max(240, room.maxWidth - 96),
              math.max(
                180,
                (room.maxHeight - reserve) /
                    PrintSheet.heightPerWidth(aspect: aspect),
              ),
            ),
          );
          return Center(
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PrintSheet(
                    width: width,
                    aspect: aspect,
                    paper: colors.print,
                    outline: colors.hairline,
                    child: image == null
                        ? Center(
                            child: Text(
                              _busy ? s.developing : s.noTestPrints,
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
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 104,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              darkroomClock(_minutes),
                              style: KalloType.plate.copyWith(
                                color: colors.ink,
                              ),
                            ),
                            Text(
                              '${widget.strip.tempC.toStringAsFixed(1)} °C',
                              style: KalloType.small.copyWith(
                                color: colors.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: KalloSpace.step3),
                      Expanded(
                        child: TimeSlider(
                          value: _minutes,
                          ticks: _ladder,
                          onChanged: _changed,
                          onSettled: _settled,
                        ),
                      ),
                    ],
                  ),
                  _strip(colors, s),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _strip(KalloColors colors, KalloStrings s) {
    final List<TestPrint> prints = widget.strip.prints;
    return SizedBox(
      height: prints.isEmpty ? 84 : 122,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 98,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.testStrip,
                    style: KalloType.caption.copyWith(
                      color: colors.inkFaint,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.stripCount(prints.length),
                    style: KalloType.small.copyWith(color: colors.inkMuted),
                  ),
                  if (prints.isEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      s.noTestPrints,
                      style: KalloType.small.copyWith(color: colors.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final TestPrint print in prints)
                      _Pegged(
                        key: _stripKey(print.minutes),
                        print: print,
                        selected: (print.minutes - _minutes).abs() < 1e-9,
                        onTap: () => _changed(print.minutes),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(KalloColors colors, KalloStrings s) {
    final FilmChart? chart = _currentChart;
    final FilmCurve? curve = _currentCurve;
    final TestPrint? exact = _printAt(_minutes);
    final double? first = widget.strip.balanceFrom;
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        s.filmCurve,
                        style: KalloType.caption.copyWith(
                          color: colors.inkFaint,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'log E →',
                        style: KalloType.folio.copyWith(color: colors.inkFaint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_series.isEmpty)
                    Text(
                      s.noCurve,
                      style: KalloType.small.copyWith(color: colors.inkFaint),
                    )
                  else
                    KalloCurves(
                      series: _series,
                      selected: _selectedCurve,
                      xs: _xs,
                      height: 104,
                    ),
                  if (curve != null) ...<Widget>[
                    const SizedBox(height: 8),
                    _Fact(label: s.gamma, value: _triple(curve.gamma)),
                    _Fact(label: s.dMax, value: _triple(curve.dMax)),
                  ] else if (chart != null) ...<Widget>[
                    const SizedBox(height: 8),
                    _Fact(label: s.gamma, value: _triple(chart.gamma)),
                    _Fact(label: s.dMax, value: _triple(chart.dMax)),
                  ],
                  const SizedBox(height: 18),
                  Container(height: 1, color: colors.hairline),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Text(
                        s.paperCurve,
                        style: KalloType.caption.copyWith(
                          color: colors.inkFaint,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _paper?.short ?? (widget.strip.paperLabel ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KalloType.folio.copyWith(color: colors.inkFaint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_paper != null)
                    KalloCurves(
                      series: <List<double>>[_paper!.density],
                      xs: _paper!.logE,
                      height: 54,
                    )
                  else
                    Text(
                      s.noCurve,
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
                Text(
                  first == null
                      ? s.testStripNote
                      : s.exposureOf(darkroomClock(first)),
                  style: KalloType.small.copyWith(color: colors.inkFaint),
                ),
                const SizedBox(height: KalloSpace.step2),
                KalloButton(
                  label: _busy
                      ? s.developing
                      : '${exact == null ? s.developStep : s.redevelop}  '
                            '${darkroomClock(_minutes)}',
                  onTap: _busy ? null : _develop,
                  filled: true,
                  height: 36,
                ),
                if (exact != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.center,
                    child: _Quiet(
                      label: s.removePrint,
                      onTap: _busy ? null : _remove,
                    ),
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

  static String _triple(List<double> values) =>
      values.map((double v) => v.toStringAsFixed(2)).join('  ');
}

/// One print on the test strip.
class _Pegged extends StatelessWidget {
  const _Pegged({
    super.key,
    required this.print,
    required this.selected,
    required this.onTap,
  });

  final TestPrint print;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final ui.Image? image = print.image;
    final double aspect = image == null ? 1.5 : image.width / image.height;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 96,
          margin: const EdgeInsets.only(right: KalloSpace.step3),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.print,
            border: Border.all(
              color: selected ? colors.accent : colors.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AspectRatio(
                aspectRatio: aspect,
                child: image == null
                    ? const SizedBox.shrink()
                    : RawImage(
                        image: image,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
              const SizedBox(height: 5),
              Text(
                print.clock,
                style: KalloType.folio.copyWith(
                  color: selected ? KalloInk.ink : KalloInk.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: <Widget>[
          Text(label, style: KalloType.small.copyWith(color: colors.inkFaint)),
          const Spacer(),
          Text(value, style: KalloType.data.copyWith(color: colors.inkMuted)),
        ],
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(
          label,
          style: KalloType.small.copyWith(
            color: onTap == null ? colors.inkFaint : colors.inkMuted,
          ),
        ),
      ),
    );
  }
}
