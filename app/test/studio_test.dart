import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/chart.dart';
import 'package:kallo_ui/lab/print.dart';
import 'package:kallo_ui/lab/stock.dart';
import 'package:kallo_ui/lab/strip.dart';
import 'package:kallo_ui/main.dart';
import 'package:kallo_ui/views/chambers.dart';
import 'package:kallo_ui/views/develop_stage.dart';
import 'package:kallo_ui/views/select_stage.dart';
import 'package:kallo_ui/views/steps.dart';
import 'package:kallo_ui/widgets/stage_tabs.dart';
import 'package:kallo_ui/widgets/studio_sidebar.dart';

Future<ui.Image> _card({int width = 600, int height = 400}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF8C6A4A),
  );
  return recorder.endRecording().toImage(width, height);
}

FilmChart _chart(double minutes) => FilmChart(
  minutes: minutes,
  tempC: 20,
  gamma: <double>[0.55, 0.57, 0.60],
  dMin: <double>[0.06, 0.06, 0.06],
  dMax: <double>[2.1, 2.3, 2.6],
  patches: <List<double>>[
    for (int i = 0; i < 9; i++) <double>[0.15 * i, 0.16 * i, 0.18 * i],
  ],
  logE: <double>[for (int i = 0; i < 9; i++) -2.0 + i * 0.35],
);

void main() {
  late ui.Image card;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    card = await _card();
  });

  testWidgets('the darkroom opens on the photograph', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      KalloApp(
        catalogue: Catalogue.carried,
        strip: const TestStrip(photo: '/photographs/uji.jpg'),
        photograph: card,
        prints: const <Print>[],
        initialStep: DarkroomStep.select,
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StudioSidebar), findsOneWidget);
    expect(find.byType(StageTabs), findsOneWidget);
    expect(find.byType(SelectStage), findsOneWidget);
    expect(find.text('暗房'), findsOneWidget);
    expect(find.text('观景台'), findsOneWidget);
    expect(find.text('原片'), findsOneWidget);
  });

  testWidgets('the develop step shows the strip and its curves', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final TestStrip strip =
        const TestStrip(
          photo: '/photographs/uji.jpg',
          stockId: 'vision3_500t',
          stockLabel: 'VISION3 500T',
        ).withPrint(
          TestPrint(minutes: 9, tempC: 20, image: card, chart: _chart(9)),
        );

    await tester.pumpWidget(
      KalloApp(
        catalogue: Catalogue.carried,
        strip: strip,
        photograph: card,
        prints: const <Print>[],
        initialStep: DarkroomStep.develop,
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DevelopStage), findsOneWidget);
    expect(find.text('试片条'), findsWidgets);
    expect(find.text('9:00'), findsWidgets);
    expect(find.text('同曝光 · 9:00'), findsOneWidget);
  });

  testWidgets('the gallery is the other room', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      KalloApp(
        catalogue: Catalogue.carried,
        strip: const TestStrip(photo: '/photographs/uji.jpg'),
        photograph: card,
        prints: const <Print>[],
        initialChamber: Chamber.gallery,
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StudioSidebar), findsOneWidget);
    expect(find.byType(StageTabs), findsNothing);
    expect(find.text('灯'), findsOneWidget);
  });
}
