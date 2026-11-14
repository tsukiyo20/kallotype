import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import 'button.dart';
import 'shadow_box.dart';

/// What to do with the prints already in a library when its folder changes.
enum FolderMoveChoice { move, useNew, cancel }

/// Ask before a folder change moves files.
///
/// The default is the safe answer: move only the marked prints, leave every
/// other picture where it is. "Use new folder only" is the escape hatch for a
/// person who wants the old library to stay on an external drive.
Future<FolderMoveChoice?> showFolderMoveSheet(
  BuildContext context, {
  required int count,
  required String destination,
}) {
  return showGeneralDialog<FolderMoveChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cancel',
    barrierColor:
        KalloScope.maybeOf(context)?.colors.scrim ?? const Color(0x99000000),
    transitionDuration: KalloMotion.settle,
    pageBuilder: (
      BuildContext dialogContext,
      Animation<double> animation,
      Animation<double> secondary,
    ) => _FolderMoveSheet(count: count, destination: destination),
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

class _FolderMoveSheet extends StatelessWidget {
  const _FolderMoveSheet({required this.count, required this.destination});

  final int count;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final KalloStrings s = KalloStrings.of(context);
    final KalloColors colors = KalloScope.colorsOf(context);
    void close(FolderMoveChoice choice) => Navigator.of(context).pop(choice);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            close(FolderMoveChoice.cancel),
      },
      child: Focus(
        autofocus: true,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(KalloSpace.step5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
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
                            s.movePrintsTitle,
                            style: KalloType.title.copyWith(
                              fontSize: 18,
                              color: colors.ink,
                            ),
                          ),
                          const SizedBox(height: KalloSpace.step2),
                          Text(
                            s.movePrintsNote(count, destination),
                            style: KalloType.body.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                          const SizedBox(height: KalloSpace.step5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              GestureDetector(
                                onTap: () => close(FolderMoveChoice.useNew),
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: KalloSpace.step3,
                                    vertical: KalloSpace.step2,
                                  ),
                                  child: Text(
                                    s.useNewFolderAction,
                                    style: KalloType.small.copyWith(
                                      color: colors.inkMuted,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: KalloSpace.step2),
                              KalloButton(
                                label: s.movePrintsAction,
                                filled: true,
                                onTap: () => close(FolderMoveChoice.move),
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
      ),
    );
  }
}
