import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kallo/lab/catalog.dart';
import 'package:kallo/lab/print.dart';
import 'package:kallo/lab/print_library.dart';
import 'package:kallo/lab/print_marker.dart';
import 'package:kallo/lab/print_meta.dart';
import 'package:kallo/lab/print_store.dart';
import 'package:kallo/lab/stock.dart';

void main() {
  late Directory root;
  late Directory folder;
  late Catalog catalog;
  late PrintLibrary library;
  final DateTime printed = DateTime.utc(2026, 11, 14, 9, 5);

  PrintMeta meta({String? id, String title = 'print 01'}) => PrintMeta(
    id: id ?? PrintMeta.newId(),
    title: title,
    kind: PrintKind.print,
    printed: printed,
    added: printed.add(const Duration(minutes: 1)),
    updated: printed.add(const Duration(minutes: 2)),
    process: FilmProcess.negative,
    film: 'KODAK PORTRA 400',
    paper: 'KODAK CRYSTAL',
    minutes: 9.5,
    tempC: 20,
  );

  Future<File> png(String name) async {
    final File file = File('${folder.path}/$name');
    final img.Image picture = img.Image(width: 4, height: 3);
    img.fill(picture, color: img.ColorRgb8(120, 30, 10));
    await file.writeAsBytes(img.encodePng(picture));
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kallo-library-');
    folder = Directory('${root.path}/Kallo')..createSync();
    catalog = Catalog.openInMemory();
    library = PrintLibrary.open(folder: folder, catalog: catalog);
  });

  tearDown(() async {
    catalog.close();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('a marked file is a print; an unmarked file is ignored', () async {
    final File marked = await png('print.png');
    await PrintMarker.finalize(marked, marked, meta());
    await png('other.png');

    final List<Print> prints = await library.read();
    expect(prints, hasLength(1));
    expect(prints.single.name, 'print 01');
    expect(prints.single.path, marked.path);
    expect(prints.single.film, 'KODAK PORTRA 400');
    expect(prints.single.printed, printed);
    expect(catalog.printsInLibrary(library.library.id), hasLength(1));
  });

  test('a renamed print keeps its id and moves its locator', () async {
    final File file = await png('print.png');
    final PrintMeta record = meta();
    await PrintMarker.finalize(file, file, record);
    await library.read();

    final File renamed = await file.rename('${folder.path}/renamed.png');
    final List<Print> prints = await library.read();
    expect(prints.single.path, renamed.path);
    expect(prints.single.name, 'print 01');
    expect(catalog.printById(record.id)?.locator, renamed.path);
  });

  test('a stripped marker keeps the print through the catalog', () async {
    final File file = await png('print.png');
    final PrintMeta record = meta();
    await PrintMarker.finalize(file, file, record);
    await library.read();

    final File unmarked = await png('replacement.png');
    await unmarked.copy(file.path);
    await unmarked.delete();

    final List<Print> prints = await library.read();
    expect(prints, hasLength(1));
    expect(prints.single.name, 'print 01');
    expect(catalog.printById(record.id)?.xmpState, XmpState.missing);
  });

  test('a missing file is retained but not hung', () async {
    final File file = await png('print.png');
    final PrintMeta record = meta();
    await PrintMarker.finalize(file, file, record);
    await library.read();

    await file.delete();
    final List<Print> prints = await library.read();
    expect(prints, isEmpty);
    expect(catalog.printById(record.id)?.missing, isTrue);
    expect(catalog.printById(record.id)?.title, 'print 01');
  });

  test('addFile marks the print and inserts its row', () async {
    final File file = await png('new.png');
    final PrintMeta record = meta(title: 'new print');
    final Print print = await library.addFile(file, record);

    expect(print.name, 'new print');
    expect((await PrintMarker.readMeta(file))?.id, record.id);
    expect(catalog.printById(record.id)?.title, 'new print');
  });

  test('legacy prints.json becomes markers and rows', () async {
    final Directory support = Directory('${root.path}/support')..createSync();
    final File file = await png('legacy.png');
    await PrintStore.remember(
      file,
      const PrintRecord(
        printNumber: 1,
        process: FilmProcess.negative,
        film: 'KODAK PORTRA 400',
        paper: 'KODAK CRYSTAL',
        minutes: 9.5,
        tempC: 20,
      ),
      directory: support,
    );

    final int migrated = await library.migrateLegacy(support: support);
    expect(migrated, 1);
    final PrintMeta? marker = await PrintMarker.readMeta(file);
    expect(marker, isNotNull);
    expect(marker?.film, 'KODAK PORTRA 400');
    expect(catalog.printsInLibrary(library.library.id), hasLength(1));
    expect(File('${support.path}/prints.json').existsSync(), isFalse);
    expect(File('${support.path}/prints.json.migrated').existsSync(), isTrue);
  });
}
