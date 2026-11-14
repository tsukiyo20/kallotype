import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo/lab/exports.dart';
import 'package:kallo/lab/print.dart';

Future<void> _png(File file, int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF8C6A4A),
  );
  final ui.Image image = await recorder.endRecording().toImage(width, height);
  addTearDown(image.dispose);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the export folder is read oldest first, one stat per file', () async {
    final Directory folder = await Directory.systemTemp.createTemp(
      'kallotype-exports-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final DateTime base = DateTime(2026, 1, 1, 12);
    final File oldest = File('${folder.path}/oldest.png');
    final File middle = File('${folder.path}/middle.png');
    final File newest = File('${folder.path}/newest.png');
    await _png(oldest, 30, 20);
    await _png(middle, 40, 30);
    await _png(newest, 50, 40);
    await oldest.setLastModified(base);
    await middle.setLastModified(base.add(const Duration(minutes: 1)));
    await newest.setLastModified(base.add(const Duration(minutes: 2)));
    await File('${folder.path}/notes.txt').writeAsString('not a print');

    final List<Print> prints = await Exports.read(folder: folder);

    expect(prints.map((Print print) => print.name), <String>[
      'oldest',
      'middle',
      'newest',
    ]);
    expect(prints.map((Print print) => print.pixels), <Size>[
      const Size(30, 20),
      const Size(40, 30),
      const Size(50, 40),
    ]);
    expect(prints.map((Print print) => print.printed), <DateTime>[
      base,
      base.add(const Duration(minutes: 1)),
      base.add(const Duration(minutes: 2)),
    ]);
  });
}
