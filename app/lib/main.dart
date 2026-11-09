import 'package:flutter/widgets.dart';

import 'design/tokens.dart';
import 'film/strip_data.dart';
import 'screens/gallery.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The strip is a rendering of the model, committed as an asset by `just
  // view`. Loading it here keeps the painter synchronous and keeps the app
  // buildable without a Rust toolchain.
  final StripData strip = await StripData.load();
  runApp(KalloApp(strip: strip));
}

/// The whole point of this file: there is no `MaterialApp`.
///
/// `WidgetsApp` gives text direction, focus, overlay, semantics and routing,
/// and gives nothing else. No ripple, no elevation, no Roboto, no type scale,
/// no colour roles. Everything you see on the other side of this is ours.
class KalloApp extends StatelessWidget {
  const KalloApp({super.key, required this.strip});

  /// What the model drew.
  final StripData strip;

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
      home: GalleryScreen(strip: strip),
    );
  }
}
