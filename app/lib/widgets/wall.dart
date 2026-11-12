import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// A wall, the sheet on it, and the label beside it.
///
/// Two rooms show a print as a print: the gallery, which hangs the work that
/// exists, and the workbench, which proves a frame before any of it is made.
/// They build the same ground, the same sheet and the same label, so that a
/// proof and a hanging are the same statement made at different times — which
/// is the only way a proof is worth trusting.

/// The wall behind a print: warm at the top, the light falling off the bottom.
class Wall extends StatelessWidget {
  const Wall({super.key, required this.wall, this.light = 1, this.child});

  /// Which wall: the light one in a light appearance, the dark one after dark.
  final KalloWall wall;

  /// The light on the wall. A wall is a reflectance too, so the lamp goes out
  /// on it before it goes out on the print — which is what makes the print hold
  /// when everything else has gone dark.
  final double light;

  final Widget? child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.10),
            radius: 0.85,
            colors: <Color>[
              KalloColors.under(wall.top, light),
              KalloColors.under(wall.base, light),
            ],
          ),
        ),
        child: child,
      );
}

/// A print on its paper: the picture, a fine print's margins, and the light.
///
/// A fine print leaves more paper at the bottom than at the top. It costs one
/// number and it is the difference between a print and a screenshot.
///
/// The picture is not an image but a thing to put on paper: the model's pixels
/// are one, and the chart a roll the model drew carries is another.
class PrintSheet extends StatelessWidget {
  const PrintSheet({
    super.key,
    required this.width,
    required this.child,
    required this.paper,
    this.outline,
    this.light = 1,
    this.aspect = 1.5,
  });

  /// How wide the sheet is. The picture is the sheet minus its margins.
  final double width;

  /// The paper the sheet is: the wall's paper when the sheet is on a wall, the
  /// bench's own when the easel sits on a page that belongs to the room.
  final Color paper;

  /// The sheet's edge, when the page under it is close to the paper's own
  /// colour: a sheet on a white page is a hairline before it is a sheet.
  final Color? outline;

  /// What is printed: a picture, or a chart of densities.
  final Widget child;

  /// The light on the print, from nothing to all of it.
  ///
  /// A print is a reflectance, so less light multiplies every channel — it is
  /// not opacity, which would fade the sheet into the wall behind it. A print
  /// at a tenth is the same print in a darker room.
  final double light;

  /// The picture's shape, width over height.
  final double aspect;

  /// The margin, as a fraction of the sheet's width.
  static const double _border = 0.030;

  /// The sheet's height for a width of it: the picture, the margin and the
  /// deeper one at the bottom.
  ///
  /// Somebody has to know it before the sheet is built — the lens, which is a
  /// sheet at another size, and the room, which has to fit one — so the
  /// arithmetic is here once rather than at each of them.
  static double heightPerWidth({double aspect = 1.5}) =>
      (1 - _border * 2) / aspect + _border * 3.2;

  /// The sheet's height for a width.
  static double heightOf(double width, {double aspect = 1.5}) =>
      width * heightPerWidth(aspect: aspect);

  @override
  Widget build(BuildContext context) {
    final double edge = width * _border;
    final double image = width - edge * 2;
    final Widget printed = SizedBox(
      width: image,
      height: image / aspect,
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KalloColors.under(paper, light),
        border: outline == null ? null : Border.all(color: outline!),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(edge, edge, edge, edge * 2.2),
        child: light >= 1
            ? printed
            : ColorFiltered(
                colorFilter: ColorFilter.matrix(<double>[
                  light, 0, 0, 0, 0, //
                  0, light, 0, 0, 0, //
                  0, 0, light, 0, 0, //
                  0, 0, 0, 1, 0, //
                ]),
                child: printed,
              ),
      ),
    );
  }
}

/// The label beside a print on a wall.
///
/// The film and the paper are set quiet and the development is set loud,
/// because on a wall of the same negative at five times the only word that
/// differs is the one worth finding. A print whose record was lost is called
/// what its file is called — it is still a print, and it is still here. A proof
/// has the same three words and no file: the frame it came from is on the
/// bench, so it does not need to be named.
List<InlineSpan> wallLabel({
  required double light,
  required KalloWall wall,
  String? film,
  String? clock,
  String? paper,
  String? fallback,
}) {
  final Color quiet = KalloColors.under(wall.label, light).withValues(alpha: 0.60);
  final Color loud = KalloColors.under(wall.label, light);
  final List<InlineSpan> spans = <InlineSpan>[];
  void add(String? text, Color colour) {
    if (text == null || text.isEmpty) {
      return;
    }
    if (spans.isNotEmpty) {
      spans.add(TextSpan(text: '   ·   ', style: TextStyle(color: quiet)));
    }
    spans.add(TextSpan(text: text, style: TextStyle(color: colour)));
  }

  add(film, quiet);
  add(clock, loud);
  add(paper, quiet);
  if (spans.isEmpty) {
    add(fallback, quiet);
  }
  return spans;
}
