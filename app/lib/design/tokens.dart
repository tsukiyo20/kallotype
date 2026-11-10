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
/// A window, a sidebar, a content area and a surface: the four planes an app is
/// made of, each a step on one warm neutral ramp. The accent is the safelight,
/// and it is the only colour that is not on that ramp.
@immutable
class KalloColors {
  const KalloColors({
    required this.ground,
    required this.sidebar,
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

  /// Behind everything, and the colour the window is.
  final Color ground;

  /// The column of places. A step darker than the content, never a border.
  final Color sidebar;

  /// A panel, a card, the inspector.
  final Color surface;

  /// Something that sits on a panel.
  final Color surfaceRaised;

  /// The one border in the app, and it is a device pixel.
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
    sidebar: Color(0xFF0A0807),
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

  /// The table, lit: a warm window, a dimmer column, white panels.
  static const KalloColors lightTable = KalloColors(
    ground: Color(0xFFEFEBE4),
    sidebar: Color(0xFFE6E1D7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    hairline: Color(0xFFD8D2C7),
    ink: Color(0xFF1F1D1A),
    inkMuted: Color(0xFF6B665D),
    inkFaint: Color(0xFFA39D92),
    accent: Color(0xFFB8501E),
    accentDim: Color(0xFFD79A6E),
    emissive: 1.0,
  );

  static KalloColors of(KalloEnvironment environment) =>
      environment == KalloEnvironment.darkroom ? darkroom : lightTable;

  static KalloColors lerp(KalloColors a, KalloColors b, double t) => KalloColors(
        ground: Color.lerp(a.ground, b.ground, t)!,
        sidebar: Color.lerp(a.sidebar, b.sidebar, t)!,
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

/// The spacing ramp. Six steps, and the gaps are the point.
abstract final class KalloSpace {
  static const double step0 = 2;
  static const double step1 = 4;
  static const double step2 = 8;
  static const double step3 = 12;
  static const double step4 = 16;
  static const double step5 = 24;
  static const double step6 = 32;
}

/// Corners. Controls are tight, cards are rounder, sheets rounder still.
abstract final class KalloRadius {
  /// A frame on the sheet. Almost sharp: a rectangle of emulsion.
  static const double film = 3;

  /// A button, a field, a segmented control.
  static const double control = 6;

  /// A card, a panel, the inspector.
  static const double card = 10;

  /// A sheet that slides over everything.
  static const double sheet = 14;
}

/// Depth.
///
/// One shadow, for things that float above the window: a card, a popover, the
/// drawer. Nothing else is raised — the planes of the app do that with colour.
abstract final class KalloShadow {
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 0)),
  ];

  static const List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), blurRadius: 32, offset: Offset(0, 10)),
  ];
}

/// Motion, stated once.
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

/// One family, three weights, and tabular figures.
///
/// Inter is the closest open face to the one the platform already uses on a
/// Mac, which is the point: the interface should read as a tool, not as a
/// poster. The Chinese cut is bundled so the six builds agree; the platform's
/// own face is only for a character the bundled cut does not carry.
abstract final class KalloType {
  static const String sans = 'Inter';

  static const List<String> fallback = <String>[
    'PlexSansSC',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
  ];

  static const List<FontFeature> _tabular = <FontFeature>[FontFeature('tnum')];

  /// The one large number: a frame, a time.
  static const TextStyle plate = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: fallback,
    fontSize: 28,
    height: 1.05,
    letterSpacing: -0.6,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
  );

  /// A screen's title.
  static const TextStyle display = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: fallback,
    fontSize: 20,
    height: 1.2,
    letterSpacing: -0.3,
    fontWeight: FontWeight.w600,
  );

  /// A section, a card title.
  static const TextStyle title = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: fallback,
    fontSize: 15,
    height: 1.25,
    letterSpacing: -0.1,
    fontWeight: FontWeight.w600,
  );

  /// Prose, and every label that is not a heading.
  static const TextStyle body = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: fallback,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  /// The small print under a thing.
  static const TextStyle small = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: fallback,
    fontSize: 11.5,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  /// A section header, set small and spaced out, always upper case.
  static const TextStyle caption = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: fallback,
    fontSize: 10.5,
    height: 1.2,
    letterSpacing: 0.7,
    fontWeight: FontWeight.w600,
  );

  /// Anything that is a measurement. Tabular, so that a number changing does
  /// not move the things around it.
  static const TextStyle data = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: fallback,
    fontSize: 12,
    height: 1.3,
    letterSpacing: 0,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
  );

  /// A frame number, an edge code.
  static const TextStyle folio = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: fallback,
    fontSize: 11,
    height: 1.2,
    letterSpacing: 0,
    fontWeight: FontWeight.w500,
    fontFeatures: _tabular,
  );
}
