import 'dart:io';
import 'dart:typed_data';

import 'package:kallo_ui/src/rust/api/catalogue.dart' as catalogue_api;
import 'package:kallo_ui/src/rust/api/contact.dart' as contact_api;
import 'package:kallo_ui/src/rust/api/print.dart' as print_api;
import 'package:kallo_ui/src/rust/api/roll.dart' as roll_api;
import 'package:kallo_ui/src/rust/frb_generated.dart';

import 'model.dart';

/// Load the model into this process.
///
/// Returns whether it loaded. A failure is not fatal: the app falls back to the
/// `kalo` binary, which is what it used before the library existed, and says so
/// in the console. That is also what happens under `flutter test`, where the
/// code asset is not bundled.
bool _loaded = false;

Future<bool> loadLinkedModel() async {
  if (_loaded) {
    return true;
  }
  try {
    await RustLib.init();
    Model.useLinked(const FfiModel());
    _loaded = true;
    return true;
  } catch (error) {
    Model.log('the linked model could not be loaded: $error');
    return false;
  }
}

/// The model, linked into the app.
///
/// The calls are the model's, on the bridge's thread pool: a roll is one call
/// that reads the photograph once and prints every frame from it, and a print
/// is the same pipeline at the size the export asks for.
class FfiModel implements Model {
  const FfiModel();

  /// The linked model is loaded before this object exists.
  @override
  bool get available => true;

  @override
  Future<void> develop({
    required File photograph,
    required String stock,
    required String paper,
    required double minutes,
    required double tempC,
    required int width,
    required File output,
    bool spectral = false,
  }) async {
    await print_api.makePrint(
      job: print_api.PrintJob(
        input: photograph.path,
        film: stock,
        paper: paper,
        minutes: minutes,
        tempC: tempC,
        width: width,
        spectral: spectral,
        evAuto: true,
        evStops: 0,
        printEv: 0,
        frameMm: 36,
        grain: true,
        grainSeed: BigInt.zero,
        halation: true,
        couplers: true,
        gpu: true,
        output: output.path,
      ),
    );
  }

  @override
  Future<void> contact({
    required File photograph,
    required String stock,
    required String paper,
    required List<double> times,
    required double tempC,
    required File sheet,
    required File record,
    int dpi = 600,
    bool spectral = false,
  }) async {
    await contact_api.makeContact(
      job: contact_api.ContactJob(
        input: photograph.path,
        film: stock,
        paper: paper,
        times: Float64List.fromList(times),
        tempC: tempC,
        spectral: spectral,
        evAuto: true,
        evStops: 0,
        printEv: 0,
        grain: true,
        halation: true,
        couplers: true,
        dpi: dpi.toDouble(),
        output: sheet.path,
        record: record.path,
      ),
    );
  }

  @override
  Future<void> roll({
    required File photograph,
    required String stock,
    required String paper,
    required List<double> times,
    required double tempC,
    required int width,
    required List<File> frames,
    File? sheet,
    File? record,
    int dpi = 600,
    bool spectral = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final Stream<roll_api.RollProgress> progress = roll_api.makeRoll(
      job: roll_api.RollJob(
        input: photograph.path,
        film: stock,
        paper: paper,
        times: Float64List.fromList(times),
        tempC: tempC,
        width: width,
        spectral: spectral,
        evAuto: true,
        evStops: 0,
        printEv: 0,
        frameMm: 36,
        grain: true,
        grainSeed: BigInt.zero,
        halation: true,
        couplers: true,
        gpu: true,
        frames: frames
            .map((File file) => file.path)
            .toList(growable: false),
        contact: sheet?.path,
        record: record?.path,
        dpi: dpi.toDouble(),
      ),
    );
    await for (final roll_api.RollProgress step in progress) {
      // The proof is a separate call, so only the frames move the bench clock.
      if (step.stage == 'frame') {
        onProgress?.call(step.done, step.total);
      }
    }
  }

  @override
  Future<String> catalogue() async => catalogue_api.catalogue();
}
