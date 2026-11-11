import 'dart:io';

import 'stock.dart';

/// The model, as a process.
///
/// The darkroom is a Rust program and this app is its face. Until the model is
/// behind an FFI, asking it to develop something means running it — which is
/// why every call goes through one method here: the shape a binding will have
/// is the shape a subprocess already has, and only the middle of this file
/// changes when the boundary moves.
class Model {
  const Model(this.executable);

  /// The `kalo` binary's path, or empty when this build cannot find one.
  final String executable;

  bool get available => executable.isNotEmpty;

  /// Find the model.
  ///
  /// In order: what the environment says, then a walk up from the running app
  /// looking for a built binary. The walk is a development convenience and not
  /// a contract — a shipped app would carry the model inside itself, which is
  /// the FFI this class exists to be replaced by.
  static Model find() {
    final String? named = Platform.environment['KALLOTYPE_MODEL'];
    if (named != null && named.isNotEmpty && File(named).existsSync()) {
      return Model(named);
    }
    // Two places to start from, because the app and the tests are launched from
    // different ones: the bundle sits inside a build directory, and the test
    // runner sits inside a Flutter SDK, but the working directory is the app's
    // own in both cases when a person is running this.
    for (final Directory? origin in <Directory?>[
      File(Platform.resolvedExecutable).parent,
      Directory.current,
    ]) {
      final Model? found = _near(origin);
      if (found != null) {
        return found;
      }
    }
    return const Model('');
  }

  /// Walk up looking for a built binary.
  static Model? _near(Directory? start) {
    Directory? directory = start;
    for (int depth = 0; depth < 12 && directory != null; depth++) {
      final File candidate = File(
        '${directory.path}${Platform.pathSeparator}target'
        '${Platform.pathSeparator}release${Platform.pathSeparator}kalo',
      );
      if (candidate.existsSync()) {
        return Model(candidate.path);
      }
      final Directory parent = directory.parent;
      directory = parent.path == directory.path ? null : parent;
    }
    return null;
  }

  /// Develop a photograph at one time, and write the print where asked.
  ///
  /// The size is the size the bench can show, not the size the photograph is.
  /// It is passed to the model rather than applied afterwards, because the
  /// grain belongs to the sampling: a smaller render is a coarser scan, and it
  /// has to look like one.
  Future<void> develop({
    required File photograph,
    required String stock,
    required double minutes,
    required double tempC,
    required int width,
    required File output,
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
      Stocks.paper,
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
      '--size',
      '$width',
    ]);
    if (result.exitCode != 0) {
      throw ModelFailed(result.stderr.toString().trim());
    }
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
