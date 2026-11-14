import 'dart:io';

import 'package:flutter/foundation.dart';

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

  /// Move every existing print to [destination] and return a library attached
  /// there.
  ///
  /// Files are copied with their marker first, the catalog rows are re-homed
  /// second, and the old files are deleted last. A failure before the catalog
  /// step leaves the old folder untouched; a failure after it can be repaired
  /// by the next scan because every new file carries the same `kallo:id`.
  Future<PrintLibrary> moveTo(Directory destination) async {
    if (destination.path == folder.path) {
      return this;
    }
    await destination.create(recursive: true);

    final String separator = Platform.pathSeparator;
    if (destination.path.startsWith('${folder.path}$separator')) {
      throw FileSystemException(
        'the new folder is inside the old one',
        destination.path,
      );
    }

    final CatalogLibrary newLibrary = catalog.ensureLibrary(
      kind: LibraryKind.folder,
      root: destination.path,
      displayName: Exports.display(destination.path),
    );
    final List<CatalogPrint> rows = catalog.printsInLibrary(library.id);
    final List<({CatalogPrint row, File source, File target})> copied =
        <({CatalogPrint row, File source, File target})>[];
    final List<({File source, File target})> frames =
        <({File source, File target})>[];
    final Directory sourceFrames = Exports.framesFolder(folder);
    final Directory targetFrames = Exports.framesFolder(destination);

    try {
      for (final CatalogPrint row in rows) {
        final File source = File(row.locator);
        if (!source.existsSync()) {
          continue;
        }
        final File target = File(
          _uniquePath(destination, source.path, separator),
        );
        await PrintMarker.write(source, target, row.meta);
        final ScannedPrint? check = await PrintMarker.read(target);
        if (check?.meta?.id != row.id) {
          throw FileSystemException(
            'the moved print did not keep its id',
            target.path,
          );
        }
        copied.add((row: row, source: source, target: target));
        if (sourceFrames.existsSync()) {
          final String sourceStem = _stem(source.path);
          final String targetStem = _stem(target.path);
          for (final FileSystemEntity entity in sourceFrames.listSync()) {
            if (entity is! File) {
              continue;
            }
            final String name = _basename(entity.path);
            if (!name.startsWith('$sourceStem-frame.')) {
              continue;
            }
            final String extension = name.substring(sourceStem.length);
            frames.add((
              source: entity,
              target: File(
                '${targetFrames.path}${Platform.pathSeparator}'
                '$targetStem$extension',
              ),
            ));
          }
        }
      }

      if (frames.isNotEmpty) {
        await targetFrames.create(recursive: true);
      }
      for (final ({File source, File target}) frame in frames) {
        await frame.source.copy(frame.target.path);
      }

      for (final ({CatalogPrint row, File source, File target}) item
          in copied) {
        final FileStat stat = await item.target.stat();
        final ScannedPrint? scan = await PrintMarker.read(item.target);
        if (scan == null) {
          throw FileSystemException(
            'the moved print is not readable',
            item.target.path,
          );
        }
        catalog.upsert(
          libraryId: newLibrary.id,
          meta: item.row.meta,
          locator: item.target.path,
          width: scan.pixels.width.round(),
          height: scan.pixels.height.round(),
          fileSize: stat.size,
          fileMtimeUs: stat.modified.microsecondsSinceEpoch,
        );
      }
    } on Object {
      for (final ({CatalogPrint row, File source, File target}) item
          in copied) {
        try {
          if (await item.target.exists()) {
            await item.target.delete();
          }
        } on FileSystemException {
          // A partial copy is a cache of nothing; leave the error visible.
        }
      }
      for (final ({File source, File target}) frame in frames) {
        try {
          if (await frame.target.exists()) {
            await frame.target.delete();
          }
        } on FileSystemException {
          // The next move can replace an orphaned frame.
        }
      }
      rethrow;
    }

    for (final ({CatalogPrint row, File source, File target}) item in copied) {
      try {
        await item.source.delete();
      } on FileSystemException {
        // The catalog already points at the new copy; an old copy is a
        // duplicate for the person to remove, not a reason to fail the move.
      }
    }
    for (final ({File source, File target}) frame in frames) {
      try {
        await frame.source.delete();
      } on FileSystemException {
        // A frame is a derived export; an old copy is harmless.
      }
    }

    return PrintLibrary._(
      catalog,
      newLibrary,
      destination,
      ownsCatalog: ownsCatalog,
    );
  }

  /// Rewrite the marker for every print whose catalog record says it is
  /// missing or stale and whose file still exists.
  ///
  /// A missing file has no marker to write; its row stays in the catalog and
  /// the person can locate it. This is a repair, not a discovery.
  Future<int> repairMarkers() async {
    final List<CatalogPrint> rows = catalog.printsInLibrary(
      library.id,
      includeMissing: true,
    );
    int repaired = 0;
    for (final CatalogPrint row in rows) {
      if (row.xmpState != XmpState.missing && row.xmpState != XmpState.stale) {
        continue;
      }
      final File file = File(row.locator);
      if (!file.existsSync()) {
        continue;
      }
      try {
        await PrintMarker.finalize(file, file, row.meta);
        final ScannedPrint? scan = await PrintMarker.read(file);
        if (scan == null) {
          continue;
        }
        final FileStat stat = await file.stat();
        catalog.touch(
          printId: row.id,
          libraryId: library.id,
          locator: file.path,
          width: scan.pixels.width.round(),
          height: scan.pixels.height.round(),
          fileSize: stat.size,
          fileMtimeUs: stat.modified.microsecondsSinceEpoch,
          xmpState: XmpState.ok,
        );
        repaired++;
      } on Object catch (error) {
        debugPrint('the marker for ${file.path} could not be repaired: $error');
      }
    }
    return repaired;
  }

  /// Attach a library to [destination] without moving any files.
  PrintLibrary switchTo(Directory destination) {
    final CatalogLibrary next = catalog.ensureLibrary(
      kind: LibraryKind.folder,
      root: destination.path,
      displayName: Exports.display(destination.path),
    );
    return PrintLibrary._(catalog, next, destination, ownsCatalog: ownsCatalog);
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

  static String _uniquePath(
    Directory folder,
    String sourcePath,
    String separator,
  ) {
    final String base = sourcePath.substring(
      sourcePath.lastIndexOf(separator) + 1,
    );
    final int dot = base.lastIndexOf('.');
    final String stem = dot <= 0 ? base : base.substring(0, dot);
    final String extension = dot <= 0 ? '' : base.substring(dot);
    int index = 1;
    File candidate = File('${folder.path}$separator$base');
    while (candidate.existsSync()) {
      index++;
      candidate = File('${folder.path}$separator$stem-$index$extension');
    }
    return candidate.path;
  }

  static bool _isImage(String path) {
    final String lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
  }

  static String _basename(String path) {
    final int slash = path.lastIndexOf(Platform.pathSeparator);
    return slash < 0 ? path : path.substring(slash + 1);
  }

  static String _stem(String path) {
    final int slash = path.lastIndexOf(Platform.pathSeparator);
    final String base = slash < 0 ? path : path.substring(slash + 1);
    final int dot = base.lastIndexOf('.');
    return dot <= 0 ? base : base.substring(0, dot);
  }
}
