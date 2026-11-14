import 'dart:math';

import 'package:flutter/foundation.dart';

import 'print.dart';
import 'stock.dart';

/// What a Kallo print is, apart from its pixels.
///
/// The catalog and the XMP marker both carry this record. The two are written
/// together: the catalog is what the app reads, and the marker is what travels
/// with the file. Neither is allowed to hold a user-facing field the other one
/// does not have.
enum PrintKind {
  print,
  import;

  static PrintKind parse(String? value) =>
      value == import.name ? import : print;
}

/// A print record with identity and provenance.
///
/// [PrintRecord] is the darkroom's record: the film, the paper, the development.
/// This is that record plus the facts a library needs: an id that survives a
/// copy, a title that survives a filename collision, and the two dates that make
/// ordering honest — when the print was made and when it entered this library.
@immutable
class PrintMeta {
  const PrintMeta({
    required this.id,
    required this.title,
    required this.kind,
    required this.printed,
    required this.added,
    required this.updated,
    this.schema = 1,
    this.printNumber = 1,
    this.process,
    this.film,
    this.paper,
    this.minutes,
    this.tempC,
    this.sourceName,
  });

  /// A new identity. UUID v4, lower-case, stable for the life of the print.
  static String newId() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  /// The record as it was before the catalog existed.
  ///
  /// A legacy record has no identity, title or dates. The caller supplies the
  /// file's own facts: the stem is the title, and the modification time is the
  /// only date a folder ever had.
  factory PrintMeta.fromLegacy({
    required PrintRecord record,
    required String title,
    required DateTime printed,
    DateTime? added,
    DateTime? updated,
    String? id,
    PrintKind kind = PrintKind.print,
    String? sourceName,
  }) {
    final DateTime made = printed.toUtc();
    return PrintMeta(
      id: id ?? newId(),
      title: title,
      kind: kind,
      printed: made,
      added: (added ?? made).toUtc(),
      updated: (updated ?? DateTime.now()).toUtc(),
      printNumber: record.printNumber,
      process: record.process,
      film: record.film,
      paper: record.paper,
      minutes: record.minutes,
      tempC: record.tempC,
      sourceName: sourceName,
    );
  }

  /// The identity. `kallo:id` in XMP; the catalog's primary key.
  final String id;

  /// The schema this record was written with. A newer schema is read with the
  /// fields this version knows and is never rewritten.
  final int schema;

  /// Whether this print was made by the darkroom or adopted from outside.
  final PrintKind kind;

  /// The display name. It is not the filename: a migration may have to rename
  /// a file to avoid a collision, and the print's name should not change.
  final String title;

  /// When the print was made, in UTC.
  final DateTime printed;

  /// When the print entered this library, in UTC.
  final DateTime added;

  /// When this record last changed, in UTC. The reconciliation clock.
  final DateTime updated;

  final int printNumber;
  final FilmProcess? process;
  final String? film;
  final String? paper;
  final double? minutes;
  final double? tempC;

  /// The original filename of an import, never a path.
  final String? sourceName;

  /// The darkroom's part of the record.
  PrintRecord get record => PrintRecord(
    printNumber: printNumber,
    process: process,
    film: film,
    paper: paper,
    minutes: minutes,
    tempC: tempC,
  );

  /// A copy with the fields the caller can change. Nullable fields use a
  /// sentinel so that clearing a film is different from leaving it alone.
  PrintMeta copyWith({
    String? id,
    int? schema,
    PrintKind? kind,
    String? title,
    DateTime? printed,
    DateTime? added,
    DateTime? updated,
    int? printNumber,
    Object? process = _unset,
    Object? film = _unset,
    Object? paper = _unset,
    Object? minutes = _unset,
    Object? tempC = _unset,
    Object? sourceName = _unset,
  }) => PrintMeta(
    id: id ?? this.id,
    schema: schema ?? this.schema,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    printed: (printed ?? this.printed).toUtc(),
    added: (added ?? this.added).toUtc(),
    updated: (updated ?? this.updated).toUtc(),
    printNumber: printNumber ?? this.printNumber,
    process: identical(process, _unset)
        ? this.process
        : process as FilmProcess?,
    film: identical(film, _unset) ? this.film : film as String?,
    paper: identical(paper, _unset) ? this.paper : paper as String?,
    minutes: identical(minutes, _unset)
        ? this.minutes
        : (minutes as num?)?.toDouble(),
    tempC: identical(tempC, _unset) ? this.tempC : (tempC as num?)?.toDouble(),
    sourceName: identical(sourceName, _unset)
        ? this.sourceName
        : sourceName as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is PrintMeta &&
      other.id == id &&
      other.schema == schema &&
      other.kind == kind &&
      other.title == title &&
      other.printed == printed &&
      other.added == added &&
      other.updated == updated &&
      other.printNumber == printNumber &&
      other.process == process &&
      other.film == film &&
      other.paper == paper &&
      other.minutes == minutes &&
      other.tempC == tempC &&
      other.sourceName == sourceName;

  @override
  int get hashCode => Object.hash(
    id,
    schema,
    kind,
    title,
    printed,
    added,
    updated,
    printNumber,
    process,
    film,
    paper,
    minutes,
    tempC,
    sourceName,
  );
}

const Object _unset = Object();
