import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/design/chrome.dart';
import 'package:kallo_ui/film/strip_data.dart';
import 'package:kallo_ui/lab/fixture.dart';
import 'package:kallo_ui/lab/print.dart';
import 'package:kallo_ui/lab/roll.dart';
import 'package:kallo_ui/main.dart';
import 'package:kallo_ui/views/places.dart';

/// Load the bundled faces, so the golden is drawn in the product's type rather
/// than in whatever the test runner has. The faces are read from disk: a test
/// runs beside the package, and this is the one place where that is the honest
/// source.
Future<void> _loadFonts() async {
  const Map<String, List<String>> faces = <String, List<String>>{
    'Inter': <String>[
      'fonts/inter-400.ttf',
      'fonts/inter-500.ttf',
      'fonts/inter-600.ttf',
    ],
    'NotoSansSC': <String>[
      'fonts/noto-sans-sc-Regular.otf',
      'fonts/noto-sans-sc-Medium.otf',
    ],
  };
  for (final MapEntry<String, List<String>> face in faces.entries) {
    final FontLoader loader = FontLoader(face.key);
    for (final String path in face.value) {
      final Uint8List bytes = File(path).readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// The print the model made, read from the two files `just print` writes.
///
/// From disk rather than through `rootBundle`, for the same reason the fonts
/// are: a test runs beside the package, and this is the honest source.
Future<Print> _hangingPrint() async {
  final ui.Codec codec = await ui.instantiateImageCodec(
    File('assets/print.png').readAsBytesSync(),
  );
  final ui.FrameInfo frame = await codec.getNextFrame();
  return Print.of(
    jsonDecode(File('assets/print.json').readAsStringSync())
        as Map<String, dynamic>,
    frame.image,
  );
}

/// The roll the model drew, five developments of one wedge.
StripData _strip() => StripData.fromJson(
      jsonDecode(File('assets/film_strip.json').readAsStringSync())
          as Map<String, dynamic>,
    );

void _window(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  // The print is decoded before any widget exists: `instantiateImageCodec` is a
  // real engine call, and a widget test runs in a zone that would never
  // complete it.
  late Print hanging;

  setUpAll(() async {
    await _loadFonts();
    hanging = await _hangingPrint();
  });

  testWidgets('the contact sheet', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      roll: interpolatedRoll(_strip()),
      appearance: Brightness.light,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/sheet.png'),
    );
  });

  testWidgets('the table, in Chinese', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      roll: interpolatedRoll(_strip()),
      locale: const Locale('zh'),
      appearance: Brightness.light,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/sheet-zh.png'),
    );
  });

  testWidgets('the drawer, in Chinese', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      roll: Roll.fromStrip(_strip()),
      locale: const Locale('zh'),
      appearance: Brightness.dark,
      drawerOpen: true,
      technicalTerms: true,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/drawer.png'),
    );
  });

  testWidgets('the gallery, lit', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      roll: Roll.fromStrip(_strip()),
      print: hanging,
      appearance: Brightness.dark,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/gallery.png'),
    );
  });

  testWidgets('the gallery, with the lamp off', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      roll: Roll.fromStrip(_strip()),
      print: hanging,
      appearance: Brightness.light,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('light')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/gallery-unlit.png'),
    );
  });
}
