import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kallo/lab/catalog.dart';
import 'package:kallo/lab/mobile_print_library.dart';
import 'package:kallo/lab/print.dart';
import 'package:kallo/lab/print_meta.dart';
import 'package:kallo/lab/print_marker.dart';
import 'package:kallo/lab/stock.dart';
import 'package:kallo/lab/system_print_service.dart';

class _FakeSystem extends SystemPrintService {
  _FakeSystem(this.info);

  final SystemLibraryInfo info;
  final List<SystemAsset> assets = <SystemAsset>[];
  final Map<String, File> files = <String, File>{};
  final List<File> picked = <File>[];
  int materialized = 0;

  @override
  Future<SystemLibraryInfo> open() async => info;

  @override
  Future<List<SystemAsset>> list() async => List<SystemAsset>.of(assets);

  @override
  Future<String?> save(File file, String name) async {
    final String locator = 'fake:${assets.length + 1}';
    final File kept = File('${info.temporaryPath}/saved-$locator');
    await file.copy(kept.path);
    final FileStat stat = await kept.stat();
    assets.add(
      SystemAsset(
        locator: locator,
        name: name,
        width: 4,
        height: 3,
        size: stat.size,
        created: DateTime.utc(2026, 11, 14, 9, 5),
        modified: stat.modified,
      ),
    );
    files[locator] = kept;
    return locator;
  }

  @override
  Future<String?> materialize(String locator) async {
    final File? source = files[locator];
    if (source == null) {
      return null;
    }
    materialized++;
    final File copy = File(
      '${info.temporaryPath}/materialized-$materialized.bin',
    );
    await source.copy(copy.path);
    return copy.path;
  }

  @override
  Future<List<File>> pick({int limit = 0}) async =>
      picked.take(limit <= 0 ? picked.length : limit).toList();

  @override
  Future<Uint8List?> thumbnail(String locator, int width) async => null;

  @override
  Future<Uint8List?> image(String locator, int? width) async => null;
}

void main() {
  late Directory root;
  late Catalog catalog;
  late _FakeSystem system;
  late MobilePrintLibrary library;
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

  Future<File> png(Directory folder, String name) async {
    final File file = File('${folder.path}/$name');
    final img.Image picture = img.Image(width: 4, height: 3);
    img.fill(picture, color: img.ColorRgb8(120, 30, 10));
    await file.writeAsBytes(img.encodePng(picture));
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kallo-mobile-');
    final Directory support = Directory('${root.path}/support')..createSync();
    final Directory temporary = Directory('${root.path}/tmp')..createSync();
    system = _FakeSystem(
      SystemLibraryInfo(
        root: 'album:test',
        displayName: 'Photos › Kallo',
        supportPath: support.path,
        temporaryPath: temporary.path,
        available: true,
      ),
    );
    catalog = Catalog.openInMemory();
    library = await MobilePrintLibrary.open(
      service: system,
      catalog: catalog,
      kind: LibraryKind.iosAlbum,
    );
  });

  tearDown(() async {
    catalog.close();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('an album asset with a marker is adopted with its record', () async {
    final File file = await png(root, 'print.png');
    final PrintMeta record = meta();
    await PrintMarker.finalize(file, file, record);
    final FileStat stat = await file.stat();
    system.assets.add(
      SystemAsset(
        locator: 'asset:1',
        name: 'print.png',
        width: 4,
        height: 3,
        size: stat.size,
        created: printed,
        modified: stat.modified,
      ),
    );
    system.files['asset:1'] = file;

    final List<Print> prints = await library.read();
    expect(prints, hasLength(1));
    expect(prints.single.name, 'print 01');
    expect(prints.single.film, 'KODAK PORTRA 400');
    expect(prints.single.path, isNull);
    expect(prints.single.ref?.locator, 'asset:1');
    expect(catalog.printById(record.id)?.xmpState, XmpState.ok);
    expect(system.materialized, 1);
  });

  test('an unmarked album asset is still a print', () async {
    final File file = await png(root, 'holiday.png');
    final FileStat stat = await file.stat();
    system.assets.add(
      SystemAsset(
        locator: 'asset:2',
        name: 'holiday.png',
        width: 4,
        height: 3,
        size: stat.size,
        created: printed,
        modified: stat.modified,
      ),
    );
    system.files['asset:2'] = file;

    final List<Print> prints = await library.read();
    expect(prints, hasLength(1));
    expect(prints.single.name, 'holiday');
    expect(prints.single.film, isNull);
    expect(
      catalog.printsInLibrary(library.library.id).single.xmpState,
      XmpState.missing,
    );
  });

  test('an existing row is not materialised again', () async {
    final File file = await png(root, 'print.png');
    await PrintMarker.finalize(file, file, meta());
    final FileStat stat = await file.stat();
    system.assets.add(
      SystemAsset(
        locator: 'asset:3',
        name: 'print.png',
        width: 4,
        height: 3,
        size: stat.size,
        created: printed,
        modified: stat.modified,
      ),
    );
    system.files['asset:3'] = file;
    await library.read();
    expect(system.materialized, 1);

    await library.read();
    expect(system.materialized, 1);
  });

  test('addFile saves the marked bytes and keeps its row', () async {
    final File file = await png(root, 'new.png');
    final PrintMeta record = meta(title: 'new print');
    final Print print = await library.addFile(file, record);

    final CatalogPrint? row = catalog.printById(record.id);
    expect(row, isNotNull);
    expect(row?.locator, startsWith('fake:'));
    expect(row?.xmpState, XmpState.ok);
    expect(print.name, 'new print');
    expect(system.assets, hasLength(1));

    final List<Print> prints = await library.read();
    expect(prints, hasLength(1));
    expect(prints.single.id, record.id);
  });

  test('an asset that leaves the album keeps its row as missing', () async {
    final File file = await png(root, 'print.png');
    final PrintMeta record = meta();
    await PrintMarker.finalize(file, file, record);
    final FileStat stat = await file.stat();
    system.assets.add(
      SystemAsset(
        locator: 'asset:4',
        name: 'print.png',
        width: 4,
        height: 3,
        size: stat.size,
        created: printed,
        modified: stat.modified,
      ),
    );
    system.files['asset:4'] = file;
    await library.read();

    system.assets.clear();
    final List<Print> prints = await library.read();
    expect(prints, isEmpty);
    expect(catalog.printById(record.id)?.missing, isTrue);
  });

  test('the picker returns local copies for import', () async {
    final File file = await png(root, 'picked.png');
    system.picked.add(file);
    final List<File> picked = await library.pickImages(limit: 1);
    expect(picked.single.path, file.path);
  });
}
