import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kallo_ui/lab/ffi_model.dart';
import 'package:kallo_ui/lab/model.dart';

/// The linked model, exercised in the app it ships in.
///
/// A unit test cannot prove this: the code asset is bundled by the platform
/// build, and `flutter test` runs without it. This test is the one that opens
/// the dynamic library, develops a roll from a single read of the photograph,
/// prints the proof from that same read, and asks for the catalogue.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('one read becomes a roll, a proof and a catalogue', () async {
    final bool loaded = await loadLinkedModel();
    expect(loaded, isTrue, reason: 'the dynamic library should load');
    // A second call must be free: the app initialises once and tests ask again.
    expect(await loadLinkedModel(), isTrue);

    final Model model = Model.find();
    expect(model.available, isTrue);

    final File photograph = File('../../file-test/DSCF0989.JPG');
    expect(photograph.existsSync(), isTrue, reason: 'the test photograph');

    final Directory folder =
        await Directory.systemTemp.createTemp('kallotype-ffi-');
    addTearDown(() => folder.delete(recursive: true));

    final List<File> frames = <File>[
      for (int i = 0; i < 5; i++) File('${folder.path}/0${i + 1}.png'),
    ];
    final File sheet = File('${folder.path}/contact.png');
    final File record = File('${folder.path}/contact.json');
    final Stopwatch watch = Stopwatch()..start();
    int reached = 0;
    await model.roll(
      photograph: photograph,
      stock: 'vision3_500t',
      paper: 'portra_endura',
      times: const <double>[3, 6, 9, 12, 15],
      tempC: 20,
      width: 1200,
      frames: frames,
      sheet: sheet,
      record: record,
      onProgress: (int done, int total) => reached = done,
    );
    watch.stop();
    // ignore: avoid_print
    print('ffi roll+proof: ${watch.elapsedMilliseconds} ms');

    expect(reached, 5);
    for (final File frame in frames) {
      expect(frame.existsSync(), isTrue);
      expect(frame.lengthSync(), greaterThan(0));
    }
    // Five developments of one negative are five different pictures; if the
    // roll forgot to move the development time, every frame would be the same
    // file and this is where that would show.
    final Set<int> sizes = frames.map((File f) => f.lengthSync()).toSet();
    expect(sizes.length, greaterThan(1), reason: 'the ladder must move');
    expect(sheet.existsSync(), isTrue);
    expect(record.existsSync(), isTrue);

    // The model's own list, not a list about it.
    final String catalogue = await model.catalogue();
    expect(catalogue, contains('vision3_500t'));

    // A print is a second reading, at the size the export asks for.
    final File exported = File('${folder.path}/print.png');
    await model.develop(
      photograph: photograph,
      stock: 'vision3_500t',
      paper: 'portra_endura',
      minutes: 9,
      tempC: 20,
      width: 2000,
      output: exported,
    );
    expect(exported.existsSync(), isTrue);
    expect(exported.lengthSync(), greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('the linked model reads a camera raw', () async {
    final bool loaded = await loadLinkedModel();
    expect(loaded, isTrue);

    final File photograph = File('../../file-test/DSC03315.ARW');
    expect(photograph.existsSync(), isTrue, reason: 'the raw fixture');
    final Directory folder =
        await Directory.systemTemp.createTemp('kallotype-ffi-raw-');
    addTearDown(() => folder.delete(recursive: true));
    final List<File> frames = <File>[
      for (int i = 0; i < 5; i++) File('${folder.path}/0${i + 1}.png'),
    ];
    final File sheet = File('${folder.path}/contact.png');
    final File record = File('${folder.path}/contact.json');
    final Model model = Model.find();
    final Stopwatch watch = Stopwatch()..start();
    await model.roll(
      photograph: photograph,
      stock: 'vision3_500t',
      paper: 'portra_endura',
      times: const <double>[3, 6, 9, 12, 15],
      tempC: 20,
      width: 1200,
      frames: frames,
      sheet: sheet,
      record: record,
    );
    watch.stop();
    // ignore: avoid_print
    print('ffi raw roll+proof: ${watch.elapsedMilliseconds} ms');
    for (final File frame in frames) {
      expect(frame.existsSync(), isTrue);
    }
    expect(sheet.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
