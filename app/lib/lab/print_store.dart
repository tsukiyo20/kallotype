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

  /// The previous version of the store. Kept beside the live file so a write
  /// that is interrupted between the two renames still has somewhere to read.
  static File? _backupFor(File? file) =>
      file == null ? null : File('${file.path}.bak');

  static File? _tempFor(File? file) =>
      file == null ? null : File('${file.path}.tmp');

  /// One writer at a time. Two prints finishing together must not both read the
  /// old map and then overwrite one another.
  static Future<void> _pending = Future<void>.value();

  static Future<void> _serialized(Future<void> Function() body) {
    final Future<void> result = _pending.then((_) => body());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

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
  }) {
    return _serialized(() async {
      final Map<String, PrintRecord> records = await _read(directory);
      records[print.path] = record;
      await _write(records, directory);
    });
  }

  static Future<Map<String, PrintRecord>> _read(Directory? directory) async {
    final File? file = _fileFor(directory);
    if (file == null) {
      return <String, PrintRecord>{};
    }
    final Map<String, PrintRecord>? live = await _decode(file);
    if (live != null) {
      return live;
    }
    // A live file that cannot be read is either a half-written old version or
    // a file somebody edited. The backup is the previous complete version.
    final Map<String, PrintRecord>? backup = await _decode(_backupFor(file));
    if (backup != null) {
      return backup;
    }
    return <String, PrintRecord>{};
  }

  static Future<Map<String, PrintRecord>?> _decode(File? file) async {
    if (file == null || !file.existsSync()) {
      return null;
    }
    try {
      final Object? json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) {
        return null;
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
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Write the whole store through a temporary file.
  ///
  /// The live file is never truncated. The old file becomes `.bak`, the
  /// temporary file is flushed and renamed over the live name, and a reader
  /// that finds a broken live file falls back to the backup.
  static Future<bool> _write(
    Map<String, PrintRecord> records,
    Directory? directory,
  ) async {
    final File? file = _fileFor(directory);
    if (file == null) {
      return false;
    }
    final File? temp = _tempFor(file);
    final File? backup = _backupFor(file);
    if (temp == null || backup == null) {
      return false;
    }
    try {
      await file.parent.create(recursive: true);
      final String text = const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          for (final MapEntry<String, PrintRecord> entry in records.entries)
            entry.key: entry.value.toJson(),
        },
      );
      final RandomAccessFile out = await temp.open(mode: FileMode.write);
      try {
        await out.writeString(text);
        await out.flush();
      } finally {
        await out.close();
      }
      if (await file.exists()) {
        try {
          if (await backup.exists()) {
            await backup.delete();
          }
          await file.rename(backup.path);
        } on FileSystemException {
          // If the old file cannot be moved aside, keep it and leave the
          // temporary file for the next attempt rather than truncating it.
          await _deleteQuietly(temp);
          return false;
        }
      }
      await temp.rename(file.path);
      return true;
    } on FileSystemException {
      await _deleteQuietly(temp);
      return false;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A leftover temporary file is harmless; the next write replaces it.
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
