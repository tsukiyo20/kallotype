import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../widgets/film_frame.dart';
import 'exports.dart';
import 'model.dart';
import 'print.dart';

/// Write the print as a finished 35 mm frame: the picture, the black rebate,
/// the sprocket holes and the edge printing, at the file's own size.
///
/// This is a second product, not a second print. The plain print is what the
/// enlarger made; the frame is what a person would put on a wall or send to
/// someone. It goes in `Frames/` inside the export folder, so the gallery does
/// not hang the same picture twice.
///
/// The frame is drawn by the same painter the gallery uses. The export is flat
/// — the loupe's distortion is a property of looking through glass, not of the
/// negative — and it is full resolution, because a border that only exists on
/// screen is a preview of an idea.
Future<File> exportFilmFrame({
  required Print print,
  int? printNumber,
  ui.Image? image,
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
    final FilmFrameMetrics metrics = FilmFrameMetrics.fromImageWidth(
      full.width.toDouble(),
      aspect: aspect,
    );
    final Rect source = Rect.fromLTWH(
      0,
      0,
      full.width.toDouble(),
      full.height.toDouble(),
    );

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    FilmFramePainter(
      image: full,
      source: source,
      film: print.film,
      printNumber: printNumber ?? print.printNumber,
      process: print.process,
      light: 1,
    ).paint(canvas, metrics.outer.size);
    final ui.Picture picture = recorder.endRecording();
    final int width = metrics.outer.width.round();
    final int height = metrics.outer.height.round();
    final ui.Image framed = await picture.toImage(width, height);
    picture.dispose();
    final ByteData? png = await framed.toByteData(
      format: ui.ImageByteFormat.png,
    );
    framed.dispose();
    if (png == null) {
      throw FileSystemException('the frame could not be encoded', path);
    }

    final Directory folder = Exports.framesFolder(File(path).parent);
    await folder.create(recursive: true);
    final File image = File(
      '${folder.path}${Platform.pathSeparator}${print.name}-frame.png',
    );
    await image.writeAsBytes(png.buffer.asUint8List(), flush: true);

    final File record = File(
      '${folder.path}${Platform.pathSeparator}${print.name}-frame.json',
    );
    await record.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'film': ?print.film,
        'paper': ?print.paper,
        'minutes': ?print.minutes,
        'temp_c': ?print.tempC,
        'print': printNumber ?? print.printNumber,
        'process': ?print.process?.name,
        'border': '35mm',
      }),
    );
    return image;
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
