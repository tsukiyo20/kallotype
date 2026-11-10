import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/roll.dart';
import '../sheets/contact_sheet.dart';
import '../widgets/edge_bar.dart';
import 'drawer.dart';

/// The room.
///
/// One place, with a drawer in the bench. The drawer is not a destination: it
/// slides over the table and the table is still there behind it.
class Room extends StatefulWidget {
  const Room({
    super.key,
    required this.roll,
    required this.locale,
    required this.onLocale,
    required this.technicalTerms,
    required this.onTechnicalTerms,
    this.initiallyOpen = false,
  });

  final Roll roll;
  final Locale? locale;
  final ValueChanged<Locale?> onLocale;
  final bool technicalTerms;
  final ValueChanged<bool> onTechnicalTerms;

  /// Opened on the first frame. The golden test uses it; the app does not.
  final bool initiallyOpen;

  @override
  State<Room> createState() => _RoomState();
}

class _RoomState extends State<Room> {
  late bool _open = widget.initiallyOpen;

  void _openDrawer() => setState(() => _open = true);

  void _closeDrawer() => setState(() => _open = false);

  void _go(Place place) {
    if (place == Place.drawer) {
      _openDrawer();
    } else if (place == Place.table) {
      _closeDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _closeDrawer,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double height =
                math.min(600, constraints.maxHeight * 0.9);
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: SheetScreen(roll: widget.roll, onPlace: _go),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_open,
                    child: GestureDetector(
                      onTap: _closeDrawer,
                      child: AnimatedOpacity(
                        duration: KalloMotion.settle,
                        curve: KalloMotion.enter,
                        opacity: _open ? 1 : 0,
                        child: ColoredBox(
                          color: colors.ink.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSlide(
                    duration: KalloMotion.settle,
                    curve: KalloMotion.enter,
                    offset: Offset(0, _open ? 0 : 1),
                    child: SizedBox(
                      height: height,
                      child: SettingsDrawer(
                        locale: widget.locale,
                        onLocale: widget.onLocale,
                        technicalTerms: widget.technicalTerms,
                        onTechnicalTerms: widget.onTechnicalTerms,
                        onClose: _closeDrawer,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
