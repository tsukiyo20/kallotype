import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'clock.dart';
import 'model.dart';
import 'stock.dart';

/// The chemistry a film's name implies, for a print written before the record
/// carried `process`.
///
/// This is a reading of the label, not a second catalogue: a new print writes
/// the exact process. The names are the ones the model carries; an unknown
/// label stays null and the edge keeps the neutral ivory ink.
FilmProcess? filmProcessFromName(String? film) {
  if (film == null || film.isEmpty) {
    return null;
  }
  final String name = film.toUpperCase();
  const List<String> reversal = <String>[
    'PROVIA',
    'VELVIA',
    'EKTACHROME',
    'FUJICHROME',
    'E-6',
  ];
  const List<String> monochrome = <String>[
    'T-MAX',
    'TRI-X',
    'DELTA',
    'HP5',
    'FP4',
    'ACROS',
    'XP2',
    'PAN F',
    'MONOCHROME',
  ];
  const List<String> negative = <String>[
    'PORTRA',
    'ULTRA MAX',
    'FUJIFILM',
    'SUPERIA',
    'GOLD',
    'VISION3',
    'EKTAR',
    'PRO 400H',
    'C200',
    'C-41',
    'NEGATIVE',
  ];
  if (reversal.any(name.contains)) {
    return FilmProcess.reversal;
  }
  if (monochrome.any(name.contains)) {
    return FilmProcess.monochrome;
  }
  if (negative.any(name.contains)) {
    return FilmProcess.negative;
  }
  return null;
}

/// The metadata a print carries besides its pixels.
///
/// This used to be a JSON sidecar beside every PNG, which made the export
/// folder a directory of pictures and records. The record now lives in the
/// app's own support folder, keyed by the print's path; the image folder holds
/// images only.
@immutable
class PrintRecord {
  const PrintRecord({
    this.printNumber = 1,
    this.process,
    this.film,
    this.paper,
    this.minutes,
    this.tempC,
  });

  final int printNumber;
  final FilmProcess? process;
  final String? film;
  final String? paper;
  final double? minutes;
  final double? tempC;

  Map<String, Object?> toJson() => <String, Object?>{
    'print': printNumber,
    'process': ?process?.name,
    'film': ?film,
    'paper': ?paper,
    'minutes': ?minutes,
    'temp_c': ?tempC,
  };

  /// Read a record from a map in either the new shape or the old sidecar's.
  static PrintRecord? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final String? film = json['film'] as String?;
    final Object? process = json['process'];
    final FilmProcess? parsed = switch (process) {
      'negative' => FilmProcess.negative,
      'reversal' => FilmProcess.reversal,
      'monochrome' => FilmProcess.monochrome,
      _ => filmProcessFromName(film),
    };
    return PrintRecord(
      printNumber:
          (json['print'] as num?)?.toInt() ??
          (json['print_number'] as num?)?.toInt() ??
          1,
      process: parsed,
      film: film,
      paper: json['paper'] as String?,
      minutes: (json['minutes'] as num?)?.toDouble(),
      tempC: (json['temp_c'] as num?)?.toDouble(),
    );
  }

  /// Whether a JSON map is one of the app's old print sidecars.
  static bool looksLikeSidecar(Map<String, dynamic> json) =>
      json['film'] is String &&
      (json['minutes'] is num ||
          json['frame'] is num ||
          json['print'] is num ||
          json['print_ev'] is num);
}

/// A print: a photograph, developed and printed, on paper.
///
/// It is a file before it is anything else. The model exports one, and the
/// gallery hangs whatever it finds — so a print is not an asset of this app,
/// and an app that has never printed anything has nothing to hang. That is the
/// truth, and the empty wall is built to say it.
///
/// The image is sRGB at full light and it is not a photograph on a screen: it
/// is a sheet of paper. How much light falls on it is the viewer's business,
/// which is why nothing here knows about the gallery's lamp.
class Print {
  const Print({
    required this.image,
    required this.name,
    this.path,
    this.pixels,
    this.printNumber = 1,
    this.process,
    this.film,
    this.paper,
    this.minutes,
    this.tempC,
    this.printed,
  });

