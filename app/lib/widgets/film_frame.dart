import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../lab/stock.dart';

/// The shape of a 35 mm frame around a print.
///
/// A frame is not a border: it is a piece of film. The picture sits in the
/// aperture, the rebate carries the sprocket holes and the edge printing, and
/// the two are not the same size — a photograph has the shape it has, and the
/// film around it has the shape of film.
///
/// The proportions are one set of ratios and they are all read from the long
/// edge of the picture. A horizontal frame puts the holes above and below; a
/// vertical one turns the strip, so the holes run down the sides. That is what
/// a rotated camera does to the film, and it is the reason a portrait print is
/// not a landscape frame with bars in it.
@immutable
class FilmFrameMetrics {
  const FilmFrameMetrics._({
    required this.outer,
    required this.aperture,
    required this.band,
    required this.side,
    required this.horizontal,
    required this.sprockets,
  });

  /// The whole piece of film, with its rebate.
  final Rect outer;

  /// The picture's window: the gate.
  final Rect aperture;

  /// The rebate on the long edges, where the sprocket holes live.
  final double band;

  /// The rebate on the short edges.
  final double side;

  /// Whether the strip runs across the picture rather than down it.
  final bool horizontal;

  /// How many holes fit along one long edge.
  final int sprockets;

  /// The ratio of the outer frame, width over height.
  double get aspect => outer.width / outer.height;

  /// The ratio of the outer frame, height over width: what a wall needs before
  /// it has a width.
  double get heightPerWidth => outer.height / outer.width;

  /// The length of the long edge of the aperture.
  double get longEdge => horizontal ? aperture.width : aperture.height;

  /// The rebate's thickness on the long edges, as a fraction of that edge.
  static const double bandRatio = 0.095;

  /// The rebate's thickness on the short edges.
  static const double sideRatio = 0.018;

  /// A frame around a picture [imageWidth] pixels wide.
  factory FilmFrameMetrics.fromImageWidth(
    double imageWidth, {
    required double aspect,
  }) {
    final bool horizontal = aspect >= 1;
    final double imageHeight = imageWidth / aspect;
    final double long = horizontal ? imageWidth : imageHeight;
    final double band = long * bandRatio;
    final double side = long * sideRatio;
    final double outerWidth = imageWidth + (horizontal ? 2 * side : 2 * band);
    final double outerHeight = imageHeight + (horizontal ? 2 * band : 2 * side);
    final double left = horizontal ? side : band;
    final double top = horizontal ? band : side;
    final int holes = (long / (horizontal ? imageHeight : imageWidth) * 5)
        .round()
        .clamp(6, 10);
    return FilmFrameMetrics._(
      outer: Rect.fromLTWH(0, 0, outerWidth, outerHeight),
      aperture: Rect.fromLTWH(left, top, imageWidth, imageHeight),
      band: band,
      side: side,
      horizontal: horizontal,
      sprockets: holes,
    );
  }

  /// A frame [outerWidth] wide around a picture of [aspect].
  factory FilmFrameMetrics.fromWidth(
    double outerWidth, {
    required double aspect,
  }) {
    final bool horizontal = aspect >= 1;
    // The outer width is the aperture plus the two long or short rebates,
    // depending on which way the strip runs.
    final double imageWidth = horizontal
        ? outerWidth / (1 + 2 * sideRatio)
        : outerWidth / (1 + 2 * bandRatio / aspect);
    return FilmFrameMetrics.fromImageWidth(imageWidth, aspect: aspect);
  }

  /// How tall a frame of [width] is, without building it.
  static double heightPerWidthFor(double aspect) =>
      FilmFrameMetrics.fromWidth(1000, aspect: aspect).heightPerWidth;

  /// The outer width a frame needs around a picture [imageWidth] wide.
  static double widthForImageWidth(
    double imageWidth, {
    required double aspect,
  }) => FilmFrameMetrics.fromImageWidth(imageWidth, aspect: aspect).outer.width;

  /// The aperture's width for an outer [width]: what the picture gets.
  static double imageWidthFor(double width, {required double aspect}) =>
      FilmFrameMetrics.fromWidth(width, aspect: aspect).aperture.width;
}

