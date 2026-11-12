import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/design/chrome.dart';
import 'package:kallo_ui/film/strip_data.dart';
import 'package:kallo_ui/lab/contact.dart';
import 'package:kallo_ui/lab/fixture.dart';
import 'package:kallo_ui/lab/print.dart';
import 'package:kallo_ui/lab/print_out.dart';
import 'package:kallo_ui/lab/roll.dart';
import 'package:kallo_ui/lab/stock.dart';
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

/// The test card: three blocks on a ramp, which no one could mistake for a
/// photograph.
///
/// The app ships no pictures, and a golden of the gallery has to have something
/// on the wall to be about. The size is the caller's because the lens is a
/// golden too, and a loupe on a 900-pixel card is a loupe on a blurred card.
Future<ui.Image> _testCard({int width = 900, int height = 600}) async {
  final double scale = width / 900;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Rect full = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(
    full,
    Paint()
      ..shader = ui.Gradient.linear(
        full.topCenter,
        full.bottomCenter,
        <Color>[const Color(0xFFF2EDE4), const Color(0xFF2A2622)],
      ),
  );
  void block(double left, double top, double w, double h, Color colour) {
    canvas.drawRect(
      Rect.fromLTWH(left * scale, top * scale, w * scale, h * scale),
      Paint()..color = colour,
    );
  }

  block(80, 120, 220, 340, const Color(0xFF8C6A4A));
  block(340, 180, 180, 260, const Color(0xFF4E6B63));
  block(560, 90, 260, 400, const Color(0xFF1E1B18));
  return recorder.endRecording().toImage(width, height);
}

