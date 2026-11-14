import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/print.dart';
import 'package:kallo_ui/lab/stock.dart';
import 'package:kallo_ui/lab/strip.dart';
import 'package:kallo_ui/main.dart';
import 'package:kallo_ui/views/chambers.dart';
import 'package:kallo_ui/widgets/film_frame.dart';

Future<ui.Image> _card({int width = 1600, int height = 1067}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Rect full = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(full, Paint()..color = const Color(0xFFD8D2C4));
  canvas.drawRect(
    Rect.fromLTWH(0, height * 0.55, width.toDouble(), height * 0.45),
    Paint()..color = const Color(0xFF4E6B63),
  );
  canvas.drawRect(
    Rect.fromLTWH(width * 0.12, height * 0.18, width * 0.3, height * 0.6),
    Paint()..color = const Color(0xFF8C6A4A),
  );
  canvas.drawRect(
    Rect.fromLTWH(width * 0.62, height * 0.24, width * 0.24, height * 0.5),
    Paint()..color = const Color(0xFF1E1B18),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the loupe bows the picture it magnifies', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Print shot;
    late ui.Image card;
    final Directory folder = (await tester.runAsync(() async {
      final Directory folder = await Directory.systemTemp.createTemp(
        'kallotype-gallery-',
      );
      final ui.Image card = await _card();
      final File file = File('${folder.path}/print-01.png');
      final ByteData? png = await card.toByteData(
        format: ui.ImageByteFormat.png,
      );
      await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      final Print? print = await Print.read(file, width: 1600);
      shot = print!;
      return folder;
    }))!;
    card = shot.image;
    addTearDown(() => folder.delete(recursive: true));
    addTearDown(card.dispose);

    await tester.pumpWidget(
      KalloApp(
        catalogue: Catalogue.carried,
        strip: const TestStrip(photo: '/photographs/uji.jpg'),
        photograph: card,
        prints: <Print>[shot],
        initialChamber: Chamber.gallery,
        locale: const Locale('zh'),
        appearance: Brightness.dark,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilmFrame).first);
    await tester.pumpAndSettle();
    expect(find.byType(FilmFrame), findsOneWidget);
    expect(tester.widget<FilmFrame>(find.byType(FilmFrame)).barrel, 0);
    expect(find.text('导出胶片边框'), findsOneWidget);

    final Offset centre = tester.getCenter(find.byType(FilmFrame));
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: centre);
    await mouse.moveTo(centre);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: centre,
        scrollDelta: const Offset(0, -300),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<FilmFrame>(find.byType(FilmFrame)).barrel,
      greaterThan(0),
      reason: 'the glass distorts what it magnifies',
    );

    await tester.tap(find.byKey(const Key('export')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-confirm')), findsOneWidget);
    expect(find.text('原尺寸'), findsOneWidget);
    expect(find.text('4096 px'), findsOneWidget);
    expect(find.text('JPEG'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('TIFF'), findsOneWidget);

    await tester.tap(find.byKey(const Key('export-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-confirm')), findsNothing);

    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('back')), findsNothing);
    expect(find.text('导出胶片边框'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