  /// The wall's copy: as wide as the wall, not as wide as the file.
  final ui.Image image;

  /// The file this print came from. Null for a print a test built, which is the
  /// one case where a print has pixels and no file behind it.
  final String? path;

  /// The file's own pixel size, which is what the loupe magnifies and what the
  /// readout says. Null when there is no file.
  final Size? pixels;

  /// The image's file name. A print with no record still has a name, and a
  /// name is what a picture remains when everything else about it was lost.
  final String name;

  /// The print's number in the batch that made it. A single print is `01`; a
  /// batch of selected frames counts `02`, `03`. It is not a film frame number:
  /// the app does not have the roll's frame yet.
  final int printNumber;

  /// Which chemistry the film is. The edge printing's colour follows it: warm
  /// ivory for a silver film, amber for a colour negative, white for a
  /// reversal. Null when an export came without a record; the edge is then
  /// neutral.
  final FilmProcess? process;

  /// When the file was written, which is when the print was made.
  final DateTime? printed;

  /// The film and the paper, as they would be printed on the box. They do not
  /// translate: they are the material's own names. Null when the export came
  /// without a record, which is a state that has to render.
  final String? film;
  final String? paper;

  /// How long it was in the developer, and how warm it was.
  final double? minutes;
  final double? tempC;

  /// The picture's shape, width over height.
  ///
  /// A print is a sheet of paper cut to the picture, so this is the paper's
  /// shape as well, and every wall that hangs one sizes it from here.
  double get aspect => image.width / image.height;

  /// `9:00`.
  String? get clock {
    final double? minutes = this.minutes;
    return minutes == null ? null : darkroomClock(minutes);
  }

  /// `01 · 9:00` — the print, and how long it was in the developer.
  String get folio {
    final String number = printNumber.toString().padLeft(2, '0');
    final String? clock = this.clock;
    return clock == null ? name : '$number   ·   $clock';
  }

  /// `21:40` — when it came off the line.
  String? get at {
    final DateTime? printed = this.printed;
    if (printed == null) {
      return null;
    }
    return '${printed.hour.toString().padLeft(2, '0')}:'
        '${printed.minute.toString().padLeft(2, '0')}';
  }

  /// A decoded print owns a texture. When the wall stops hanging it, the
  /// texture goes too — otherwise every visit to a folder with four prints in
  /// it costs a hundred megabytes that nothing will ever free.
  void dispose() => image.dispose();

  /// The print at its own size, for the loupe.
  ///
  /// The wall holds every print at 1600 points because the wall is 660 wide and
  /// holding the difference would cost a hundred megabytes to throw away. The
  /// loupe is the one place the difference is the point: it shows the file's
  /// own pixels, so what you see at 1:1 is what the model wrote.
  ///
  /// Null when there is no file behind this print, or when the file cannot be
  /// decoded any more — the wall's copy is always there to fall back to.
  Future<ui.Image?> full() async {
    final String? path = this.path;
    if (path == null) {
      return null;
    }
    try {
      final Uint8List bytes = await File(path).readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    } on Object catch (error) {
      Model.log('no larger print for $path: $error');
      return null;
    }
  }

  /// The print at a size worth looking through.
  ///
  /// The wall holds every print at 1600 points because the wall is 660 wide and
  /// holding the difference would cost a hundred megabytes; a loupe that
  /// magnified that copy would only magnify a screen image. Four thousand is
  /// what three times the wall needs to be honest at a device pixel ratio of
  /// two, and it is thrown away when the pointer leaves the print.
  Future<ui.Image?> magnified({int width = 4000}) async {
    final String? path = this.path;
    if (path == null) {
      return null;
    }
    try {
      final Uint8List bytes = await File(path).readAsBytes();
      final int source = pixels?.width.toInt() ?? 0;
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: source > width ? width : null,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    } on Object catch (error) {
      Model.log('no magnified print for $path: $error');
      return null;
    }
  }

