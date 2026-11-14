import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/export_format.dart';
import '../lab/film_export.dart';
import '../lab/model.dart';
import '../lab/print.dart';
import '../lab/stock.dart';
import '../widgets/export_sheet.dart';
import '../widgets/film_frame.dart';
import '../widgets/lens.dart';
import '../widgets/switch.dart';
import '../widgets/wall.dart';

/// The gallery: the last place. One wall, every print, one lamp.
///
/// A print is not a picture, it is a sheet of paper reflecting whatever light
/// falls on it. So the room is built the way that physics is built: every
/// surface is a reflectance, the lamp is a single number, and the number is
/// multiplied into each of them.
///
/// The wall is the window's: a gallery is white in daylight and dark after
/// hours. The lamp is the gallery's: turn it off and the wall goes black, the
/// labels go with it — and the prints do not go out, they stay at a tenth. What
/// does not move is the window around them. Turning a lamp off is not the same
/// event as the system changing its theme, and a person who turned the light
/// off to look at a print still has to be able to find the way back.
///
/// The work on this wall is not a sheet of paper with a margin: it is a 35 mm
/// frame. The black rebate, the sprocket holes and the edge printing are the
/// film the photograph was made on, and the picture is the aperture. That is
/// the thing people mean when they ask for the film look, and it is a finished
/// product as much as a view: the loupe writes it out at the file's own size.
///
/// The wall is arranged in a grid and not hung like a salon, because a grid is
/// the only arrangement that says nothing about the pictures: five developments
/// of one negative are five equal things, and the wall should not pretend to
/// prefer one.
class Gallery extends StatefulWidget {
  const Gallery({
    super.key,
    required this.prints,
    required this.light,
    required this.onLight,
  });

  /// Everything exported, oldest first.
  final List<Print> prints;

  /// The lamp on the wall, from off to all of it. It is the room's, and it
  /// takes the wall and the work with it — not the window around them.
  final double light;

  /// The switch belongs to the room, not to the wall.
  final VoidCallback onLight;

  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  /// The print being looked at closely, if one is.
  Print? _near;
  int _nearPrintNumber = 1;

  /// The print under the lens, and where the lens is.
  ///
  /// The lens is a loupe held over the film, not a picture viewer: it shows the
  /// frame at three times the wall, from a decode wide enough that the glass
  /// has something to show. It goes away when the pointer does, and clicking
  /// still walks up to the whole frame.
  Print? _lensFor;
  ui.Image? _lens;
  Offset _lensAt = Offset.zero;
  Offset _lensPoint = Offset.zero;
  double _lensWidth = 0;
  int _lensPrintNumber = 1;

  /// The wall's box, which is where the lens is placed.
  final GlobalKey _field = GlobalKey(debugLabel: 'wall');

  void _lookAt(
    Print print,
    int printNumber,
    Offset local,
    double width,
    Offset global,
  ) {
    final RenderBox? box =
        _field.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    if (!identical(print, _lensFor)) {
      _lensFor = print;
      _lensPrintNumber = printNumber;
      _dropLens();
      unawaited(_loadLens(print));
    } else {
      _lensPrintNumber = printNumber;
    }
    setState(() {
      _lensAt = box.globalToLocal(global);
      _lensPoint = local;
      _lensWidth = width;
    });
  }

  void _leaveLens() {
    if (_lensFor == null) {
      return;
    }
    setState(() {
      _lensFor = null;
      _dropLens();
    });
  }

