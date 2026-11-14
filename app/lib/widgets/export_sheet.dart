import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/export_format.dart';
import 'button.dart';
import 'chip.dart';

/// A sheet that asks how a finished picture should be written.
///
/// It is a route over the window, not a Material dialog: the barrier is the
/// window's own ink at a low alpha, and the card is the surface plane with a
/// hairline. The size row says what the pixels do, the format row says what
/// happens to them, and the note under it is the trade — JPEG throws detail
/// away for a small file; PNG and TIFF do not.
Future<ExportOptions?> showExportSheet(
  BuildContext context, {
  required String title,
  required String confirm,
  required List<ExportSize> sizes,
  required List<ExportFormat> formats,
  int initialSize = 0,
  ExportFormat initialFormat = ExportFormat.jpeg,
}) {
  final KalloStrings s = KalloStrings.of(context);
  final KalloColors colors = KalloScope.colorsOf(context);
  return showGeneralDialog<ExportOptions>(
    context: context,
    barrierDismissible: true,
    barrierLabel: s.cancel,
    barrierColor: colors.scrim,
    transitionDuration: KalloMotion.settle,
    pageBuilder:
        (
          BuildContext dialogContext,
          Animation<double> animation,
          Animation<double> secondary,
        ) => _ExportSheet(
          title: title,
          confirm: confirm,
          sizes: sizes,
          formats: formats,
          initialSize: initialSize,
          initialFormat: initialFormat,
        ),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondary,
          Widget child,
        ) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: KalloMotion.enter),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(
              CurvedAnimation(parent: animation, curve: KalloMotion.enter),
            ),
            child: child,
          ),
        ),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({
    required this.title,
    required this.confirm,
    required this.sizes,
    required this.formats,
    required this.initialSize,
    required this.initialFormat,
  });

  final String title;
  final String confirm;
  final List<ExportSize> sizes;
  final List<ExportFormat> formats;
  final int initialSize;
  final ExportFormat initialFormat;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late int _size = widget.initialSize.clamp(0, widget.sizes.length - 1);
  late ExportFormat _format = widget.formats.contains(widget.initialFormat)
      ? widget.initialFormat
      : widget.formats.first;

  void _cancel() => Navigator.of(context).pop();

  void _confirm() =>
      Navigator.of(context)
          .pop(ExportOptions(size: widget.sizes[_size].value, format: _format));

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: Focus(
        autofocus: true,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(KalloSpace.step5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(KalloRadius.sheet),
                    boxShadow: KalloShadow.sheet,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      KalloSpace.step5 + 2,
                      KalloSpace.step5,
                      KalloSpace.step5 + 2,
                      KalloSpace.step5,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                widget.title,
                                style: KalloType.display.copyWith(
                                  color: colors.ink,
                                ),
                              ),
                            ),
                            GestureDetector(
                              key: const Key('export-cancel'),
                              onTap: _cancel,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.all(KalloSpace.step2),
                                child: Text(
                                  s.cancel,
                                  style: KalloType.small.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: KalloSpace.step5),
                        Text(
                          s.size,
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
                            for (int i = 0; i < widget.sizes.length; i++)
                              KalloChip(
                                label: widget.sizes[i].label,
                                selected: _size == i,
                                onTap: () => setState(() => _size = i),
                              ),
                          ],
                        ),
                        const SizedBox(height: KalloSpace.step2),
                        Text(
                          s.noUpscale,
                          style: KalloType.small.copyWith(
                            color: colors.inkFaint,
                          ),
                        ),
                        const SizedBox(height: KalloSpace.step5),
                        Text(
                          s.format,
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
                            for (final ExportFormat format in widget.formats)
                              KalloChip(
                                label: format.label,
                                selected: _format == format,
                                onTap: () => setState(() => _format = format),
                              ),
                          ],
                        ),
                        const SizedBox(height: KalloSpace.step3),
                        Text(
                          _format.lossless ? s.losslessNote : s.lossyNote,
                          style: KalloType.small.copyWith(
                            color: colors.inkFaint,
                          ),
                        ),
                        const SizedBox(height: KalloSpace.step5),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: KalloButton(
                                label: s.cancel,
                                onTap: _cancel,
                                height: 34,
                              ),
                            ),
                            const SizedBox(width: KalloSpace.step3),
                            Expanded(
                              child: KalloButton(
                                key: const Key('export-confirm'),
                                label: widget.confirm,
                                onTap: _confirm,
                                filled: true,
                                height: 34,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
