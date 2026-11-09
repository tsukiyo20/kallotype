import 'package:flutter/widgets.dart';

import 'design/tokens.dart';
import 'screens/gallery.dart';

void main() => runApp(const KalloApp());

/// The whole point of this file: there is no `MaterialApp`.
///
/// `WidgetsApp` gives text direction, focus, overlay, semantics and routing,
/// and gives nothing else. No ripple, no elevation, no Roboto, no type scale,
/// no colour roles. Everything you see on the other side of this is ours.
class KalloApp extends StatelessWidget {
  const KalloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: KalloColors.darkroom.ground,
      title: 'Kallotype',
      textStyle: KalloType.body,
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) =>
              builder(context),
        );
      },
      home: const GalleryScreen(),
    );
  }
}
