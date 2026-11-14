import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../src/rust/api/thumbnail.dart' as thumbnail_api;
import 'model.dart';
import 'print.dart';
import 'settings.dart';

/// A thumbnail that a widget is holding.
///
/// Releasing it lets the cache evict the image when it needs the room. An
/// image that is still on screen is never evicted: the lease is the count of
/// people looking at it.
class PrintThumbnail {
  PrintThumbnail._(this.image, this._release);

  final ui.Image image;
  final void Function({bool drop}) _release;
  bool _released = false;

  /// Let the image go. [drop] also removes it from the cache instead of
  /// leaving it for the next card, which is what a viewer's large preview
  /// wants when the viewer closes.
  void release({bool drop = false}) {
    if (_released) {
      return;
    }
    _released = true;
    _release(drop: drop);
  }
}

/// A bounded cache of decoded wall-sized prints.
///
/// The gallery and the rack want 512-pixel paper, not a 26-megapixel file. The
/// first visit decodes the visible prints once and writes the result beside
/// the app; the next visit reads the small file, and the decoded image is kept
/// only while some room is looking at it.
class PrintThumbnailCache {
  PrintThumbnailCache._();

  static final PrintThumbnailCache instance = PrintThumbnailCache._();

  /// A cache with a folder of its own, for tests that must not touch the app's
  /// support directory.
  @visibleForTesting
  PrintThumbnailCache.forTesting(Directory folder) {
    _folder = folder;
    _folderChecked = true;
  }

  /// The width of the paper the rooms hang. The rack's cards are around 260
  /// points; the gallery's are larger, and the near view reads the file again.
  static const int thumbnailWidth = 512;

  /// The smallest width of the copy a print viewer opens. The viewer asks for
  /// the width the print actually occupies on screen, so a 4K window gets a
  /// sharper preview than a laptop window; this floor keeps a small window
  /// from asking for a new copy for every layout change.
  static const int previewWidth = 1600;

  /// The largest preview the viewer asks for. Beyond this the detail pass
  /// takes over; a preview is for looking at the whole print, not for zoom.
  static const int previewMaxWidth = 4096;

  /// The decoded images the cache may keep. A 512-pixel print is roughly two
  /// to four megabytes in the engine's wide-gamut form; this is enough for the
  /// cards in a room and one viewer's preview, and lets the preview go when
  /// the viewer closes.
  static const int memoryBudget = 32 * 1024 * 1024;

  /// The small files may live on disk longer than the images live in memory.
  static const int diskBudget = 256 * 1024 * 1024;

  static const int _version = 1;

  /// A fast scroll across a thousand cards must not queue a thousand decodes.
  /// The visible cards are re-requested when they are built again; the oldest
  /// waiting work is dropped first.
  static const int _maxQueued = 32;

  final LinkedHashMap<String, _Entry> _entries =
      LinkedHashMap<String, _Entry>();
  final Map<String, Future<_Entry?>> _inflight = <String, Future<_Entry?>>{};
  final Queue<_ThumbJob> _queue = Queue<_ThumbJob>();
  int _active = 0;
  int _bytes = 0;
  Directory? _folder;
  bool _folderChecked = false;
  bool _pruning = false;
  int _writesSincePrune = 0;

  /// A decoded copy, or null when the print has no file and no image.
  ///
  /// The caller must [PrintThumbnail.release] the result when the widget that
  /// holds it goes away.
  Future<PrintThumbnail?> acquire(
    Print print, {
    int maxWidth = thumbnailWidth,
  }) async {
    final ui.Image? ready = print.image;
    if (ready != null) {
      return PrintThumbnail._(ready, ({bool drop = false}) {});
    }
    final String? path = print.path;
    if (path == null) {
      return null;
    }
    final File source = File(path);
    final FileStat stat;
    try {
      stat = await source.stat();
    } on FileSystemException catch (error) {
      Model.log('no thumbnail source at $path: $error');
      return null;
    }
    final String key = _key(path, stat, maxWidth);
    final _Entry? cached = _entries[key];
    if (cached != null) {
      return _lease(cached);
    }
    final Future<_Entry?> future = _inflight.putIfAbsent(key, () {
      final Future<_Entry?> next = _enqueue(
        () => _produce(key, source, maxWidth),
      );
      next.whenComplete(() {
        if (identical(_inflight[key], next)) {
          _inflight.remove(key);
        }
      });
      return next;
    });
    final _Entry? entry;
    try {
      entry = await future;
    } on Object catch (error) {
      Model.log('no thumbnail for $path: $error');
      return null;
    }
    if (entry == null) {
      return null;
    }
    final _Entry? current = _entries[key];
    if (current == null) {
      return null;
    }
    return _lease(current);
  }

