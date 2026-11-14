import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'print.dart';
import 'print_store.dart';

/// The export folder: where the model's prints land, and what is in there.
///
/// A print is a file before it is anything else. The model writes it out and
/// the gallery hangs whatever it finds, so nothing is bundled with the app and
/// an app that has never printed anything has nothing to hang — which is the
/// truth, and is the state the gallery is built to show.
///
/// When the model is behind an FFI, this is the folder it writes to, and this
/// class is the one place that knows where that is.
abstract final class Exports {
  /// The name of the folder inside the pictures directory.
  static const String folder = 'Kallotype';

  /// The folder of finished film frames, inside the export folder.
  ///
  /// A framed export is a second finished thing, not another print: the gallery
  /// reads the export folder itself, and a frame beside a print would hang
  /// twice. The subfolder is also where a person goes when they want the
  /// version with the rebate.
  static const String frames = 'Frames';

  /// Where a print's film frames are written.
  static Directory framesFolder(Directory folder) =>
      Directory('${folder.path}${Platform.pathSeparator}$frames');

  /// Whether the app can ask for a folder.
  ///
  /// A chooser is a desktop idea. A phone does not let an app browse the
  /// filesystem, and it does not need to: the system already decides where an
  /// app's documents are, and it shows them — Files on iOS, the storage browser
  /// on Android. Asking the user to pick a folder there would be asking them to
  /// undo the platform.
  static bool get canChoose =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Where prints go when the user has not said otherwise.
  ///
  /// On a phone there is nowhere else: the app's own container is the one place
  /// it can write without a permission dialog, and iOS shows that container as
  /// the app's folder in Files. On the desktop it is the pictures folder the
  /// person already has, because that is where pictures go.
  static Directory? get defaultDirectory {
    final Map<String, String> environment = Platform.environment;
    if (Platform.isIOS) {
      final String? home = environment['HOME'];
      return home == null ? null : Directory('$home/Documents');
    }
    if (!canChoose) {
      // Android owns a directory of its own for an app, and finding it needs
      // the platform's API rather than a guess: `Android/data/...` is a path
      // that changes shape between devices and versions. Until that call is
      // made, the honest answer is that there is no folder yet.
      return null;
    }
    final String? pictures = environment['XDG_PICTURES_DIR'];
    if (pictures != null && pictures.isNotEmpty) {
      return Directory('$pictures/$folder');
    }
    final String? home = environment['HOME'] ?? environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      return null;
    }
    return Directory(
      '$home${Platform.pathSeparator}Pictures'
      '${Platform.pathSeparator}$folder',
    );
  }

  /// The folder in use: the one the user chose, or the platform's own.
  static Directory? directoryFor(String? chosen) =>
      chosen != null && chosen.isNotEmpty
      ? Directory(chosen)
      : defaultDirectory;

  /// `~/Pictures/Kallotype` — a path with the home shortened, because a path
  /// that begins with a person's name begins with noise.
  static String display(String? path) {
    if (path == null || path.isEmpty) {
      return '';
    }
    final String? home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  /// Ask the system for a folder. Null when the platform has no such dialog, or
  /// the person changed their mind.
  static Future<String?> choose() async {
    if (!canChoose) {
      return null;
    }
    return getDirectoryPath(confirmButtonText: 'Choose');
  }

  /// Every exported print, oldest first, so that the last one is the one that
  /// would be hanging.
  ///
  /// A folder that does not exist is an empty gallery, not an error: nobody has
  /// printed anything yet, which is the ordinary state of a darkroom.
  static Future<List<Print>> read({Directory? folder, int width = 1600}) async {
    if (folder == null || !folder.existsSync()) {
      return const <Print>[];
    }
    final List<File> images =
        <File>[
          for (final FileSystemEntity entity in folder.listSync())
            if (entity is File && entity.path.toLowerCase().endsWith('.png'))
              entity,
        ]..sort((File a, File b) {
          final DateTime left = a.statSync().modified;
          final DateTime right = b.statSync().modified;
          return left.compareTo(right);
        });

    final Map<String, PrintRecord> metadata = await PrintStore.load(
      exports: folder,
      frames: framesFolder(folder),
    );
    final List<Print> prints = <Print>[];
    for (final File image in images) {
      final Print? print = await Print.read(
        image,
        width: width,
        record: metadata[image.path],
      );
      if (print != null) {
        prints.add(print);
      }
    }
    return prints;
  }
}

/// What the drawer needs to say about the export folder, and what it can do
/// about it.
@immutable
class ExportSetting {
  const ExportSetting({
    required this.label,
    required this.canChoose,
    required this.custom,
    this.onChoose,
    this.onReset,
  });

  /// The folder as a person reads it: `~/Pictures/Kallotype`.
  final String label;

  /// Whether a chooser exists on this platform.
  final bool canChoose;

  /// Whether the folder is the person's choice rather than the platform's.
  final bool custom;

  final VoidCallback? onChoose;
  final VoidCallback? onReset;
}
