import 'dart:io';

import 'catalog.dart';
import 'exports.dart';
import 'print.dart';
import 'print_marker.dart';
import 'print_meta.dart';
import 'print_store.dart';
import 'settings.dart';

/// The desktop library: one folder, one catalog, and the records in its files.
///
/// A scan reconciles three things: the files on disk, the XMP marker inside
/// each file, and the catalog row. The catalog is what the rooms read; the
/// marker is what makes the folder portable; the file's own header is what
/// tells the scanner the image is still the image.
class PrintLibrary {
  PrintLibrary._(
    this.catalog,
    this.library,
    this.folder, {
    required this.ownsCatalog,
  });

  final Catalog catalog;
  final CatalogLibrary library;
  final Directory folder;
  final bool ownsCatalog;

  /// Open the app's catalog and attach it to [folder].
  ///
  /// The catalog lives in the app's support folder, not in the picture folder.
  /// The picture folder stays a folder of pictures.
  static PrintLibrary open({required Directory folder, Catalog? catalog}) {
    final Directory? support = Settings.directory;
    final Catalog store =
        catalog ??
        Catalog.open(
          File('${support!.path}${Platform.pathSeparator}library.sqlite'),
        );
    final CatalogLibrary attached = store.ensureLibrary(
      kind: LibraryKind.folder,
      root: folder.path,
      displayName: Exports.display(folder.path),
    );
    return PrintLibrary._(
      store,
      attached,
      folder,
      ownsCatalog: catalog == null,
    );
  }

  /// Read the folder and return the prints the rooms should hang.
  ///
  /// A file with a marker is a print. A file without one is somebody else's
  /// picture unless the catalog already knew the path; that is the case a
  /// marker-stripping editor leaves behind, and the catalog keeps the print
  /// visible.
  Future<List<Print>> read() async {
    if (!folder.existsSync()) {
      return const <Print>[];
    }

    final List<({File file, FileStat stat})> images =
        <({File file, FileStat stat})>[];
    for (final FileSystemEntity entity in folder.listSync()) {
      if (entity is! File || !_isImage(entity.path)) {
        continue;
      }
      try {
        images.add((file: entity, stat: entity.statSync()));
      } on FileSystemException {
        // A file that vanished between list and stat is not a print.
      }
    }
    images.sort((a, b) => a.file.path.compareTo(b.file.path));

    final List<CatalogPrint> rows = catalog.printsInLibrary(
      library.id,
      includeMissing: true,
    );
    final Map<String, CatalogPrint> byId = <String, CatalogPrint>{
      for (final CatalogPrint row in rows) row.id: row,
    };
    final Map<String, CatalogPrint> byLocator = <String, CatalogPrint>{
      for (final CatalogPrint row in rows)
        if (!row.missing) row.locator: row,
    };

    final Set<String> seen = <String>{};
    final List<({CatalogPrint row, ScannedPrint scan, String path})> found =
        <({CatalogPrint row, ScannedPrint scan, String path})>[];

    for (final ({File file, FileStat stat}) image in images) {
      final ScannedPrint? scan = await PrintMarker.read(image.file);
      if (scan == null) {
        continue;
      }
      final PrintMeta? marked = scan.meta;
      if (marked != null) {
        PrintMeta meta = marked;
        if (meta.title.trim().isEmpty) {
          meta = meta.copyWith(title: _stem(image.file.path));
        }
        final CatalogPrint? row = byId[meta.id];
        if (row == null) {
          _upsert(image, meta, scan);
        } else if (meta.updated.isAfter(row.updatedAt)) {
          _upsert(image, meta, scan);
        } else if (row.updatedAt.isAfter(meta.updated)) {
          _touch(image, row, scan, XmpState.stale);
        } else {
          _touch(image, row, scan, XmpState.ok);
        }
        final CatalogPrint? current = catalog.printById(meta.id);
        if (current != null && seen.add(current.id)) {
          found.add((row: current, scan: scan, path: image.file.path));
        }
      } else {
        final CatalogPrint? row = byLocator[image.file.path];
        if (row != null) {
          _touch(image, row, scan, XmpState.missing);
          if (seen.add(row.id)) {
            found.add((row: row, scan: scan, path: image.file.path));
          }
        }
      }
    }

    for (final CatalogPrint row in rows) {
      if (!seen.contains(row.id) && !row.missing) {
        catalog.markMissing(row.id);
      }
    }
    catalog.setLastScan(library.id, DateTime.now());

    found.sort((a, b) => a.row.addedAt.compareTo(b.row.addedAt));
    return <Print>[
      for (final ({CatalogPrint row, ScannedPrint scan, String path}) item
          in found)
        _print(item.row, item.scan, item.path),
    ];
  }

