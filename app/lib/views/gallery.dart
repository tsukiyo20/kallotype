import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';
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
/// Everything exported hangs here, because a gallery shows the work there is.
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

  /// The print under the lens, and where the lens is.
  ///
  /// The lens is a loupe held over the sheet, not a picture viewer: it shows
  /// the print at the scale a loupe would, three times the wall, from a decode
  /// wide enough that the glass has something to show. It goes away when the
  /// pointer does, and clicking still walks up to the whole file.
  Print? _lensFor;
  ui.Image? _lens;
  Offset _lensAt = Offset.zero;
  Offset _lensPoint = Offset.zero;
  Size _lensSheet = Size.zero;

  /// The wall's box, which is where the lens is placed.
  final GlobalKey _field = GlobalKey(debugLabel: 'wall');

  void _lookAt(Print print, Offset local, Size sheet, Offset global) {
    final RenderBox? box = _field.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    if (!identical(print, _lensFor)) {
      _lensFor = print;
      _dropLens();
      unawaited(_loadLens(print));
    }
    setState(() {
      _lensAt = box.globalToLocal(global);
      _lensPoint = local;
      _lensSheet = sheet;
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
    final KalloWall wall =
        KalloWall.of(KalloScope.colorsOf(context).brightness);
    final double light = widget.light;
    final Print? near = _near;
    // The paper holds its light better than the room does, for the same reason
    // everything else does not: the eye is the instrument here, not the lamp.
    final double printed = KalloWall.darkAdaptation +
        (1 - KalloWall.darkAdaptation) * light;
    final List<Print> prints = widget.prints;

    if (near != null) {
      return _Loupe(
        print: near,
        wall: wall,
        light: light,
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
        // Three prints across a 1280 window, four across a wide one, and never
        // fewer columns than there are prints to put in them.
        final int fitting =
            math.max(1, math.min(5, ((available + gap) / 328).floor()));
        final int columns = math.max(1, math.min(prints.length, fitting));
        // A wall hangs one paper. A sheet is the shape of the picture on it,
        // so the sheets cannot all be the same width and also the same size: a
        // vertical frame would be twice the paper of a horizontal one. They
        // are given the same **area** instead — the same sheet, turned —
        // and `paper` is the width a 3:2 sheet of that area would have.
        final double perWidth = prints.isEmpty
            ? 0.74
            : prints
                .map(
                  (Print print) =>
                      PrintSheet.heightPerWidth(aspect: print.aspect),
                )
                .fold(0.74, math.max);
        final double paper = math.min(
          math.min(
            (available - gap * (columns - 1)) / columns,
            (room.maxHeight - floor - 40) / perWidth,
          ),
          KalloWall.largest,
        );
        final double area = paper * paper / 1.5;
        double widthOf(Print print) => math.sqrt(area * print.aspect);
        double heightOf(Print print) =>
            PrintSheet.heightOf(widthOf(print), aspect: print.aspect);
        final int rows = (prints.length / columns).ceil();
        final double tallest =
            prints.isEmpty ? 0.0 : prints.map(heightOf).reduce(math.max);
        final double height = math.max(paper * 0.74, tallest) + 30;
        final double content =
            rows * height + math.max(0, rows - 1) * gap;
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
                    for (final Print print in prints)
                      _Hung(
                        print: print,
                        wall: wall,
                        width: widthOf(print),
                        light: light,
                        printed: printed,
                        cursor: _lensFor == null
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.none,
                        onHover: (Offset local, Size sheet, Offset global) =>
                            _lookAt(print, local, sheet, global),
                        onLeave: _leaveLens,
                        onTap: () => setState(() => _near = print),
                      ),
                  ],
                ),
              ),
            if (_lensFor != null)
              _Lens(
                key: const Key('lens'),
                at: _lensAt,
                sheet: _lensSheet,
                point: _lensPoint,
                image: _lens ?? _lensFor!.image,
                wall: wall,
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
                        KalloColors.under(wall.base, light).withValues(alpha: 0),
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
/// The wall hangs a print 660 points wide because that is what a wall is; the
/// file the model wrote is 6000, and the difference is the whole point of
/// walking up to it. The paper does not grow — this is not a picture viewer, it
/// is a loupe on a sheet — so the sheet keeps its size and shape, and the image
/// is magnified *inside* it, clipped by its own margin. What you never see is a
/// photograph floating on a background: you see paper, and a corner of it
/// enlarged.
///
/// The scale readout is absolute: it says how big one of the file's pixels is on
/// this display, so `1:1` means one image pixel per device pixel and is as far
/// as the loupe goes. Past that there is nothing left in the file to show.
class _Loupe extends StatefulWidget {
  const _Loupe({
    required this.print,
    required this.wall,
    required this.light,
    required this.onLight,
    required this.onClose,
  });

  final Print print;

  /// Which wall: the one the print was hanging on.
  final KalloWall wall;

  /// The room's light: the sheet and its label are under it.
  final double light;

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

  /// Magnification over the fit: 1 is the whole print, and the ceiling is the
  /// scale at which one image pixel is one device pixel.
  double _mag = 1;

  /// Where the print is held, in points, from the centre of its area.
  Offset _pan = Offset.zero;

  /// The loupe takes the keyboard while it is open, so that escape closes it
  /// rather than anything behind it. The room already has a focus node and
  /// autofocus on this one would not take it away from a node that has it.
  final FocusNode _keys = FocusNode(debugLabel: 'loupe');

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
        pixels: declared ??
            Size(full.width.toDouble(), full.height.toDouble()),
      );
    }
    final ui.Image wall = widget.print.image;
    return (
      image: wall,
      pixels: widget.print.pixels ??
          Size(wall.width.toDouble(), wall.height.toDouble()),
    );
  }

  double get _aspect {
    final Size pixels = _pixels.pixels;
    return pixels.width / pixels.height;
  }

  /// One image pixel per device pixel, as a magnification over the fit.
  double _ceiling(double fit) => fit >= 1 ? 1 : 1 / fit;

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final double light = widget.light;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
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
                // A fine print's margin, as on the wall: 3 % on three sides
                // and a little more at the bottom.
                const double border = 0.030;
                final double perWidth =
                    border + (1 - border * 2) / aspect + border * 2.2;
                final double freeWidth =
                    math.max(240, room.maxWidth - 80);
                final double freeHeight =
                    math.max(200, room.maxHeight - 132);
                final double paper = math.min(
                  freeWidth,
                  freeHeight / perWidth,
                );
                final double edge = paper * border;
                final double area =
                    paper - edge * 2;
                final double fit = math.min(1, dpr * area / pixels.width);
                final double ceiling = _ceiling(fit);
                final double mag = _mag.clamp(1.0, ceiling);
                final double percent = fit * mag * 100;
                final Size held = Size(area * mag, area * mag / aspect);
                final Offset pan = _clamp(
                  _pan,
                  Size(
                    math.max(0, held.width - area) / 2,
                    math.max(0, held.height - area / aspect) / 2,
                  ),
                );

                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Align(
                      alignment: const Alignment(0, -0.12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: KalloColors.under(widget.wall.paper, light),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            edge,
                            edge,
                            edge,
                            edge * 2.2,
                          ),
                          child: SizedBox(
                            width: area,
                            height: area / aspect,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.zoomIn,
                              child: Listener(
                                onPointerSignal: (PointerSignalEvent event) {
                                if (event is PointerScrollEvent) {
                                  _zoom(event, area, aspect, ceiling);
                                }
                              },
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (DragUpdateDetails d) => setState(
                                  () => _pan = _clamp(
                                    _pan + d.delta,
                                    Size(
                                      math.max(0, held.width - area) / 2,
                                      math.max(0, held.height - area / aspect) /
                                          2,
                                    ),
                                  ),
                                ),
                                onDoubleTap: () => setState(() {
                                  _mag = _mag >= ceiling - 0.001 ? 1 : ceiling;
                                  _pan = Offset.zero;
                                }),
                                  child: ClipRect(
                                    child: Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()
                                        ..translateByDouble(
                                          pan.dx,
                                          pan.dy,
                                          0,
                                          1,
                                        )
                                        ..scaleByDouble(mag, mag, 1, 1),
                                      child: RawImage(
                                        image: _pixels.image,
                                        fit: BoxFit.fill,
                                        filterQuality: FilterQuality.high,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
                                      film: widget.print.film,
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
    final double fit = _mag;
    final double next =
        (fit * math.exp(-event.scrollDelta.dy / 420)).clamp(1.0, ceiling);
    if ((next - fit).abs() < 0.001) {
      return;
    }
    final Offset centre = Offset(area / 2, area / aspect / 2);
    final Offset held = event.localPosition - centre;
    setState(() {
      _pan = _clamp(
        _pan * (next / fit) + held * (1 - next / fit),
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
    required this.label,
    required this.control,
    required this.onTap,
  });

  final String label;

  /// The wall's own light: a pale control on a dark wall, ink on a light one.
  final Color control;

  final VoidCallback onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color control = widget.control;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const Key('back'),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: KalloSpace.step3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: control.withValues(alpha: _hover ? 0.10 : 0.04),
            borderRadius: BorderRadius.circular(KalloRadius.control),
            border: Border.all(
              color: control.withValues(alpha: _hover ? 0.28 : 0.16),
            ),
          ),
          child: Text(
            widget.label,
            style: KalloType.small.copyWith(
              color: control.withValues(alpha: _hover ? 0.92 : 0.70),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// One print on the wall, with the label under it.
class _Hung extends StatelessWidget {
  const _Hung({
    required this.print,
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

  /// Which wall: the light one in a light appearance, the dark one after dark.
  final KalloWall wall;

  final double width;

  /// The light on the wall, which the label is on.
  final double light;

  /// The light on the print, which holds a little longer.
  final double printed;

  /// What the pointer is over the print: a hand until the loupe is up, and
  /// then nothing — the glass is where the pointer is, and a hand inside it is
  /// a hand on the picture.
  final MouseCursor cursor;

  /// The lens: the pointer over the sheet, its place on the sheet, the sheet's
  /// size, and where it is on the wall.
  final void Function(Offset local, Size sheet, Offset global) onHover;
  final VoidCallback onLeave;

  /// Walking up to the print: the loupe.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double aspect = print.aspect;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MouseRegion(
            cursor: cursor,
            onHover: (PointerHoverEvent event) => onHover(
              event.localPosition,
              Size(width, PrintSheet.heightOf(width, aspect: aspect)),
              event.position,
            ),
            onExit: (_) => onLeave(),
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: PrintSheet(
                width: width,
                aspect: aspect,
                paper: wall.paper,
                outline: wall.outline,
                light: printed,
                child: RawImage(
                  image: print.image,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          const SizedBox(height: KalloSpace.step3 - 2),
          Text.rich(
            TextSpan(
              children: wallLabel(
                light: light,
                wall: wall,
                film: print.film,
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

/// The switch on the wall, and the only thing in this room that is its own
/// light: it does not dim, because a control you cannot find in the dark is a
/// control that has been taken away.
/// A loupe held over the wall.
///
/// It is the print at three times the wall, from a decode wide enough that the
/// glass has something to show: magnifying the wall's own copy would only
/// magnify a screen image. The glass is a real object — a bezel and a
/// reflection — because a loupe is held, and a circle of nothing is not held.
class _Lens extends StatelessWidget {
  const _Lens({
    super.key,
    required this.at,
    required this.sheet,
    required this.point,
    required this.image,
    required this.wall,
  });

  /// Where the lens is, in the wall's coordinates.
  final Offset at;

  /// The sheet's size on the wall.
  final Size sheet;

  /// Where the pointer is on the sheet.
  final Offset point;

  /// The print's picture, at the best size there is.
  final ui.Image image;

  final KalloWall wall;

  static const double radius = 90;
  static const double _magnification = 3;

  @override
  Widget build(BuildContext context) {
    final double aspect = image.width / image.height;
    final double width = sheet.width * _magnification;
    final double height = sheet.height * _magnification;
    return KalloLens(
      at: at,
      radius: radius,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: radius - (point.dx / sheet.width) * width,
            top: radius - (point.dy / sheet.height) * height,
            child: PrintSheet(
              width: width,
              aspect: aspect,
              paper: wall.paper,
              outline: wall.outline,
              child: RawImage(
                image: image,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