  /// Free the magnified copy, but only after the frame that drew it: a texture
  /// disposed while it is on screen is a texture that draws as nothing.
  void _dropLens() {
    final ui.Image? old = _lens;
    _lens = null;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  Future<void> _loadLens(Print print) async {
    final ui.Image? image = await print.magnified();
    if (!mounted || !identical(print, _lensFor)) {
      image?.dispose();
      return;
    }
    setState(() => _lens = image);
  }

  @override
  void dispose() {
    _lens?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(Gallery old) {
    super.didUpdateWidget(old);
    // Prints are re-read when the folder changes, and the one in hand is about
    // to be disposed: a loupe cannot look at a texture that no longer exists.
    final Print? near = _near;
    if (near != null && !widget.prints.any((Print p) => identical(p, near))) {
      _near = null;
    }
    final Print? lens = _lensFor;
    if (lens != null && !widget.prints.any((Print p) => identical(p, lens))) {
      _lensFor = null;
      _dropLens();
    }
  }

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    // The wall is the appearance's: a gallery is white in daylight and dark
    // after hours, and the lamp goes out in both.
    final KalloWall wall = KalloWall.of(
      KalloScope.colorsOf(context).brightness,
    );
    final double light = widget.light;
    final Print? near = _near;
    // The film holds its light better than the room does, for the same reason
    // everything else does not: the eye is the instrument here, not the lamp.
    final double printed =
        KalloWall.darkAdaptation + (1 - KalloWall.darkAdaptation) * light;
    final List<Print> prints = widget.prints;

    if (near != null) {
      return _Loupe(
        print: near,
        printNumber: _nearPrintNumber,
        wall: wall,
        light: light,
        printed: printed,
        onLight: widget.onLight,
        onClose: () => setState(() => _near = null),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints room) {
        const double gap = 28;
        const double margin = 40;
        // The switch floats over the wall, so the wall fades under it rather
        // than putting a panel in front of the work.
        const double floor = 120;
        final double available = math.max(200, room.maxWidth - margin * 2);
        // Three frames across a 1280 window, four across a wide one, and never
        // fewer columns than there are frames to put in them.
        final int fitting = math.max(
          1,
          math.min(5, ((available + gap) / 328).floor()),
        );
        final int columns = math.max(1, math.min(prints.length, fitting));
        // A wall hangs one frame. A frame is the picture's shape plus its
        // rebate, so the frames cannot all be the same width and also the same
        // size: a portrait frame would be nearly twice the film of a landscape
        // one. They are given the same **area** instead, and `film` is the
        // width a landscape 3:2 frame of that area would have.
        final double perWidth = prints.isEmpty
            ? FilmFrameMetrics.heightPerWidthFor(1.5)
            : prints
                  .map(
                    (Print print) =>
                        FilmFrameMetrics.heightPerWidthFor(print.aspect),
                  )
                  .fold(0.74, math.max);
        final double film = math.min(
          math.min(
            (available - gap * (columns - 1)) / columns,
            (room.maxHeight - floor - 40) / perWidth,
          ),
          KalloWall.largest,
        );
        // A landscape 3:2 frame gets the full `film` width; a portrait gets
        // the same area, so it is the same piece of film turned.
        final double landscape = FilmFrameMetrics.fromWidth(
          1000,
          aspect: 1.5,
        ).aspect;
        final double area = film * film / landscape;
        double frameAspect(Print print) =>
            FilmFrameMetrics.fromWidth(1000, aspect: print.aspect).aspect;
        double widthOf(Print print) => math.sqrt(area * frameAspect(print));
        double heightOf(Print print) => widthOf(print) / frameAspect(print);
        final int rows = (prints.length / columns).ceil();
        final double tallest = prints.isEmpty
            ? 0.0
            : prints.map(heightOf).reduce(math.max);
        final double height = math.max(film * 0.74, tallest) + 30;
        final double content = rows * height + math.max(0, rows - 1) * gap;
        final double top = math.max(margin, (room.maxHeight - content) / 2);

        return Stack(
          key: _field,
          fit: StackFit.expand,
          children: <Widget>[
            Wall(wall: wall, light: light),
            if (prints.isNotEmpty)
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(margin, top, margin, floor),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    for (int i = 0; i < prints.length; i++)
                      _Hung(
                        print: prints[i],
                        printNumber: prints[i].printNumber,
                        wall: wall,
                        width: widthOf(prints[i]),
                        light: light,
                        printed: printed,
                        cursor: _lensFor == null
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.none,
                        onHover: (Offset local, Offset global) => _lookAt(
                          prints[i],
                          prints[i].printNumber,
                          local,
                          widthOf(prints[i]),
                          global,
                        ),
                        onLeave: _leaveLens,
                        onTap: () => setState(() {
                          _near = prints[i];
                          _nearPrintNumber = prints[i].printNumber;
                        }),
                      ),
                  ],
                ),
              ),
            if (_lensFor != null)
              _Lens(
                key: const Key('lens'),
                at: _lensAt,
                width: _lensWidth,
                point: _lensPoint,
                image: _lens ?? _lensFor!.image,
                film: _lensFor!.film,
                printNumber: _lensPrintNumber,
                process: _lensFor!.process,
                light: printed,
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: floor,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        KalloColors.under(
                          wall.base,
                          light,
                        ).withValues(alpha: 0),
                        KalloColors.under(wall.base, light),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: KalloSpace.step6,
              child: Center(
                child: KalloSwitch(
                  key: const Key('light'),
                  label: s.roomLight,
                  control: wall.controlAt(light),
                  on: light > 0.5,
                  onTap: widget.onLight,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The print, looked at closely.
///
/// The wall hangs a frame 660 points wide because that is what a wall is; the
/// file the model wrote is 6000, and the difference is the whole point of
/// walking up to it. The film does not grow — this is not a picture viewer, it
/// is a loupe on a frame — so the rebate keeps its size and shape, and the
/// image is magnified *inside* the aperture, clipped by the gate. What you
/// never see is a photograph floating on a background: you see film, and a
/// corner of it enlarged.
///
/// The scale readout is absolute: it says how big one of the file's pixels is on
/// this display, so `1:1` means one image pixel per device pixel and is as far
/// as the loupe goes. Past that there is nothing left in the file to show.
///
/// The image is seen through the glass, so it bows a little at the edge. The
/// export is the flat frame: a lens is how you look, not what the film is.
class _Loupe extends StatefulWidget {
  const _Loupe({
    required this.print,
    required this.printNumber,
    required this.wall,
    required this.light,
    required this.printed,
    required this.onLight,
    required this.onClose,
  });

  final Print print;
  final int printNumber;

  /// Which wall: the one the print was hanging on.
  final KalloWall wall;

  /// The room's light: the wall and its label are under it.
  final double light;

  /// The light on the film, which holds a little after the wall has gone out.
  final double printed;

  /// The lamp is the room's, and this is still the room: a person who walked up
  /// to a print in the dark has to be able to turn the light on.
  final VoidCallback onLight;

  final VoidCallback onClose;

  @override
  State<_Loupe> createState() => _LoupeState();
}

class _LoupeState extends State<_Loupe> {
  /// The file's own pixels, once they have been decoded. The wall's copy stands
  /// in until then, which is what the eye was already looking at.
  ui.Image? _full;

  /// Magnification over the fit: 1 is the whole frame, and the ceiling is the
  /// scale at which one image pixel is one device pixel.
  double _mag = 1;

  /// Where the picture is held, in points, from the centre of its aperture.
  Offset _pan = Offset.zero;

  bool _exporting = false;
  bool _exported = false;
  bool _exportFailed = false;
  Timer? _exportedTimer;

  /// The loupe takes the keyboard while it is open, so that escape closes it
  /// rather than anything behind it. The room already has a focus node and
  /// autofocus on this one would not take it away from a node that has it.
  final FocusNode _keys = FocusNode(debugLabel: 'loupe');

  bool get _canExport => widget.print.path != null;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keys.requestFocus();
      }
    });
  }

  Future<void> _load() async {
    final ui.Image? full = await widget.print.full();
    if (!mounted) {
      full?.dispose();
      return;
    }
    setState(() => _full = full);
  }

  @override
  void dispose() {
    _exportedTimer?.cancel();
    _full?.dispose();
    _keys.dispose();
    super.dispose();
  }

  /// The image and the size it says it is: the file's, or the wall's copy when
  /// the print had no file behind it.
  ({ui.Image image, Size pixels}) get _pixels {
    final ui.Image? full = _full;
    if (full != null) {
      final Size? declared = widget.print.pixels;
      return (
        image: full,
        pixels: declared ?? Size(full.width.toDouble(), full.height.toDouble()),
      );
    }
    final ui.Image wall = widget.print.image;
    return (
      image: wall,
      pixels:
          widget.print.pixels ??
          Size(wall.width.toDouble(), wall.height.toDouble()),
    );
  }

  double get _aspect {
    final Size pixels = _pixels.pixels;
    return pixels.width / pixels.height;
  }

  /// One image pixel per device pixel, as a magnification over the fit.
  double _ceiling(double fit) => fit >= 1 ? 1 : 1 / fit;

  Future<void> _chooseExport() async {
    if (_exporting || !_canExport) {
      return;
    }
    final KalloStrings s = KalloStrings.of(context);
    final ExportOptions? options = await showExportSheet(
      context,
      title: s.exportFrame,
      confirm: s.export,
      sizes: <ExportSize>[
        ExportSize(s.originalSize, null),
        const ExportSize('4096 px', 4096),
      ],
      formats: const <ExportFormat>[
        ExportFormat.jpeg,
        ExportFormat.png,
        ExportFormat.tiff,
      ],
      initialFormat: ExportFormat.jpeg,
    );
    if (options == null || !mounted) {
      return;
    }
    await _export(options);
  }

  Future<void> _export(ExportOptions options) async {
    if (_exporting || !_canExport) {
      return;
    }
    _exportedTimer?.cancel();
    setState(() {
      _exporting = true;
      _exported = false;
      _exportFailed = false;
    });
    try {
      await exportFilmFrame(
        print: widget.print,
        printNumber: widget.printNumber,
        image: _full,
        maxEdge: options.size,
        format: options.format,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _exporting = false;
        _exported = true;
      });
      _exportedTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _exported = false);
        }
      });
    } on Object catch (error) {
      Model.log('the film frame could not be exported: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _exporting = false;
        _exportFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final double light = widget.light;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        if (_canExport)
          const SingleActivator(LogicalKeyboardKey.keyE): () =>
              unawaited(_chooseExport()),
      },
      child: Focus(
        focusNode: _keys,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Wall(wall: widget.wall, light: light),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints room) {
                final Size pixels = _pixels.pixels;
                final double aspect = _aspect;
                final double perWidth = FilmFrameMetrics.heightPerWidthFor(
                  aspect,
                );
                final double freeWidth = math.max(240, room.maxWidth - 80);
                final double freeHeight = math.max(200, room.maxHeight - 150);
                final double filmWidth = math.min(
                  freeWidth,
                  freeHeight / perWidth,
                );
                final FilmFrameMetrics metrics = FilmFrameMetrics.fromWidth(
                  filmWidth,
                  aspect: aspect,
                );
                final double fit = math.min(
                  1,
                  dpr * metrics.aperture.width / pixels.width,
                );
                final double ceiling = _ceiling(fit);
                final double mag = _mag.clamp(1.0, ceiling);
                final double percent = fit * mag * 100;
                final double limitX =
                    math.max(
                      0,
                      metrics.aperture.width * mag - metrics.aperture.width,
                    ) /
                    2;
                final double limitY =
                    math.max(
                      0,
                      metrics.aperture.height * mag - metrics.aperture.height,
                    ) /
                    2;
                final Offset pan = _clamp(_pan, Size(limitX, limitY));
                final double sourceWidth = pixels.width / mag;
                final double sourceHeight = pixels.height / mag;
                final Offset centre = Offset(
                  pixels.width / 2 -
                      pan.dx * sourceWidth / metrics.aperture.width,
                  pixels.height / 2 -
                      pan.dy * sourceHeight / metrics.aperture.height,
                );
                final Rect source = Rect.fromLTWH(
                  (centre.dx - sourceWidth / 2).clamp(
                    0,
                    math.max(0, pixels.width - sourceWidth),
                  ),
                  (centre.dy - sourceHeight / 2).clamp(
                    0,
                    math.max(0, pixels.height - sourceHeight),
                  ),
                  sourceWidth,
                  sourceHeight,
                );
                final double barrel = ceiling > 1.001
                    ? 0.075 * ((mag - 1) / (ceiling - 1)).clamp(0.0, 1.0)
                    : 0;
                final String exportLabel = _exporting
                    ? s.exportingFrame
                    : _exportFailed
                    ? s.exportFailed
                    : _exported
                    ? s.exportedFrame
                    : s.exportFrame;

                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Align(
                      alignment: const Alignment(0, -0.12),
                      child: SizedBox(
                        width: metrics.outer.width,
                        height: metrics.outer.height,
                        child: Stack(
                          children: <Widget>[
                            FilmFrame(
                              image: _pixels.image,
                              width: metrics.outer.width,
                              source: source,
                              film: widget.print.film,
                              printNumber: widget.printNumber,
                              process: widget.print.process,
                              light: widget.printed,
                              barrel: barrel,
                            ),
                            Positioned.fromRect(
                              rect: metrics.aperture,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.zoomIn,
                                child: Listener(
                                  onPointerSignal: (PointerSignalEvent event) {
                                    if (event is PointerScrollEvent) {
                                      _zoom(
                                        event,
                                        metrics.aperture.width,
                                        aspect,
                                        ceiling,
                                      );
                                    }
                                  },
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanUpdate: (DragUpdateDetails d) =>
                                        setState(
                                          () => _pan = _clamp(
                                            _pan + d.delta,
                                            Size(limitX, limitY),
                                          ),
                                        ),
                                    onDoubleTap: () => setState(() {
                                      _mag = _mag >= ceiling - 0.001
                                          ? 1
                                          : ceiling;
                                      _pan = Offset.zero;
                                    }),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 40,
                      right: 40,
                      bottom: 28,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text.rich(
                                  TextSpan(
                                    children: wallLabel(
                                      light: light,
                                      wall: widget.wall,
                                      film: filmEdgeName(widget.print.film),
                                      clock: widget.print.clock,
                                      paper: widget.print.paper,
                                      fallback: widget.print.name,
                                    ),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: KalloType.caption.copyWith(
                                    letterSpacing: 0.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s.magnification(
                                    '${pixels.width.round()} × '
                                    '${pixels.height.round()}',
                                    percent >= 99.5
                                        ? s.actualPixels
                                        : '${percent.round()} %',
                                  ),
                                  style: KalloType.data.copyWith(
                                    color: KalloColors.under(
                                      widget.wall.label,
                                      light,
                                    ).withValues(alpha: 0.60),
                                    fontFeatures: const <FontFeature>[
                                      FontFeature('tnum'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: KalloSpace.step4),
                          KalloSwitch(
                            label: s.roomLight,
                            control: widget.wall.controlAt(light),
                            on: widget.light > 0.5,
                            onTap: widget.onLight,
                          ),
                          const SizedBox(width: KalloSpace.step3),
                          _Pill(
                            key: const Key('export'),
                            label: exportLabel,
                            control: widget.wall.controlAt(light),
                            onTap: _canExport
                                ? () => unawaited(_chooseExport())
                                : null,
                            enabled: _canExport && !_exporting,
                          ),
                          const SizedBox(width: KalloSpace.step3),
                          _Pill(
                            key: const Key('back'),
                            label: s.back,
                            control: widget.wall.controlAt(light),
                            onTap: widget.onClose,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Zoom about the pointer, so that what is under it stays under it.
  void _zoom(
    PointerScrollEvent event,
    double area,
    double aspect,
    double ceiling,
  ) {
    final double current = _mag;
    final double next = (current * math.exp(-event.scrollDelta.dy / 420)).clamp(
      1.0,
      ceiling,
    );
    if ((next - current).abs() < 0.001) {
      return;
    }
    final Offset centre = Offset(area / 2, area / aspect / 2);
    final Offset held = event.localPosition - centre;
    setState(() {
      _pan = _clamp(
        _pan * (next / current) + held * (1 - next / current),
        Size(
          math.max(0, area * next - area) / 2,
          math.max(0, area * next / aspect - area / aspect) / 2,
        ),
      );
      _mag = next;
    });
  }

  static Offset _clamp(Offset value, Size limit) => Offset(
    value.dx.clamp(-limit.width, limit.width),
    value.dy.clamp(-limit.height, limit.height),
  );
}

/// A control on the wall, lit by itself: a pill you can still find in the dark.
class _Pill extends StatefulWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.control,
    required this.onTap,
    this.enabled = true,
  });

  final String label;

  /// The wall's own light: a pale control on a dark wall, ink on a light one.
  final Color control;

  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color control = widget.control;
    final bool lit = widget.enabled && _hover;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: KalloSpace.step3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: control.withValues(alpha: lit ? 0.10 : 0.04),
            borderRadius: BorderRadius.circular(KalloRadius.control),
            border: Border.all(
              color: control.withValues(alpha: lit ? 0.28 : 0.16),
            ),
          ),
          child: Text(
            widget.label,
            style: KalloType.small.copyWith(
              color: control.withValues(
                alpha: widget.enabled ? (lit ? 0.92 : 0.70) : 0.34,
              ),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// One print on the wall: a 35 mm frame, with the label under it.
class _Hung extends StatelessWidget {
  const _Hung({
    required this.print,
    required this.printNumber,
    required this.wall,
    required this.width,
    required this.light,
    required this.printed,
    required this.cursor,
    required this.onHover,
    required this.onLeave,
    required this.onTap,
  });

  final Print print;
  final int printNumber;

  /// Which wall: the light one in a light appearance, the dark one after dark.
  final KalloWall wall;

  final double width;

  /// The light on the wall, which the label is on.
  final double light;

  /// The light on the film, which holds a little longer.
  final double printed;

  /// What the pointer is over the print: a hand until the loupe is up, and
  /// then nothing — the glass is where the pointer is, and a hand inside it is
  /// a hand on the picture.
  final MouseCursor cursor;

  /// The lens: the pointer over the frame, its place on the frame, and where
  /// it is on the wall.
  final void Function(Offset local, Offset global) onHover;
  final VoidCallback onLeave;

  /// Walking up to the print: the loupe.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MouseRegion(
            cursor: cursor,
            onHover: (PointerHoverEvent event) =>
                onHover(event.localPosition, event.position),
            onExit: (_) => onLeave(),
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: FilmFrame(
                image: print.image,
                width: width,
                film: print.film,
                printNumber: printNumber,
                process: print.process,
                light: printed,
                semanticLabel: filmEdgeName(print.film).isEmpty
                    ? '${print.name} · ${printNumber.toString().padLeft(2, '0')}'
                    : '${filmEdgeName(print.film)} · '
                          '${printNumber.toString().padLeft(2, '0')}',
              ),
            ),
          ),
          const SizedBox(height: KalloSpace.step3 - 2),
          Text.rich(
            TextSpan(
              children: wallLabel(
                light: light,
                wall: wall,
                film: filmEdgeName(print.film),
                clock: print.clock,
                paper: print.paper,
                fallback: print.name,
              ),
            ),
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
    );
  }
}

/// A loupe held over the wall.
///
/// It is the frame at three times the wall, from a decode wide enough that the
/// glass has something to show: magnifying the wall's own copy would only
/// magnify a screen image. The glass is a real object — a bezel and a
/// reflection — because a loupe is held, and a circle of nothing is not held.
/// The picture under it is seen through the glass, so it bows at the edge; the
/// frame and the holes stay flat.
class _Lens extends StatelessWidget {
  const _Lens({
    super.key,
    required this.at,
    required this.width,
    required this.point,
    required this.image,
    required this.film,
    required this.printNumber,
    required this.process,
    required this.light,
  });

  /// Where the lens is, in the wall's coordinates.
  final Offset at;

  /// The frame's width on the wall.
  final double width;

  /// Where the pointer is on the frame.
  final Offset point;

  /// The print's picture, at the best size there is.
  final ui.Image image;

  final String? film;
  final int printNumber;
  final FilmProcess? process;
  final double light;

  static const double radius = 90;
  static const double _magnification = 3;

  @override
  Widget build(BuildContext context) {
    final double filmWidth = width * _magnification;
    return KalloLens(
      at: at,
      radius: radius,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: radius - point.dx * _magnification,
            top: radius - point.dy * _magnification,
            child: FilmFrame(
              image: image,
              width: filmWidth,
              film: film,
              printNumber: printNumber,
              process: process,
              light: light,
              barrel: 0.075,
            ),
          ),
        ],
      ),
    );
  }
}
