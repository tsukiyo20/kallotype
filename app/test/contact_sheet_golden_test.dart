import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Brightness, Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/design/chrome.dart';
import 'package:kallo_ui/film/strip_data.dart';
import 'package:kallo_ui/lab/fixture.dart';
import 'package:kallo_ui/lab/roll.dart';
import 'package:kallo_ui/main.dart';

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

void main() {
  setUpAll(_loadFonts);

  testWidgets('the contact sheet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final StripData strip = StripData.fromJson(
      jsonDecode(File('assets/film_strip.json').readAsStringSync())
          as Map<String, dynamic>,
    );

    await tester.pumpWidget(KalloApp(
      roll: interpolatedRoll(strip),
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
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final StripData strip = StripData.fromJson(
      jsonDecode(File('assets/film_strip.json').readAsStringSync())
          as Map<String, dynamic>,
    );

    await tester.pumpWidget(KalloApp(
      roll: interpolatedRoll(strip),
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
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final StripData strip = StripData.fromJson(
      jsonDecode(File('assets/film_strip.json').readAsStringSync())
          as Map<String, dynamic>,
    );

    await tester.pumpWidget(KalloApp(
      roll: Roll.fromStrip(strip),
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
}
