import 'package:flutter/widgets.dart';

/// Everything the interface is allowed to be coloured with.
///
/// A window, a column of places, a content field and a surface: the four planes
/// an app is made of. Two complete sets, one for each appearance, and the
/// system decides which unless the user pins one.
///
/// The accent is the safelight, turned down: it appears on a selection and on
/// the tone curve, and nowhere else. Everything else is a neutral, because the
/// colour in this product belongs to the photographs.
@immutable
class KalloColors {
  const KalloColors({
    required this.brightness,
    required this.ground,
    required this.sidebar,
    required this.content,
    required this.surface,
    required this.hairline,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.accentDim,
    required this.print,
  });

  final Brightness brightness;

  /// Behind everything, and the colour the window is.
  final Color ground;

  /// The column of places: a step off the content, toward the chrome.
  final Color sidebar;

  /// The field the work is on.
  final Color content;

  /// The inspector, a card, a panel that sits on the content.
  final Color surface;

  /// The one border in the app, and it is a device pixel.
  final Color hairline;

  /// Text that must be read.
  final Color ink;

  /// Text that must be present.
  final Color inkMuted;

  /// Text that must be felt.
  final Color inkFaint;

  /// The safelight, turned down. Selection, and the curve. Nothing else.
  final Color accent;

  /// The accent at rest.
  final Color accentDim;

  /// The paper a print sits on. Always warm, in both appearances: it is the one
  /// surface in the product that is a material rather than a plane.
  final Color print;

  static const KalloColors light = KalloColors(
    brightness: Brightness.light,
    ground: Color(0xFFF6F5F2),
    sidebar: Color(0xFFF0EEE9),
    content: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    hairline: Color(0xFFE2DFD8),
    ink: Color(0xFF1D1B18),
    inkMuted: Color(0xFF6E6A63),
    inkFaint: Color(0xFFA6A199),
    accent: Color(0xFF9A4318),
    accentDim: Color(0xFFE3C6B4),
    print: Color(0xFFFFFCF7),
  );

  static const KalloColors dark = KalloColors(
    brightness: Brightness.dark,
    ground: Color(0xFF1A1917),
    sidebar: Color(0xFF252320),
    content: Color(0xFF1C1B19),
    surface: Color(0xFF232120),
    hairline: Color(0xFF35322D),
    ink: Color(0xFFF1EEE8),
    inkMuted: Color(0xFFA29C93),
    inkFaint: Color(0xFF6E6962),
    accent: Color(0xFFC4652F),
    accentDim: Color(0xFF5A2E18),
    print: Color(0xFFF3EFE7),
  );

  static KalloColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The colour with this much light on it.
  ///
  /// Multiplied, not blended: a wall in a dark room is the same wall lit less,
  /// and a paper that was white is grey without turning blue. Alpha survives,
  /// because dimming a room is not the same as making it transparent.
  static Color under(Color colour, double light) {
    final double k = light.clamp(0.0, 1.0);
    if (k >= 1) {
      return colour;
    }
    return Color.from(
      alpha: colour.a,
      red: colour.r * k,
      green: colour.g * k,
      blue: colour.b * k,
    );
  }
}

/// What is written on a print's paper.
///
/// A sheet is a light surface in both appearances — the paper does not turn
/// dark when the window does — so what is written on it is the light set's ink
/// and it does not follow the window. The accent is the safelight at its light
/// weight: a mark on a contact sheet is a pencil, and a pencil is warm.
///
/// It is a separate vocabulary from [`KalloColors`] for the same reason the
/// wall's is: this is not a plane of the window but a material in the work.
abstract final class KalloInk {
  /// A frame's number: the one thing written on the sheet by hand.
  static const Color ink = Color(0xFF1D1B18);

  /// A time, a development, a note.
  static const Color muted = Color(0xFF6E6A63);

  /// The paper's name in the margin, and anything that is a caption.
  static const Color faint = Color(0xFFA6A199);

  /// The mark on the frame that was chosen.
  static const Color accent = Color(0xFF9A4318);
}

/// A wall: its ground, the paper on it, and the graphite beside it.
///
/// Two sets, because a wall is lit by the room it stands in. The gallery is a
/// room with a lamp, and a lamp is not a dark room: in a light appearance the
/// wall is a wall in daylight, in a dark one it is the wall after dark. The
/// lamp still goes out — but it takes the wall and the work with it, not the
/// window around them.
class KalloWall {
  const KalloWall({
    required this.top,
    required this.base,
    required this.paper,
    required this.label,
    required this.control,
    this.outline,
  });

  /// The wall at the top, where the lamp is.
  final Color top;

  /// The wall at the bottom, where the light has fallen off.
  final Color base;

  /// The paper the print is on. Warmer and duller than the screen's white,
  /// because it is the one surface here that is a material.
  final Color paper;

  /// The graphite of a wall label.
  final Color label;

  /// A control on the wall — the switch, the readout. It is the wall's own
  /// light: pale on a dark wall, ink on a light one.
  final Color control;

  /// The sheet's edge, when the wall is close to the paper's own colour. On a
  /// dark wall the paper states its own edge; on a light one it needs the
  /// hairline to be a sheet and not a hole.
  final Color? outline;

  static const KalloWall light = KalloWall(
    top: Color(0xFFF4F0E8),
    base: Color(0xFFE3DDD0),
    paper: Color(0xFFFFFDF8),
    label: Color(0xFF6E6A63),
    control: Color(0xFF3F3A33),
    outline: Color(0xFFD8D2C5),
  );

  static const KalloWall dark = KalloWall(
    top: Color(0xFF262119),
    base: Color(0xFF090807),
    paper: Color(0xFFFFFBF2),
    label: Color(0xFF9A9387),
    control: Color(0xFFF4EFE6),
  );

  static KalloWall of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The colour a control on the wall is, at this light.
  ///
  /// The lamp takes the wall and the wall's control with it. A switch you
  /// cannot find in the dark is a switch that has been taken away, so the
  /// control that can be found is the one the dark wall would have had: ink on
  /// a lit wall, the pale slate on a wall that has gone out.
  Color controlAt(double light) =>
      Color.lerp(control, KalloWall.dark.control, 1 - light)!;

  /// The largest a print gets on a wall. One print alone should not become a
  /// billboard, and five in a row should not become stamps.
  static const double largest = 660;

  /// In a dark room an eye keeps about this much. Not a fade to nothing: a print
  /// you can still find, and only just.
  static const double darkAdaptation = 0.10;
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
/// One shadow, for the one thing that floats above the window: the drawer.
/// Nothing else is raised — the planes of the app do that with colour, and a
/// shadow that is not a thing sitting on another thing is decoration.
abstract final class KalloShadow {
  static const List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(color: Color(0x24000000), blurRadius: 32, offset: Offset(0, 10)),
  ];
}

/// Motion, stated once.
abstract final class KalloMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration settle = Duration(milliseconds: 240);
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
    'NotoSansSC',
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
