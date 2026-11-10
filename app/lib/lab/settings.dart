import 'dart:convert';
import 'dart:io';

/// The choices that outlive a window.
///
/// A file, not a service: this app has one setting the system does not already
/// own, and a file a person can open and delete is worth more than one they
/// cannot. It is also the file the next four settings will go in.
class Settings {
  const Settings({this.exportPath});

  /// The folder prints are exported to and read from, or null for the place the
  /// platform gives the app.
  final String? exportPath;

  Settings withExports(String? path) => Settings(exportPath: path);

  static const String _name = 'settings.json';

  /// Where the platform puts an app's own settings. Null where there is no
  /// such place to name, and then nothing is remembered — which is better than
  /// remembering it in whatever the working directory happens to be.
  static File? get file {
    final String separator = Platform.pathSeparator;
    final Map<String, String> environment = Platform.environment;
    final String? home = environment['HOME'];
    if (Platform.isMacOS && home != null) {
      return File('$home/Library/Application Support/dev.kallotype.app'
          '$separator$_name');
    }
    if (Platform.isWindows) {
      final String? roaming = environment['APPDATA'];
      if (roaming != null) {
        return File('$roaming${separator}Kallotype$separator$_name');
      }
    }
    final String? config = environment['XDG_CONFIG_HOME'];
    if (config != null && config.isNotEmpty) {
      return File('$config/kallotype/$_name');
    }
    // A phone has no XDG and no APPDATA: the app's container is its home, and
    // the file lives quietly inside it.
    if (home != null) {
      return File('$home/.config/kallotype/$_name');
    }
    return null;
  }

  static Future<Settings> read() async {
    final File? file = Settings.file;
    if (file == null || !file.existsSync()) {
      return const Settings();
    }
    final String text;
    try {
      text = await file.readAsString();
    } on FileSystemException {
      return const Settings();
    }
    try {
      final Object? json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        final Object? exports = json['exports'];
        return Settings(exportPath: exports is String ? exports : null);
      }
    } on FormatException {
      // A settings file that is not JSON is a settings file somebody edited.
      // Start again rather than refusing to open.
      return const Settings();
    }
    return const Settings();
  }

  Future<void> write() async {
    final File? file = Settings.file;
    if (file == null) {
      return;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          if (exportPath != null) 'exports': exportPath,
        }),
      );
    } on FileSystemException {
      // A setting that cannot be saved is a setting that does not survive the
      // window. It is not worth a dialog.
    }
  }
}
