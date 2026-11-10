import 'dart:io';

import 'image_file.dart';
import 'model.dart';
import 'roll.dart';
import 'roll_store.dart';
import 'stock.dart';

/// The ladder: what "the same frame, five ways" means, in minutes.
///
/// Three to fifteen, and the reference time of most colour negative processes
/// sits inside it. Five is the number the contact sheet can show on one line
/// and the number a person can hold in their head while comparing.
const List<double> ladder = <double>[3, 6, 9, 12, 15];

/// The width the bench renders at.
///
/// The medium's own size is 26 megapixels, and the bench is a window: the model
/// is asked for this width rather than given the photograph's, because the
/// grain belongs to the sampling and a render scaled afterwards would be a lie
/// about it.
const int benchWidth = 1200;

/// Develop a photograph into a roll.
///
/// One photograph through the developer five times, which is the product's
/// whole argument: what changes between the frames on the sheet is the time and
/// nothing else, so the sheet is a comparison rather than a collection.
Future<Roll> develop({
  required Model model,
  required File photograph,
  required Stock stock,
  List<double> times = ladder,
  double tempC = 20,
  Directory? folder,
  void Function(int done, int total)? onProgress,
}) async {
  final Directory target = folder ?? RollStore.folder!;
  await target.create(recursive: true);

  final List<Frame> frames = <Frame>[];
  for (int i = 0; i < times.length; i++) {
    final double minutes = times[i];
    final File output = RollStore.frameFile(target, i + 1);
    await model.develop(
      photograph: photograph,
      stock: stock.id,
      minutes: minutes,
      tempC: tempC,
      width: benchWidth,
      output: output,
    );
    frames.add(
      Frame(
        number: i + 1,
        minutes: minutes,
        tempC: tempC,
        image: await decode(output, width: benchWidth),
      ),
    );
    onProgress?.call(i + 1, times.length);
  }

  final Roll roll = Roll(
    number: 1,
    stockId: stock.id,
    stockLabel: stock.label,
    photo: photograph.path,
    frames: frames,
  );
  await RollStore.save(roll, folder: target);
  return roll;
}
