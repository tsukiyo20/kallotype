import 'dart:convert';
import 'dart:io';

/// The choices that outlive a window.
///
/// A file, not a service: these are the two choices the system does not already
/// own — where prints go, and which path a new roll is developed through — and
/// a file a person can open and delete is worth more than one they cannot.
class Settings {
  const Settings({this.exportPath, this.spectral = false});

  /// The folder prints are exported to and read from, or null for the place the
  /// platform gives the app.
  final String? exportPath;

  /// Whether a new roll is developed through the spectral path.
  ///
  /// It is a setting rather than a fact of the app because the model keeps it
  /// opt-in: the structure is physical end to end and every spectral input is
  /// still a placeholder shape (ADR 0003, 0005, 0006), so it changes the colour
  /// and not only its accuracy. The render is the same speed on a GPU and slower
  /// on a CPU, which is why the switch says nothing about speed either.
  final bool spectral;

  Settings withExports(String? path) =>
      Settings(exportPath: path, spectral: spectral);

  Settings withSpectral(bool on) =>
      Settings(exportPath: exportPath, spectral: on);

  static const String _name = 'settings.json';

  /// The app's own folder: settings, and the roll being carried. Null where
  /// there is no such place to name.
  static Directory? get directory {
    final String separator = Platform.pathSeparator;
    final Map<String, String> environment = Platform.environment;
    final String? home = environment['HOME'];
    if (Platform.isMacOS && home != null) {
      return Directory('$home/Library/Application Support/dev.kallotype.app');
    }
    if (Platform.isWindows) {
      final String? roaming = environment['APPDATA'];
      if (roaming != null) {
        return Directory('$roaming${separator}Kallotype');
      }
    }
    final String? config = environment['XDG_CONFIG_HOME'];
    if (config != null && config.isNotEmpty) {
      return Directory('$config/kallotype');
    }
    // A phone has no XDG and no APPDATA: the app's container is its home, and
    // the file lives quietly inside it.
    if (home != null) {
      return Directory('$home/.config/kallotype');
    }
    return null;
  }

  static File? get file {
    final Directory? folder = directory;
    return folder == null
        ? null
        : File('${folder.path}${Platform.pathSeparator}$_name');
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
        return Settings(
          exportPath: exports is String ? exports : null,
          spectral: json['spectral'] == true,
        );
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
          if (spectral) 'spectral': true,
        }),
      );
    } on FileSystemException {
      // A setting that cannot be saved is a setting that does not survive the
      // window. It is not worth a dialog.
    }
  }
}
