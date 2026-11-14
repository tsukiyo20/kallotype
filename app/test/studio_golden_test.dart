import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo/design/chrome.dart';
import 'package:kallo/lab/chart.dart';
import 'package:kallo/lab/model.dart';
import 'package:kallo/lab/print.dart';
import 'package:kallo/lab/stock.dart';
import 'package:kallo/lab/strip.dart';
import 'package:kallo/main.dart';
import 'package:kallo/views/chambers.dart';
import 'package:kallo/views/steps.dart';
import 'package:kallo/widgets/film_frame.dart';

/// The studio's pictures.
///
/// They are drawn with the bundled faces and belong to the renderer that made
/// them, so the baselines live under a platform folder: `goldens/macos/` was
/// drawn on this Mac, `goldens/windows/` is where a Windows pass draws its own.
/// The test is opt-in, because CI must not compare against another machine's
/// pixels. Ask for it:
///
/// ```bash
/// flutter test --dart-define=studio-goldens=true \
///   test/studio_golden_test.dart
/// ```
const bool _paint = bool.fromEnvironment('studio-goldens');
final bool _paintHere = _paint && (Platform.isMacOS || Platform.isWindows);
final String _platform = Platform.isWindows ? 'windows' : 'macos';

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

/// A model that writes the test card instead of rendering: the golden is about
/// the bench, and the model's own pixels are tested where the library is.
class _CardModel extends ProcessModel {
  _CardModel(this.bytes, this.card) : super('');

  final Uint8List bytes;
  final ui.Image card;

  @override
  bool get available => true;

  @override
  Future<void> develop({
    required File photograph,
    required String stock,
    required String paper,
    required double minutes,
    required double tempC,
    required int width,
    required File output,
    bool spectral = false,
    double? balanceFrom,
    double printEv = 0,
    String filters = '',
    String? heatGlass,
  }) async {
    output.writeAsBytesSync(bytes, flush: true);
  }

  @override
  Future<String> catalogue() async => '{"films":[],"papers":[]}';

  /// The bench's session, without a decode: the golden is about the bench, and
  /// the frame it shows is the card the test already drew.
  @override
  Future<PreviewSession?> openPreview({
    required File photograph,
    required String stock,
    required String paper,
    required double tempC,
    required int width,
    bool spectral = false,
  }) async => _CardPreviewSession(card);

  @override
  Future<FilmCurve?> filmCurve({
    required String film,
    required double minutes,
    required double tempC,
  }) async {
    const List<double> dMin = <double>[0.05, 0.05, 0.06];
    const List<double> dMax = <double>[1.65, 1.95, 2.20];
    final List<double> logE = <double>[
      for (int i = 0; i < 64; i++) -3.0 + i * 0.07,
    ];
    final double x0 = -0.35 - (minutes - 6) * 0.06;
    return FilmCurve(
      film: film,
      minutes: minutes,
      tempC: tempC,
      gamma: <double>[0.62, 0.66, 0.70],
      dMin: dMin,
      dMax: dMax,
      logE: logE,
      density: <List<double>>[
        for (final double x in logE)
          <double>[
            for (int c = 0; c < 3; c++)
              dMin[c] +
                  (dMax[c] - dMin[c]) / (1 + math.exp(-(x - x0) * 3.2)) * 0.94,
          ],
      ],
    );
  }

  @override
  Future<PrintCurve?> printCurve({
    required String film,
    required String paper,
    required double minutes,
    required double tempC,
    double printEv = 0,
    String filters = '',
    String? heatGlass,
    bool spectral = false,
  }) async {
    final List<double> logE = <double>[
      for (int i = 0; i < 48; i++) -3.5 + i * 0.077,
    ];
    final double timer = printEv * 0.30103;
    final List<double> shift = <double>[
      0.10 + timer,
      0.04 + timer,
      -0.02 + timer,
    ];
    final PrintCurve curve = PrintCurve(
      film: film,
      paper: paper,
      minutes: minutes,
      tempC: tempC,
      shift: shift,
      logE: logE,
      density: <List<double>>[
        for (final double x in logE)
          <double>[
            for (final double s in shift)
              0.06 + 2.24 / (1 + math.exp(-(x + s + 0.1) * 4.0)),
          ],
      ],
    );
    return curve;
  }

