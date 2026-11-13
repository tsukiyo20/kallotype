/// The densitometry behind a print.
///
/// A print is a picture; the chart beside it is the measurement the picture
/// came from: the same nine-step wedge through the developed curve. The model
/// computes it from the stock and the development, not from the photograph, so
/// a roll the app developed can carry the same chart the committed strip does.
class FilmChart {
  const FilmChart({
    required this.minutes,
    required this.tempC,
    required this.gamma,
    required this.dMin,
    required this.dMax,
    required this.patches,
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

  /// Dye density per patch, three numbers each, before the base is counted in.
  final List<List<double>> patches;
}
