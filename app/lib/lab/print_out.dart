import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'model.dart';
import 'roll.dart';
import 'roll_store.dart';
import 'stock.dart';

/// A print being made.
///
/// The print is a render and not a copy, so it takes time, and this is what the
/// line shows while it does. It carries the frame, because the only picture of
/// a print that does not exist yet is the frame it will be made from.
class PrintJob {
  const PrintJob({required this.frame, required this.exports});

  final Frame frame;

  /// Where it is going, so that the line can say it without being told twice.
  final Directory exports;
}

/// Print a frame: render it at the size a print is, and put the paper where the
/// gallery looks.
///
/// The bench works at a preview's width. A print is not a preview: it is
/// rendered again from the photograph at the size the photograph has, because
/// the two things that make a print look like a print — halation scattering
/// light eleven micrometres through the emulsion, and the couplers diffusing
/// twenty — are smaller than a preview's pixel and disappear in it.
///
/// A roll from before the photograph was kept has no readable source, and then
/// the print falls back to the frame's own render: a smaller print is still a
/// print, and refusing to make one would be worse than making it at the bench's
/// size.
Future<File> printFrame({
  required Roll roll,
  required Frame frame,
  required Directory exports,
  required String paperName,
  Stock? stock,
  Directory? rollFolder,
}) async {
  final Directory source = rollFolder ?? RollStore.folder!;
  await exports.create(recursive: true);

  // The frame it came from, and the minutes: the two facts that tell one print
  // of a ladder from the next, in a name a person can read in a folder.
  final String name = 'print-${frame.number.toString().padLeft(2, '0')}'
      '-${frame.minutes.toStringAsFixed(frame.minutes == frame.minutes.roundToDouble() ? 0 : 1)}min';
  final File image = File('${exports.path}${Platform.pathSeparator}$name.png');

  bool rendered = false;
  final String? photograph = roll.photo;
  if (photograph != null) {
    final File file = File(photograph);
    if (file.existsSync()) {
      try {
        final int width = await _width(file);
        await Model.find().develop(
          photograph: file,
          stock: roll.stockId,
          paper: roll.paper,
          minutes: frame.minutes,
          tempC: frame.tempC,
          width: width > _largest ? _largest : width,
          output: image,
        );
        rendered = true;
      } on Object {
        // The photograph is there and cannot be read: a temporary copy of
        // something, a folder somebody moved. Fall through to the bench render.
      }
    }
  }
  if (!rendered) {
    await RollStore.frameFile(source, frame.number).copy(image.path);
  }

  final File record = File('${exports.path}${Platform.pathSeparator}$name.json');
  await record.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'frame': frame.number,
      'film': stock?.short ?? roll.stockLabel,
      'paper': paperName,
      'minutes': frame.minutes,
      'temp_c': frame.tempC,
    }),
  );
  return image;
}

/// The largest print this pipeline is asked for, in pixels of width.
///
/// A 35 mm frame at this size is sampled every six micrometres, which is where
/// the emulsion's own blur stops being smaller than a pixel. Bigger than this
/// is a bigger file and not a better print.
const int _largest = 6000;

/// A file's width, read from its header rather than by decoding it.
Future<int> _width(File file) async {
  final ui.ImmutableBuffer buffer =
      await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
  final ui.ImageDescriptor descriptor =
      await ui.ImageDescriptor.encoded(buffer);
  final int width = descriptor.width;
  descriptor.dispose();
  buffer.dispose();
  return width;
}
