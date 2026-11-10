import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'clock.dart';

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
    this.film,
    this.paper,
    this.minutes,
    this.tempC,
  });

  final ui.Image image;

  /// The image's file name. A print with no record still has a name, and a
  /// name is what a picture remains when everything else about it was lost.
  final String name;

  /// The film and the paper, as they would be printed on the box. They do not
  /// translate: they are the material's own names. Null when the export came
  /// without a record, which is a state that has to render.
  final String? film;
  final String? paper;

  /// How long it was in the developer, and how warm it was.
  final double? minutes;
  final double? tempC;

  /// `9:00`.
  String? get clock {
    final double? minutes = this.minutes;
    return minutes == null ? null : darkroomClock(minutes);
  }

  /// A decoded print owns a texture. When the wall stops hanging it, the
  /// texture goes too — otherwise every visit to a folder with four prints in
  /// it costs a hundred megabytes that nothing will ever free.
  void dispose() => image.dispose();

  /// Read one exported print.
  ///
  /// The image is decoded at the display's width rather than the file's: an
  /// export is a 26-megapixel print and the wall is 660 points wide, and
  /// holding the difference would cost a hundred megabytes to throw away. The
  /// header is read first so that a small export is never upscaled.
  static Future<Print?> read(File image, {int width = 1600}) async {
    final Uint8List bytes = await image.readAsBytes();
    final int source = _pngWidth(bytes);
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: source > width ? width : null,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    return Print(
      image: frame.image,
      name: _name(image.path),
      film: _record(image, 'film') as String?,
      paper: _record(image, 'paper') as String?,
      minutes: (_record(image, 'minutes') as num?)?.toDouble(),
      tempC: (_record(image, 'temp_c') as num?)?.toDouble(),
    );
  }

  /// The width a PNG says it is. Position 16 is where the first chunk's data
  /// begins, and it is the only part of a decode that costs nothing.
  static int _pngWidth(Uint8List bytes) => bytes.length < 24
      ? 0
      : (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];

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