/// A picture for the goldens, drawn here and never committed.
Future<List<Print>> _fixturePrints() async {
  final ui.Image image = await _testCard();
  // Three developments of one negative is the wall this product exists to show,
  // so the fixture is three of them rather than one large one.
  return <Print>[
    for (final double minutes in <double>[3, 6, 9])
      Print(
        image: image,
        name: 'test-card',
        // A print is 6000 wide; the test card stands in for the picture, and
        // the record's dimensions are what the loupe's readout says.
        pixels: const Size(6000, 4000),
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

/// The catalogue the goldens draw, pinned rather than asked for.
///
/// Eight films, because a shelf is about the fact that there are many: four
/// colour negatives, two reversals and two silver films, so that the shelf's
/// three groups are all on the page. The provenance is the model's, copied from
/// `kalo stocks --json`; the list is the test's, so that a golden does not show
/// the model binary on whatever machine ran it.
const Catalogue _catalogue = Catalogue(
  films: <Stock>[
    Stock(
      id: 'kodak_ektar_100',
      short: 'EKTAR 100',
      label: 'KODAK PROFESSIONAL EKTAR 100',
      process: FilmProcess.negative,
      referenceMinutes: 6.5,
      referenceTempC: 20,
      provenance: Provenance(
        publication: 'E-4046',
        page: '4',
        retrieved: '2026-11-08',
      ),
      measured: <Measured>[
        Measured(field: 'curves', claim: 'measured', detail: ''),
        Measured(field: 'layers', claim: 'measured', detail: ''),
        Measured(
          field: 'dyes',
          claim: 'borrowed',
          detail: 'the VISION3 500T digitisation',
        ),
        Measured(field: 'mask', claim: 'measured', detail: ''),
        Measured(field: 'mtf', claim: 'measured', detail: ''),
        Measured(field: 'grain', claim: 'placeholder', detail: ''),
      ],
    ),
    Stock(
      id: 'kodak_gold200',
      short: 'GOLD 200',
      label: 'KODAK GOLD 200',
      process: FilmProcess.negative,
    ),
    Stock(
      id: 'kodak_portra_400',
      short: 'PORTRA 400',
      label: 'KODAK PROFESSIONAL PORTRA 400',
      process: FilmProcess.negative,
    ),
    Stock(
      id: 'vision3_500t',
      short: 'VISION3 500T',
      label: 'KODAK VISION3 500T 5219/7219, ECN-2',
      process: FilmProcess.negative,
      referenceMinutes: 6.5,
      referenceTempC: 20,
      provenance: Provenance(
        publication: 'H-1-5219',
        page: '3',
        retrieved: '2026-11-08',
      ),
      measured: <Measured>[
        Measured(field: 'curves', claim: 'measured', detail: ''),
        Measured(field: 'layers', claim: 'measured', detail: ''),
        Measured(field: 'dyes', claim: 'borrowed', detail: ''),
        Measured(field: 'mask', claim: 'measured', detail: ''),
        Measured(field: 'mtf', claim: 'borrowed', detail: ''),
        Measured(field: 'grain', claim: 'placeholder', detail: ''),
      ],
    ),
    Stock(
      id: 'provia_100f',
      short: 'PROVIA 100F',
      label: 'FUJICHROME PROVIA 100F (RDP III), E-6',
      process: FilmProcess.reversal,
    ),
    Stock(
      id: 'velvia_50',
      short: 'VELVIA 50',
      label: 'FUJICHROME VELVIA 50 (RVP), E-6',
      process: FilmProcess.reversal,
    ),
    Stock(
      id: 'ilford_delta400',
      short: 'DELTA 400',
      label: 'ILFORD DELTA 400 PROFESSIONAL, ID-11 8 min 24 °C',
      process: FilmProcess.monochrome,
    ),
    Stock(
      id: 'kodak_trix400',
      short: 'TRI-X 400',
      label: 'KODAK TRI-X 400 PROFESSIONAL (400TX), D-76 6 min 20 °C',
      process: FilmProcess.monochrome,
    ),
  ],
  papers: <Stock>[
    Stock(
      id: 'fuji_crystal_archive_pearl',
      short: 'CRYSTAL ARCHIVE PEARL',
      label: 'FUJICOLOR CRYSTAL ARCHIVE DIGITAL PEARL PAPER, RA-4',
      emulsion: PaperEmulsion.colour,
      provenance: Provenance(
        publication: 'AF3-0220E',
        page: '4',
        retrieved: '2026-11-09',
      ),
      measured: <Measured>[
        Measured(
          field: 'curve',
          claim: 'measured',
          detail: 'chart 15, three layers averaged, rms 0.019',
        ),
        Measured(field: 'layers', claim: 'measured', detail: ''),
        Measured(field: 'dyes', claim: 'measured', detail: ''),
        Measured(
          field: 'white',
          claim: '',
          detail: 'not stated on the sheet; the toe of the curves is the paper\'s '
              'own density',
        ),
      ],
    ),
    Stock(
      id: 'endura_premier',
      short: 'ENDURA PREMIER',
      label: 'KODAK PROFESSIONAL ENDURA Premier Paper, RA-4',
      emulsion: PaperEmulsion.colour,
    ),
    Stock(
      id: 'portra_endura',
      short: 'PORTRA ENDURA',
      label: 'KODAK PROFESSIONAL PORTRA ENDURA, RA-4',
      emulsion: PaperEmulsion.colour,
    ),
    Stock(
      id: 'polymax_ii_rc',
      short: 'POLYMAX II RC',
      label: 'KODAK PROFESSIONAL POLYMAX II RC Paper, F surface',
      emulsion: PaperEmulsion.silver,
    ),
  ],
);

/// Where prints come from, pinned rather than read: a golden that showed
/// whoever ran it's home folder would be a golden of a person, not of the app.
final Directory _prints = Directory('/prints');
final Directory _roll = Directory('/roll');

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

/// The proof, drawn rather than printed.
///
/// The real sheet is the model's; a widget test has no model to ask, so this
/// draws the shape a proof has — five strips on paper, black rebate, one sheet
/// — with the test card where the photograph would be. It is a layout fixture,
/// like the card itself: it is not model output and does not stand in for it.
Future<ContactProof> _proof(ui.Image card) async {
  // Drawn at twice the sheet's display size, so that the loupe has more than
  // the table's copy to magnify.
  const double logicalWidth = 1320;
  const double logicalHeight = 810;
  const double scale = 2;
  const double margin = 60;
  const double stripWidth = 380;
  const double stripHeight = 330;
  const double gap = 30;
  const double inset = 14;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.scale(scale);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, logicalWidth, logicalHeight),
    Paint()..color = const Color(0xFFF7F4EC),
  );
  final List<ContactFrame> frames = <ContactFrame>[];
  for (int i = 0; i < 5; i++) {
    final double left = margin + (i % 3) * (stripWidth + gap);
    final double top = margin + (i ~/ 3) * (stripHeight + gap);
    canvas.drawRect(
      Rect.fromLTWH(left, top, stripWidth, stripHeight),
      Paint()..color = const Color(0xFF0A0A0A),
    );
    final Rect frame = Rect.fromLTWH(
      left + inset,
      top + 48,
      stripWidth - inset * 2,
      (stripWidth - inset * 2) / 1.5,
    );
    frames.add(
      ContactFrame(
        number: i + 1,
        minutes: 3.0 * (i + 1),
        rect: Rect.fromLTWH(
          frame.left * scale,
          frame.top * scale,
          frame.width * scale,
          frame.height * scale,
        ),
      ),
    );
    // The ladder, drawn as a ladder: one exposure under five developments
    // prints darker at the short end, and a proof whose strips all printed
    // alike would be a picture of something else.
    final double printed = 0.12 + 0.22 * i;
    canvas.drawImageRect(
      card,
      Rect.fromLTWH(0, 0, card.width.toDouble(), card.height.toDouble()),
      frame,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.matrix(<double>[
          printed, 0, 0, 0, 0,
          0, printed, 0, 0, 0,
          0, 0, printed, 0, 0,
          0, 0, 0, 1, 0,
        ]),
    );
  }
  final ui.Image sheet = await recorder.endRecording().toImage(
        (logicalWidth * scale).toInt(),
        (logicalHeight * scale).toInt(),
      );
  return ContactProof(
    image: sheet,
    pixels: const Size(logicalWidth * scale, logicalHeight * scale),
    frames: frames,
    paperMargin: margin * scale,
  );
}

/// A roll the way a developed one looks: five frames, one picture each, and no
/// chart — the same shape the shelf produces, with the test card standing in
/// for the photograph.
Roll _developed(ui.Image image, {ContactProof? contact}) => Roll(
      stockId: 'vision3_500t',
      stockLabel: 'KODAK VISION3 500T 5219/7219, ECN-2',
      photo: '/photographs/uji.jpg',
      // What the shelf develops a negative onto, so that the record on every
      // page is the roll's own and not the app's fallback.
      paperId: 'fuji_crystal_archive_pearl',
      contact: contact,
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
    developed = _developed(
      hanging.first.image,
      contact: await _proof(hanging.first.image),
    );
  });

  testWidgets('the contact sheet', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
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

  testWidgets('the table, a roll from the shelf', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: developed,
      appearance: Brightness.light,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    // One sheet of paper and not a grid of cards: the contact proof says what
    // paper it is, which is the thing a preview of the prints cannot say.
    expect(find.text('CRYSTAL ARCHIVE PEARL'), findsOneWidget);

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/table-roll.png'),
    );
  });

  testWidgets('the table, under the loupe', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: developed,
      appearance: Brightness.light,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    final ContactProof proof = developed.contact!;
    final Rect sheet = tester.getRect(find.byKey(const Key('proof')));
    final double scale = sheet.width / proof.pixels.width;
    // The first strip, off its centre: at arm's length a five-stop-darker print
    // is a black rectangle; through the glass it is a picture — and the same
    // one, because the loupe magnifies the paper and not the enlarger's print.
    final ContactFrame first = proof.frames.first;
    final Offset at = sheet.topLeft +
        Offset(
              first.rect.left + first.rect.width * 0.62,
              first.rect.top + first.rect.height * 0.5,
            ) *
            scale;

    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(at);
    await tester.pump();

    expect(find.byKey(const Key('lens')), findsOneWidget);
    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/table-lens.png'),
    );

    // Off the sheet, off the glass.
    await mouse.moveTo(const Offset(4, 4));
    await tester.pump();
    expect(find.byKey(const Key('lens')), findsNothing);
  });

  testWidgets('the table, in Chinese', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
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
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: Roll.fromStrip(_strip()),
      locale: const Locale('zh'),
      appearance: Brightness.dark,
      drawerOpen: true,
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
      catalogue: _catalogue,
      roll: Roll.fromStrip(_strip()),
      prints: hanging,
      exportsFolder: _prints,
      rollFolder: _roll,
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

  testWidgets('the gallery, lit, in a light room', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      roll: Roll.fromStrip(_strip()),
      prints: hanging,
      exportsFolder: _prints,
      rollFolder: _roll,
      appearance: Brightness.light,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/gallery-light.png'),
    );
  });

  testWidgets('the gallery, with the lamp off', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      roll: Roll.fromStrip(_strip()),
      prints: hanging,
      exportsFolder: _prints,
      rollFolder: _roll,
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

  testWidgets('the lens is a loupe on the wall', (WidgetTester tester) async {
    _window(tester);

    // The lens decodes the print's own file, so the print has one. Three
    // thousand wide is what three times the wall needs to be sharp here. The
    // engine's own work happens outside the test's clock, or it never happens.
    final Print print = (await tester.runAsync(() async {
      final ui.Image card = await _testCard(width: 3000, height: 2000);
      final ByteData png =
          (await card.toByteData(format: ui.ImageByteFormat.png))!;
      final Directory folder =
          Directory.systemTemp.createTempSync('kallo-lens');
      addTearDown(() => folder.deleteSync(recursive: true));
      final File file = File('${folder.path}/test-card.png');
      file.writeAsBytesSync(png.buffer.asUint8List());
      return Print(
        image: card,
        name: 'test-card',
        path: file.path,
        pixels: const Size(3000, 2000),
        frame: 3,
        film: 'VISION3 500T',
        paper: 'CRYSTAL ARCHIVE PEARL',
        minutes: 9,
        tempC: 20,
        printed: DateTime(2026, 10, 2, 21, 40),
      );
    }))!;

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      roll: Roll.fromStrip(_strip()),
      prints: <Print>[print],
      exportsFolder: _prints,
      rollFolder: _roll,
      appearance: Brightness.light,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lens')), findsNothing);
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    // Off the middle of the card, so that the lens has an edge in it: a loupe
    // over a flat patch is a circle of one colour and proves nothing.
    await mouse.moveTo(
      tester.getCenter(find.byType(RawImage).first) + const Offset(46, 0),
    );
    await tester.pump();
    // Let the decode land: the lens is a loupe on the file, not on the wall's
    // copy, and the file is read for real.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.byKey(const Key('lens')), findsOneWidget);
    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/gallery-lens.png'),
    );

    // Off the print, off the glass: the lens is held over a sheet, not a mode.
    await mouse.moveTo(const Offset(4, 4));
    await tester.pump();
    expect(find.byKey(const Key('lens')), findsNothing);
  });

  testWidgets('the gallery with nothing printed', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
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

  testWidgets('the print, looked at closely', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      roll: Roll.fromStrip(_strip()),
      prints: hanging,
      exportsFolder: _prints,
      rollFolder: _roll,
      appearance: Brightness.dark,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    // Walking up to a print: the wall goes away and the sheet stays, with the
    // file's own size under it and the scale the eye is at.
    await tester.tap(find.byType(RawImage).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('6000 × 4000'), findsOneWidget);
    expect(find.byKey(const Key('back')), findsOneWidget);

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/gallery-loupe.png'),
    );

    // And back out to the wall, where the prints are.
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    expect(find.textContaining('6000 × 4000'), findsNothing);
  });

  testWidgets('the loupe goes to 1:1, and escape goes back', (
    WidgetTester tester,
  ) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      roll: Roll.fromStrip(_strip()),
      prints: hanging,
      exportsFolder: _prints,
      rollFolder: _roll,
      appearance: Brightness.light,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RawImage).first);
    await tester.pumpAndSettle();

    // The print is on the paper at the scale the room is at, which is a
    // fraction of the file: the readout says how much.
    expect(find.textContaining('6000 × 4000 pixels'), findsOneWidget);
    expect(find.textContaining('1:1'), findsNothing);

    // Twice on the paper: the file's own pixels, one image pixel to one device
    // pixel, and the loupe stops there.
    await tester.tap(find.byType(RawImage).first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(RawImage).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('1:1'), findsOneWidget);

    // Escape puts the print back on the wall.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('6000 × 4000 pixels'), findsNothing);
    expect(find.byKey(const Key('light')), findsOneWidget);
  });

  testWidgets('the wheel magnifies the print', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      roll: Roll.fromStrip(_strip()),
      prints: hanging,
      exportsFolder: _prints,
      rollFolder: _roll,
      appearance: Brightness.dark,
      initialPlace: Place.gallery,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RawImage).first);
    await tester.pumpAndSettle();

    double readout() {
      final Text text = tester.widget<Text>(find.textContaining('pixels'));
      final Match match =
          RegExp(r'([0-9.]+)\s*%').firstMatch(text.data!)!;
      return double.parse(match.group(1)!);
    }

    final double before = readout();
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    final Offset at = tester.getCenter(find.byType(RawImage).first);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -240)));
    await tester.pumpAndSettle();

    expect(readout(), greaterThan(before));
  });

  testWidgets('the drawer, on prints', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
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

  testWidgets('the drawer, on colour', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: Roll.fromStrip(_strip()),
      locale: const Locale('zh'),
      appearance: Brightness.light,
      drawerOpen: true,
      // The one thing on this card that changes the picture.
      spectral: true,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('色彩'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/drawer-colour.png'),
    );
  });

  testWidgets('one print hangs on its own', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: <Print>[hanging.last],
      exportsFolder: _prints,
      rollFolder: _roll,
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
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
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

  testWidgets('the shelf, with a silver film taken', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: Roll.fromStrip(_strip()),
      appearance: Brightness.light,
      initialPlace: Place.shelf,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    // Taking a silver film changes what the paper shelf offers: both families,
    // and the app's sheet gives way to the paper the film is actually made for.
    await tester.tap(find.text('DELTA 400'));
    await tester.pumpAndSettle();

    expect(find.text('SILVER PAPER'), findsOneWidget);
    expect(find.text('COLOUR PAPER'), findsOneWidget);

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/shelf-silver.png'),
    );
  });

  testWidgets('a reversal has no paper to choose', (WidgetTester tester) async {
    _window(tester);

    // The roll on the table was made of PROVIA, so the shelf starts there — and
    // a reversal has no print stage, so the shelf offers no papers at all and
    // the form has no paper row.
    final Roll reversal = Roll(
      stockId: 'provia_100f',
      stockLabel: 'FUJICHROME PROVIA 100F (RDP III), E-6',
      photo: '/photographs/uji.jpg',
      frames: <Frame>[
        Frame(
          number: 1,
          minutes: 6,
          tempC: 20,
          image: hanging.first.image,
        ),
      ],
    );
    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: reversal,
      appearance: Brightness.light,
      initialPlace: Place.shelf,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    expect(find.text('COLOUR PAPER'), findsNothing);
    expect(find.text('SILVER PAPER'), findsNothing);
    expect(find.textContaining('no print'), findsOneWidget);
    // The film row is still there: the roll was made of something.
    expect(find.text('PROVIA 100F'), findsWidgets);
  });

  testWidgets('the shelf in a narrow window', (WidgetTester tester) async {
    // The minimum window is 960 wide, and the content column is that minus the
    // sidebar: not enough for a form and a shelf side by side, so the shelf goes
    // under the bench instead of beside it.
    tester.view.physicalSize = const Size(960, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: Roll.fromStrip(_strip()),
      appearance: Brightness.light,
      initialPlace: Place.shelf,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/shelf-narrow.png'),
    );
  });

  testWidgets('the workbench', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
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

  testWidgets('the workbench, proved', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: developed,
      appearance: Brightness.light,
      initialPlace: Place.workbench,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('proof')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/workbench-proof.png'),
    );
  });

  testWidgets('the proof follows the ladder', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: developed,
      appearance: Brightness.light,
      initialPlace: Place.workbench,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('proof-label')), findsNothing);
    await tester.tap(find.byKey(const Key('proof')));
    await tester.pumpAndSettle();

    String label() =>
        tester.widget<Text>(find.byKey(const Key('proof-label'))).textSpan!
            .toPlainText();
    expect(label(), contains('VISION3 500T'));
    expect(label(), contains('9:00'));
    expect(label(), contains('CRYSTAL ARCHIVE PEARL'));

    // The proof is a way of looking, not a frame's property: the ladder still
    // chooses the time, and the wall follows it.
    await tester.tap(find.text('12:00'));
    await tester.pumpAndSettle();
    expect(label(), contains('12:00'));
    expect(label(), isNot(contains('9:00')));

    // And the easel comes back with the switch, not by leaving the bench.
    await tester.tap(find.byKey(const Key('proof')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('proof-label')), findsNothing);
  });

  testWidgets('a reversal has no print', (WidgetTester tester) async {
    _window(tester);

    // A roll developed from a slide: the model has no print stage for it, so
    // the bench must not offer one. The note stands where the button would be.
    final Roll reversal = Roll(
      stockId: 'provia_100f',
      stockLabel: 'FUJICHROME PROVIA 100F (RDP III), E-6',
      photo: '/photographs/uji.jpg',
      frames: <Frame>[
        Frame(
          number: 1,
          minutes: 6,
          tempC: 20,
          image: hanging.first.image,
        ),
      ],
    );
    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: reversal,
      appearance: Brightness.light,
      initialPlace: Place.workbench,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Print'), findsNothing);
    expect(find.byKey(const Key('proof')), findsNothing);
    expect(find.textContaining('reversal is its own picture'), findsOneWidget);
  });

  testWidgets('the line', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: hanging,
      jobs: <PrintJob>[
        PrintJob(frame: developed.frames[3], exports: _prints),
      ],
      exportsFolder: _prints,
      rollFolder: _roll,
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

  testWidgets('the binder', (WidgetTester tester) async {
    _window(tester);

    await tester.pumpWidget(KalloApp(
      catalogue: _catalogue,
      prints: const <Print>[],
      exportsFolder: _prints,
      rollFolder: _roll,
      roll: developed,
      appearance: Brightness.light,
      initialPlace: Place.binder,
      chrome: WindowChrome.mac,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KalloApp),
      matchesGoldenFile('goldens/binder.png'),
    );
  });
}
