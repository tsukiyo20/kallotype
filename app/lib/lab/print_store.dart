import 'dart:convert';
import 'dart:io';

import 'print.dart';
import 'settings.dart';

/// Print metadata, kept in the app's own support folder.
///
/// A JSON sidecar beside every PNG made the export folder a directory of
/// pictures and records. The records still have to exist — the gallery needs
/// the stock, the paper, the development and the print number — but they
/// belong to the app, not to the person's folder. One file, keyed by the
/// print's path.
///
/// On the first read after this change, old sidecars are imported and then
/// deleted. The file names and the record shape are the app's own; a JSON that
/// is not one of those is left alone.
abstract final class PrintStore {
  static const String _name = 'prints.json';

  static File? _fileFor(Directory? directory) {
    final Directory? folder = directory ?? Settings.directory;
    if (folder == null) {
      return null;
    }
    return File('${folder.path}${Platform.pathSeparator}$_name');
  }

  /// Read the store, import any old sidecars in [exports], and drop the old
  /// frame records in [frames].
  ///
  /// [directory] is the app's support folder; tests pass one. The store is
  /// written before any sidecar is deleted, so a failed write cannot lose the
  /// metadata it was importing.
  static Future<Map<String, PrintRecord>> load({
    Directory? exports,
    Directory? frames,
    Directory? directory,
  }) async {
    final Map<String, PrintRecord> records = await _read(directory);

    final List<File> obsolete = <File>[];
    bool changed = false;
    if (exports != null && exports.existsSync()) {
      for (final FileSystemEntity entity in exports.listSync()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
          continue;
        }
        final String stem = _stem(entity.path);
        final File image = File('$stem.png');
        if (!image.existsSync()) {
          continue;
        }
        final Map<String, dynamic>? json = _json(entity);
        if (json == null || !PrintRecord.looksLikeSidecar(json)) {
          continue;
        }
        final PrintRecord? record = PrintRecord.fromJson(json);
        if (record == null) {
          continue;
        }
        records[image.path] = record;
        obsolete.add(entity);
        changed = true;
      }
    }

    if (changed) {
      final bool saved = await _write(records, directory);
      if (saved) {
        for (final File file in obsolete) {
          try {
            await file.delete();
          } on FileSystemException {
            // A record that stays is not a reason to fail the gallery.
          }
        }
      }
    }

    if (frames != null && frames.existsSync()) {
      for (final FileSystemEntity entity in frames.listSync()) {
        if (entity is! File || !entity.path.endsWith('-frame.json')) {
          continue;
        }
        final Map<String, dynamic>? json = _json(entity);
        if (json != null && json['border'] == '35mm') {
          try {
            await entity.delete();
          } on FileSystemException {
            // The frame record is not read; a leftover is harmless.
          }
        }
      }
    }

    return records;
  }

  /// Remember the record for one exported print.
  static Future<void> remember(
    File print,
    PrintRecord record, {
    Directory? directory,
  }) async {
    final Map<String, PrintRecord> records = await _read(directory);
    records[print.path] = record;
    await _write(records, directory);
  }

  static Future<Map<String, PrintRecord>> _read(Directory? directory) async {
    final File? file = _fileFor(directory);
    if (file == null || !file.existsSync()) {
      return <String, PrintRecord>{};
    }
    try {
      final Object? json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) {
        return <String, PrintRecord>{};
      }
      final Map<String, PrintRecord> records = <String, PrintRecord>{};
      for (final MapEntry<String, dynamic> entry in json.entries) {
        final PrintRecord? record = PrintRecord.fromJson(entry.value);
        if (record != null) {
          records[entry.key] = record;
        }
      }
      return records;
    } on FormatException {
      return <String, PrintRecord>{};
    } on FileSystemException {
      return <String, PrintRecord>{};
    }
  }

  static Future<bool> _write(
    Map<String, PrintRecord> records,
    Directory? directory,
  ) async {
    final File? file = _fileFor(directory);
    if (file == null) {
      return false;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          for (final MapEntry<String, PrintRecord> entry in records.entries)
            entry.key: entry.value.toJson(),
        }),
      );
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static Map<String, dynamic>? _json(File file) {
    try {
      final Object? json = jsonDecode(file.readAsStringSync());
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static String _stem(String path) {
    final int dot = path.lastIndexOf('.');
    return dot < 0 ? path : path.substring(0, dot);
  }
}
