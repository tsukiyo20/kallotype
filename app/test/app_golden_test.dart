import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/design/chrome.dart';
import 'package:kallo_ui/film/strip_data.dart';
import 'package:kallo_ui/lab/exports.dart';
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

/// A picture for the goldens, drawn here and never committed.
///
/// The app ships no photographs: a print is a file the model exports, and the
/// gallery reads the export folder. But a golden of the gallery has to have
/// something on the wall to be about, so the test paints a test card — three
/// blocks on a ramp, which no one could mistake for a photograph.
Future<List<Print>> _fixturePrints() async {
  const double width = 900;
  const double height = 600;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Rect full = Rect.fromLTWH(0, 0, width, height);
  canvas.drawRect(
    full,
    Paint()
      ..shader = ui.Gradient.linear(
        full.topCenter,
        full.bottomCenter,
        <Color>[const Color(0xFFF2EDE4), const Color(0xFF2A2622)],
      ),
  );
  canvas.drawRect(
    const Rect.fromLTWH(80, 120, 220, 340),
    Paint()..color = const Color(0xFF8C6A4A),
  );
  canvas.drawRect(
    const Rect.fromLTWH(340, 180, 180, 260),
    Paint()..color = const Color(0xFF4E6B63),
  );
  canvas.drawRect(
    const Rect.fromLTWH(560, 90, 260, 400),
    Paint()..color = const Color(0xFF1E1B18),
  );
  final ui.Image image = await recorder.endRecording().toImage(
        width.toInt(),
        height.toInt(),
      );
  // Three developments of one negative is the wall this product exists to show,
  // so the fixture is three of them rather than one large one.
  return <Print>[
    for (final double minutes in <double>[3, 6, 9])
      Print(
        image: image,
        name: 'test-card',
        frame: 3,
        film: 'VISION3 500T',
        paper: 'CRYSTAL ARCHIVE PEARL',
        minutes: minutes,
        tempC: 20,
        // A fixed hour, so that a golden is a picture of the app rather than a
        // picture of when it was run.
        printed: DateTime(2026, 10, 2, 21, 40),
      ),
  ];
}

/// Where prints come from, pinned rather than read: a golden that showed
/// whoever ran it's home folder would be a golden of a person, not of the app.
const ExportSetting _exports = ExportSetting(
  label: '~/Pictures/Kallotype',
  canChoose: true,
  custom: false,
);

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

/// A roll the way a developed one looks: five frames, one picture each, and no
/// chart — the same shape the shelf produces, with the test card standing in
/// for the photograph.
Roll _developed(ui.Image image) => Roll(
      number: 1,
      stockId: 'vision3_500t',
      stockLabel: 'KODAK VISION3 500T 5219/7219, ECN-2',
      photo: '/photographs/uji.jpg',
      frames: <Frame>[
        for (int i = 0; i < 5; i++)
          Frame(
            number: i + 1,
            minutes: 3.0 * (i + 1),
            tempC: 20,
            image: image,
          ),
      ],
    );

void main() {
  // The print is decoded before any widget exists: `instantiateImageCodec` is a
  // real engine call, and a widget test runs in a zone that would never
  // complete it.
  late List<Print> hanging;
  late Roll developed;

  setUpAll(() async {
    await _loadFonts();
    hanging = await _fixturePrints();
    developed = _developed(hanging.first.image);
  });

  testWidgets('the contact sheet', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      prints: const <Print>[],
      export: _exports,
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
      prints: const <Print>[],
      export: _exports,
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
      prints: const <Print>[],
      export: _exports,
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
      prints: hanging,
      export: _exports,
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
      prints: hanging,
      export: _exports,
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

  testWidgets('the gallery with nothing printed', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      prints: const <Print>[],
      export: _exports,
      roll: Roll.fromStrip(_strip()),
      appearance: Brightness.light,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    // A wall with nothing on it and a switch: no print, and no label claiming
    // one. This is the state the app is in before anything has been exported.
    expect(find.byType(RawImage), findsNothing);
    expect(find.text('Light'), findsOneWidget);
  });

  testWidgets('the drawer, on prints', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      prints: const <Print>[],
      export: _exports,
      roll: Roll.fromStrip(_strip()),
      locale: const Locale('zh'),
      appearance: Brightness.light,
      drawerOpen: true,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('印相'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/drawer-prints.png'),
    );
  });

  testWidgets('one print hangs on its own', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      prints: <Print>[hanging.last],
      export: _exports,
      roll: Roll.fromStrip(_strip()),
      appearance: Brightness.dark,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    // One print is a print, not a sheet of stamps and not a billboard: 660
    // points of paper, centred, with the paper's own margin inside it.
    final Size image = tester.getSize(find.byType(RawImage));
    expect(image.width, closeTo(660 * (1 - 0.06), 1));
    expect(image.height, closeTo(image.width / 1.5, 1));
  });

  testWidgets('the shelf', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      prints: const <Print>[],
      export: _exports,
      roll: Roll.fromStrip(_strip()),
      appearance: Brightness.light,
      initialPlace: Place.shelf,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/shelf.png'),
    );
  });

  testWidgets('the workbench', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      prints: const <Print>[],
      export: _exports,
      roll: developed,
      appearance: Brightness.light,
      initialPlace: Place.workbench,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/workbench.png'),
    );
  });

  testWidgets('the line', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      prints: hanging,
      export: _exports,
      roll: developed,
      appearance: Brightness.light,
      initialPlace: Place.line,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/line.png'),
    );
  });
}
