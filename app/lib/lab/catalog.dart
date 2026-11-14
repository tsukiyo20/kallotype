import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'print_meta.dart';
import 'stock.dart';

/// What a library is.
enum LibraryKind {
  folder,
  iosAlbum,
  androidFolder;

  static LibraryKind parse(String value) =>
      LibraryKind.values.firstWhere((LibraryKind kind) => kind.name == value);
}

/// How the portable copy of a record is doing.
enum XmpState {
  ok,
  missing,
  stale,
  unreadable,
  notRead;

  static XmpState parse(String value) =>
      XmpState.values.firstWhere((XmpState state) => state.name == value);
}

/// One library the catalog knows: a folder, an iOS album, an Android folder.
@immutable
class CatalogLibrary {
  const CatalogLibrary({
    required this.id,
    required this.kind,
    required this.root,
    required this.displayName,
    required this.createdAt,
    this.lastScanAt,
  });

  final String id;
  final LibraryKind kind;
  final String root;
  final String displayName;
  final DateTime createdAt;
  final DateTime? lastScanAt;
}

/// One print as the catalog sees it.
@immutable
class CatalogPrint {
  const CatalogPrint({
    required this.id,
    required this.libraryId,
    required this.locator,
    required this.title,
    required this.kind,
    required this.printedAt,
    required this.addedAt,
    required this.printNumber,
    required this.createdAt,
    required this.updatedAt,
    required this.xmpState,
    required this.missing,
    this.process,
    this.film,
    this.paper,
    this.minutes,
    this.tempC,
    this.sourceName,
    this.width,
    this.height,
    this.fileSize,
    this.fileMtimeUs,
    this.contentHash,
    this.missingSince,
  });

  final String id;
  final String libraryId;
  final String locator;
  final String title;
  final PrintKind kind;
  final DateTime? printedAt;
  final DateTime addedAt;
  final DateTime updatedAt;
  final int printNumber;
  final FilmProcess? process;
  final String? film;
  final String? paper;
  final double? minutes;
  final double? tempC;
  final String? sourceName;
  final int? width;
  final int? height;
  final int? fileSize;
  final int? fileMtimeUs;
  final String? contentHash;
  final XmpState xmpState;
  final bool missing;
  final DateTime? missingSince;
  final DateTime createdAt;

  PrintMeta get meta => PrintMeta(
    id: id,
    title: title,
    kind: kind,
    printed: printedAt ?? addedAt,
    added: addedAt,
    updated: updatedAt,
    printNumber: printNumber,
    process: process,
    film: film,
    paper: paper,
    minutes: minutes,
    tempC: tempC,
    sourceName: sourceName,
  );
}

/// The SQLite catalog.
///
/// The catalog is authoritative for the running library. The XMP marker is the
/// print's portable record; [PrintMarker] is the other half of the pair.
///
/// All methods are synchronous. SQLite is fast enough for the desktop library;
/// callers that scan a folder run this on one isolate and serialize writes.
class Catalog {
  Catalog._(this.db);

  final Database db;

  static const int schemaVersion = 1;

  /// Open the catalog, creating the parent folder and the schema if needed.
  static Catalog open(File file) {
    file.parent.createSync(recursive: true);
    final Database database = sqlite3.open(file.path);
    final Catalog catalog = Catalog._(database);
    try {
      catalog._configure();
      catalog._migrate();
      return catalog;
    } on Object {
      database.close();
      rethrow;
    }
  }

  /// An empty catalog for tests and for a temporary library.
  static Catalog openInMemory() {
    final Database database = sqlite3.openInMemory();
    final Catalog catalog = Catalog._(database);
    try {
      catalog._configure();
      catalog._migrate();
      return catalog;
    } on Object {
      database.close();
      rethrow;
    }
  }

  void _configure() {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA busy_timeout = 5000');
  }

  void _migrate() {
    final int version =
        db.select('PRAGMA user_version').first.columnAt(0) as int? ?? 0;
    if (version > schemaVersion) {
      throw StateError(
        'this catalog is newer than this Kallo (schema $version)',
      );
    }
    if (version == 0) {
      db.execute('''
        CREATE TABLE libraries (
          id            TEXT PRIMARY KEY,
          kind          TEXT NOT NULL,
          root          TEXT NOT NULL,
          display_name  TEXT NOT NULL,
          created_at    TEXT NOT NULL,
          last_scan_at  TEXT,
          UNIQUE (kind, root)
        );

        CREATE TABLE prints (
          id             TEXT PRIMARY KEY,
          library_id     TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
          locator        TEXT NOT NULL,
          title          TEXT NOT NULL,
          kind           TEXT NOT NULL CHECK (kind IN ('print', 'import')),
          printed_at     TEXT,
          added_at       TEXT NOT NULL,
          print_number   INTEGER NOT NULL DEFAULT 1,
          process        TEXT,
          film           TEXT,
          paper          TEXT,
          minutes        REAL,
          temp_c         REAL,
          source_name    TEXT,
          width          INTEGER,
          height         INTEGER,
          file_size      INTEGER,
          file_mtime_us  INTEGER,
          content_hash   TEXT,
          xmp_state      TEXT NOT NULL DEFAULT 'ok',
          missing        INTEGER NOT NULL DEFAULT 0,
          missing_since  TEXT,
          created_at     TEXT NOT NULL,
          updated_at     TEXT NOT NULL
        );

        CREATE INDEX prints_added   ON prints (library_id, added_at);
        CREATE INDEX prints_printed ON prints (library_id, printed_at);
        CREATE INDEX prints_missing ON prints (library_id, missing);
        CREATE INDEX prints_title   ON prints (title);
        CREATE UNIQUE INDEX prints_locator
          ON prints (library_id, locator) WHERE missing = 0;

        PRAGMA user_version = 1;
      ''');
    }
  }