  /// Drop every decoded image. The disk cache is untouched; this is for tests
  /// and for a window that is closing.
  @visibleForTesting
  void clear() {
    for (final _Entry entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    _bytes = 0;
  }

  PrintThumbnail _lease(_Entry entry) {
    entry.refs++;
    _entries.remove(entry.key);
    _entries[entry.key] = entry;
    _evict();
    return PrintThumbnail._(
      entry.image,
      ({bool drop = false}) => _release(entry, drop: drop),
    );
  }

  void _release(_Entry entry, {bool drop = false}) {
    if (entry.refs > 0) {
      entry.refs--;
    }
    if (drop && entry.refs == 0) {
      _remove(entry);
      return;
    }
    _evict();
  }

  void _remove(_Entry entry) {
    if (_entries.remove(entry.key) != null) {
      _bytes -= entry.bytes;
      entry.image.dispose();
    }
  }

  void _evict() {
    while (_bytes > memoryBudget) {
      _Entry? oldest;
      for (final _Entry entry in _entries.values) {
        if (entry.refs == 0) {
          oldest = entry;
          break;
        }
      }
      if (oldest == null) {
        return;
      }
      _entries.remove(oldest.key);
      _bytes -= oldest.bytes;
      oldest.image.dispose();
    }
  }

  Future<_Entry?> _produce(String key, File source, int maxWidth) async {
    final _Entry? existing = _entries[key];
    if (existing != null) {
      return existing;
    }
    final Directory? folder = await _ensureFolder();
    final File? cached = folder == null
        ? null
        : File('${folder.path}${Platform.pathSeparator}$key.png');
    ui.Image? image;
    if (cached != null && cached.existsSync()) {
      image = await _decode(cached);
      if (image == null) {
        try {
          await cached.delete();
        } on FileSystemException {
          // A cache file that cannot be removed is replaced below, if possible.
        }
      }
    }
    image ??= await _generate(source, cached, maxWidth);
    if (image == null) {
      return null;
    }
    final _Entry entry = _Entry(key, image);
    _entries[key] = entry;
    _bytes += entry.bytes;
    return entry;
  }

  Future<ui.Image?> _decode(File file) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      try {
        final ui.FrameInfo frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } on Object catch (error) {
      Model.log('the thumbnail at ${file.path} could not be read: $error');
      return null;
    }
  }

  Future<ui.Image?> _generate(File source, File? cached, int maxWidth) async {
    if (cached != null) {
      try {
        await cached.parent.create(recursive: true);
        if (Platform.isMacOS) {
          await const MethodChannel('com.kallo.app/thumbnails')
              .invokeMethod<void>('make', <String, Object>{
                'input': source.path,
                'output': cached.path,
                'width': maxWidth,
              });
        } else {
          await thumbnail_api.makeThumbnail(
            input: source.path,
            output: cached.path,
            width: maxWidth,
          );
        }
        final ui.Image? image = await _decode(cached);
        if (image != null) {
          _schedulePrune(cached.parent);
          return image;
        }
      } on Object catch (error) {
        Model.log('the platform thumbnail could not be made: $error');
      }
      if (Platform.isMacOS) {
        // The channel is the fast path. If it is missing — a test, a window
        // built without the platform code — the model's image reader is the
        // next best decoder and keeps the engine's large buffer out of it.
        try {
          await thumbnail_api.makeThumbnail(
            input: source.path,
            output: cached.path,
            width: maxWidth,
          );
          final ui.Image? image = await _decode(cached);
          if (image != null) {
            _schedulePrune(cached.parent);
            return image;
          }
        } on Object catch (error) {
          Model.log('the model could not make a thumbnail: $error');
        }
      }
    }
    return _generateWithEngine(source, cached, maxWidth);
  }

