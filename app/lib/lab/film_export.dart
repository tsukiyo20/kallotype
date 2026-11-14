import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../widgets/film_frame.dart';
import 'export_format.dart';
import 'exports.dart';
import 'model.dart';
import 'print.dart';

/// Write the print as a finished 35 mm frame: the picture, the black rebate,
/// the sprocket holes and the edge printing.
///
/// This is a second product, not a second print. The plain print is what the
/// enlarger made; the frame is what a person would put on a wall or send to
/// someone. It goes in `Frames/` inside the export folder, so the gallery does
/// not hang the same picture twice.
///
/// The frame is drawn by the same painter the gallery uses, then encoded in
/// [format]. The export is flat — the loupe's distortion is a property of
/// looking through glass, not of the negative. A null [maxEdge] keeps the
/// print's own pixel size; a value caps the frame's long edge. JPEG is the
/// default because a lossless full-resolution frame was a 100 MB file.
Future<File> exportFilmFrame({
  required Print print,
  int? printNumber,
  ui.Image? image,
  int? maxEdge,
  ExportFormat format = ExportFormat.jpeg,
}) async {
  final String? path = print.path;
  if (path == null) {
    throw const FileSystemException(
      'a print with no file has no frame to export',
    );
  }
  final bool owns = image == null;
  final ui.Image? full = image ?? await print.full();
  if (full == null) {
    throw FileSystemException('the print could not be read again', path);
  }

  try {
    final double aspect = full.width / full.height;
    final FilmFrameMetrics whole = FilmFrameMetrics.fromImageWidth(
      full.width.toDouble(),
      aspect: aspect,
    );
    final double scale = maxEdge != null && whole.outer.width > maxEdge
        ? maxEdge / whole.outer.width
        : 1;
    final int width = (whole.outer.width * scale).round();
    final int height = (whole.outer.height * scale).round();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    FilmFramePainter(
      image: full,
      source: Rect.fromLTWH(
        0,
        0,
        full.width.toDouble(),
        full.height.toDouble(),
      ),
      film: print.film,
      printNumber: printNumber ?? print.printNumber,
      process: print.process,
      light: 1,
    ).paint(canvas, Size(width.toDouble(), height.toDouble()));
    final ui.Picture picture = recorder.endRecording();
    final ui.Image framed = await picture.toImage(width, height);
    picture.dispose();
    final ByteData? raw = await framed.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    framed.dispose();
    if (raw == null) {
      throw FileSystemException('the frame could not be read', path);
    }

    final Uint8List rgba = raw.buffer.asUint8List(
      raw.offsetInBytes,
      raw.lengthInBytes,
    );
    final Uint8List encoded = await Isolate.run(() {
      final img.Image picture = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba.buffer,
        bytesOffset: rgba.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return switch (format) {
        ExportFormat.jpeg => img.encodeJpg(
          picture,
          quality: 92,
          chroma: img.JpegChroma.yuv420,
        ),
        ExportFormat.png => img.encodePng(picture),
        ExportFormat.tiff => img.encodeTiff(picture),
      };
    });

    final Directory folder = Exports.framesFolder(File(path).parent);
    await folder.create(recursive: true);
    final File file = File(
      '${folder.path}${Platform.pathSeparator}${print.name}-frame.'
      '${format.extension}',
    );
    await file.writeAsBytes(encoded, flush: true);

    // One frame, one file: choosing TIFF today should not leave yesterday's
    // JPEG beside it.
    for (final String extension in <String>['jpg', 'png', 'tiff']) {
      if (extension == format.extension) {
        continue;
      }
      final File old = File(
        '${folder.path}${Platform.pathSeparator}${print.name}-frame.'
        '$extension',
      );
      if (old.existsSync()) {
        try {
          await old.delete();
        } on FileSystemException {
          // A file in use is not a reason to lose the new export.
        }
      }
    }
    return file;
  } on FileSystemException {
    rethrow;
  } on Object catch (error) {
    Model.log('the film frame could not be exported: $error');
    rethrow;
  } finally {
    if (owns) {
      full.dispose();
    }
  }
}
