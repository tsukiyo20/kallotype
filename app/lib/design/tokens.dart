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

  /// The safelight in the dark, and the grease pencil in the light. The same
  /// hue in two materials, and the only saturated colour in the chrome.
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

  /// The table, lit: warm paper, ink, and a grease pencil.
  static const KalloColors lightTable = KalloColors(
    ground: Color(0xFFF5F1E9),
    surface: Color(0xFFFCFAF6),
    surfaceRaised: Color(0xFFFFFFFF),
    hairline: Color(0xFFD9D1C3),
    ink: Color(0xFF1A1712),
    inkMuted: Color(0xFF6E6659),
    inkFaint: Color(0xFFA69C8C),
    accent: Color(0xFF9E3B14),
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

/// One superfamily, four cuts, three voices.
///
/// Bundled rather than borrowed from the platform, because the product has to
/// look identical on six of them and because the golden tests can then be
/// portable: a face the test does not have is a box, and a design judged on its
/// type cannot be judged as boxes.
///
/// | cut | voice |
/// |---|---|
/// | [sans] | body, controls |
/// | [condensed] | the film: labels, the big numeral |
/// | [mono] | the instrument: anything measured |
/// | [serif] | the paper: records, captions, prose |
///
/// The Chinese cut is bundled too, one weight. It is 8.4 MB, and it is the
/// difference between six builds that agree and six that each borrow a face.
abstract final class KalloType {
  static const String sans = 'PlexSans';
  static const String condensed = 'PlexCondensed';
  static const String mono = 'PlexMono';
  static const String serif = 'PlexSerif';

  /// Families the engine falls back to for everything Plex has no glyph for.
  /// Bundled first, so Chinese is the same on all six platforms; the platform's
  /// own face is only for the rare character the bundled cut does not carry.
  static const List<String> cjkFallback = <String>[
    'PlexSansSC',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
  ];

  static const String monoFallback = 'Menlo';

  /// A number may sit next to a Chinese word — `显影 04` — so the mono cut has
  /// to fall back to the same Chinese as everything else.
  static const List<String> monoFallbackList = <String>[
    monoFallback,
    'PlexSansSC',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
  ];

  static const List<FontFeature> _tabular = <FontFeature>[FontFeature('tnum')];

  /// The one big numeral on a screen.
  static const TextStyle plate = TextStyle(
    fontFamily: condensed,
    fontFamilyFallback: cjkFallback,
    fontSize: 34,
    height: 1.0,
    letterSpacing: 0.4,
    fontWeight: FontWeight.w600,
  );

  /// A screen's title.
  static const TextStyle display = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: cjkFallback,
    fontSize: 30,
    height: 1.1,
    letterSpacing: -0.6,
    fontWeight: FontWeight.w400,
  );

  /// A section of paper.
  static const TextStyle title = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: cjkFallback,
    fontSize: 19,
    height: 1.25,
    fontWeight: FontWeight.w400,
  );

  /// Prose.
  static const TextStyle body = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: cjkFallback,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  /// A label, set small and spaced out, always upper case.
  static const TextStyle caption = TextStyle(
    fontFamily: condensed,
    fontFamilyFallback: cjkFallback,
    fontSize: 9.5,
    height: 1.2,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w600,
  );

  /// Anything that is a measurement. Tabular, so that a number changing does
  /// not move the things around it.
  static const TextStyle data = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallbackList,
    fontSize: 12.5,
    height: 1.3,
    letterSpacing: 0.1,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
  );

  /// A frame number, an edge code. Smaller than [data], still tabular.
  static const TextStyle folio = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallbackList,
    fontSize: 10,
    height: 1.2,
    letterSpacing: 0.5,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
  );
}
