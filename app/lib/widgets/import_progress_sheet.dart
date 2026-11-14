import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import 'button.dart';
import 'shadow_box.dart';

/// The state of one import run.
///
/// The import itself is sequential: a copy and two marker writes per file.
/// This is the one place the person can see it happening, and the one place
/// they can stop after the file in hand.
class ImportProgress {
  ImportProgress._(this.total)
    : done = ValueNotifier<int>(0),
      current = ValueNotifier<String?>(null);

  final int total;
  final ValueNotifier<int> done;
  final ValueNotifier<String?> current;
  final Completer<void> _ready = Completer<void>();
  VoidCallback? _close;
  bool _closePending = false;

  bool canceled = false;

  /// Completes once the sheet is on screen. The import can be short; closing
  /// a route that has not been pushed yet would pop the room instead.
  Future<void> get ready => _ready.future;

  void _attach(VoidCallback close) {
    _close = close;
    if (!_ready.isCompleted) {
      _ready.complete();
    }
    if (_closePending) {
      _closePending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
    }
  }

  void cancel() => canceled = true;

  void close() {
    final VoidCallback? close = _close;
    if (close == null) {
      _closePending = true;
    } else {
      close();
    }
  }
}

ImportProgress showImportProgressSheet(
  BuildContext context, {
  required int total,
}) {
  final ImportProgress progress = ImportProgress._(total);
  unawaited(
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor:
          KalloScope.maybeOf(context)?.colors.scrim ?? const Color(0x99000000),
      transitionDuration: KalloMotion.settle,
      pageBuilder:
          (
            BuildContext dialogContext,
            Animation<double> animation,
            Animation<double> secondary,
          ) {
            final NavigatorState navigator = Navigator.of(dialogContext);
            progress._attach(navigator.pop);
            return _ImportProgressSheet(progress: progress);
          },
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondary,
            Widget child,
          ) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: KalloMotion.enter,
            ),
            child: child,
          ),
    ),
  );
  return progress;
}

class _ImportProgressSheet extends StatelessWidget {
  const _ImportProgressSheet({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final KalloColors colors = KalloScope.colorsOf(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(KalloSpace.step5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: KalloShadowBox(
              kind: KalloShadowKind.sheet,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(KalloRadius.sheet),
                  border: Border.all(color: colors.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(KalloSpace.step5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.importingImages,
                        style: KalloType.title.copyWith(
                          fontSize: 18,
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: KalloSpace.step2),
                      ValueListenableBuilder<int>(
                        valueListenable: progress.done,
                        builder: (BuildContext context, int done, Widget? _) {
                          return Text(
                            s.importProgress(done, progress.total),
                            style: KalloType.body.copyWith(
                              color: colors.inkMuted,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: KalloSpace.step3),
                      ValueListenableBuilder<String?>(
                        valueListenable: progress.current,
                        builder:
                            (BuildContext context, String? name, Widget? _) {
                              return Text(
                                name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KalloType.data.copyWith(
                                  color: colors.inkFaint,
                                ),
                              );
                            },
                      ),
                      const SizedBox(height: KalloSpace.step4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: KalloButton(
                          label: progress.canceled ? s.cancelling : s.cancel,
                          onTap: progress.canceled ? null : progress.cancel,
                        ),
                      ),
                    ],
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
