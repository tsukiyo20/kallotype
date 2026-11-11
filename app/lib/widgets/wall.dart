import 'package:flutter/widgets.dart';

import '../design/tokens.dart';

/// A wall, the sheet on it, and the label beside it.
///
/// Two rooms show a print as a print: the gallery, which hangs the work that
/// exists, and the workbench, which proves a frame before any of it is made.
/// They build the same ground, the same sheet and the same label, so that a
/// proof and a hanging are the same statement made at different times — which
/// is the only way a proof is worth trusting.

/// The wall behind a print: warm at the top, black at the bottom.
class Wall extends StatelessWidget {
  const Wall({super.key, this.light = 1, this.child});

  /// The light on the wall. A wall is a reflectance too, so the lamp goes out
  /// on it before it goes out on the print — which is what makes the print hold
  /// when everything else has gone black.
  final double light;

  final Widget? child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.10),
            radius: 0.85,
            colors: <Color>[
              KalloColors.under(KalloWall.top, light),
              KalloColors.under(KalloWall.base, light),
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
    this.paper = KalloWall.paper,
    this.outline,
    this.light = 1,
    this.aspect = 1.5,
  });

  /// How wide the sheet is. The picture is the sheet minus its margins.
  final double width;

  /// The paper the sheet is.
  ///
  /// The wall's is a constant, because a room with one lamp does not follow the
  /// window. The bench's easel is the window's paper, because the easel sits on
  /// a page that belongs to the room.
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
  String? film,
  String? clock,
  String? paper,
  String? fallback,
}) {
  final Color quiet =
      KalloColors.under(KalloWall.label, light).withValues(alpha: 0.60);
  final Color loud = KalloColors.under(KalloWall.label, light);
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
