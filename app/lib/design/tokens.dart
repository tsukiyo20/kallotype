import 'package:flutter/widgets.dart';

/// Where the product is.
///
/// These are not themes. A darkroom is a dark room with one safelight in it; a
/// light table is a lit surface with film lying on it. The app moves between
/// two places, and the transition between them is a transition between
/// *lighting*, not between colour schemes.
enum KalloEnvironment { darkroom, lightTable }

double _mix(double a, double b, double t) => a + (b - a) * t;

/// Everything the interface is allowed to be coloured with.
///
/// One accent. Everything else is a neutral on a single luminance ramp, because
/// the contrast in this product comes from density — from brightness — and not
/// from hue. That is also how a negative works.
@immutable
class KalloColors {
  const KalloColors({
    required this.ground,
    required this.surface,
    required this.surfaceRaised,
    required this.hairline,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.accentDim,
    required this.emissive,
  });

  /// Behind everything.
  final Color ground;

  /// What a panel is made of.
  final Color surface;

  /// What a panel that sits on a panel is made of.
  final Color surfaceRaised;

  /// The only border in the app. There are no shadows for depth.
  final Color hairline;

  /// Text that must be read.
  final Color ink;

  /// Text that must be present.
  final Color inkMuted;

  /// Text that must be felt.
  final Color inkFaint;

  /// The safelight. The only saturated colour in the product.
  final Color accent;

  /// The safelight, further away.
  final Color accentDim;

  /// 0 in the darkroom, 1 on the light table.
  ///
  /// Everything that appears to give off light is multiplied by this, and it is
  /// the quantity the environment transition animates. It is a property of the
  /// colors rather than of the enum so that it can be interpolated.
  final double emissive;

  static const KalloColors darkroom = KalloColors(
    ground: Color(0xFF060505),
    surface: Color(0xFF0D0B0A),
    surfaceRaised: Color(0xFF141110),
    hairline: Color(0xFF231D18),
    ink: Color(0xFFC8BCAC),
    inkMuted: Color(0xFF7C7164),
    inkFaint: Color(0xFF4B433A),
    accent: Color(0xFFD0672A),
    accentDim: Color(0xFF7E3A15),
    emissive: 0.0,
  );

  static const KalloColors lightTable = KalloColors(
    ground: Color(0xFFE9E6E0),
    surface: Color(0xFFF7F5F1),
    surfaceRaised: Color(0xFFFFFFFF),
    hairline: Color(0xFFD5CFC5),
    ink: Color(0xFF171410),
    inkMuted: Color(0xFF6A6459),
    inkFaint: Color(0xFFA29B90),
    accent: Color(0xFF9B3A12),
    accentDim: Color(0xFFC9805C),
    emissive: 1.0,
  );

  static KalloColors of(KalloEnvironment environment) =>
      environment == KalloEnvironment.darkroom ? darkroom : lightTable;

  static KalloColors lerp(KalloColors a, KalloColors b, double t) => KalloColors(
        ground: Color.lerp(a.ground, b.ground, t)!,
        surface: Color.lerp(a.surface, b.surface, t)!,
        surfaceRaised: Color.lerp(a.surfaceRaised, b.surfaceRaised, t)!,
        hairline: Color.lerp(a.hairline, b.hairline, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
        inkMuted: Color.lerp(a.inkMuted, b.inkMuted, t)!,
        inkFaint: Color.lerp(a.inkFaint, b.inkFaint, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        accentDim: Color.lerp(a.accentDim, b.accentDim, t)!,
        emissive: _mix(a.emissive, b.emissive, t),
      );
}

/// Six steps, and nothing between them.
///
/// The gaps are the point: a layout that uses 4, 8, 16 and 32 reads as
/// deliberate, and one that uses 4, 6, 8, 10, 12 reads as default.
abstract final class KalloSpace {
  static const double step0 = 2;
  static const double step1 = 4;
  static const double step2 = 8;
  static const double step3 = 16;
  static const double step4 = 32;
  static const double step5 = 64;
}

/// Two radii, and nothing between them.
abstract final class KalloRadius {
  /// Film is almost sharp. A frame is a rectangle of emulsion, not a card.
  static const double film = 1.5;

  /// A sheet of paper, a panel, a popover.
  static const double sheet = 12;
}

/// Motion, stated once.
///
/// Durations sit in the 90–460 ms band and the curves are not `easeInOut`:
/// `enter` arrives fast and stops, `leave` departs without ceremony, `settle`
/// lands with weight. Anything that moves together is staggered by [stagger].
abstract final class KalloMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration settle = Duration(milliseconds: 240);

  /// The environment transition: a light coming up, not a page changing.
  static const Duration slow = Duration(milliseconds: 460);

  static const Duration stagger = Duration(milliseconds: 40);

  static const Curve enter = Cubic(0.16, 1.0, 0.30, 1.0);
  static const Curve leave = Cubic(0.70, 0.0, 0.84, 0.0);
  static const Curve settleCurve = Cubic(0.22, 0.61, 0.36, 1.0);
}

/// Five roles, not fifteen sizes.
///
/// A face is not chosen yet: [sans] is `null`, which means the platform's own,
/// and it is a variable rather than a constant so that a face can be loaded at
/// startup — and so that the golden test can load a real one, because the test
/// renderer otherwise draws every glyph as a box.
abstract final class KalloType {
  static String? sans;

  /// The face covers Latin; the labels are Chinese. These are the families the
  /// engine falls back to for everything the first one has no glyph for, in the
  /// order the platforms are likeliest to have them.
  static const List<String> sansFallback = <String>[
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'DengXian',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
  ];

  static const String monoFamily = 'Menlo';
  static const List<String> monoFallback = <String>[
    'SF Mono',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'monospace',
  ];

  static const TextStyle _display = TextStyle(
    fontFamilyFallback: sansFallback,
    fontSize: 34,
    height: 1.06,
    letterSpacing: -0.9,
    fontWeight: FontWeight.w300,
  );

  static const TextStyle _title = TextStyle(
    fontFamilyFallback: sansFallback,
    fontSize: 19,
    height: 1.2,
    letterSpacing: -0.2,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle _body = TextStyle(
    fontFamilyFallback: sansFallback,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle _caption = TextStyle(
    fontFamilyFallback: sansFallback,
    fontSize: 10.5,
    height: 1.2,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w600,
  );

  /// The one number on the screen that matters.
  static TextStyle get display => _display.copyWith(fontFamily: sans);

  /// A section, a name.
  static TextStyle get title => _title.copyWith(fontFamily: sans);

  /// Prose.
  static TextStyle get body => _body.copyWith(fontFamily: sans);

  /// A label, set small and spaced out, always upper case.
  static TextStyle get caption => _caption.copyWith(fontFamily: sans);

  /// Anything that is a measurement. Tabular, so that a number changing does
  /// not move the things around it.
  static const TextStyle data = TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: 12.5,
    height: 1.3,
    letterSpacing: 0.2,
    fontWeight: FontWeight.w400,
    fontFeatures: <FontFeature>[FontFeature('tnum')],
  );
}
