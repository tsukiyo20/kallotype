import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';
import '../lab/thumbnails.dart';
import 'shadow_box.dart';
import 'wall.dart';

/// One print, held up inside the drying rack's room.
///
/// It is not a route and not a second environment: the sidebars are the
/// window's, not the picture's, and they keep their own switches. The room's
/// ground and the window's ink are the ones already in use, so the print is
/// simply taken off the wire and looked at, not carried into a black box.
class PrintViewer extends StatefulWidget {
  const PrintViewer({
    super.key,
    required this.print,
    required this.onClose,
    this.topInset = 0,
  });

  final Print print;
  final VoidCallback onClose;

  /// The transparent chrome at the top of the window. The room's own head
  /// starts below it, like the rack's.
  final double topInset;

  @override
  State<PrintViewer> createState() => _PrintViewerState();
}

class _PrintViewerState extends State<PrintViewer>
    with SingleTickerProviderStateMixin {
  /// A copy wide enough for the window, loaded at once and dropped on close.
  PrintThumbnail? _preview;

  /// The width that copy was asked for, not the width it came back at: a
  /// small source is returned at its own size.
  int _previewTarget = 0;

  /// The newest preview request. A resize can ask for a wider copy while the
  /// first one is still decoding; only the newest may be installed.
  int _previewRequest = 0;

  /// The original, loaded only after the print is actually magnified. A glance
  /// at ten prints must not decode ten originals.
  ui.Image? _detail;
  PrintThumbnail? _thumbnail;
  bool _askingDetail = false;
  final FocusNode _keys = FocusNode(debugLabel: 'print-viewer');
  final TransformationController _transform = TransformationController();

  /// The print comes up, not the whole window: fading the viewer itself would
  /// make the engine raster a full 4K window for 160 ms and keep the caches
  /// afterwards. The header and the room's ground are already there.
  late final AnimationController _enter;
  late final CurvedAnimation _fade;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: KalloMotion.quick,
      reverseDuration: KalloMotion.instant,
    )..forward();
    _fade = CurvedAnimation(
      parent: _enter,
      curve: KalloMotion.enter,
      reverseCurve: KalloMotion.leave,
    );
    _loadThumbnail();
    _transform.addListener(_zoomChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keys.requestFocus();
      }
    });
  }

  Future<void> _loadThumbnail() async {
    final PrintThumbnail? thumbnail = await PrintThumbnailCache.instance
        .acquire(widget.print);
    if (!mounted || _preview != null || _detail != null) {
      thumbnail?.release();
      return;
    }
    setState(() => _thumbnail = thumbnail);
  }

  /// The preview is as wide as the paper on screen, not as wide as the file.
  ///
  /// A 4K window shows a print at more than 2400 physical pixels; a pinned
  /// 1600 copy would be visibly soft there. A 1016 window still asks for 1600,
  /// so the small-window path is unchanged.
  Future<void> _ensurePreview(int target) async {
    if (_detail != null || (_preview != null && _previewTarget >= target)) {
      return;
    }
    if (_previewTarget == target) {
      // Already in flight; a second request for the same width would decode
      // the same file twice.
      return;
    }
    _previewTarget = target;
    final int request = ++_previewRequest;
    final PrintThumbnail? preview = await PrintThumbnailCache.instance.acquire(
      widget.print,
      maxWidth: target,
    );
    if (!mounted || request != _previewRequest || _detail != null) {
      preview?.release(drop: true);
      return;
    }
    if (preview == null) {
      // Let the next build try again rather than treating a failed decode as
      // a preview that is already wide enough.
      if (_previewTarget == target) {
        _previewTarget = 0;
      }
      return;
    }
    final PrintThumbnail? old = _preview;
    final PrintThumbnail? oldThumbnail = _thumbnail;
    setState(() {
      _preview = preview;
      _thumbnail = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old?.release(drop: true);
      oldThumbnail?.release();
    });
  }

  /// The width of the preview for a print that is [width] points wide.
  ///
  /// It is quantised to 256-pixel steps, so resizing a window does not leave a
  /// new cache file for every pixel. The source's own width is the ceiling;
  /// this is a downscale, never an enlargement.
  int _previewWidthFor(double width) {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int source = widget.print.pixels?.width.round() ?? 1 << 20;
    int target = (width * dpr).ceil().clamp(
      PrintThumbnailCache.previewWidth,
      PrintThumbnailCache.previewMaxWidth,
    );
    target = ((target + 255) ~/ 256) * 256;
    return math.min(target, math.max(PrintThumbnailCache.previewWidth, source));
  }

  void _zoomChanged() {
    if (_detail == null &&
        !_askingDetail &&
        _transform.value.getMaxScaleOnAxis() > 1.5) {
      unawaited(_loadDetail());
    }
  }

  Future<void> _loadDetail() async {
    _askingDetail = true;
    // The original, not a 4000-pixel compromise: zoom is where the file's own
    // detail is the point. It is one image, disposed when the viewer closes.
    final ui.Image? detail = await widget.print.full();
    if (!mounted) {
      detail?.dispose();
      return;
    }
    if (detail == null) {
      _askingDetail = false;
      return;
    }
    final PrintThumbnail? oldPreview = _preview;
    final PrintThumbnail? oldThumbnail = _thumbnail;
    setState(() {
      _detail = detail;
      _preview = null;
      _thumbnail = null;
      _previewTarget = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldPreview?.release(drop: true);
      oldThumbnail?.release();
    });
  }

  void _close() {
    if (_leaving) {
      return;
    }
    _leaving = true;
    _enter.reverse().whenComplete(() {
      if (mounted) {
        widget.onClose();
      }
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    _fade.dispose();
    _enter.dispose();
    _detail?.dispose();
    _preview?.release(drop: true);
    _thumbnail?.release();
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloRack rack = KalloRack.of(colors.brightness);
    final ui.Image? image =
        _detail ?? _preview?.image ?? _thumbnail?.image ?? widget.print.image;
    final Print print = widget.print;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        focusNode: _keys,
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.62),
                radius: 1.08,
                colors: <Color>[rack.top, rack.base],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, widget.topInset + 16, 28, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _head(s, print, colors),
                  const SizedBox(height: 12),
                  Expanded(child: _picture(image, print, colors)),
                  const SizedBox(height: 10),
                  _foot(print, colors),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(KalloStrings s, Print print, KalloColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                print.folio,
                style: KalloType.data.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                s.rack,
                style: KalloType.caption.copyWith(
                  color: colors.inkFaint,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        _ViewerButton(
          key: const Key('print-viewer-close'),
          onTap: _close,
          label: s.close,
        ),
      ],
    );
  }

  Widget _picture(ui.Image? image, Print print, KalloColors colors) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints room) {
        final double heightPerWidth = PrintSheet.heightPerWidth(
          aspect: print.aspect,
        );
        final double width = math.max(
          180,
          math.min(
            room.maxWidth,
            math.max(220, room.maxHeight / heightPerWidth),
          ),
        );
        final int target = _previewWidthFor(width);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_ensurePreview(target));
          }
        });
        return InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(120),
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: KalloShadowBox(
                kind: KalloShadowKind.sheet,
                child: PrintSheet(
                  width: width,
                  aspect: print.aspect,
                  paper: colors.print,
                  outline: colors.hairline,
                  light: 1,
                  child: image == null
                      ? ColoredBox(color: colors.fill.withValues(alpha: 0.35))
                      : RawImage(
                          image: image,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _foot(Print print, KalloColors colors) {
    final List<String> facts = <String>[
      if (print.filmDisplay.isNotEmpty) print.filmDisplay,
      if (print.paperDisplay.isNotEmpty) print.paperDisplay,
      if (print.clock != null) print.clock!,
      if (print.tempC != null) '${print.tempC!.toStringAsFixed(1)} °C',
      if (print.pixels != null)
        '${print.pixels!.width.round()} × ${print.pixels!.height.round()}',
    ];
    return Text(
      facts.join('   ·   '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: KalloType.small.copyWith(color: colors.inkMuted),
    );
  }
}

class _ViewerButton extends StatefulWidget {
  const _ViewerButton({super.key, required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  State<_ViewerButton> createState() => _ViewerButtonState();
}

class _ViewerButtonState extends State<_ViewerButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: KalloMotion.instant,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _hover ? colors.fillStrong : colors.fill,
              shape: BoxShape.circle,
              border: Border.all(color: colors.hairline),
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(12, 12),
                painter: _ClosePainter(_hover ? colors.ink : colors.inkMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClosePainter extends CustomPainter {
  const _ClosePainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = colour
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(1, 1),
      Offset(size.width - 1, size.height - 1),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width - 1, 1),
      Offset(1, size.height - 1),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_ClosePainter old) => old.colour != colour;
}