  /// The library for a root, or a new one.
  CatalogLibrary ensureLibrary({
    required LibraryKind kind,
    required String root,
    required String displayName,
    String? id,
    DateTime? now,
  }) {
    final CatalogLibrary? existing = libraryByRoot(kind, root);
    if (existing != null) {
      return existing;
    }
    final DateTime created = (now ?? DateTime.now()).toUtc();
    final String libraryId = id ?? PrintMeta.newId();
    db.execute(
      'INSERT INTO libraries '
      '(id, kind, root, display_name, created_at) VALUES (?, ?, ?, ?, ?)',
      <Object?>[libraryId, kind.name, root, displayName, _date(created)],
    );
    return CatalogLibrary(
      id: libraryId,
      kind: kind,
      root: root,
      displayName: displayName,
      createdAt: created,
    );
  }

  CatalogLibrary? libraryByRoot(LibraryKind kind, String root) {
    final ResultSet rows = db.select(
      'SELECT * FROM libraries WHERE kind = ? AND root = ?',
      <Object?>[kind.name, root],
    );
    return rows.isEmpty ? null : _library(rows.first);
  }

  CatalogLibrary? libraryById(String id) {
    final ResultSet rows = db.select(
      'SELECT * FROM libraries WHERE id = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : _library(rows.first);
  }

  /// Insert or update one print. A locator conflict with another print marks
  /// the other print missing; the path now belongs to the new id.
  void upsert({
    required String libraryId,
    required PrintMeta meta,
    required String locator,
    int? width,
    int? height,
    int? fileSize,
    int? fileMtimeUs,
    XmpState xmpState = XmpState.ok,
    bool missing = false,
    DateTime? now,
  }) {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    db.execute('BEGIN IMMEDIATE');
    try {
      final ResultSet conflict = db.select(
        'SELECT id FROM prints '
        'WHERE library_id = ? AND locator = ? AND id <> ? AND missing = 0',
        <Object?>[libraryId, locator, meta.id],
      );
      for (final Row row in conflict) {
        db.execute(
          'UPDATE prints SET missing = 1, missing_since = ?, updated_at = ? '
          'WHERE id = ?',
          <Object?>[_date(stamp), _date(stamp), row['id']],
        );
      }
      db.execute(
        '''
        INSERT INTO prints (
          id, library_id, locator, title, kind, printed_at, added_at,
          print_number, process, film, paper, minutes, temp_c, source_name,
          width, height, file_size, file_mtime_us, xmp_state, missing,
          missing_since, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                  ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          library_id = excluded.library_id,
          locator = excluded.locator,
          title = excluded.title,
          kind = excluded.kind,
          printed_at = excluded.printed_at,
          added_at = excluded.added_at,
          print_number = excluded.print_number,
          process = excluded.process,
          film = excluded.film,
          paper = excluded.paper,
          minutes = excluded.minutes,
          temp_c = excluded.temp_c,
          source_name = excluded.source_name,
          width = excluded.width,
          height = excluded.height,
          file_size = excluded.file_size,
          file_mtime_us = excluded.file_mtime_us,
          xmp_state = excluded.xmp_state,
          missing = excluded.missing,
          missing_since = excluded.missing_since,
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          meta.id,
          libraryId,
          locator,
          meta.title,
          meta.kind.name,
          _dateOrNull(meta.printed),
          _date(meta.added),
          meta.printNumber,
          meta.process?.name,
          meta.film,
          meta.paper,
          meta.minutes,
          meta.tempC,
          meta.sourceName,
          width,
          height,
          fileSize,
          fileMtimeUs,
          xmpState.name,
          missing ? 1 : 0,
          missing ? _date(stamp) : null,
          _date(stamp),
          _date(meta.updated),
        ],
      );
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  CatalogPrint? printById(String id) {
    final ResultSet rows = db.select(
      'SELECT * FROM prints WHERE id = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : _print(rows.first);
  }

  CatalogPrint? printByLocator(String libraryId, String locator) {
    final ResultSet rows = db.select(
      'SELECT * FROM prints '
      'WHERE library_id = ? AND locator = ? AND missing = 0',
      <Object?>[libraryId, locator],
    );
    return rows.isEmpty ? null : _print(rows.first);
  }

  /// Prints in one library, oldest first by the time they entered it.
  List<CatalogPrint> printsInLibrary(
    String libraryId, {
    bool includeMissing = false,
  }) {
    final ResultSet rows = db.select(
      'SELECT * FROM prints WHERE library_id = ?'
      '${includeMissing ? '' : ' AND missing = 0'} '
      'ORDER BY added_at ASC, title ASC',
      <Object?>[libraryId],
    );
    return <CatalogPrint>[for (final Row row in rows) _print(row)];
  }

  /// Update only the file-side facts for an existing print, without touching
  /// the record's metadata or its `updated_at`.
  void touch({
    required String printId,
    required String libraryId,
    required String locator,
    int? width,
    int? height,
    int? fileSize,
    int? fileMtimeUs,
    XmpState? xmpState,
    bool missing = false,
  }) {
    db.execute(
      'UPDATE prints SET library_id = ?, locator = ?, width = ?, height = ?, '
      'file_size = ?, file_mtime_us = ?, xmp_state = COALESCE(?, xmp_state), '
      'missing = ?, '
      'missing_since = ? WHERE id = ?',
      <Object?>[
        libraryId,
        locator,
        width,
        height,
        fileSize,
        fileMtimeUs,
        xmpState?.name,
        missing ? 1 : 0,
        missing ? _date(DateTime.now().toUtc()) : null,
        printId,
      ],
    );
  }

  void markMissing(String printId, {DateTime? now}) {
    final DateTime stamp = (now ?? DateTime.now()).toUtc();
    db.execute(
      'UPDATE prints SET missing = 1, missing_since = ?, updated_at = ? '
      'WHERE id = ? AND missing = 0',
      <Object?>[_date(stamp), _date(stamp), printId],
    );
  }

  void setXmpState(String printId, XmpState state) {
    db.execute('UPDATE prints SET xmp_state = ? WHERE id = ?', <Object?>[
      state.name,
      printId,
    ]);
  }

  void setLastScan(String libraryId, DateTime at) {
    db.execute('UPDATE libraries SET last_scan_at = ? WHERE id = ?', <Object?>[
      _date(at.toUtc()),
      libraryId,
    ]);
  }

  void deleteLibrary(String id) {
    db.execute('DELETE FROM libraries WHERE id = ?', <Object?>[id]);
  }

  void close() => db.close();

  static CatalogLibrary _library(Row row) => CatalogLibrary(
    id: row['id'] as String,
    kind: LibraryKind.parse(row['kind'] as String),
    root: row['root'] as String,
    displayName: row['display_name'] as String,
    createdAt: _parse(row['created_at'] as String)!,
    lastScanAt: _parse(row['last_scan_at'] as String?),
  );

  static CatalogPrint _print(Row row) => CatalogPrint(
    id: row['id'] as String,
    libraryId: row['library_id'] as String,
    locator: row['locator'] as String,
    title: row['title'] as String,
    kind: PrintKind.parse(row['kind'] as String),
    printedAt: _parse(row['printed_at'] as String?),
    addedAt: _parse(row['added_at'] as String)!,
    updatedAt: _parse(row['updated_at'] as String)!,
    printNumber: row['print_number'] as int,
    process: _process(row['process'] as String?),
    film: row['film'] as String?,
    paper: row['paper'] as String?,
    minutes: (row['minutes'] as num?)?.toDouble(),
    tempC: (row['temp_c'] as num?)?.toDouble(),
    sourceName: row['source_name'] as String?,
    width: row['width'] as int?,
    height: row['height'] as int?,
    fileSize: row['file_size'] as int?,
    fileMtimeUs: row['file_mtime_us'] as int?,
    contentHash: row['content_hash'] as String?,
    xmpState: XmpState.parse(row['xmp_state'] as String),
    missing: (row['missing'] as int) != 0,
    missingSince: _parse(row['missing_since'] as String?),
    createdAt: _parse(row['created_at'] as String)!,
  );

  static FilmProcess? _process(String? value) => switch (value) {
    'negative' => FilmProcess.negative,
    'reversal' => FilmProcess.reversal,
    'monochrome' => FilmProcess.monochrome,
    _ => null,
  };

  static String _date(DateTime date) => date.toUtc().toIso8601String();

  static String? _dateOrNull(DateTime? date) =>
      date == null ? null : _date(date);

  static DateTime? _parse(String? value) =>
      value == null ? null : DateTime.tryParse(value)?.toUtc();
}
