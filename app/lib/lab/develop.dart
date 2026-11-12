import 'dart:io';

import 'contact.dart';
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
  Stock? paper,
  bool spectral = false,
  List<double> times = ladder,
  double tempC = 20,
  Directory? folder,
  void Function(int done, int total)? onProgress,
}) async {
  final Directory target = folder ?? RollStore.folder!;
  await target.create(recursive: true);
  // The photograph comes into the roll's own folder before it is developed.
  // A file panel can hand over a temporary copy of something in a photo
  // library, and a record that points at a file which will be gone tomorrow is
  // not a record — it is a note to self that the work cannot be done again.
  final File source = await _keep(photograph, target);

  final List<File> outputs = <File>[
    for (int i = 0; i < times.length; i++) RollStore.frameFile(target, i + 1),
  ];
  // A proof from an earlier roll would be a proof of another photograph: the
  // folder is reused, so the old sheet goes before the new one is asked for.
  for (final File stale in <File>[
    RollStore.contactFile(target),
    RollStore.contactRecord(target),
  ]) {
    if (stale.existsSync()) {
      stale.deleteSync();
    }
  }
  final bool prints = stock.process != FilmProcess.reversal;
  // One call, because the five frames are five developments of one negative:
  // the photograph is read once and each print is made from that read, with
  // the proof printed from the same read. The subprocess path does the same
  // five calls it always did.
  await model.roll(
    photograph: source,
    stock: stock.id,
    // The paper is part of the roll: every frame the bench shows is already
    // printed, and a print is balanced against the paper's own curve. A
    // reversal skips the print stage, and the model ignores this argument.
    paper: paper?.id ?? Stocks.paper,
    times: times,
    tempC: tempC,
    width: benchWidth,
    frames: outputs,
    sheet: prints ? RollStore.contactFile(target) : null,
    record: prints ? RollStore.contactRecord(target) : null,
    spectral: spectral,
    onProgress: onProgress,
  );
  final List<Frame> frames = <Frame>[
    for (int i = 0; i < times.length; i++)
      Frame(
        number: i + 1,
        minutes: times[i],
        tempC: tempC,
        image: await decode(outputs[i], width: benchWidth),
      ),
  ];

  // The proof is printed from the same photograph and the same times as the
  // frames, but as one exposure of the ladder rather than a corrected print of
  // each frame — which is the one thing the bench cannot draw.
  ContactProof? contact;
  if (prints) {
    try {
      contact = await ContactProof.read(
        RollStore.contactFile(target),
        RollStore.contactRecord(target),
      );
    } catch (error) {
      // A roll without its proof is still a roll, and the model already said
      // why in the console.
      Model.log('the contact proof could not be read: $error');
    }
  }

  final Roll roll = Roll(
    stockId: stock.id,
    stockLabel: stock.label,
    paperId: paper?.id,
    paperLabel: paper?.label,
    spectral: spectral,
    photo: source.path,
    frames: frames,
    contact: contact,
  );
  await RollStore.save(roll, folder: target);
  return roll;
}

/// Copy the photograph in, unless it is already here.
///
/// The name is kept rather than invented: the photograph is the one thing in
/// this folder the app did not make, and it should still be called what it was
/// called.
Future<File> _keep(File photograph, Directory folder) async {
  final String name = photograph.path.split(Platform.pathSeparator).last;
  final File kept = File('${folder.path}${Platform.pathSeparator}$name');
  if (kept.absolute.path == photograph.absolute.path) {
    return kept;
  }
  return photograph.copy(kept.path);
}
