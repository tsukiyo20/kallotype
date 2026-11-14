/// Who the app is.
///
/// The version is repeated from `pubspec.yaml` because Flutter does not expose
/// the package's version to the Dart runtime. `app_info_test.dart` reads the
/// pubspec and fails when the two disagree.
abstract final class KalloInfo {
  static const String name = 'Kallo';
  static const String version = '0.1.0';
  static const String repository = 'https://github.com/tsukiyo20/kallotype';
}
