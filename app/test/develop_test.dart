import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/develop.dart';
import 'package:kallo_ui/lab/model.dart';
import 'package:kallo_ui/lab/print.dart';
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
      paper: Stocks.crystal,
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
      paperName: Stocks.paperShort,
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
    // The paper is part of the roll's record: the shelf chose it before the
    // first frame went in, and a roll that printed on a different sheet would
    // be a different roll.
    expect(roll.paperId, Stocks.paper);
    expect(stored.paperId, Stocks.paper);
    expect(stored.paperName(Catalogue.carried), 'CRYSTAL ARCHIVE PEARL');
  }, skip: ready ? false : 'no model or no photograph on this machine',
      timeout: const Timeout(Duration(minutes: 3)));

  test('the roll is printed on the paper the shelf chose', () async {
    final Catalogue catalogue = await Catalogue.load(model);
    final Stock paper = catalogue.paper('portra_endura') ?? Stocks.crystal;
    final Directory folder =
        await Directory.systemTemp.createTemp('kallotype-paper-');
    addTearDown(() => folder.delete(recursive: true));

    final Roll roll = await develop(
      model: model,
      photograph: photograph,
      stock: Stocks.vision,
      paper: paper,
      times: <double>[9],
      folder: folder,
    );

    // The paper goes to the model, comes back on the roll, and is read back out
    // of the record: a choice that stopped at the shelf would be a label.
    expect(roll.paperId, paper.id);
    expect(roll.paperId, isNot(Stocks.paper));
    expect(roll.paperName(catalogue), paper.short);

    final Roll? stored = await RollStore.load(folder: folder);
    expect(stored, isNotNull);
    expect(stored!.paperName(catalogue), paper.short);

    final Directory exports = Directory('${folder.path}/exports');
    final File image = await printFrame(
      roll: stored,
      frame: stored.frames.first,
      exports: exports,
      paperName: stored.paperName(catalogue),
      stock: Stocks.vision,
      rollFolder: folder,
    );
    final Map<String, dynamic> record = jsonDecode(
      File('${exports.path}/print-01-9min.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(image.existsSync(), isTrue);
    expect(record['paper'], paper.short);

    // The wall holds the print small and the loupe holds it whole: the file is
    // 6000 wide, the wall's copy is 1600, and walking up decodes the rest.
    final Print? shown = await Print.read(image);
    expect(shown, isNotNull);
    expect(shown!.image.width, 1600);
    expect(shown.pixels, const Size(6000, 4000));
    final ui.Image? everyPixel = await shown.full();
    expect(everyPixel, isNotNull);
    expect(everyPixel!.width, 6000);
    everyPixel.dispose();
    shown.dispose();
    // And the roll printed on the paper is still the roll's film.
    expect(record['film'], 'VISION3 500T');
  }, skip: ready ? false : 'no model or no photograph on this machine',
      timeout: const Timeout(Duration(minutes: 3)));

  test('the shelf is the model\'s own list', () async {
    final Catalogue catalogue = await Catalogue.load(model);

    // Every film the model can render, and no film it cannot. Twenty is a floor
    // rather than the number: a build that retired a stock is allowed to say so.
    expect(catalogue.films.length, greaterThan(20));
    expect(catalogue.papers, isNotEmpty);

    final Stock vision = catalogue.film('vision3_500t')!;
    expect(vision.short, 'VISION3 500T');
    expect(vision.process, FilmProcess.negative);
    expect(vision.provenance.publication, 'H-1-5219');
    expect(vision.referenceMinutes, 6.5);
    // The record is what the binder draws; a film with no fields would leave
    // that section saying nothing.
    expect(vision.measured, isNotEmpty);

    for (final Stock film in catalogue.films) {
      expect(film.process, isNotNull, reason: film.id);
      expect(film.short, isNotEmpty, reason: film.id);
      expect(film.measured, isNotEmpty, reason: film.id);
      expect(film.provenance.publication, isNotEmpty, reason: film.id);
    }
    // The one paper the app prints on is on the shelf too, with a name.
    expect(catalogue.paper(Stocks.paper)?.short, 'CRYSTAL ARCHIVE PEARL');
  }, skip: model.available ? false : 'no model on this machine');

  test('the spectral path is a different photograph', () async {
    final Directory folder =
        await Directory.systemTemp.createTemp('kallotype-spectral-');
    addTearDown(() => folder.delete(recursive: true));

    Future<Roll> developInto(String name, {required bool spectral}) =>
        develop(
          model: model,
          photograph: photograph,
          stock: Stocks.vision,
          paper: Stocks.crystal,
          times: <double>[9],
          folder: Directory('${folder.path}/$name'),
          spectral: spectral,
        );

    final Roll scalar = await developInto('scalar', spectral: false);
    final Roll spectrum = await developInto('spectral', spectral: true);

    // The roll remembers how it was made, and the record keeps it.
    expect(scalar.spectral, isFalse);
    expect(spectrum.spectral, isTrue);
    final Roll? stored = await RollStore.load(folder: Directory('${folder.path}/spectral'));
    expect(stored, isNotNull);
    expect(stored!.spectral, isTrue);

    // And the two frames are not the same picture: the path is a different
    // model, not a different label, so this is the assertion that the flags
    // reached the renderer at all.
    Future<List<int>> pixels(Roll roll) async {
      final ByteData data =
          (await roll.frames.first.image!.toByteData())!;
      return data.buffer.asUint8List();
    }

    final List<int> a = await pixels(scalar);
    final List<int> b = await pixels(spectrum);
    expect(a.length, b.length);
    double total = 0;
    int counted = 0;
    for (int i = 0; i < a.length; i += 4) {
      for (int channel = 0; channel < 3; channel++) {
        total += (a[i + channel] - b[i + channel]).abs();
        counted++;
      }
    }
    final double difference = total / counted;
    expect(
      difference,
      greaterThan(2.0),
      reason: 'the two paths rendered the same pixels: ${difference.toStringAsFixed(2)}',
    );
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
      stockId: 'vision3_500t',
      stockLabel: 'KODAK VISION3 500T 5219/7219, ECN-2',
      frames: <Frame>[frame],
    );

    final File print = await printFrame(
      roll: whole,
      frame: frame,
      exports: exports,
      paperName: Stocks.paperShort,
      stock: Stocks.vision,
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
