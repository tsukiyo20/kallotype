import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../lab/print.dart';
import '../lab/thumbnails.dart';
import 'film_frame.dart';

/// A print's picture, loaded only when someone is looking at it.
///
/// The rack and the gallery hold metadata, not textures. This widget asks the
/// thumbnail cache for the one picture it needs and lets it go when it leaves
/// the tree, which is what makes a wall of a thousand prints a wall and not a
/// decoded copy of the folder.
class PrintImage extends StatefulWidget {
  const PrintImage({
    super.key,
    required this.print,
    this.fit = BoxFit.cover,
    this.quality = FilterQuality.medium,
  });

  final Print print;
  final BoxFit fit;
  final FilterQuality quality;

  @override
  State<PrintImage> createState() => _PrintImageState();
}

class _PrintImageState extends State<PrintImage> {
  PrintThumbnail? _thumbnail;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PrintImage old) {
    super.didUpdateWidget(old);
    if (!identical(old.print, widget.print)) {
      _thumbnail?.release();
      _thumbnail = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.print.image != null) {
      return;
    }
    final int generation = ++_generation;
    final PrintThumbnail? thumbnail = await PrintThumbnailCache.instance
        .acquire(widget.print);
    if (!mounted || generation != _generation) {
      thumbnail?.release();
      return;
    }
    setState(() => _thumbnail = thumbnail);
  }

  @override
  void dispose() {
    _thumbnail?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _thumbnail?.image ?? widget.print.image;
    if (image != null) {
      return RawImage(
        image: image,
        fit: widget.fit,
        filterQuality: widget.quality,
      );
    }
    return ColoredBox(
      color: KalloScope.colorsOf(context).fill.withValues(alpha: 0.45),
    );
  }
}

/// A print in its film frame, loaded at thumbnail size.
///
/// The gallery spends its grid on the film, not on a photograph floating in
/// space, so the loading state is a blank piece of film rather than a spinner.
/// The frame and its label arrive with the same [Print]; only the aperture is
/// waiting.
class PrintFilmFrame extends StatefulWidget {
  const PrintFilmFrame({
    super.key,
    required this.print,
    required this.width,
    this.printNumber,
    this.source,
    this.light = 1,
    this.barrel = 0,
    this.semanticLabel,
  });

  final Print print;
  final double width;
  final int? printNumber;
  final Rect? source;
  final double light;
  final double barrel;
  final String? semanticLabel;

  @override
  State<PrintFilmFrame> createState() => _PrintFilmFrameState();
}

class _PrintFilmFrameState extends State<PrintFilmFrame> {
  PrintThumbnail? _thumbnail;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PrintFilmFrame old) {
    super.didUpdateWidget(old);
    if (!identical(old.print, widget.print)) {
      _thumbnail?.release();
      _thumbnail = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.print.image != null) {
      return;
    }
    final int generation = ++_generation;
    final PrintThumbnail? thumbnail = await PrintThumbnailCache.instance
        .acquire(widget.print);
    if (!mounted || generation != _generation) {
      thumbnail?.release();
      return;
    }
    setState(() => _thumbnail = thumbnail);
  }

  @override
  void dispose() {
    _thumbnail?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _thumbnail?.image ?? widget.print.image;
    if (image != null) {
      return FilmFrame(
        image: image,
        width: widget.width,
        source: widget.source,
        film: widget.print.film,
        printNumber: widget.printNumber ?? widget.print.printNumber,
        process: widget.print.process,
        light: widget.light,
        barrel: widget.barrel,
        semanticLabel: widget.semanticLabel,
      );
    }
    final FilmFrameMetrics metrics = FilmFrameMetrics.fromWidth(
      widget.width,
      aspect: widget.print.aspect,
    );
    return SizedBox(
      width: metrics.outer.width,
      height: metrics.outer.height,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: KalloFilm.rebate),
        child: Center(
          child: SizedBox(
            width: metrics.aperture.width,
            height: metrics.aperture.height,
            child: ColoredBox(color: KalloFilm.gate.withValues(alpha: 0.35)),
          ),
        ),
      ),
    );
  }
}
