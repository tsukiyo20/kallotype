/// A film stock: an id the model knows, and the name on the box.
///
/// The id is the model's — `vision3_500t` is how `kalo` spells it — and the
/// label is the manufacturer's, which is why it never translates.
class Stock {
  const Stock({
    required this.id,
    required this.label,
    required this.short,
    this.note = '',
  });

  final String id;
  final String label;

  /// The name a wall label would use: the box's name, without the catalogue
  /// numbers and the process. `VISION3 500T`, not the whole line.
  final String short;

  /// How the stock describes itself in the model: what was measured and what
  /// was borrowed. Empty when the app has not been told.
  final String note;
}

/// The stocks this build knows.
///
/// One, because one is what the app can develop without a catalogue behind the
/// shelf, and because it is the stock with nothing borrowed in it. The list
/// comes off a command line today; it will come off the model tomorrow, and the
/// shelf will be a shelf.
abstract final class Stocks {
  static const Stock vision = Stock(
    id: 'vision3_500t',
    label: 'KODAK VISION3 500T 5219/7219, ECN-2',
    short: 'VISION3 500T',
  );

  static const List<Stock> all = <Stock>[vision];

  static Stock? byId(String id) {
    for (final Stock stock in all) {
      if (stock.id == id) {
        return stock;
      }
    }
    return null;
  }

  /// The paper the app prints on. One, for the same reason.
  static const String paper = 'fuji_crystal_archive_pearl';
  static const String paperLabel = 'FUJICOLOR CRYSTAL ARCHIVE PEARL, RA-4';

  /// What the paper is called on a wall label.
  static const String paperShort = 'CRYSTAL ARCHIVE PEARL';
}
