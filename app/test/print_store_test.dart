import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kallo/lab/print.dart';
import 'package:kallo/lab/print_store.dart';
import 'package:kallo/lab/stock.dart';

void main() {
  test('old sidecars move into the app folder and the pictures stay', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'kallotype-store-',
    );
    addTearDown(() => root.delete(recursive: true));
    final Directory exports = Directory('${root.path}/exports')
      ..createSync(recursive: true);
    final Directory app = Directory('${root.path}/app');
    final Directory frames = Directory('${exports.path}/Frames')
      ..createSync(recursive: true);

    final File print = File('${exports.path}/print-01.png')
      ..writeAsBytesSync(<int>[137, 80, 78, 71]);
    final File sidecar = File('${exports.path}/print-01.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'frame': 9,
          'film': 'KODAK PROFESSIONAL T-MAX 400, D-76 8 min 20 °C',
          'paper': 'POLYMAX II RC',
          'minutes': 11.5,
          'temp_c': 20.0,
        }),
      );
    final File frameImage = File('${frames.path}/print-01-frame.png')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final File frameRecord = File('${frames.path}/print-01-frame.json')
      ..writeAsStringSync('{"border": "35mm", "print": 1}');

    final Map<String, PrintRecord> records = await PrintStore.load(
      exports: exports,
      frames: frames,
      directory: app,
    );

    expect(sidecar.existsSync(), isFalse);
    expect(frameRecord.existsSync(), isFalse);
    expect(frameImage.existsSync(), isTrue);
    expect(File('${app.path}/prints.json').existsSync(), isTrue);

    final PrintRecord? record = records[print.path];
    expect(record, isNotNull);
    expect(record!.printNumber, 1);
    expect(record.process, FilmProcess.monochrome);
    expect(record.minutes, 11.5);
    expect(record.paper, 'POLYMAX II RC');
    expect(record.film, 'KODAK PROFESSIONAL T-MAX 400, D-76 8 min 20 °C');

    final Map<String, PrintRecord> again = await PrintStore.load(
      exports: exports,
      frames: frames,
      directory: app,
    );
    expect(again[print.path]?.process, FilmProcess.monochrome);
  });

  test('a new print is remembered when there is no sidecar', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'kallotype-store-',
    );
    addTearDown(() => root.delete(recursive: true));
    final File print = File('${root.path}/print-02.png')
      ..writeAsBytesSync(<int>[1, 2, 3]);

    await PrintStore.remember(
      print,
      const PrintRecord(
        printNumber: 2,
        process: FilmProcess.negative,
        film: 'ULTRA MAX 400',
        paper: 'PORTRA ENDURA',
        minutes: 9,
        tempC: 20,
      ),
      directory: root,
    );

    final File store = File('${root.path}/prints.json');
    expect(store.existsSync(), isTrue);
    final Map<String, dynamic> json =
        jsonDecode(store.readAsStringSync()) as Map<String, dynamic>;
    expect(json[print.path], isA<Map<String, dynamic>>());
    expect(json[print.path]['process'], 'negative');
    expect(json[print.path]['print'], 2);
  });

  test('the store keeps the previous complete file as a backup', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'kallotype-store-',
    );
    addTearDown(() => root.delete(recursive: true));
    final File first = File('${root.path}/print-01.png')
      ..writeAsBytesSync(<int>[1]);
    final File second = File('${root.path}/print-02.png')
      ..writeAsBytesSync(<int>[2]);

    await PrintStore.remember(
      first,
      const PrintRecord(printNumber: 1, film: 'GOLD 200', minutes: 9),
      directory: root,
    );
    await PrintStore.remember(
      second,
      const PrintRecord(printNumber: 2, film: 'ULTRA MAX 400', minutes: 12),
      directory: root,
    );

    final File live = File('${root.path}/prints.json');
    final File backup = File('${root.path}/prints.json.bak');
    final File temp = File('${root.path}/prints.json.tmp');
    expect(live.existsSync(), isTrue);
    expect(backup.existsSync(), isTrue);
    expect(temp.existsSync(), isFalse);

    final Map<String, dynamic> backupJson =
        jsonDecode(backup.readAsStringSync()) as Map<String, dynamic>;
    expect(backupJson.keys, <String>[first.path]);
    final Map<String, dynamic> liveJson =
        jsonDecode(live.readAsStringSync()) as Map<String, dynamic>;
    expect(liveJson.keys, containsAll(<String>[first.path, second.path]));

    // A live file that is half-written is not the store: the previous complete
    // version is still readable.
    live.writeAsStringSync('{');
    final Map<String, PrintRecord> recovered = await PrintStore.load(
      directory: root,
    );
    expect(recovered.keys, <String>[first.path]);
    expect(recovered[first.path]?.film, 'GOLD 200');
  });

  test('two prints finishing together keep both records', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'kallotype-store-',
    );
    addTearDown(() => root.delete(recursive: true));
    final File first = File('${root.path}/print-01.png')
      ..writeAsBytesSync(<int>[1]);
    final File second = File('${root.path}/print-02.png')
      ..writeAsBytesSync(<int>[2]);

    await Future.wait(<Future<void>>[
      PrintStore.remember(
        first,
        const PrintRecord(printNumber: 1, film: 'GOLD 200'),
        directory: root,
      ),
      PrintStore.remember(
        second,
        const PrintRecord(printNumber: 2, film: 'ULTRA MAX 400'),
        directory: root,
      ),
    ]);

    final Map<String, PrintRecord> records = await PrintStore.load(
      directory: root,
    );
    expect(records.keys, containsAll(<String>[first.path, second.path]));
    expect(records[first.path]?.printNumber, 1);
    expect(records[second.path]?.printNumber, 2);
  });

}
