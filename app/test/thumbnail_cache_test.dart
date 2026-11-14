import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo/lab/print.dart';
import 'package:kallo/lab/thumbnails.dart';

Future<ui.Image> _card({int width = 300, int height = 200}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF8C6A4A),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a scanned print has a shape but no pixels', () async {
    final Directory folder = await Directory.systemTemp.createTemp(
      'kallotype-scan-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final ui.Image card = await _card();
    addTearDown(card.dispose);
    final File file = File('${folder.path}/print-01.png');
    final ByteData? png = await card.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);

    final Print? print = await Print.scan(file);
    expect(print, isNotNull);
    expect(print!.image, isNull);
    expect(print.pixels, const Size(300, 200));
  });

  test('a thumbnail is made once and kept on disk', () async {
    final Directory folder = await Directory.systemTemp.createTemp(
      'kallotype-thumb-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final Directory cacheDirectory = Directory('${folder.path}/thumbs');
    final ui.Image card = await _card();
    addTearDown(card.dispose);
    final File file = File('${folder.path}/print-01.png');
    final ByteData? png = await card.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
    final Print print = (await Print.scan(file))!;

    final PrintThumbnailCache cache = PrintThumbnailCache.forTesting(
      cacheDirectory,
    );
    addTearDown(cache.clear);
    final PrintThumbnail? first = await cache.acquire(print);
    expect(first, isNotNull);
    expect(first!.image.width, 300);
    first.release();

    final List<FileSystemEntity> stored = cacheDirectory.listSync();
    expect(stored, hasLength(1));
    expect(
      (stored.single as File).path,
      matches(RegExp(r'thumb-[0-9a-f]{16}\.png$')),
    );

    // The second read is served from disk: clearing the decoded images must
    // not make the print be decoded from its 300-pixel source again.
    cache.clear();
    final PrintThumbnail? second = await cache.acquire(print);
    expect(second, isNotNull);
    second!.release();
  });
}
