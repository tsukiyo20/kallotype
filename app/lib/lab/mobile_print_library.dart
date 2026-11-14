import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'print.dart';
import 'print_library.dart';
import 'print_marker.dart';
import 'print_meta.dart';
import 'settings.dart';
import 'system_print_service.dart';

/// A print library the platform owns: Photos on iOS, MediaStore on Android.
///
/// The catalog and the marker are the same as on desktop. The difference is
/// the locator: an album identifier is not a path, and the app never sees the
/// original file unless it asks the platform for it.
///
/// A picture in the album is a print even when its marker was lost. That is the
/// opposite of the desktop rule, where an unmarked file the catalog has never
/// seen is somebody else's picture; here the album is the boundary. Adoption
/// reads the marker when it can, and otherwise makes a minimal neutral record
/// the catalog can repair later.
class MobilePrintLibrary extends PrintLibrary {
  MobilePrintLibrary({
    required this.service,
    required this.catalog,
    required this.library,
    required this.info,
    required this.workFolder,
    required this.ownsCatalog,
  });

  final SystemPrintService service;

  @override
  final Catalog catalog;

  @override
  final CatalogLibrary library;

  final SystemLibraryInfo info;

  @override
  final Directory workFolder;

  final bool ownsCatalog;

  static Future<MobilePrintLibrary> open({
    SystemPrintService? service,
    Catalog? catalog,
    LibraryKind? kind,
  }) async {
    final SystemPrintService bridge = service ?? SystemPrintService();
    final SystemLibraryInfo info = await bridge.open();
    final Directory support = Directory(
      info.supportPath.isEmpty
          ? (Settings.directory?.path ?? Directory.systemTemp.path)
          : info.supportPath,
    );
    support.createSync(recursive: true);
    Settings.useDirectory(support);

    final Catalog store =
        catalog ??
        Catalog.open(
          File('${support.path}${Platform.pathSeparator}library.sqlite'),
        );
    final LibraryKind libraryKind =
        kind ??
        (Platform.isIOS ? LibraryKind.iosAlbum : LibraryKind.androidFolder);
    final CatalogLibrary attached = store.ensureLibrary(
      kind: libraryKind,
      root: info.root,
      displayName: info.displayName,
    );
    final Directory work = Directory(
      '${info.temporaryPath}${Platform.pathSeparator}Kallo',
    );
    await work.create(recursive: true);
    return MobilePrintLibrary(
      service: bridge,
      catalog: store,
      library: attached,
      info: info,
      workFolder: work,
      ownsCatalog: catalog == null,
    );
  }

  @override
  Directory? get folder => null;

  @override
  String get locationLabel => info.displayName;

  @override
  bool get canChooseFolder => false;

  @override
  bool get canListAll => info.canListAll;

  @override
  bool get canPickImages => true;

  @override
  Future<List<Print>> read() async {
    final List<SystemAsset> assets = await service.list();
    final List<CatalogPrint> rows = catalog.printsInLibrary(
      library.id,
      includeMissing: true,
    );
    final Map<String, CatalogPrint> byLocator = <String, CatalogPrint>{
      for (final CatalogPrint row in rows)
        if (!row.missing) row.locator: row,
    };

    final Set<String> seen = <String>{};
    final List<CatalogPrint> found = <CatalogPrint>[];
    for (final SystemAsset asset in assets) {
      if (asset.locator.isEmpty) {
        continue;
      }
      CatalogPrint? row = byLocator[asset.locator];
      if (row == null) {
        row = await _adopt(asset);
      } else {
        catalog.touch(
          printId: row.id,
          libraryId: library.id,
          locator: asset.locator,
          width: asset.width > 0 ? asset.width : row.width,
          height: asset.height > 0 ? asset.height : row.height,
          fileSize: asset.size > 0 ? asset.size : row.fileSize,
          fileMtimeUs: asset.modified?.microsecondsSinceEpoch,
        );
        row = catalog.printById(row.id) ?? row;
      }
      if (row != null && seen.add(row.id)) {
        found.add(row);
      }
    }

    for (final CatalogPrint row in rows) {
      if (!seen.contains(row.id) && !row.missing) {
        catalog.markMissing(row.id);
      }
    }
    catalog.setLastScan(library.id, DateTime.now());
    found.sort((a, b) => a.addedAt.compareTo(b.addedAt));

    return <Print>[
      for (final CatalogPrint row in found)
        Print(
          id: row.id,
          name: row.title,
          pixels: _pixels(row),
          printNumber: row.printNumber,
          process: row.process,
          printed: row.printedAt ?? row.addedAt,
          film: row.film,
          paper: row.paper,
          minutes: row.minutes,
          tempC: row.tempC,
          ref: SystemPrintRef(
            service: service,
            locator: row.locator,
            name: row.title,
          ),
        ),
    ];
  }