/// A print in a 35 mm frame: the aperture, the rebate, the holes and the ink.
///
/// The lens is passed in as [barrel]: a loupe is glass, and glass bends the
/// edge of what is under it. The frame itself stays a frame — film is flat —
/// and only the picture is seen through the glass. A barrel of zero is the
/// flat, exported frame.
class FilmFrame extends StatelessWidget {
  const FilmFrame({
    super.key,
    required this.image,
    required this.width,
    this.source,
    this.film,
    this.printNumber = 1,
    this.process,
    this.light = 1,
    this.barrel = 0,
    this.semanticLabel,
  });

  /// The picture. Its own shape is the aperture's shape.
  final ui.Image image;

  /// The outer width of the piece of film.
  final double width;

  /// The part of the picture to show, in image pixels. Null is all of it.
  ///
  /// The loupe uses this to look closer without making the film itself bigger:
  /// the frame holds still and the picture moves under it.
  final Rect? source;

  /// The name printed on the rebate. The film's own name, so it does not
  /// translate.
  final String? film;

  /// The print's number in its batch: `01` for a single print, `02`, `03` in
  /// a batch. It is not a film frame number.
  final int printNumber;

  /// The film's chemistry, which decides the edge ink: ivory, amber or white.
  final FilmProcess? process;

  /// The light on the film, from nothing to all of it.
  final double light;

  /// The loupe's distortion: zero is flat, and a small positive number bows
  /// the picture out at its edges. It never touches the rebate.
  final double barrel;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final double aspect = image.width / image.height;
    final FilmFrameMetrics metrics = FilmFrameMetrics.fromWidth(
      width,
      aspect: aspect,
    );
    final Rect full = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final Widget painted = SizedBox(
      width: metrics.outer.width,
      height: metrics.outer.height,
      child: CustomPaint(
        painter: FilmFramePainter(
          image: image,
          source: source ?? full,
          film: film,
          printNumber: printNumber,
          process: process,
          light: light,
          barrel: barrel,
        ),
      ),
    );
    final String? label = semanticLabel;
    return label == null ? painted : Semantics(label: label, child: painted);
  }
}

/// The name a film's edge carries, and the name a frame's caption uses.
///
/// The record keeps the whole catalogue label — `KODAK PROFESSIONAL T-MAX 400,
/// D-76 8 min 20 °C` — because that is the stock's name. A rebate has room for
/// the name a printer says out loud, and so does a caption under a frame.
String filmEdgeName(String? film) {
  if (film == null || film.isEmpty) {
    return '';
  }
  String name = film.split(',').first.trim();
  for (final String prefix in <String>[
    'KODAK PROFESSIONAL ',
    'KODAK ',
    'ILFORD ',
  ]) {
    if (name.toUpperCase().startsWith(prefix)) {
      name = name.substring(prefix.length);
      break;
    }
  }
  name = name.replaceFirst(RegExp(r'\s+PROFESSIONAL$'), '');
  return name.isEmpty ? film : name;
}

/// Paints [FilmFrame].
class FilmFramePainter extends CustomPainter {
  const FilmFramePainter({
    required this.image,
    required this.source,
    this.film,
    this.printNumber = 1,
    this.process,
    this.light = 1,
    this.barrel = 0,
  });

  final ui.Image image;

  /// The part of [image] in the aperture, in image pixels.
  final Rect source;

  final String? film;
  final int printNumber;
  final FilmProcess? process;
  final double light;
  final double barrel;

  @override
  void paint(Canvas canvas, Size size) {
    final FilmFrameMetrics metrics = FilmFrameMetrics.fromWidth(
      size.width,
      aspect: image.width / image.height,
    );
    _paint(canvas, metrics);
  }

  /// Where the film is, for a frame of [width] and this picture.
  static FilmFrameMetrics metricsFor(double width, ui.Image image) =>
      FilmFrameMetrics.fromWidth(width, aspect: image.width / image.height);