  @override
  Future<PaperCurve?> paperCurve({required String paper}) async {
    final List<double> logE = <double>[
      for (int i = 0; i < 48; i++) -3.0 + i * 0.09,
    ];
    return PaperCurve(
      id: paper,
      short: 'PORTRA ENDURA',
      emulsion: 'colour',
      dMin: 0.06,
      dMax: 2.30,
      gamma: 2.4,
      logE0: -0.1,
      targetMidReflectance: 0.18,
      logE: logE,
      density: <double>[
        for (final double x in logE)
          0.06 + 2.24 / (1 + math.exp(-(x + 0.1) * 4.0)),
      ],
    );
  }
}

class _CardPreviewSession implements PreviewSession {
  _CardPreviewSession(this._image);

  final ui.Image _image;

  @override
  Future<ui.Image> frame({
    required double minutes,
    double? balanceFrom,
    double printEv = 0,
    String filters = '',
    String? heatGlass,
  }) async => _image.clone();

  @override
  void dispose() {}
}

/// The catalogue the goldens draw, pinned rather than asked for.
const Catalogue _catalogue = Catalogue(
  films: <Stock>[
    Stocks.vision,
    Stock(
      id: 'kodak_portra_400',
      short: 'PORTRA 400',
      label: 'KODAK PROFESSIONAL PORTRA 400',
      process: FilmProcess.negative,
    ),
    Stock(
      id: 'provia_100f',
      short: 'PROVIA 100F',
      label: 'FUJICHROME PROVIA 100F (RDP III), E-6',
      process: FilmProcess.reversal,
    ),
    Stock(
      id: 'ilford_delta400',
      short: 'DELTA 400',
      label: 'ILFORD DELTA 400 PROFESSIONAL, ID-11 8 min 24 C',
      process: FilmProcess.monochrome,
    ),
  ],
  papers: <Stock>[
    Stocks.crystal,
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

List<Print> _prints(ui.Image card) => <Print>[
  for (int i = 0; i < 3; i++)
    Print(
      image: card,
      name: 'uji',
      pixels: const Size(1200, 800),
      printNumber: 1,
      process: FilmProcess.negative,
      film: 'ULTRA MAX 400',
      paper: 'PORTRA ENDURA',
      minutes: <double>[6, 9, 12][i],
      tempC: 20,
      printed: DateTime(2026, 11, 13, 21, 30),
    ),
];

List<Print> _rackPrints(ui.Image card) => <Print>[
  for (int i = 0; i < 7; i++)
    Print(
      image: card,
      name: 'uji-${i + 1}',
      pixels: const Size(1200, 800),
      printNumber: 1,
      process: i == 2 ? FilmProcess.monochrome : FilmProcess.negative,
      film: i == 2 ? 'T-MAX 400' : 'ULTRA MAX 400',
      paper: i == 2 ? 'POLYMAX II RC' : 'PORTRA ENDURA',
      minutes: <double>[6, 7.5, 9, 10.5, 12, 13.5, 15][i],
      tempC: 20,
      printed: DateTime(2026, 11, 13, 21, 30),
    ),
];

Future<ui.Image> _card({int width = 1200, int height = 800}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Rect full = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(full, Paint()..color = const Color(0xFFD8D2C4));
  canvas.drawRect(
    Rect.fromLTWH(0, height * 0.58, width.toDouble(), height * 0.42),
    Paint()..color = const Color(0xFF4E6B63),
  );
  canvas.drawRect(
    Rect.fromLTWH(width * 0.08, height * 0.14, width * 0.36, height * 0.62),
    Paint()..color = const Color(0xFF8C6A4A),
  );
  canvas.drawRect(
    Rect.fromLTWH(width * 0.55, height * 0.20, width * 0.30, height * 0.50),
    Paint()..color = const Color(0xFF1E1B18),
  );
  return recorder.endRecording().toImage(width, height);
}

FilmChart _chart(double minutes) => FilmChart(
  minutes: minutes,
  tempC: 20,
  gamma: <double>[0.48 + minutes / 100, 0.5 + minutes / 100, 0.53],
  dMin: <double>[0.04, 0.04, 0.04],
  dMax: <double>[1.7, 1.9, 2.1],
  patches: <List<double>>[
    for (int i = 0; i < 9; i++) <double>[0.12 * i, 0.13 * i, 0.15 * i],
  ],
  logE: <double>[for (int i = 0; i < 9; i++) -2.0 + i * 0.35],
);

void _window(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late ui.Image card;
  late Uint8List cardPng;

  setUpAll(() async {
    await _loadFonts();
    card = await _card();
    final ByteData? png = await card.toByteData(format: ui.ImageByteFormat.png);
    cardPng = png!.buffer.asUint8List();
    Model.useLinked(_CardModel(cardPng, card));
  });

  group('studio', skip: _paintHere ? false : 'the studio goldens are opt-in and have baselines on macOS and Windows', () {
    testWidgets('the select step', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: const <Print>[],
          initialStep: DarkroomStep.select,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/select.png'),
      );
    });

    testWidgets('the select step in daylight', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: const <Print>[],
          initialStep: DarkroomStep.select,
          appearance: Brightness.light,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/select-light.png'),
      );
    });

    testWidgets('the develop step, a strip of two', (
      WidgetTester tester,
    ) async {
      _window(tester);
      final TestStrip strip =
          const TestStrip(
                photo: '/photographs/uji.jpg',
                stockId: 'vision3_500t',
                stockLabel: 'VISION3 500T',
                paperId: 'portra_endura',
                paperLabel: 'PORTRA ENDURA',
              )
              .withPrint(
                TestPrint(minutes: 6, tempC: 20, image: card, chart: _chart(6)),
              )
              .withPrint(
                TestPrint(
                  minutes: 12,
                  tempC: 20,
                  image: card,
                  chart: _chart(12),
                ),
              );
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: strip,
          photograph: card,
          prints: const <Print>[],
          initialStep: DarkroomStep.develop,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/develop.png'),
      );
    });

    testWidgets('the print step', (WidgetTester tester) async {
      _window(tester);
      final TestStrip strip =
          const TestStrip(
            photo: '/photographs/uji.jpg',
            stockId: 'vision3_500t',
            stockLabel: 'VISION3 500T',
            paperId: 'portra_endura',
            paperLabel: 'PORTRA ENDURA',
          ).withPrint(
            TestPrint(minutes: 12, tempC: 20, image: card, chart: _chart(12)),
          );
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: strip,
          photograph: card,
          prints: const <Print>[],
          initialStep: DarkroomStep.print,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      // The print preview is the one image in these goldens that is decoded
      // from a file the model wrote: give it the frames it needs.
      for (int i = 0; i < 50; i++) {
        if (find.byType(RawImage).evaluate().isNotEmpty) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 20));
      }
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/print.png'),
      );
    });

    testWidgets('the drying rack', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: _rackPrints(card),
          initialChamber: Chamber.rack,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/rack.png'),
      );
    });

    testWidgets('the drying rack in daylight', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: _rackPrints(card),
          initialChamber: Chamber.rack,
          appearance: Brightness.light,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/rack-light.png'),
      );
    });

    testWidgets('a print taken off the rack', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: _rackPrints(card),
          initialChamber: Chamber.rack,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('rack-print-0')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/viewer.png'),
      );
    });

    testWidgets('the gallery', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: _prints(card),
          initialChamber: Chamber.gallery,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/gallery.png'),
      );
    });

    testWidgets('the gallery in daylight', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: _prints(card),
          initialChamber: Chamber.gallery,
          appearance: Brightness.light,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/gallery-light.png'),
      );
    });

    testWidgets('a portrait frame', (WidgetTester tester) async {
      _window(tester);
      final ui.Image portrait = await _card(width: 800, height: 1200);
      addTearDown(portrait.dispose);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: portrait,
          prints: <Print>[
            Print(
              image: portrait,
              name: 'portrait',
              pixels: const Size(800, 1200),
              printNumber: 1,
              process: FilmProcess.monochrome,
              film: 'T-MAX 400',
              paper: 'POLYMAX II RC',
              minutes: 9,
              tempC: 20,
            ),
          ],
          initialChamber: Chamber.gallery,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/portrait.png'),
      );
    });

    testWidgets('the lens on a frame', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: _prints(card),
          initialChamber: Chamber.gallery,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('loupe')));
      await tester.pumpAndSettle();
      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final Finder frame = find.byType(FilmFrame).first;
      final Offset origin = tester.getTopLeft(frame);
      final Size size = tester.getSize(frame);
      await mouse.moveTo(
        origin + Offset(size.width * 0.50, size.height * 0.40),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/lens.png'),
      );
    });

    testWidgets('a frame under the loupe', (WidgetTester tester) async {
      _window(tester);
      await tester.pumpWidget(
        KalloApp(
          catalogue: _catalogue,
          strip: const TestStrip(photo: '/photographs/uji.jpg'),
          photograph: card,
          prints: _prints(card),
          initialChamber: Chamber.gallery,
          appearance: Brightness.dark,
          chrome: WindowChrome.mac,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilmFrame).first);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(KalloApp),
        matchesGoldenFile('goldens/$_platform/loupe.png'),
      );
    });
  });
}
