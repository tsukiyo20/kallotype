import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'clock.dart';

/// A print: a photograph, developed and printed, on paper.
///
/// Both files it is read from are the model's — `just print` writes them — so
/// what hangs in the gallery is a rendering of the model at a commit, like the
/// strip, and not a picture this app drew.
///
/// The image is sRGB at full light and it is not a photograph on a screen: it
/// is a sheet of paper. How much light falls on it is the viewer's business,
/// which is why nothing here knows about the gallery's lamp.
class Print {
  const Print({
    required this.image,
    required this.film,
    required this.paper,
    required this.minutes,
    required this.tempC,
  });

  final ui.Image image;

  /// The film and the paper, as they would be printed on the box. They do not
  /// translate: they are the material's own names.
  final String film;
  final String paper;

  /// How long it was in the developer, and how warm it was.
  final double minutes;
  final double tempC;

  /// `9:00`.
  String get clock => darkroomClock(minutes);

  static const String _image = 'assets/print.png';
  static const String _record = 'assets/print.json';

  /// Read the print this repository carries.
  static Future<Print> load(AssetBundle bundle) async {
    final Map<String, dynamic> record =
        jsonDecode(await bundle.loadString(_record)) as Map<String, dynamic>;
    final ByteData file = await bundle.load(_image);
    final ui.Codec codec =
        await ui.instantiateImageCodec(file.buffer.asUint8List());
    final ui.FrameInfo frame = await codec.getNextFrame();
    return Print.of(record, frame.image);
  }

  /// The record and the pixels, together: one without the other is a picture
  /// nobody can label.
  factory Print.of(Map<String, dynamic> record, ui.Image image) => Print(
        image: image,
        film: record['film'] as String,
        paper: record['paper'] as String,
        minutes: (record['minutes'] as num).toDouble(),
        tempC: (record['temp_c'] as num).toDouble(),
      );
}