  @override
  Future<Print> addFile(File file, PrintMeta meta) async {
    await PrintMarker.finalize(file, file, meta);
    final ScannedPrint? scan = await PrintMarker.read(file);
    if (scan == null) {
      throw const FormatException('the print is not a PNG or JPEG');
    }
    final FileStat stat = await file.stat();
    final String? locator = await service.save(
      file,
      _displayName(meta, scan.format),
    );
    if (locator == null || locator.isEmpty) {
      throw StateError('the photo library did not keep the print');
    }
    catalog.upsert(
      libraryId: library.id,
      meta: meta,
      locator: locator,
      width: scan.pixels.width.round(),
      height: scan.pixels.height.round(),
      fileSize: stat.size,
      fileMtimeUs: stat.modified.microsecondsSinceEpoch,
      xmpState: XmpState.ok,
    );
    final CatalogPrint? row = catalog.printById(meta.id);
    if (row == null) {
      throw StateError('the catalog did not keep ${meta.id}');
    }
    return Print(
      id: row.id,
      name: row.title,
      pixels: scan.pixels,
      printNumber: row.printNumber,
      process: row.process,
      printed: row.printedAt ?? row.addedAt,
      film: row.film,
      paper: row.paper,
      minutes: row.minutes,
      tempC: row.tempC,
      ref: SystemPrintRef(
        service: service,
        locator: row.locator,
        name: row.title,
      ),
    );
  }

  @override
  Future<int> repairMarkers() async {
    // A system asset cannot be written in place. Repair means saving a marked
    // copy over the asset, and on iOS that is a new asset and a delete. Until
    // that replacement path exists, the next import or save is what writes a
    // marker; the catalog row and its picture stay.
    return 0;
  }

  @override
  Future<List<File>> pickImages({int limit = 0}) => service.pick(limit: limit);

  @override
  void close() {
    if (ownsCatalog) {
      catalog.close();
    }
  }

  Future<CatalogPrint?> _adopt(SystemAsset asset) async {
    ScannedPrint? scan;
    File? temp;
    try {
      final String? path = await service.materialize(asset.locator);
      if (path != null) {
        temp = File(path);
        if (await temp.exists()) {
          scan = await PrintMarker.read(temp);
        }
      }
    } on Object catch (error) {
      debugPrint('the marker for ${asset.name} could not be read: $error');
    } finally {
      if (temp != null) {
        try {
          if (await temp.exists()) {
            await temp.delete();
          }
        } on FileSystemException {
          // A temporary copy the system cleans up later is not a failure.
        }
      }
    }

    final DateTime now = DateTime.now().toUtc();
    PrintMeta? meta = scan?.meta;
    if (meta == null) {
      meta = PrintMeta(
        id: PrintMeta.newId(),
        title: _stem(asset.name),
        kind: PrintKind.import,
        printed: asset.created ?? now,
        added: now,
        updated: now,
        sourceName: asset.name,
      );
    } else if (meta.title.trim().isEmpty) {
      meta = meta.copyWith(title: _stem(asset.name));
    }

    final int width = asset.width > 0
        ? asset.width
        : (scan?.pixels.width.round() ?? 0);
    final int height = asset.height > 0
        ? asset.height
        : (scan?.pixels.height.round() ?? 0);
    catalog.upsert(
      libraryId: library.id,
      meta: meta,
      locator: asset.locator,
      width: width > 0 ? width : null,
      height: height > 0 ? height : null,
      fileSize: asset.size > 0 ? asset.size : null,
      fileMtimeUs: asset.modified?.microsecondsSinceEpoch,
      xmpState: scan?.meta == null ? XmpState.missing : XmpState.ok,
    );
    return catalog.printById(meta.id);
  }

  static Size? _pixels(CatalogPrint row) {
    final int? width = row.width;
    final int? height = row.height;
    return width == null || height == null || width <= 0 || height <= 0
        ? null
        : Size(width.toDouble(), height.toDouble());
  }

  static String _displayName(PrintMeta meta, PrintImageFormat format) {
    final String title = meta.title
        .replaceAll(RegExp(r'[/\\]'), '-')
        .replaceAll(RegExp(r'^\s+|\s+$'), '');
    final String stem = title.isEmpty ? 'print' : title;
    return '$stem.${format == PrintImageFormat.png ? 'png' : 'jpg'}';
  }

  static String _stem(String name) {
    final int dot = name.lastIndexOf('.');
    final String stem = dot <= 0 ? name : name.substring(0, dot);
    return stem.trim().isEmpty ? 'print' : stem;
  }
}
