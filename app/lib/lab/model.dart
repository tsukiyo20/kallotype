import 'dart:io';

import 'package:flutter/foundation.dart';

import 'chart.dart';

/// The model, as this app sees it.
///
/// There are two ways to reach the same Rust code today: a `kalo` binary run as
/// a subprocess, and the model linked into the app through `flutter_rust_bridge`
/// as a dynamic library. They answer the same calls, so this is the interface
/// both implement, and `find()` picks one.
///
/// The subprocess is the development path — no rebuild of the app, a crash in
/// the model is a crash of a process — and the library is the shipping path.
/// The shape of a call is the subprocess's shape, which is why moving the
/// boundary changed only the middle of this file.
abstract class Model {
  /// Whether the model can be asked to do anything.
  bool get available;

  /// Develop a photograph at one time, and write the print where asked.
  ///
  /// The size is the size the bench can show, not the size the photograph is.
  /// It is passed to the model rather than applied afterwards, because the
  /// grain belongs to the sampling: a smaller render is a coarser scan, and it
  /// has to look like one.
  Future<void> develop({
    required File photograph,
    required String stock,
    required String paper,
    required double minutes,
    required double tempC,
    required int width,
    required File output,
    bool spectral = false,
  });

  /// Print the contact proof: the ladder on one sheet, exposed once.
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
  });

  /// Develop a whole roll: one read of the photograph, one print per time.
  ///
  /// The subprocess implementation is the same five calls `develop` makes, one
  /// after another. The library implementation is one call, because the
  /// photograph is read once and every frame is a different development of the
  /// same negative — which is what a roll is.
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
  });

  /// The densitometer's reading of the strip: nine patches per development.
  ///
  /// A non-null answer is a measurement — the dye plus the base, fog and mask
  /// the instrument reads through — not the curves sampled at nine exposures.
  /// Null when the model cannot be asked: the subprocess writes pixels and no
  /// densities, so a roll developed that way has pictures and no chart.
  Future<List<FilmChart>?> chart({
    required String stock,
    required List<double> times,
    required double tempC,
  });

  /// Ask the model what stock it carries.
  ///
  /// One call, one document: every film and paper with its provenance, so that
  /// the shelf and the binder show the model's own list rather than a list
  /// about it.
  Future<String> catalogue();

  /// Something the model said that the app can live without.
  ///
  /// A missing catalogue is not a broken app: the shelf holds its one film and
  /// says so. It is worth a line in the console and nothing more.
  static void log(String message) => debugPrint(message);

  /// The linked model, once [Model] has been told it loaded.
  static Model? _linked;

  /// Tell [find] that the library is loaded and should be preferred.
  static void useLinked(Model model) => _linked = model;

  /// Find the model.
  ///
  /// The linked library first, because a shipped app carries it. Then the
  /// subprocess, in order: what the environment says, then a walk up from the
  /// running app looking for a built binary. The walk is a development
  /// convenience and not a contract.
  static Model find() {
    final Model? linked = _linked;
    if (linked != null) {
      return linked;
    }
    return ProcessModel.find();
  }
}

/// The model, as a process.
///
/// The darkroom is a Rust program and this app is its face. Until the library
/// is loaded, asking it to develop something means running it — which is why
/// every call goes through one method here.
class ProcessModel implements Model {
  const ProcessModel(this.executable);

  /// The `kalo` binary's path, or empty when this build cannot find one.
  final String executable;

