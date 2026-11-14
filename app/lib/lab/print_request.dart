/// What the print stage asks the model for.
///
/// A finished print is not the test strip's print: it is balanced for its own
/// negative, with the enlarger's timer, its colour pack and its glass. The
/// strip chose the development; this is the print.
class PrintRequest {
  const PrintRequest({
    required this.minutes,
    this.printEv = 0,
    this.filters = '',
    this.heatGlass,
    this.width,
  });

  final double minutes;

  /// The finished print's width in pixels; null keeps the photograph's own.
  final int? width;

  /// The enlarger's timer, in stops, on top of the solved balance.
  final double printEv;

  /// The colour pack, in Kodak CC units: `10M`, `20Y+5M`.
  final String filters;

  /// A heat-absorbing glass by name: `kg3`.
  final String? heatGlass;
}
