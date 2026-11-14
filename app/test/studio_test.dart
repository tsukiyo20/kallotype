import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/design/scope.dart';
import 'package:kallo_ui/design/strings.dart';
import 'package:kallo_ui/design/tokens.dart';
import 'package:kallo_ui/lab/chart.dart';
import 'package:kallo_ui/lab/print.dart';
import 'package:kallo_ui/lab/stock.dart';
import 'package:kallo_ui/lab/strip.dart';
import 'package:kallo_ui/main.dart';
import 'package:kallo_ui/views/chambers.dart';
import 'package:kallo_ui/views/develop_stage.dart';
import 'package:kallo_ui/views/rack.dart';
import 'package:kallo_ui/views/select_stage.dart';
import 'package:kallo_ui/views/steps.dart';
import 'package:kallo_ui/widgets/film_frame.dart';
import 'package:kallo_ui/widgets/stage_tabs.dart';
import 'package:kallo_ui/widgets/stepper.dart';
import 'package:kallo_ui/widgets/print_viewer.dart';
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
    expect(find.text('晾片架'), findsOneWidget);
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

  testWidgets('the temperature dial asks for the next step', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    double? chosen;
    final TestStrip strip =
        const TestStrip(photo: '/photographs/uji.jpg', tempC: 20).withPrint(
          TestPrint(minutes: 9, tempC: 20, image: card, chart: _chart(9)),
        );
    await tester.pumpWidget(
      KalloScope(
        colors: KalloColors.dark,
        pinned: Brightness.dark,
        onPin: (Brightness? _) {},
        child: Localizations(
          locale: const Locale('zh'),
          delegates: const <LocalizationsDelegate<Object>>[
            KalloStrings.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DevelopStage(
              strip: strip,
              onTemperature: (double value) => chosen = value,
              onDevelop: (_) async {},
              onRemove: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder stepper = find.byType(KalloStepper);
    expect(stepper, findsOneWidget);
    await tester.tap(find.descendant(of: stepper, matching: find.text('+')));
    expect(chosen, 20.5);
  });

  testWidgets('the window holds at its smallest size', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(960, 600);
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
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('stage-tabs')), findsOneWidget);
  });

  testWidgets('the sides of the window can be put away', (
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

    expect(find.byKey(const Key('studio-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('select-inspector')), findsOneWidget);
    expect(find.text('彩色负片'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('studio-sidebar')), findsNothing);
    expect(find.byType(StudioSidebar), findsNothing);
    expect(find.byType(SelectStage), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('studio-sidebar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('彩色负片'), findsNothing);
    expect(find.byType(SelectStage), findsOneWidget);

    await tester.tap(find.byKey(const Key('inspector-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('彩色负片'), findsOneWidget);
  });

  testWidgets('the rack wraps its prints and opens one full screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final List<Print> prints = <Print>[
      for (int i = 0; i < 6; i++)
        Print(
          image: card,
          name: 'uji-$i',
          printNumber: 1,
          film: 'ULTRA MAX 400',
          paper: 'PORTRA ENDURA',
          minutes: 6 + i.toDouble(),
          tempC: 20,
        ),
    ];
    await tester.pumpWidget(
      KalloApp(
        catalogue: Catalogue.carried,
        strip: const TestStrip(photo: '/photographs/uji.jpg'),
        photograph: card,
        prints: prints,
        initialChamber: Chamber.rack,
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    final Scrollable scroll = tester.widget<Scrollable>(
      find.descendant(
        of: find.byKey(const Key('rack-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scroll.axisDirection, AxisDirection.down);
    expect(find.byKey(const ValueKey<String>('rack-line-0')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('rack-line-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('rack-print-0')));
    await tester.pumpAndSettle();
    expect(find.byType(PrintViewer), findsOneWidget);
    expect(find.byKey(const Key('print-viewer-close')), findsOneWidget);

    await tester.tap(find.byKey(const Key('print-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byType(PrintViewer), findsNothing);
  });

  testWidgets('the rack is beside the darkroom', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final Print print = Print(
      image: card,
      name: 'uji',
      printNumber: 1,
      film: 'ULTRA MAX 400',
      paper: 'PORTRA ENDURA',
      minutes: 9,
      tempC: 20,
    );
    await tester.pumpWidget(
      KalloApp(
        catalogue: Catalogue.carried,
        strip: const TestStrip(photo: '/photographs/uji.jpg'),
        photograph: card,
        prints: <Print>[print],
        initialChamber: Chamber.rack,
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StudioSidebar), findsOneWidget);
    expect(find.byType(Rack), findsOneWidget);
    expect(find.byType(StageTabs), findsNothing);
    expect(find.text('晾片架'), findsNWidgets(2));
    expect(find.text('01   ·   9:00'), findsOneWidget);
  });

  testWidgets('the gallery is the other room, and it shows film', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final Print print = Print(
      image: card,
      name: 'uji',
      printNumber: 1,
      film: 'ULTRA MAX 400',
      paper: 'PORTRA ENDURA',
      minutes: 9,
      tempC: 20,
    );
    await tester.pumpWidget(
      KalloApp(
        catalogue: Catalogue.carried,
        strip: const TestStrip(photo: '/photographs/uji.jpg'),
        photograph: card,
        prints: <Print>[print],
        initialChamber: Chamber.gallery,
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StudioSidebar), findsOneWidget);
    expect(find.byType(StageTabs), findsNothing);
    expect(find.byType(FilmFrame), findsOneWidget);
    expect(find.text('灯'), findsOneWidget);
  });
}
