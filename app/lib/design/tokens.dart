import 'package:flutter/widgets.dart';

/// Everything the interface is allowed to be coloured with.
///
/// A window, a column of places, a content field and a surface: the four planes
/// an app is made of. Two complete sets, one for each appearance, and the
/// system decides which unless the user pins one.
///
/// The accent is the safelight: a selection, the tone curve, and the one action
/// on a page. Everything else is a neutral, because the colour in this product
/// belongs to the photographs.
@immutable
class KalloColors {
  const KalloColors({
    required this.brightness,
    required this.ground,
    required this.sidebar,
    required this.content,
    required this.surface,
    required this.fill,
    required this.fillStrong,
    required this.elevated,
    required this.hairline,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.print,
    required this.scrim,
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

  /// The recessed fill of a control: a track, a field, an unfilled chip.
  final Color fill;

  /// The same fill under the pointer. One step, not a second palette.
  final Color fillStrong;

  /// A control that has lifted off its fill: a chosen segment, a raised key.
  final Color elevated;

  /// The one border in the app, and it is a device pixel.
  final Color hairline;

  /// Text that must be read.
  final Color ink;

  /// Text that must be present.
  final Color inkMuted;

  /// Text that must be felt.
  final Color inkFaint;

  /// The safelight turned up: the one tint in the chrome. Selection, the tone
  /// curve, and the one primary action.
  final Color accent;

  /// The accent at rest: the wash behind a selected row, never a border.
  final Color accentSoft;

  /// Text drawn on [accent].
  final Color onAccent;

  /// The paper a print sits on. Always warm, in both appearances: it is the one
  /// surface in the product that is a material rather than a plane.
  final Color print;

  /// A modal's dimming. Black in both appearances, because a sheet dims the
  /// room, not the ink.
  final Color scrim;

  static const KalloColors light = KalloColors(
    brightness: Brightness.light,
    ground: Color(0xFFF2F2F7),
    sidebar: Color(0xFFF7F7FA),
    content: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F7FA),
    fill: Color(0xFFECECF0),
    fillStrong: Color(0xFFE1E1E6),
    elevated: Color(0xFFFFFFFF),
    hairline: Color(0xFFD6D6DB),
    ink: Color(0xFF1D1D1F),
    inkMuted: Color(0xFF6E6E73),
    inkFaint: Color(0xFF8E8E93),
    accent: Color(0xFFC2410C),
    accentSoft: Color(0xFFFBE9DE),
    onAccent: Color(0xFFFFFFFF),
    print: Color(0xFFFFFCF7),
    scrim: Color(0x52000000),
  );

  static const KalloColors dark = KalloColors(
    brightness: Brightness.dark,
    ground: Color(0xFF000000),
    sidebar: Color(0xFF0B0B0D),
    content: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    fill: Color(0xFF2C2C2E),
    fillStrong: Color(0xFF3A3A3C),
    elevated: Color(0xFF3A3A3C),
    hairline: Color(0xFF38383A),
    ink: Color(0xFFF5F5F7),
    inkMuted: Color(0xFFAEAEB2),
    inkFaint: Color(0xFF8E8E93),
    accent: Color(0xFFFF9F0A),
    accentSoft: Color(0xFF3A2A12),
    onAccent: Color(0xFF1C1206),
    print: Color(0xFFF7F2E9),
    scrim: Color(0x99000000),
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

/// The film itself: the rebate, the clear holes and the printing on the edge.
///
/// These are not planes of the window. A film frame is an object in the work,
/// like the paper, so its colours are stated here once and lit by the room's
/// lamp where a frame is hung.
abstract final class KalloFilm {
  /// The exposed rebate: black, because it was never in the gate.
  static const Color rebate = Color(0xFF0B0A09);

  /// The film's outer edge, for the one hairline around the rebate.
  static const Color edge = Color(0xFFB0B0B4);

  /// The edge printing of a silver film: warm ivory, the positive view of the
  /// dark letters on a negative.
  static const Color edgeMono = Color(0xFFF1E8D8);

  /// The edge printing of a colour negative: the amber of its base and mask.
  static const Color edgeNegative = Color(0xFFD8AE72);

  /// The edge printing of a reversal: white on black, because the rebate is
  /// the unexposed film and the letters are the developed image.
  static const Color edgeReversal = Color(0xFFF7F3EA);

  /// A sprocket hole: clear film, and what is behind it.
  static const Color clear = Color(0xFFE9E9E7);

  /// The gate's own edge, around the picture.
  static const Color gate = Color(0xFF2C2C2E);
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
  static const Color ink = Color(0xFF1D1D1F);

  /// A time, a development, a note.
  static const Color muted = Color(0xFF6E6E73);

  /// The paper's name in the margin, and anything that is a caption.
  static const Color faint = Color(0xFF8E8E93);

  /// The mark on the frame that was chosen.
  static const Color accent = Color(0xFFC2410C);
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
    top: Color(0xFFF7F7FA),
    base: Color(0xFFE6E6EB),
    paper: Color(0xFFFFFDF8),
    label: Color(0xFF5F5F64),
    control: Color(0xFF1D1D1F),
    outline: Color(0xFFDADAE0),
  );

  static const KalloWall dark = KalloWall(
    top: Color(0xFF222224),
    base: Color(0xFF000000),
    paper: Color(0xFFFBF8F1),
    label: Color(0xFFB0B0B5),
    control: Color(0xFFF5F5F7),
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

/// The drying rack: a room that is not the gallery's wall.
///
/// A rack is a working surface with wires across it, not a neutral plane. Its
/// ground is still one of the window's neutrals; the wire and the clip are the
/// only things that are metal, and they are stated here once.
class KalloRack {
  const KalloRack({
    required this.top,
    required this.base,
    required this.wire,
    required this.clip,
    required this.label,
  });

  /// The end of the room the window is on.
  final Color top;

  /// The end the floor is on.
  final Color base;

  /// The line a print hangs from.
  final Color wire;

  /// The clip holding it there.
  final Color clip;

  /// The graphite under a print.
  final Color label;

  static const KalloRack light = KalloRack(
    top: Color(0xFFF4F4F7),
    base: Color(0xFFE3E3E8),
    wire: Color(0xFFADADB5),
    clip: Color(0xFF7A7A80),
    label: Color(0xFF5F5F64),
  );

  static const KalloRack dark = KalloRack(
    top: Color(0xFF151517),
    base: Color(0xFF040405),
    wire: Color(0xFF5A5A5F),
    clip: Color(0xFFB8B8BE),
    label: Color(0xFFB0B0B5),
  );

  static KalloRack of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// A picture taken off the wall and looked at on its own.
///
/// The viewer is black in both appearances: it is not a room and not a sheet,
/// it is the absence of everything except the print. Its ink is fixed because
/// the background is.
abstract final class KalloViewer {
  static const Color background = Color(0xFF09090B);
  static const Color ink = Color(0xFFF5F5F7);
  static const Color muted = Color(0xFFAEAEB2);
  static const Color fill = Color(0x1FFFFFFF);
  static const Color hairline = Color(0x26FFFFFF);
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
  /// A button, a field, a chip, a segmented control.
  static const double control = 8;

  /// A card, a panel, the inspector.
  static const double card = 14;

  /// A sheet that slides over everything.
  static const double sheet = 20;

  /// A capsule: a tab track, a toolbar control.
  static const double pill = 999;
}

/// Depth.
///
/// A plane still rises by being lighter, not by a blur. The shadows here are
/// objects: a sheet over the window, a print hanging in air, and the one pixel
/// under a segment that has lifted off its track.
abstract final class KalloShadow {
  /// A sheet over the window, or a full-screen viewer.
  static const List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(color: Color(0x24000000), blurRadius: 40, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Paper on the rack: a material in a room, not a card in a layout.
  static const List<BoxShadow> paper = <BoxShadow>[
    BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x10000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  /// A segment or key lifted off its fill.
  static const List<BoxShadow> control = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
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
    letterSpacing: 0.5,
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
