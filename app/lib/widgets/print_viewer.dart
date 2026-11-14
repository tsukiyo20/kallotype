import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/print.dart';
import 'wall.dart';

/// Open a print at the window's full size.
///
/// The rack is a place to hang paper; this is the same paper taken down and
/// held up. It covers the window, including both sidebars, because the point
/// of walking up to a print is that the room gets out of the way.
Future<void> showPrintViewer(BuildContext context, {required Print print}) {
  final KalloStrings s = KalloStrings.of(context);
  final KalloColors colors = KalloScope.colorsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: s.close,
    barrierColor: colors.scrim,
    transitionDuration: KalloMotion.settle,
    pageBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondary,
    ) => PrintViewer(print: print),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondary,
          Widget child,
        ) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: KalloMotion.enter),
          child: child,
        ),
  );
}

/// One print, as large as the window lets it be.
class PrintViewer extends StatefulWidget {
  const PrintViewer({super.key, required this.print});

  final Print print;

  @override
  State<PrintViewer> createState() => _PrintViewerState();
}

class _PrintViewerState extends State<PrintViewer> {
  /// The file's copy, when the wall's copy is not the whole picture.
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

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final ui.Image image = _full ?? widget.print.image;
    final Print print = widget.print;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        focusNode: _keys,
        child: ColoredBox(
          color: KalloViewer.background,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // A little light on the paper's own wall, so the black is a room
              // and not a hole.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.18),
                    radius: 0.95,
                    colors: <Color>[Color(0xFF17171A), KalloViewer.background],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _head(s, print),
                      const SizedBox(height: 12),
                      Expanded(child: _picture(image, print)),
                      const SizedBox(height: 10),
                      _foot(print),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _head(KalloStrings s, Print print) {
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
                  color: KalloViewer.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                s.rack,
                style: KalloType.caption.copyWith(
                  color: KalloViewer.muted,
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

  Widget _picture(ui.Image image, Print print) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints room) {
        final double heightPerWidth = PrintSheet.heightPerWidth(
          aspect: print.aspect,
        );
        final double width = math.max(
          180,
          math.min(
            room.maxWidth,
            math.max(220, (room.maxHeight) / heightPerWidth),
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
                paper: KalloColors.light.print,
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

  Widget _foot(Print print) {
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
      style: KalloType.small.copyWith(color: KalloViewer.muted),
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
              color: _hover ? const Color(0x33FFFFFF) : KalloViewer.fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: _hover ? const Color(0x4DFFFFFF) : KalloViewer.hairline,
              ),
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(12, 12),
                painter: _ClosePainter(
                  _hover ? KalloViewer.ink : KalloViewer.muted,
                ),
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
