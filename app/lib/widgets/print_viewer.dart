import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';
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

class _PrintViewerState extends State<PrintViewer> {
  /// The file's copy, when the rack's copy is not the whole picture.
  ui.Image? _full;
  final FocusNode _keys = FocusNode(debugLabel: 'print-viewer');

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
    if (full != null) {
      setState(() => _full = full);
    }
  }

  @override
  void dispose() {
    _full?.dispose();
    _keys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloRack rack = KalloRack.of(colors.brightness);
    final ui.Image image = _full ?? widget.print.image;
    final Print print = widget.print;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
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
          onTap: widget.onClose,
          label: s.close,
        ),
      ],
    );
  }

  Widget _picture(ui.Image image, Print print, KalloColors colors) {
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
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(120),
          child: Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: KalloShadow.sheet),
              child: PrintSheet(
                width: width,
                aspect: print.aspect,
                paper: colors.print,
                outline: colors.hairline,
                light: 1,
                child: RawImage(
                  image: image,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
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