  @override
  bool get available => executable.isNotEmpty;

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
    if (!available) {
      throw const ModelMissing();
    }
    final ProcessResult result = await Process.run(executable, <String>[
      'render',
      photograph.path,
      '-o',
      output.path,
      '--film',
      stock,
      '--paper',
      paper,
      '--dev',
      minutes.toStringAsFixed(2),
      '--temp',
      tempC.toStringAsFixed(1),
      '--ev',
      'auto',
      '--grain',
      // The two stages that cost nothing and are physics rather than polish:
      // light that scattered in the emulsion and reflected off the base, and
      // the inhibition a developing layer releases into its neighbours. Both
      // are sub-pixel at the bench's width — a 30 µm pixel cannot show an 11 µm
      // scatter — so they read as a slight change of density and edge contrast
      // here, and as themselves in a full-size print.
      '--halation',
      '--couplers',
      // The three spectral stages, when asked for: the input is reconstructed
      // into a spectrum and integrated against the film's layers, the print
      // goes through dye absorption and the paper's layers, and the scan turns
      // reflectance into XYZ and linear sRGB. The model keeps them opt-in and
      // the ADRs say why: the structure is physical end to end, the numbers
      // behind it are still placeholder shapes.
      if (spectral) ...<String>[
        '--spectral',
        '--spectral-print',
        '--spectral-scan',
      ],
      '--size',
      '$width',
    ]);
    if (result.exitCode != 0) {
      throw ModelFailed(result.stderr.toString().trim());
    }
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
    if (!available) {
      throw const ModelMissing();
    }
    final ProcessResult result = await Process.run(executable, <String>[
      'contact',
      photograph.path,
      '-o',
      sheet.path,
      '--record',
      record.path,
      '--film',
      stock,
      '--paper',
      paper,
      '--dev',
      times.map((double minutes) => minutes.toStringAsFixed(2)).join(','),
      '--temp',
      tempC.toStringAsFixed(1),
      '--ev',
      'auto',
      '--grain',
      '--halation',
      '--couplers',
      // The proof is a print, not a scan: the spectral stages that make sense
      // here are the exposure and the print, and the model's `contact` command
      // carries exactly those.
      if (spectral) '--spectral',
      '--dpi',
      '$dpi',
    ]);
    if (result.exitCode != 0) {
      throw ModelFailed(result.stderr.toString().trim());
    }
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
    for (int i = 0; i < times.length; i++) {
      await develop(
        photograph: photograph,
        stock: stock,
        paper: paper,
        minutes: times[i],
        tempC: tempC,
        width: width,
        output: frames[i],
        spectral: spectral,
      );
      onProgress?.call(i + 1, times.length);
    }
    if (sheet != null && record != null) {
      // A roll without its proof is still a roll: the table falls back to the
      // chart it can draw, and the developer can say why in the console.
      try {
        await contact(
          photograph: photograph,
          stock: stock,
          paper: paper,
          times: times,
          tempC: tempC,
          sheet: sheet,
          record: record,
          dpi: dpi,
          spectral: spectral,
        );
      } catch (error) {
        Model.log('the contact proof could not be printed: $error');
      }
    }
  }

  /// The subprocess writes pixels, not the densities behind them: a chart it
  /// could not measure is a chart with rows invented, so it is null.
  @override
  Future<List<FilmChart>?> chart({
    required String stock,
    required List<double> times,
    required double tempC,
  }) async =>
      null;

  @override
  Future<String> catalogue() async {
    if (!available) {
      throw const ModelMissing();
    }
    final ProcessResult result = await Process.run(executable, <String>[
      'stocks',
      '--json',
    ]);
    if (result.exitCode != 0) {
      throw ModelFailed(result.stderr.toString().trim());
    }
    return result.stdout as String;
  }

  /// Find the binary.
  ///
  /// In order: what the environment says, then a walk up from the running app
  /// looking for a built binary. The walk is a development convenience and not
  /// a contract — a shipped app carries the library instead.
  static ProcessModel find() {
    final String? named = Platform.environment['KALLOTYPE_MODEL'];
    if (named != null && named.isNotEmpty && File(named).existsSync()) {
      return ProcessModel(named);
    }
    // Two places to start from, because the app and the tests are launched from
    // different ones: the bundle sits inside a build directory, and the test
    // runner sits inside a Flutter SDK, but the working directory is the app's
    // own in both cases when a person is running this.
    for (final Directory? origin in <Directory?>[
      File(Platform.resolvedExecutable).parent,
      Directory.current,
    ]) {
      final ProcessModel? found = _near(origin);
      if (found != null) {
        return found;
      }
    }
    return const ProcessModel('');
  }

  /// Walk up looking for a built binary.
  static ProcessModel? _near(Directory? start) {
    Directory? directory = start;
    for (int depth = 0; depth < 12 && directory != null; depth++) {
      final File candidate = File(
        '${directory.path}${Platform.pathSeparator}target'
        '${Platform.pathSeparator}release${Platform.pathSeparator}kalo',
      );
      if (candidate.existsSync()) {
        return ProcessModel(candidate.path);
      }
      final Directory parent = directory.parent;
      directory = parent.path == directory.path ? null : parent;
    }
    return null;
  }
}

/// There is no model on this machine: the shelf can hold stock, but nothing can
/// be developed until there is a binary to ask.
class ModelMissing implements Exception {
  const ModelMissing();

  @override
  String toString() => 'no kalo binary';
}

/// The model ran and would not do it.
class ModelFailed implements Exception {
  const ModelFailed(this.message);

  final String message;

  @override
  String toString() => message;
}