  /// Read one exported print.
  ///
  /// The image is decoded at the display's width rather than the file's: an
  /// export is a 26-megapixel print and the wall is 660 points wide, and
  /// holding the difference would cost a hundred megabytes to throw away. The
  /// header is read first so that a small export is never upscaled.
  ///
  /// A print written before the record carried a print number is print `01`;
  /// the old `frame` field was the strip's order, not a print number, so it is
  /// deliberately not read.
  static Future<Print?> read(
    File image, {
    int width = 1600,
    PrintRecord? record,
  }) async {
    final Uint8List bytes = await image.readAsBytes();
    final Size? pixels = _pngSize(bytes) ?? await _encodedSize(bytes);
    final int source = pixels?.width.toInt() ?? 0;
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: source > width ? width : null,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final String? film = record?.film ?? _record(image, 'film') as String?;
    final Object? processRecord = _record(image, 'process');
    final FilmProcess? process =
        record?.process ??
        switch (processRecord) {
          'negative' => FilmProcess.negative,
          'reversal' => FilmProcess.reversal,
          'monochrome' => FilmProcess.monochrome,
          _ => filmProcessFromName(film),
        };
    return Print(
      image: frame.image,
      name: _name(image.path),
      path: image.path,
      pixels: pixels,
      printNumber:
          record?.printNumber ??
          (_record(image, 'print') as num?)?.toInt() ??
          (_record(image, 'print_number') as num?)?.toInt() ??
          1,
      process: process,
      printed: image.statSync().modified,
      film: film,
      paper: record?.paper ?? _record(image, 'paper') as String?,
      minutes:
          record?.minutes ?? (_record(image, 'minutes') as num?)?.toDouble(),
      tempC: record?.tempC ?? (_record(image, 'temp_c') as num?)?.toDouble(),
    );
  }

  /// The size any encoded image says it is, for a format whose header is not
  /// read by [_pngSize] — JPEG, today.
  static Future<Size?> _encodedSize(Uint8List bytes) async {
    try {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        bytes,
      );
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final Size size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      return size;
    } on Object {
      return null;
    }
  }

  /// The size a PNG says it is. Position 16 is where the first chunk's data
  /// begins, and it is the only part of a decode that costs nothing.
  static Size? _pngSize(Uint8List bytes) {
    if (bytes.length < 24 ||
        bytes[0] != 137 ||
        bytes[1] != 80 ||
        bytes[2] != 78 ||
        bytes[3] != 71 ||
        bytes[4] != 13 ||
        bytes[5] != 10 ||
        bytes[6] != 26 ||
        bytes[7] != 10) {
      return null;
    }
    final int width =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final int height =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return width <= 0 || height <= 0
        ? null
        : Size(width.toDouble(), height.toDouble());
  }

  /// The record beside the image, if there is one. A file that is not JSON is
  /// a missing record, not a crash: the folder belongs to a person.
  static Object? _record(File image, String key) {
    final File file = File('${_stem(image.path)}.json');
    if (!file.existsSync()) {
      return null;
    }
    try {
      final Object? value =
          (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)[key];
      return value;
    } on FormatException {
      return null;
    }
  }

  /// The path without its extension: where the record beside it lives.
  static String _stem(String path) {
    final int dot = path.lastIndexOf('.');
    return dot <= path.lastIndexOf(Platform.pathSeparator)
        ? path
        : path.substring(0, dot);
  }

  /// The file's own name, without the folder: what a print is called when
  /// nothing else knows what it is.
  static String _name(String path) {
    final int slash = path.lastIndexOf(Platform.pathSeparator);
    final String base = slash < 0 ? path : path.substring(slash + 1);
    final int dot = base.lastIndexOf('.');
    return dot < 0 ? base : base.substring(0, dot);
  }
}
