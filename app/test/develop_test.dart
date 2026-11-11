import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/develop.dart';
import 'package:kallo_ui/lab/model.dart';
import 'package:kallo_ui/lab/print_out.dart';
import 'package:kallo_ui/lab/roll.dart';
import 'package:kallo_ui/lab/roll_store.dart';
import 'package:kallo_ui/lab/stock.dart';

/// The model is a binary and the photograph is somebody's, so this test runs
/// where both are and says so where they are not. It is the one test in the app
/// that proves the pipeline rather than a layout: without it, every picture the
/// interface draws is a picture of a class.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Model model = Model.find();
  // Outside the repository on purpose: the photograph is the author's, and the
  // app is never given it as an asset.
  final File photograph = File('../../file-test/DSCF0989.JPG');
  final bool ready = model.available && photograph.existsSync();

  test('a photograph becomes a roll, and the roll comes back', () async {
    final Directory folder =
        await Directory.systemTemp.createTemp('kallotype-roll-');
    addTearDown(() => folder.delete(recursive: true));

    final Roll roll = await develop(
      model: model,
      photograph: photograph,
      stock: Stocks.vision,
      times: <double>[3, 9],
      folder: folder,
    );

    expect(roll.frames, hasLength(2));
    for (final Frame frame in roll.frames) {
      expect(frame.image, isNotNull);
      expect(frame.image!.width, benchWidth);
      expect(frame.isMeasured, isFalse);
      expect(frame.toneCurve, isNull);
    }
    expect(roll.frames.first.clock, '3:00');
    // The photograph is kept inside the roll, under its own name: the record
    // has to point at something that will still be there tomorrow.
    expect(roll.photo, '${folder.path}/DSCF0989.JPG');
    expect(File(roll.photo!).existsSync(), isTrue);

    final Directory exports = Directory('${folder.path}/exports');
    final File print = await printFrame(
      roll: roll,
      frame: roll.frames.first,
      exports: exports,
      rollFolder: folder,
    );
    // A print is rendered again from the photograph, so it is the size of the
    // photograph and not the size of the bench.
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(print.readAsBytesSync());
    final ui.ImageDescriptor descriptor =
        await ui.ImageDescriptor.encoded(buffer);
    // The photograph is 6240 wide; a print is capped at 6000, which is where
    // the emulsion's own blur stops being smaller than a pixel.
    expect(descriptor.width, 6000);
    descriptor.dispose();

    final Roll? stored = await RollStore.load(folder: folder);
    expect(stored, isNotNull);
    expect(stored!.frames, hasLength(2));
    expect(stored.frames.last.clock, '9:00');
    expect(stored.frames.last.image!.width, benchWidth);
    expect(stored.stockId, Stocks.vision.id);
  }, skip: ready ? false : 'no model or no photograph on this machine',
      timeout: const Timeout(Duration(minutes: 3)));

  test('a frame becomes a print, with the record that labels it', () async {
    final Directory folder =
        await Directory.systemTemp.createTemp('kallotype-print-');
    addTearDown(() => folder.delete(recursive: true));
    final Directory roll = Directory('${folder.path}/roll')
      ..createSync(recursive: true);
    final Directory exports = Directory('${folder.path}/exports');

    // A picture of nothing in particular: this test is about the file and the
    // record, and the photograph is the other test's business.
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 3, 2),
      Paint()..color = const Color(0xFF808080),
    );
    final ui.Image image = await recorder.endRecording().toImage(3, 2);
    final ByteData png =
        (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('${roll.path}/03.png').writeAsBytesSync(png.buffer.asUint8List());

    final Frame frame =
        Frame(number: 3, minutes: 9, tempC: 20, image: image);
    final Roll whole = Roll(
      number: 1,
      stockId: 'vision3_500t',
      stockLabel: 'KODAK VISION3 500T 5219/7219, ECN-2',
      frames: <Frame>[frame],
    );

    final File print = await printFrame(
      roll: whole,
      frame: frame,
      exports: exports,
      rollFolder: roll,
    );
    expect(print.existsSync(), isTrue);
    expect(print.path.endsWith('print-03-9min.png'), isTrue);

    final Map<String, dynamic> record = jsonDecode(
      File('${exports.path}/print-03-9min.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(record['film'], 'VISION3 500T');
    expect(record['paper'], 'CRYSTAL ARCHIVE PEARL');
    expect(record['minutes'], 9);
    expect(record['temp_c'], 20);
  });
}
