import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo/lab/export_codec.dart';
import 'package:kallo/lab/export_format.dart';
import 'package:kallo/lab/exports.dart';
import 'package:kallo/lab/film_export.dart';
import 'package:kallo/lab/print.dart';
import 'package:kallo/lab/stock.dart';
import 'package:kallo/widgets/film_frame.dart';

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

  test('the edge carries the maker and the name a printer says', () {
    expect(
      filmEdgeName('KODAK PROFESSIONAL T-MAX 400, D-76 8 min 20 °C'),
      'KODAK T-MAX 400',
    );
    expect(filmEdgeName('KODAK ULTRA MAX 400'), 'KODAK ULTRA MAX 400');
    expect(filmEdgeName('FUJIFILM 200'), 'FUJIFILM 200');
    expect(
      filmEdgeName('ILFORD DELTA 400 PROFESSIONAL, ID-11'),
      'ILFORD DELTA 400',
    );
    expect(filmEdgeName(null), '');
    expect(filmEdgeName('GOLD 200'), 'KODAK GOLD 200');
    expect(filmEdgeName('PROVIA 100F'), 'FUJIFILM PROVIA 100F');
    expect(
      stockDisplayName('ENDURA PREMIER METALLIC'),
      'KODAK ENDURA PREMIER METALLIC',
    );
    expect(
      stockDisplayName('CRYSTAL ARCHIVE PEARL'),
      'FUJIFILM CRYSTAL ARCHIVE PEARL',
    );
    expect(stockDisplayName('KODAK GOLD 200'), 'KODAK GOLD 200');
    expect(
      filmProcessFromName('KODAK PROFESSIONAL T-MAX 400, D-76 8 min 20 °C'),
      FilmProcess.monochrome,
    );
    expect(filmProcessFromName('KODAK ULTRA MAX 400'), FilmProcess.negative);
    expect(
      filmProcessFromName('FUJICHROME PROVIA 100F (RDP III), E-6'),
      FilmProcess.reversal,
    );
    expect(filmProcessFromName(null), isNull);
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

  test('a print without a record is print 01, not its folder place', () async {
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
    expect(prints[0].printNumber, 1);
    expect(prints[1].printNumber, 1);
  });

  test('a batch record carries its print number and chemistry', () async {
    final Directory folder = await Directory.systemTemp.createTemp(
      'kallotype-batch-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final ui.Image card = await _card();
    addTearDown(card.dispose);
    final File file = File('${folder.path}/print-02.png');
    final Uint8List png = (await card.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    await file.writeAsBytes(png);
    await File('${folder.path}/print-02.json').writeAsString(
      '{"print": 2, "process": "monochrome", "film": "T-MAX 400", '
      '"minutes": 9}',
    );

    final Print? print = await Print.read(file);
    addTearDown(() => print?.dispose());
    expect(print, isNotNull);
    expect(print!.printNumber, 2);
    expect(print.process, FilmProcess.monochrome);
    expect(print.folio, startsWith('02'));
  });

  test(
    'a large print exports a capped JPEG, not a hundred-megabyte PNG',
    () async {
      final Directory folder = await Directory.systemTemp.createTemp(
        'kallotype-large-frame-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final ui.Image card = await _card(width: 5000, height: 3333);
      addTearDown(card.dispose);
      final File printFile = File('${folder.path}/print-large.png');
      final ByteData? png = await card.toByteData(
        format: ui.ImageByteFormat.png,
      );
      await printFile.writeAsBytes(png!.buffer.asUint8List(), flush: true);

      final Print print = Print(
        image: card,
        name: 'print-large',
        path: printFile.path,
        pixels: const Size(5000, 3333),
        printNumber: 1,
        process: FilmProcess.negative,
        film: 'ULTRA MAX 400',
        paper: 'PORTRA ENDURA',
        minutes: 9,
        tempC: 20,
      );

      final File framed = await exportFilmFrame(print: print, maxEdge: 4096);
      final ui.Codec codec = await ui.instantiateImageCodec(
        await framed.readAsBytes(),
      );
      final ui.FrameInfo info = await codec.getNextFrame();
      addTearDown(info.image.dispose);
      expect(info.image.width, lessThanOrEqualTo(4096));
      expect(framed.lengthSync(), lessThan(8 * 1024 * 1024));
    },
  );

  test('a PNG becomes JPEG or TIFF, and a JPEG print reads back', () async {
    final ui.Image card = await _card();
    addTearDown(card.dispose);
    final Uint8List png = (await card.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();

    final Uint8List jpeg = await encodePngAs(png, ExportFormat.jpeg);
    expect(jpeg[0], 0xFF);
    expect(jpeg[1], 0xD8);
    final Uint8List tiff = await encodePngAs(png, ExportFormat.tiff);
    expect(tiff[0], anyOf(0x49, 0x4D));

    final Directory folder = await Directory.systemTemp.createTemp(
      'kallotype-jpeg-print-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final File file = File('${folder.path}/print-01.jpg');
    await file.writeAsBytes(jpeg);
    final Print? print = await Print.read(file);
    addTearDown(() => print?.dispose());
    expect(print, isNotNull);
    expect(print!.pixels, const Size(300, 200));
    expect(print.printNumber, 1);
  });

  test('the frame can be written as PNG or TIFF', () async {
    final Directory folder = await Directory.systemTemp.createTemp(
      'kallotype-frame-formats-',
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
      process: FilmProcess.monochrome,
      film: 'T-MAX 400',
      minutes: 9,
      tempC: 20,
    );

    final File asPng = await exportFilmFrame(
      print: print,
      format: ExportFormat.png,
    );
    expect(asPng.path, endsWith('.png'));
    expect((await asPng.readAsBytes()).sublist(0, 4), <int>[137, 80, 78, 71]);

    final File asTiff = await exportFilmFrame(
      print: print,
      format: ExportFormat.tiff,
    );
    expect(asTiff.path, endsWith('.tiff'));
    final Uint8List tiff = await asTiff.readAsBytes();
    expect(tiff[0], anyOf(0x49, 0x4D));
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
      printNumber: 1,
      process: FilmProcess.negative,
      film: 'ULTRA MAX 400',
      paper: 'PORTRA ENDURA',
      minutes: 9,
      tempC: 20,
    );

    final File framed = await exportFilmFrame(print: print, printNumber: 1);
    expect(framed.existsSync(), isTrue);
    expect(framed.path, contains('${Platform.pathSeparator}Frames'));
    expect(framed.path, endsWith('.jpg'));
    expect(framed.lengthSync(), greaterThan(0));
    expect(framed.lengthSync(), lessThan(5 * 1024 * 1024));

    final ui.Codec codec = await ui.instantiateImageCodec(
      await framed.readAsBytes(),
    );
    final ui.FrameInfo info = await codec.getNextFrame();
    addTearDown(info.image.dispose);
    expect(info.image.width, greaterThan(300));
    expect(info.image.height, greaterThan(200));

    expect(
      File(framed.path.replaceFirst('.jpg', '.json')).existsSync(),
      isFalse,
      reason: 'the frame folder holds the image, not a record',
    );
  });
}
