import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/exports.dart';
import 'package:kallo_ui/lab/film_export.dart';
import 'package:kallo_ui/lab/print.dart';
import 'package:kallo_ui/widgets/film_frame.dart';

Future<ui.Image> _card({int width = 300, int height = 200}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF8C6A4A),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, height * 0.6, width.toDouble(), height * 0.4),
    Paint()..color = const Color(0xFF4E6B63),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the edge carries the name a printer says', () {
    expect(
      filmEdgeName('KODAK PROFESSIONAL T-MAX 400, D-76 8 min 20 °C'),
      'T-MAX 400',
    );
    expect(filmEdgeName('KODAK ULTRA MAX 400'), 'ULTRA MAX 400');
    expect(filmEdgeName('FUJIFILM 200'), 'FUJIFILM 200');
    expect(filmEdgeName('ILFORD DELTA 400 PROFESSIONAL, ID-11'), 'DELTA 400');
    expect(filmEdgeName(null), 'KALLOTYPE');
  });

  test('a landscape frame is a 3:2 aperture in a 35 mm rebate', () {
    final FilmFrameMetrics frame = FilmFrameMetrics.fromWidth(
      1000,
      aspect: 1.5,
    );
    expect(frame.outer.width, 1000);
    expect(frame.horizontal, isTrue);
    expect(frame.sprockets, 8);
    expect(frame.aperture.width, closeTo(1000 / 1.036, 0.001));
    expect(frame.aperture.height, closeTo(frame.aperture.width / 1.5, 0.001));
    expect(frame.aspect, greaterThan(1.15));
    expect(frame.aspect, lessThan(1.25));
  });

  test('a vertical frame turns the strip and keeps the same holes', () {
    final FilmFrameMetrics frame = FilmFrameMetrics.fromWidth(
      1000,
      aspect: 2 / 3,
    );
    expect(frame.outer.width, 1000);
    expect(frame.horizontal, isFalse);
    expect(frame.sprockets, 8);
    expect(frame.aperture.height, greaterThan(frame.aperture.width));
    expect(frame.heightPerWidth, greaterThan(1.1));
  });

  test('the frame gets the picture width plus the rebate', () {
    final double image = 6000;
    final FilmFrameMetrics frame = FilmFrameMetrics.fromImageWidth(
      image,
      aspect: 1.5,
    );
    expect(frame.aperture.width, image);
    expect(frame.outer.width, greaterThan(image));
    expect(
      frame.outer.width,
      closeTo(FilmFrameMetrics.widthForImageWidth(image, aspect: 1.5), 0.001),
    );
  });

  test('an old print gets its place in the folder for the edge', () async {
    final Directory folder = await Directory.systemTemp.createTemp(
      'kallotype-order-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final ui.Image card = await _card();
    addTearDown(card.dispose);
    final Uint8List png = (await card.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    await File('${folder.path}/print-01.png').writeAsBytes(png);
    await File('${folder.path}/print-02.png').writeAsBytes(png);

    final List<Print> prints = await Exports.read(folder: folder);
    addTearDown(() {
      for (final Print print in prints) {
        print.dispose();
      }
    });
    expect(prints, hasLength(2));
    expect(prints[0].frame, 1);
    expect(prints[1].frame, 2);
  });

  test('the finished frame is written beside the print, in Frames', () async {
    final Directory folder = await Directory.systemTemp.createTemp(
      'kallotype-frame-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final ui.Image card = await _card();
    addTearDown(card.dispose);

    final File printFile = File('${folder.path}/print-01.png');
    final ByteData? png = await card.toByteData(format: ui.ImageByteFormat.png);
    await printFile.writeAsBytes(png!.buffer.asUint8List(), flush: true);

    final Print print = Print(
      image: card,
      name: 'print-01',
      path: printFile.path,
      pixels: const Size(300, 200),
      frame: 1,
      film: 'ULTRA MAX 400',
      paper: 'PORTRA ENDURA',
      minutes: 9,
      tempC: 20,
    );

    final File framed = await exportFilmFrame(print: print, frame: 1);
    expect(framed.existsSync(), isTrue);
    expect(framed.path, contains('${Platform.pathSeparator}Frames'));
    expect(framed.lengthSync(), greaterThan(0));

    final ui.Codec codec = await ui.instantiateImageCodec(
      await framed.readAsBytes(),
    );
    final ui.FrameInfo info = await codec.getNextFrame();
    addTearDown(info.image.dispose);
    expect(info.image.width, greaterThan(300));
    expect(info.image.height, greaterThan(200));

    final File record = File(framed.path.replaceFirst('.png', '.json'));
    expect(record.existsSync(), isTrue);
    final Map<String, dynamic> json =
        jsonDecode(await record.readAsString()) as Map<String, dynamic>;
    expect(json['border'], '35mm');
    expect(json['frame'], 1);
    expect(json['film'], 'ULTRA MAX 400');
  });
}
