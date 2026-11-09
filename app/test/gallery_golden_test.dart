import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/design/tokens.dart';
import 'package:kallo_ui/main.dart';

/// The faces the tokens ask for, in the order each platform is likeliest to
/// have them.
const Map<String, List<String>> _faces = <String, List<String>>{
  'Kallo Sans': <String>[
    r'C:\Windows\Fonts\segoeui.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
  ],
  'DengXian': <String>[
    r'C:\Windows\Fonts\Deng.ttf',
    '/System/Library/Fonts/Supplemental/Songti.ttc',
  ],
  // The mono role asks for Menlo; Consolas stands in for it on Windows.
  'Menlo': <String>[
    r'C:\Windows\Fonts\consola.ttf',
    '/System/Library/Fonts/Menlo.ttc',
  ],
};

/// The test renderer has no fonts: every glyph would be a box, and a design
/// that is judged on its type cannot be judged as boxes. So the machine's own
/// faces are loaded under the names the tokens ask for.
Future<bool> _loadFont(String family, String path) async {
  final File file = File(path);
  if (!file.existsSync()) {
    return false;
  }
  final Uint8List bytes = await file.readAsBytes();
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
  return true;
}

Future<void> _loadPlatformFaces() async {
  for (final MapEntry<String, List<String>> face in _faces.entries) {
    for (final String path in face.value) {
      if (await _loadFont(face.key, path)) {
        break;
      }
    }
  }
  KalloType.sans = 'Kallo Sans';
}

/// The committed baselines were drawn on Windows, with that machine's own
/// Segoe UI and DengXian. A golden is a photograph of one machine; until the
/// app pins a face of its own, comparing anywhere else compares two different
/// designs and calls the difference a failure.
bool get _goldensApply =>
    Platform.isWindows &&
    _faces.values.any(
      (List<String> paths) => paths.any((String path) => File(path).existsSync()),
    );

Future<void> _pumpGallery(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1180);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const KalloApp());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadPlatformFaces);

  testWidgets(
    'the light table',
    (WidgetTester tester) async {
      await _pumpGallery(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/light_table.png'),
      );
    },
    skip: !_goldensApply,
  );

  testWidgets(
    'the darkroom',
    (WidgetTester tester) async {
      await _pumpGallery(tester);

      await tester.tap(find.text('DARKROOM'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/darkroom.png'),
      );
    },
    skip: !_goldensApply,
  );
}
