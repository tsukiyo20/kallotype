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
}