  /// The fallback when neither the platform nor the model can make a file.
  ///
  /// This path is deliberately last: the engine can be asked for a target
  /// width, but a PNG still decodes at its own size first.
  Future<ui.Image?> _generateWithEngine(
    File source,
    File? cached,
    int maxWidth,
  ) async {
    try {
      final Uint8List bytes = await source.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: maxWidth,
        allowUpscaling: false,
      );
      final ui.Image image;
      try {
        final ui.FrameInfo frame = await codec.getNextFrame();
        image = frame.image;
      } finally {
        codec.dispose();
      }
      if (cached != null) {
        final ByteData? encoded = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (encoded != null) {
          try {
            await cached.parent.create(recursive: true);
            final File temporary = File('${cached.path}.tmp');
            await temporary.writeAsBytes(
              encoded.buffer.asUint8List(
                encoded.offsetInBytes,
                encoded.lengthInBytes,
              ),
              flush: true,
            );
            await temporary.rename(cached.path);
            _schedulePrune(cached.parent);
          } on FileSystemException catch (error) {
            Model.log('the thumbnail could not be kept: $error');
          }
        }
      }
      return image;
    } on Object catch (error) {
      Model.log('the thumbnail for ${source.path} could not be made: $error');
      return null;
    }
  }

  Future<Directory?> _ensureFolder() async {
    if (_folderChecked) {
      return _folder;
    }
    _folderChecked = true;
    final Directory? base = Settings.directory;
    if (base == null) {
      return null;
    }
    final Directory folder = Directory(
      '${base.path}${Platform.pathSeparator}thumbnails',
    );
    try {
      await folder.create(recursive: true);
      _folder = folder;
      _schedulePrune(folder, force: true);
    } on FileSystemException catch (error) {
      Model.log('the thumbnail folder could not be made: $error');
    }
    return _folder;
  }

  /// Pruning is a background housekeeping job, not part of loading a card.
  /// Doing a full directory stat after every thumbnail is O(n²) for a wall of
  /// a thousand; a pass after every thirty-two new files is enough to keep the
  /// cache bounded.
  void _schedulePrune(Directory folder, {bool force = false}) {
    _writesSincePrune++;
    if (!force && _writesSincePrune < 32) {
      return;
    }
    _writesSincePrune = 0;
    if (_pruning) {
      return;
    }
    _pruning = true;
    unawaited(
      _pruneDisk(folder).whenComplete(() {
        _pruning = false;
      }),
    );
  }

  Future<void> _pruneDisk(Directory folder) async {
    try {
      final List<File> files = <File>[];
      await for (final FileSystemEntity entity in folder.list()) {
        if (entity is File && entity.path.endsWith('.png')) {
          files.add(entity);
        }
      }
      if (files.isEmpty) {
        return;
      }
      final List<FileStat> stats = <FileStat>[
        for (final File file in files) await file.stat(),
      ];
      int total = 0;
      for (final FileStat stat in stats) {
        total += stat.size;
      }
      if (total <= diskBudget) {
        return;
      }
      final List<int> order = <int>[
        for (int i = 0; i < files.length; i++) i,
      ]..sort((int a, int b) => stats[a].modified.compareTo(stats[b].modified));
      for (final int index in order) {
        if (total <= diskBudget * 0.8) {
          break;
        }
        try {
          await files[index].delete();
          total -= stats[index].size;
        } on FileSystemException {
          // A cache that cannot be pruned is not a reason to fail a room.
        }
      }
    } on FileSystemException {
      // The cache is an optimisation; a missing folder is not an error.
    }
  }

  Future<_Entry?> _enqueue(Future<_Entry?> Function() task) {
    while (_queue.length >= _maxQueued) {
      final _ThumbJob dropped = _queue.removeFirst();
      if (!dropped.completer.isCompleted) {
        // The card that asked is no longer on screen. A card that comes back
        // asks again; it must not inherit a queue from a fast scroll.
        dropped.completer.complete(null);
      }
    }
    final Completer<_Entry?> completer = Completer<_Entry?>();
    _queue.add(_ThumbJob(task, completer));
    _pump();
    return completer.future;
  }

  void _pump() {
    while (_active < 2 && _queue.isNotEmpty) {
      final _ThumbJob job = _queue.removeFirst();
      _active++;
      Future<void>(() async {
        try {
          job.completer.complete(await job.task());
        } on Object catch (error, stack) {
          job.completer.completeError(error, stack);
        }
      }).whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  static String _key(String path, FileStat stat, int maxWidth) {
    final String source =
        '$path|${stat.modified.millisecondsSinceEpoch}|${stat.size}|$maxWidth|'
        '$_version';
    int hash = 0x811c9dc5;
    for (final int unit in utf8.encode(source)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 'thumb-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}

class _Entry {
  _Entry(this.key, this.image);

  final String key;
  final ui.Image image;
  int refs = 0;

  int get bytes => image.width * image.height * 8;
}

class _ThumbJob {
  _ThumbJob(this.task, this.completer);

  final Future<_Entry?> Function() task;
  final Completer<_Entry?> completer;
}
