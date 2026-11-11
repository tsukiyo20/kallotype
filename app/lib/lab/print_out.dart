import 'dart:convert';
import 'dart:io';

import 'roll.dart';
import 'roll_store.dart';
import 'stock.dart';

/// Print a frame: put it on paper, and put the paper where the gallery looks.
///
/// A print is a file, and printing one is copying it. The frame's PNG is
/// already on the roll — the model made it — so what a print adds is the paper
/// and the record beside it: the file name, the film, the paper, the time.
/// That record is what the wall label reads, which is why it is written here
/// and not in the gallery.
Future<File> printFrame({
  required Roll roll,
  required Frame frame,
  required Directory exports,
  Directory? rollFolder,
}) async {
  final Directory source = rollFolder ?? RollStore.folder!;
  await exports.create(recursive: true);

  // The frame it came from, and the minutes: the two facts that tell one print
  // of a ladder from the next, in a name a person can read in a folder.
  final String name = 'print-${frame.number.toString().padLeft(2, '0')}'
      '-${frame.minutes.toStringAsFixed(frame.minutes == frame.minutes.roundToDouble() ? 0 : 1)}min';
  final File image = File('${exports.path}${Platform.pathSeparator}$name.png');
  await RollStore.frameFile(source, frame.number).copy(image.path);

  final Stock? stock = Stocks.byId(roll.stockId);
  final File record = File('${exports.path}${Platform.pathSeparator}$name.json');
  await record.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'frame': frame.number,
      'film': stock?.short ?? roll.stockLabel,
      'paper': Stocks.paperShort,
      'minutes': frame.minutes,
      'temp_c': frame.tempC,
    }),
  );
  return image;
}