  /// Mark [file] and insert or update its catalog row.
  ///
  /// The final filename is unchanged: the marker is written to a temporary
  /// file and renamed over the print only after the bytes are complete.
  Future<Print> addFile(File file, PrintMeta meta) async {
    await PrintMarker.finalize(file, file, meta);
    final ScannedPrint? scan = await PrintMarker.read(file);
    if (scan == null) {
      throw const FormatException('the print is not a PNG or JPEG');
    }
    final FileStat stat = await file.stat();
    _upsert((file: file, stat: stat), meta, scan, xmpState: XmpState.ok);
    final CatalogPrint? row = catalog.printById(meta.id);
    if (row == null) {
      throw StateError('the catalog did not keep ${meta.id}');
    }
    return _print(row, scan, file.path);
  }

  /// Import the old `prints.json` and the old sidecars once.
  ///
  /// A file gets its marker before its row, so a failure leaves the legacy
  /// store in place and the next launch can retry. The store is renamed only
  /// after every existing record has been migrated.
  Future<int> migrateLegacy({Directory? support}) async {
    support ??= Settings.directory;
    if (support == null || !folder.existsSync()) {
      return 0;
    }
    final Map<String, PrintRecord> records = await PrintStore.load(
      exports: folder,
      frames: Exports.framesFolder(folder),
      directory: support,
    );
    int migrated = 0;
    for (final MapEntry<String, PrintRecord> entry in records.entries) {
      final File file = File(entry.key);
      if (!file.existsSync()) {
        continue;
      }
      ScannedPrint? scan = await PrintMarker.read(file);
      if (scan == null) {
        continue;
      }
      final FileStat stat = await file.stat();
      final PrintMeta meta =
          scan.meta ??
          PrintMeta.fromLegacy(
            record: entry.value,
            title: _stem(file.path),
            printed: stat.modified,
            added: stat.modified,
          );
      if (scan.meta == null) {
        await PrintMarker.finalize(file, file, meta);
        scan = await PrintMarker.read(file);
        if (scan == null) {
          continue;
        }
      }
      _upsert((file: file, stat: stat), meta, scan);
      migrated++;
    }

    final File store = File(
      '${support.path}${Platform.pathSeparator}prints.json',
    );
    if (await store.exists()) {
      final File migratedFile = File('${store.path}.migrated');
      if (await migratedFile.exists()) {
        await migratedFile.delete();
      }
      await store.rename(migratedFile.path);
    }
    return migrated;
  }

  void close() {
    if (ownsCatalog) {
      catalog.close();
    }
  }

  void _upsert(
    ({File file, FileStat stat}) image,
    PrintMeta meta,
    ScannedPrint scan, {
    XmpState xmpState = XmpState.ok,
  }) {
    catalog.upsert(
      libraryId: library.id,
      meta: meta,
      locator: image.file.path,
      width: scan.pixels.width.round(),
      height: scan.pixels.height.round(),
      fileSize: image.stat.size,
      fileMtimeUs: image.stat.modified.microsecondsSinceEpoch,
      xmpState: xmpState,
    );
  }

  void _touch(
    ({File file, FileStat stat}) image,
    CatalogPrint row,
    ScannedPrint scan,
    XmpState state,
  ) {
    catalog.touch(
      printId: row.id,
      libraryId: library.id,
      locator: image.file.path,
      width: scan.pixels.width.round(),
      height: scan.pixels.height.round(),
      fileSize: image.stat.size,
      fileMtimeUs: image.stat.modified.microsecondsSinceEpoch,
      xmpState: state,
    );
  }

  static Print _print(CatalogPrint row, ScannedPrint scan, String path) =>
      Print(
        name: row.title,
        path: path,
        pixels: scan.pixels,
        printNumber: row.printNumber,
        process: row.process,
        printed: row.printedAt ?? row.addedAt,
        film: row.film,
        paper: row.paper,
        minutes: row.minutes,
        tempC: row.tempC,
      );

  static bool _isImage(String path) {
    final String lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
  }

  static String _stem(String path) {
    final int slash = path.lastIndexOf(Platform.pathSeparator);
    final String base = slash < 0 ? path : path.substring(slash + 1);
    final int dot = base.lastIndexOf('.');
    return dot <= 0 ? base : base.substring(0, dot);
  }
}
