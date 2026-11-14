/// The densitometer's reading of a developed strip.
///
/// A print is a picture; the chart beside it is the measurement the picture
/// came from: the same nine-step wedge, read through the base, the fog and the
/// mask. It depends on the stock and the development, not on the photograph, so
/// a roll the app developed carries the same wedge the committed strip does.
class FilmChart {
  const FilmChart({
    required this.minutes,
    required this.tempC,
    required this.gamma,
    required this.dMin,
    required this.dMax,
    required this.patches,
    required this.logE,
  });

  /// How long this frame was developed.
  final double minutes;

  /// The developer's temperature.
  final double tempC;

  /// Contrast in the red, green and blue records.
  final List<double> gamma;

  /// The dye's density floor, after fog.
  final List<double> dMin;

  /// The dye's density ceiling.
  final List<double> dMax;

  /// Status density per patch, three numbers each, as the instrument reads it:
  /// the dye plus the strip's own base, fog and mask.
  final List<List<double>> patches;

  /// The log10 exposure each patch received.
  final List<double> logE;
}

/// A film's developed characteristic curve, sampled by the model.
///
/// This is the curve itself, not the nine-patch wedge a densitometer reads: its
/// toe and shoulder are the film's, and every development of a stock is sampled
/// over the same exposure range so a strip's curves overlay.
class FilmCurve {
  const FilmCurve({
    required this.film,
    required this.minutes,
    required this.tempC,
    required this.gamma,
    required this.dMin,
    required this.dMax,
    required this.logE,
    required this.density,
  });

  final String film;
  final double minutes;
  final double tempC;
  final List<double> gamma;
  final List<double> dMin;
  final List<double> dMax;
  final List<double> logE;

  /// The developed density per layer at each sample.
  final List<List<double>> density;

  /// The three layers averaged: what the panel draws as one line.
  List<double> get tone => <double>[
    for (final List<double> sample in density)
      (sample[0] + sample[1] + sample[2]) / 3,
  ];
}

/// A paper's characteristic curve, as the model sampled it.
class PaperCurve {
  const PaperCurve({
    required this.id,
    required this.short,
    required this.emulsion,
    required this.dMin,
    required this.dMax,
    required this.gamma,
    required this.logE0,
    required this.targetMidReflectance,
    required this.logE,
    required this.density,
  });

  final String id;
  final String short;

  /// `colour` or `silver`.
  final String emulsion;
  final double dMin;
  final double dMax;
  final double gamma;
  final double logE0;

  /// Linear reflectance a balanced print reaches for an 18 % grey card.
  final double targetMidReflectance;

  final List<double> logE;
  final List<double> density;
}

/// The print's tone: the paper under one enlarger balance.
class PrintCurve {
  const PrintCurve({
    required this.film,
    required this.paper,
    required this.minutes,
    required this.tempC,
    required this.shift,
    required this.logE,
    required this.density,
  });

  final String film;
  final String paper;
  final double minutes;
  final double tempC;

  /// The enlarger's exposure per layer, in decades.
  final List<double> shift;

  /// The negative's log10 exposure, increasing to the right.
  final List<double> logE;

  /// The paper's density per channel at each sample.
  final List<List<double>> density;
}
