import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kallo/lab/catalog.dart';
import 'package:kallo/lab/print_meta.dart';
import 'package:kallo/lab/stock.dart';

void main() {
  final DateTime at = DateTime.utc(2026, 11, 14, 9, 5);

  PrintMeta meta({String? id, String title = 'print 01'}) => PrintMeta(
    id: id ?? PrintMeta.newId(),
    title: title,
    kind: PrintKind.print,
    printed: at,
    added: at.add(const Duration(minutes: 1)),
    updated: at.add(const Duration(minutes: 2)),
    printNumber: 2,
    process: FilmProcess.negative,
    film: 'KODAK PORTRA 400',
    paper: 'KODAK CRYSTAL',
    minutes: 9.5,
    tempC: 20,
  );

  test('the schema opens and a print round-trips', () {
    final Catalog catalog = Catalog.openInMemory();
    addTearDown(catalog.close);

    final CatalogLibrary library = catalog.ensureLibrary(
      kind: LibraryKind.folder,
      root: '/tmp/kallo',
      displayName: 'Kallo',
      now: at,
    );
    expect(library.kind, LibraryKind.folder);

    final PrintMeta record = meta();
    catalog.upsert(
      libraryId: library.id,
      meta: record,
      locator: '/tmp/kallo/print-01.png',
      width: 6000,
      height: 4000,
      fileSize: 1024,
      fileMtimeUs: 99,
      now: at,
    );

    final CatalogPrint? print = catalog.printById(record.id);
    expect(print, isNotNull);
    expect(print?.title, 'print 01');
    expect(print?.film, 'KODAK PORTRA 400');
    expect(print?.width, 6000);
    expect(print?.kind, PrintKind.print);
    expect(print?.meta, record);

    expect(catalog.printsInLibrary(library.id), hasLength(1));
    expect(
      catalog.libraryByRoot(LibraryKind.folder, '/tmp/kallo')?.id,
      library.id,
    );
  });

  test('a locator conflict marks the old print missing', () {
    final Catalog catalog = Catalog.openInMemory();
    addTearDown(catalog.close);
    final CatalogLibrary library = catalog.ensureLibrary(
      kind: LibraryKind.folder,
      root: '/tmp/kallo',
      displayName: 'Kallo',
      now: at,
    );

    final PrintMeta old = meta(title: 'old');
    final PrintMeta replacement = meta(title: 'new');
    catalog.upsert(
      libraryId: library.id,
      meta: old,
      locator: '/tmp/kallo/print.png',
      now: at,
    );
    catalog.upsert(
      libraryId: library.id,
      meta: replacement,
      locator: '/tmp/kallo/print.png',
      now: at.add(const Duration(minutes: 1)),
    );

    expect(catalog.printById(old.id)?.missing, isTrue);
    expect(catalog.printById(replacement.id)?.missing, isFalse);
    expect(catalog.printsInLibrary(library.id), hasLength(1));
    expect(
      catalog.printsInLibrary(library.id, includeMissing: true),
      hasLength(2),
    );
  });

  test('an id can move to a new locator and library', () {
    final Catalog catalog = Catalog.openInMemory();
    addTearDown(catalog.close);
    final CatalogLibrary first = catalog.ensureLibrary(
      kind: LibraryKind.folder,
      root: '/tmp/one',
      displayName: 'One',
      now: at,
    );
    final CatalogLibrary second = catalog.ensureLibrary(
      kind: LibraryKind.folder,
      root: '/tmp/two',
      displayName: 'Two',
      now: at,
    );
    final PrintMeta record = meta();
    catalog.upsert(
      libraryId: first.id,
      meta: record,
      locator: '/tmp/one/print.png',
      now: at,
    );
    catalog.upsert(
      libraryId: second.id,
      meta: record,
      locator: '/tmp/two/print.png',
      now: at,
    );

    expect(catalog.printById(record.id)?.libraryId, second.id);
    expect(catalog.printById(record.id)?.locator, '/tmp/two/print.png');
    expect(catalog.printsInLibrary(first.id), isEmpty);
    expect(catalog.printsInLibrary(second.id), hasLength(1));
  });

  test('missing rows are retained and can come back', () {
    final Catalog catalog = Catalog.openInMemory();
    addTearDown(catalog.close);
    final CatalogLibrary library = catalog.ensureLibrary(
      kind: LibraryKind.folder,
      root: '/tmp/kallo',
      displayName: 'Kallo',
      now: at,
    );
    final PrintMeta record = meta();
    catalog.upsert(
      libraryId: library.id,
      meta: record,
      locator: '/tmp/kallo/print.png',
      now: at,
    );

    catalog.markMissing(record.id, now: at.add(const Duration(minutes: 1)));
    expect(catalog.printById(record.id)?.missing, isTrue);
    expect(catalog.printById(record.id)?.missingSince, isNotNull);
    expect(catalog.printsInLibrary(library.id), isEmpty);

    catalog.upsert(
      libraryId: library.id,
      meta: record,
      locator: '/tmp/kallo/print.png',
      now: at.add(const Duration(minutes: 2)),
    );
    expect(catalog.printById(record.id)?.missing, isFalse);
    expect(catalog.printsInLibrary(library.id), hasLength(1));
  });

  test('deleting a library removes its prints', () {
    final Catalog catalog = Catalog.openInMemory();
    addTearDown(catalog.close);
    final CatalogLibrary library = catalog.ensureLibrary(
      kind: LibraryKind.folder,
      root: '/tmp/kallo',
      displayName: 'Kallo',
      now: at,
    );
    final PrintMeta record = meta();
    catalog.upsert(
      libraryId: library.id,
      meta: record,
      locator: '/tmp/kallo/print.png',
      now: at,
    );
    catalog.deleteLibrary(library.id);
    expect(catalog.printById(record.id), isNull);
  });

  test('the schema survives a file reopen', () {
    final Directory root = Directory.systemTemp.createTempSync('kallo-cat-');
    addTearDown(() => root.deleteSync(recursive: true));
    final File file = File('${root.path}/library.sqlite');

    final Catalog first = Catalog.open(file);
    final CatalogLibrary library = first.ensureLibrary(
      kind: LibraryKind.folder,
      root: '/tmp/kallo',
      displayName: 'Kallo',
      now: at,
    );
    final PrintMeta record = meta();
    first.upsert(
      libraryId: library.id,
      meta: record,
      locator: '/tmp/kallo/print.png',
      now: at,
    );
    first.close();

    final Catalog second = Catalog.open(file);
    addTearDown(second.close);
    expect(second.printById(record.id)?.title, 'print 01');
    expect(second.libraryById(library.id)?.root, '/tmp/kallo');
  });
}
