import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kallo_ui/lab/develop.dart';
import 'package:kallo_ui/lab/model.dart';
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
    expect(roll.photo, photograph.path);

    final Roll? stored = await RollStore.load(folder: folder);
    expect(stored, isNotNull);
    expect(stored!.frames, hasLength(2));
    expect(stored.frames.last.clock, '9:00');
    expect(stored.frames.last.image!.width, benchWidth);
    expect(stored.stockId, Stocks.vision.id);
  }, skip: ready ? false : 'no model or no photograph on this machine',
      timeout: const Timeout(Duration(minutes: 3)));
}