  void _paint(Canvas canvas, FilmFrameMetrics m) {
    final Color rebate = _lit(KalloFilm.rebate);
    final Color hole = _lit(KalloFilm.clear.withValues(alpha: 0.72));
    final Color edge = _lit(_edgeColour.withValues(alpha: 0.92));
    final Color gate = _lit(KalloFilm.gate.withValues(alpha: 0.92));

    canvas.drawRect(m.outer, Paint()..color = rebate);

    final Paint holePaint = Paint()..color = hole;
    for (final RRect sprocket in _sprockets(m)) {
      canvas.drawRRect(sprocket, holePaint);
    }

    canvas.save();
    canvas.clipRect(m.aperture);
    _image(canvas, m.aperture);
    canvas.restore();

    // The gate's own edge, one hairline: a picture is not pinned to the film,
    // it was exposed through a window.
    canvas.drawRect(
      m.aperture.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = gate,
    );

    _edgeInk(canvas, m, edge);

    // On a dark wall a black frame is almost the wall; one hairline keeps the
    // piece of film a thing rather than a hole.
    canvas.drawRect(
      m.outer.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _lit(KalloFilm.edge.withValues(alpha: 0.16)),
    );
  }

  /// The picture, flat or through the loupe's glass.
  ///
  /// The mesh is the lens: every vertex is pushed out by the radius it sits
  /// at, and the texture coordinate stays where the pixel came from. A grid of
  /// triangles is enough at this size, and it costs no shader and no second
  /// decode.
  void _image(Canvas canvas, Rect destination) {
    final ColorFilter? filter = light >= 1
        ? null
        : ColorFilter.matrix(<double>[
            light,
            0,
            0,
            0,
            0,
            0,
            light,
            0,
            0,
            0,
            0,
            0,
            light,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]);
    if (barrel <= 0.001) {
      final Paint paint = Paint()
        ..filterQuality = FilterQuality.high
        ..colorFilter = filter;
      canvas.drawImageRect(image, source, destination, paint);
      return;
    }

    final int columns = (destination.width / 22).ceil().clamp(12, 64);
    final int rows = (destination.height / 22).ceil().clamp(12, 64);
    final List<Offset> positions = <Offset>[];
    final List<Offset> texture = <Offset>[];
    for (int row = 0; row <= rows; row++) {
      final double v = row / rows;
      for (int column = 0; column <= columns; column++) {
        final double u = column / columns;
        final double x = u * 2 - 1;
        final double y = v * 2 - 1;
        final double radius = x * x + y * y;
        final double bend = 1 + barrel * radius;
        // The centre stays put; the edge of the glass sees a little more film.
        final double sx = ((x * bend) + 1) / 2;
        final double sy = ((y * bend) + 1) / 2;
        positions.add(
          Offset(
            destination.left + u * destination.width,
            destination.top + v * destination.height,
          ),
        );
        texture.add(
          Offset(
            source.left + sx * source.width,
            source.top + sy * source.height,
          ),
        );
      }
    }
    final List<int> indices = <int>[];
    final int stride = columns + 1;
    for (int row = 0; row < rows; row++) {
      for (int column = 0; column < columns; column++) {
        final int a = row * stride + column;
        final int b = a + 1;
        final int c = a + stride;
        final int d = c + 1;
        indices.addAll(<int>[a, b, c, b, d, c]);
      }
    }
    final ui.Vertices vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texture,
      indices: indices,
    );
    final Paint paint = Paint()
      ..shader = ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.high,
      )
      ..colorFilter = filter;
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
  }

  /// The sprocket holes, in the outer half of each long rebate.
  Iterable<RRect> _sprockets(FilmFrameMetrics m) sync* {
    final double pitch = m.longEdge / m.sprockets;
    final double length = pitch * 0.48;
    final double thickness = m.band * 0.30;
    final Radius radius = Radius.circular(thickness * 0.30);
    if (m.horizontal) {
      final double top = m.outer.top + m.band * 0.32;
      final double bottom = m.outer.bottom - m.band * 0.32;
      for (int i = 0; i < m.sprockets; i++) {
        final double x = m.aperture.left + (i + 0.5) * pitch;
        yield RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, top),
            width: length,
            height: thickness,
          ),
          radius,
        );
        yield RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, bottom),
            width: length,
            height: thickness,
          ),
          radius,
        );
      }
      return;
    }
    final double left = m.outer.left + m.band * 0.32;
    final double right = m.outer.right - m.band * 0.32;
    for (int i = 0; i < m.sprockets; i++) {
      final double y = m.aperture.top + (i + 0.5) * pitch;
      yield RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(left, y),
          width: thickness,
          height: length,
        ),
        radius,
      );
      yield RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(right, y),
          width: thickness,
          height: length,
        ),
        radius,
      );
    }
  }

  /// The edge printing: the stock and the print number on one edge, the
  /// process and the format on the other. It is the film's own vocabulary and
  /// does not translate.
  void _edgeInk(Canvas canvas, FilmFrameMetrics m, Color colour) {
    final double size = math.max(6.0, m.outer.width * 0.016);
    final TextStyle style = KalloType.folio.copyWith(
      fontSize: size,
      letterSpacing: size * 0.14,
      color: colour,
      fontFeatures: const <FontFeature>[FontFeature('tnum')],
    );
    final double pad = math.max(2.0, size * 0.36);
    final String stock = filmEdgeName(film);
    final String number = printNumber.toString().padLeft(2, '0');
    final String chemical = _processLabel();
    final String format = '135';
    final double half = math.max(
      1,
      (m.horizontal ? m.aperture.width : m.aperture.height) / 2 - pad * 2,
    );

    TextPainter ink(String text) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: half);

    if (m.horizontal) {
      final double top = m.outer.top + m.band * 0.74;
      final double bottom = m.outer.bottom - m.band * 0.74;
      _left(canvas, ink(stock), m.aperture.left + pad, top);
      _right(canvas, ink(number), m.aperture.right - pad, top);
      _left(canvas, ink(chemical), m.aperture.left + pad, bottom);
      _right(canvas, ink(format), m.aperture.right - pad, bottom);
      return;
    }

    final double left = m.outer.left + m.band * 0.75;
    final double right = m.outer.right - m.band * 0.75;
    final double top = m.aperture.top + pad;
    final double middle = m.aperture.top + m.aperture.height / 2;
    _down(canvas, ink(stock), left, top);
    _down(canvas, ink(number), left, middle);
    _down(canvas, ink(chemical), right, top);
    _down(canvas, ink(format), right, middle);
  }

  void _left(Canvas canvas, TextPainter text, double x, double centre) =>
      text.paint(canvas, Offset(x, centre - text.height / 2));

  void _right(Canvas canvas, TextPainter text, double x, double centre) =>
      text.paint(canvas, Offset(x - text.width, centre - text.height / 2));

  /// Text running down a vertical frame. The translation is the text's right
  /// edge, because a quarter turn sends its height to the left.
  void _down(Canvas canvas, TextPainter text, double x, double y) {
    canvas.save();
    canvas.translate(x + text.height / 2, y);
    canvas.rotate(math.pi / 2);
    text.paint(canvas, Offset.zero);
    canvas.restore();
  }

  /// The ink of the edge, by the film's chemistry.
  Color get _edgeColour => switch (process) {
    FilmProcess.monochrome => KalloFilm.edgeMono,
    FilmProcess.negative => KalloFilm.edgeNegative,
    FilmProcess.reversal => KalloFilm.edgeReversal,
    null => KalloFilm.edgeMono,
  };

  /// The process mark. Motion-picture negative is ECN-2, not C-41; the name is
  /// the only place the app has to tell them apart.
  String _processLabel() {
    if (process == null) {
      return '';
    }
    final String name = (film ?? '').toUpperCase();
    return switch (process) {
      FilmProcess.monochrome => 'B&W',
      FilmProcess.reversal => 'E-6',
      FilmProcess.negative => name.contains('VISION3') ? 'ECN-2' : 'C-41',
      null => '',
    };
  }

  Color _lit(Color colour) => KalloColors.under(colour, light);

  @override
  bool shouldRepaint(FilmFramePainter old) =>
      old.image != image ||
      old.source != source ||
      old.film != film ||
      old.printNumber != printNumber ||
      old.process != process ||
      old.light != light ||
      old.barrel != barrel;
}
