import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/design/chrome.dart';
import 'package:kallo_ui/lab/chart.dart';
import 'package:kallo_ui/lab/model.dart';
import 'package:kallo_ui/lab/print.dart';
import 'package:kallo_ui/lab/stock.dart';
import 'package:kallo_ui/lab/strip.dart';
import 'package:kallo_ui/main.dart';
import 'package:kallo_ui/views/chambers.dart';
import 'package:kallo_ui/views/steps.dart';

/// The new shell's pictures.
///
/// They are not drawn on this Mac: the baselines belong to the Windows machine
/// the type was measured on, and a Mac's Impeller draws a different pixel.
/// Ask for them deliberately, on Windows:
///
/// ```bash
/// flutter test --dart-define=studio-goldens=true --update-goldens \
///   test/studio_golden_test.dart
/// ```
const bool _paint = bool.fromEnvironment('studio-goldens');

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
  _CardModel(this.bytes) : super('');

  final Uint8List bytes;

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
    await output.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<String> catalogue() async => '{"films":[],"papers":[]}';
}

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
    Model.useLinked(_CardModel(cardPng));
  });

  group(
    'studio',
    skip: _paint
        ? false
        : 'new baselines are drawn on Windows with --update-goldens',
    () {
      testWidgets('the select step', (WidgetTester tester) async {
        _window(tester);
        await tester.pumpWidget(
          KalloApp(
            catalogue: Catalogue.carried,
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
          matchesGoldenFile('goldens2/select.png'),
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
                  TestPrint(
                    minutes: 6,
                    tempC: 20,
                    image: card,
                    chart: _chart(6),
                  ),
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
            catalogue: Catalogue.carried,
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
          matchesGoldenFile('goldens2/develop.png'),
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
            catalogue: Catalogue.carried,
            strip: strip,
            photograph: card,
            prints: const <Print>[],
            initialStep: DarkroomStep.print,
            appearance: Brightness.dark,
            chrome: WindowChrome.mac,
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(KalloApp),
          matchesGoldenFile('goldens2/print.png'),
        );
      });

      testWidgets('the gallery', (WidgetTester tester) async {
        _window(tester);
        final List<Print> prints = <Print>[
          for (final double minutes in <double>[6, 9, 12])
            Print(
              image: card,
              name: 'uji',
              pixels: const Size(6000, 4000),
              frame: 1,
              film: 'ULTRA MAX 400',
              paper: 'PORTRA ENDURA',
              minutes: minutes,
              tempC: 20,
              printed: DateTime(2026, 11, 13, 21, 30),
            ),
        ];
        await tester.pumpWidget(
          KalloApp(
            catalogue: Catalogue.carried,
            strip: const TestStrip(photo: '/photographs/uji.jpg'),
            photograph: card,
            prints: prints,
            initialChamber: Chamber.gallery,
            appearance: Brightness.dark,
            chrome: WindowChrome.mac,
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(KalloApp),
          matchesGoldenFile('goldens2/gallery.png'),
        );
      });
    },
  );
}
