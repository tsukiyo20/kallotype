import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'export_format.dart';

/// Encode an already-written PNG as [format], in an isolate.
///
/// The model writes PNG. When the person asks for JPEG or TIFF, the bytes are
/// decoded and encoded once; the picture's pixels and the file stay on disk
/// for the duration. PNG is returned untouched, because it already is one.
Future<Uint8List> encodePngAs(Uint8List png, ExportFormat format) async {
  if (format == ExportFormat.png) {
    return png;
  }
  return Isolate.run(() {
    final img.Image? picture = img.decodePng(png);
    if (picture == null) {
      throw const FormatException('the print is not a PNG');
    }
    return switch (format) {
      ExportFormat.jpeg => img.encodeJpg(
        picture,
        quality: 92,
        chroma: img.JpegChroma.yuv420,
      ),
      ExportFormat.tiff => img.encodeTiff(picture),
      ExportFormat.png => png,
    };
  });
}
