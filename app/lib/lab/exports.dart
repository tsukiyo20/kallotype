import 'dart:io';

import 'print.dart';

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

  /// Where a person would look for it: the pictures folder the platform
  /// already has, because that is where pictures go. Null where there is no
  /// such place to name — an app on a phone has its own container instead, and
  /// that path is a platform question this build does not answer yet.
  static Directory? get directory {
    final Map<String, String> environment = Platform.environment;
    final String? pictures = environment['XDG_PICTURES_DIR'];
    if (pictures != null && pictures.isNotEmpty) {
      return Directory('$pictures/$folder');
    }
    final String? home =
        environment['HOME'] ?? environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      return null;
    }
    return Directory('$home${Platform.pathSeparator}Pictures'
        '${Platform.pathSeparator}$folder');
  }

  /// Every exported print, oldest first, so that the last one is the one that
  /// would be hanging.
  ///
  /// A folder that does not exist is an empty gallery, not an error: nobody has
  /// printed anything yet, which is the ordinary state of a darkroom.
  static Future<List<Print>> read({int width = 1600}) async {
    final Directory? folder = directory;
    if (folder == null || !folder.existsSync()) {
      return const <Print>[];
    }
    final List<File> images = <File>[
      for (final FileSystemEntity entity in folder.listSync())
        if (entity is File && entity.path.toLowerCase().endsWith('.png'))
          entity,
    ]..sort((File a, File b) {
        final DateTime left = a.statSync().modified;
        final DateTime right = b.statSync().modified;
        return left.compareTo(right);
      });

    final List<Print> prints = <Print>[];
    for (final File image in images) {
      final Print? print = await Print.read(image, width: width);
      if (print != null) {
        prints.add(print);
      }
    }
    return prints;
  }
}
