import 'dart:convert';

import 'model.dart';

/// The manufacturer a stock's label names, or the name it is known by.
///
/// The model carries the manufacturer in the label, not in a field of its own.
/// A film's short name is the product (`GOLD 200`); a print's record may carry
/// either shape. These three functions are the one place the app adds the
/// manufacturer back, so a box, a caption and a rebate all say the same thing.
String stockMaker(String? name) {
  final String upper = (name ?? '').toUpperCase();
  if (upper.isEmpty) {
    return '';
  }
  if (upper.startsWith('KODAK') ||
      <String>[
        'T-MAX',
        'TRI-X',
        'PORTRA',
        'ULTRA MAX',
        'GOLD',
        'VISION3',
        'EKTAR',
        'EKTACHROME',
        'ENDURA',
        'POLYMAX',
      ].any(upper.contains)) {
    return 'KODAK';
  }
  if (upper.startsWith('FUJI') ||
      <String>[
        'PROVIA',
        'VELVIA',
        'SUPERIA',
        'CRYSTAL ARCHIVE',
        'PRO 400H',
        'C200',
        'ACROS',
      ].any(upper.contains)) {
    return 'FUJIFILM';
  }
  if (upper.startsWith('ILFORD') ||
      <String>['DELTA', 'HP5', 'FP4', 'XP2', 'PAN F'].any(upper.contains)) {
    return 'ILFORD';
  }
  return upper.split(RegExp(r'\s+')).first;
}

/// A stock's product name without the manufacturer, process or data sheet.
///
/// A full label is the manufacturer's sentence: `KODAK PROFESSIONAL T-MAX 400,
/// D-76 8 min 20 °C`. A box, a chip and a rebate want the noun. The short name
/// is already that noun, so callers with a [Stock] should use [Stock.displayName]
/// rather than this function.
String stockProductName(String? name, {String? maker}) {
  String value = (name ?? '').split(',').first.trim();
  if (value.isEmpty) {
    return '';
  }
  value = value.replaceAll(
    RegExp(r'\bPROFESSIONAL\b', caseSensitive: false),
    '',
  );
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  final String brand = maker ?? stockMaker(value);
  for (final String prefix in <String>[
    'KODAK',
    'FUJIFILM',
    'FUJICOLOR',
    'FUJICHROME',
    'ILFORD',
  ]) {
    if (value.toUpperCase().startsWith(prefix)) {
      value = value.substring(prefix.length).trim();
      break;
    }
  }
  value = value
      .replaceAll(RegExp(r'\s+Color Negative Film$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+Film$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+Paper$', caseSensitive: false), '')
      .trim();
  if (value.toUpperCase().startsWith(brand.toUpperCase())) {
    value = value.substring(brand.length).trim();
  }
  return value;
}

/// A stock's manufacturer and product, as a box would print it.
///
/// `GOLD 200` becomes `KODAK GOLD 200`; a full label becomes `KODAK T-MAX 400`.
/// A name that already carries the manufacturer is left alone, so calling this
/// twice does not print it twice.
String stockDisplayName(String? name) {
  final String value = (name ?? '').split(',').first.trim();
  if (value.isEmpty) {
    return '';
  }
  final String maker = stockMaker(value);
  final String product = stockProductName(value, maker: maker);
  if (product.isEmpty) {
    return maker;
  }
  if (product.toUpperCase().startsWith(maker.toUpperCase())) {
    return product;
  }
  return '$maker $product';
}

/// Which chemistry a film is, and therefore which stages a print runs.
///
/// A negative is developed, printed onto paper and scanned; a reversal is
/// developed to a positive and scanned, with no print between; a silver image
/// has one record, no dyes and no mask. The app does not simulate any of that —
/// the model does — but it says which one a roll is, because "print" means
/// something different for each.
enum FilmProcess { negative, reversal, monochrome }

/// What a paper carries.
///
/// A colour paper has three dye-forming layers and records colour; a silver
/// paper has one silver image, no dyes, and records luminance. The model's
/// print stage is three channels either way, so the difference is a fact the
/// shelf needs: a colour film on a silver paper renders colour, and that is not
/// what a silver paper does.
enum PaperEmulsion { colour, silver }

/// One field of a stock's record: what it is, and what the file admits to.
///
/// The sentence is the file's, split at its own verdict. `claim` is
/// `measured`, `borrowed`, `placeholder` or `none` when the file said so and
/// empty when it said something the four words cannot carry — in which case the
/// detail is the whole sentence and is shown as it stands.
class Measured {
  const Measured({
    required this.field,
    required this.claim,
    required this.detail,
  });

  final String field;
  final String claim;
  final String detail;

  /// The verdicts the catalogue's vocabulary has words for.
  static const List<String> claims = <String>[
    'measured',
    'borrowed',
    'placeholder',
    'none',
  ];

  static Measured fromJson(Map<String, dynamic> json) => Measured(
    field: json['field'] as String? ?? '',
    claim: json['claim'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
  );
}

/// Where a stock's numbers came from: a data sheet, a printed page, a date, and
/// the digest of the document itself.
class Provenance {
  const Provenance({
    this.publication = '',
    this.page = '',
    this.retrieved = '',
    this.checksum = '',
  });

  final String publication;
  final String page;
  final String retrieved;
  final String checksum;

  bool get isEmpty => publication.isEmpty && retrieved.isEmpty;

  static Provenance fromJson(Map<String, dynamic> json) => Provenance(
    publication: json['publication'] as String? ?? '',
    page: json['page'] as String? ?? '',
    retrieved: json['retrieved'] as String? ?? '',
    checksum: json['checksum'] as String? ?? '',
  );
}

/// A stock: an id the model knows, the name on the box, and the record behind
/// both.
///
/// The id is the model's — `vision3_500t` is how `kalo` spells it — and the
/// label is the manufacturer's, which is why it never translates. `short` is
/// the film's own name in two words, which is what a wall label under a print
/// has room for.
class Stock {
  const Stock({
    required this.id,
    required this.short,
    required this.label,
    this.process,
    this.emulsion,
    this.note = '',
    this.referenceMinutes = 0,
    this.referenceTempC = 0,
    this.provenance = const Provenance(),
    this.measured = const <Measured>[],
  });

  final String id;

  /// The name a box carries: `PORTRA 400`, not the whole catalogue line.
  final String short;

  /// The manufacturer's full name, as the data sheet prints it.
  final String label;

  /// The manufacturer, added back where the interface shows a film or paper.
  String get maker => stockMaker(label.isNotEmpty ? label : short);

  /// The product alone, for a shelf that has already named the maker.
  String get productName =>
      stockProductName(short.isNotEmpty ? short : label, maker: maker);

  /// The stock as a box prints it: manufacturer and product, no data sheet.
  String get displayName {
    final String base = short.isNotEmpty ? short : label;
    if (base.isEmpty || base.toUpperCase().startsWith(maker.toUpperCase())) {
      return base;
    }
    return '$maker $base';
  }

  /// Which chemistry the film is. Null for a paper, which has no process of its
  /// own: it records what is on the negative.
  final FilmProcess? process;

  /// What the paper carries. Null for a film, which is not a paper.
  final PaperEmulsion? emulsion;

  /// What this stock is, and what it is not, in the model's own words.
  final String note;

  /// The development the characteristic curve was measured at.
  final double referenceMinutes;
  final double referenceTempC;

  final Provenance provenance;

  /// One line per field: measured, borrowed, a placeholder, or absent.
  final List<Measured> measured;

  static Stock fromJson(Map<String, dynamic> json) {
    final Object? reference = json['reference'];
    final Map<String, dynamic>? measuredAt = reference is Map<String, dynamic>
        ? reference
        : null;
    final Object? measured = json['measured'];
    return Stock(
      id: json['id'] as String? ?? '',
      short: json['short'] as String? ?? json['label'] as String? ?? '',
      label: json['label'] as String? ?? '',
      process: switch (json['process']) {
        'negative' => FilmProcess.negative,
        'reversal' => FilmProcess.reversal,
        'monochrome' => FilmProcess.monochrome,
        _ => null,
      },
      emulsion: switch (json['emulsion']) {
        'colour' => PaperEmulsion.colour,
        'silver' => PaperEmulsion.silver,
        _ => null,
      },
      note: json['note'] as String? ?? '',
      referenceMinutes: (measuredAt?['minutes'] as num?)?.toDouble() ?? 0,
      referenceTempC: (measuredAt?['temp_c'] as num?)?.toDouble() ?? 0,
      provenance: Provenance.fromJson(
        json['provenance'] is Map<String, dynamic>
            ? json['provenance'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      measured: <Measured>[
        if (measured is List)
          for (final Object? row in measured)
            if (row is Map<String, dynamic>) Measured.fromJson(row),
      ],
    );
  }
}

/// What the model carries: every film and paper it can render, with each one's
/// provenance.
///
/// It comes off the model as one document (`kalo stocks --json`) rather than
/// being written down here, because a shelf that showed a film the model did
/// not have would be an interface lying about its own model.
class Catalogue {
  const Catalogue({required this.films, this.papers = const <Stock>[]});

  final List<Stock> films;
  final List<Stock> papers;

  /// What this build carries when the model does not answer: one film, and the
  /// paper every print is made on.
  static const Catalogue carried = Catalogue(
    films: <Stock>[Stocks.vision],
    papers: <Stock>[Stocks.crystal],
  );

  /// Every film, grouped by chemistry in the order the shelf shows them.
  List<Stock> of(FilmProcess process) => <Stock>[
    for (final Stock stock in films)
      if (stock.process == process) stock,
  ];

  Stock? film(String id) {
    for (final Stock stock in films) {
      if (stock.id == id) {
        return stock;
      }
    }
    return null;
  }

  Stock? paper(String id) {
    for (final Stock stock in papers) {
      if (stock.id == id) {
        return stock;
      }
    }
    return null;
  }

  /// The papers that can print a film of this chemistry.
  ///
  /// A reversal has no print stage at all, so it has no papers. A silver paper
  /// records luminance and the model's print is three channels, so a colour
  /// film on one would render colour — the shelf does not offer what the model
  /// cannot do. A silver film is offered both, its own paper first, because a
  /// silver negative on a colour paper is a print a darkroom actually makes.
  List<Stock> papersFor(FilmProcess? process) {
    if (process == FilmProcess.reversal) {
      return const <Stock>[];
    }
    if (process == FilmProcess.monochrome) {
      // Its own paper first. A silver negative on a colour paper is a print a
      // darkroom does make, so both are offered — the darkroom's own paper is
      // simply the one in front.
      return <Stock>[
        for (final Stock paper in papers)
          if (isSilver(paper)) paper,
        for (final Stock paper in papers)
          if (!isSilver(paper)) paper,
      ];
    }
    return <Stock>[
      for (final Stock paper in papers)
        if (!isSilver(paper)) paper,
    ];
  }

  /// Whether a paper is silver. A paper that did not say is a colour paper:
  /// that is the model's default path, and what every paper before the key was.
  static bool isSilver(Stock paper) => paper.emulsion == PaperEmulsion.silver;

  /// Ask the model for its catalogue.
  ///
  /// A model that cannot be found, or that does not answer, is not an error
  /// worth a dialog: the shelf holds the one film the app carries and the
  /// develop button says why nothing can be developed.
  static Future<Catalogue> load(Model model) async {
    if (!model.available) {
      return carried;
    }
    try {
      final String json = await model.catalogue();
      return Catalogue.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } on Object catch (error) {
      // A catalogue is an enhancement, not a requirement: the app is allowed to
      // work with less than the model knows.
      Model.log('no catalogue: $error');
      return carried;
    }
  }

  static Catalogue fromJson(Map<String, dynamic> json) {
    List<Stock> stocks(String key) => <Stock>[
      if (json[key] is List)
        for (final Object? row in json[key] as List)
          if (row is Map<String, dynamic>) Stock.fromJson(row),
    ];
    return Catalogue(films: stocks('films'), papers: stocks('papers'));
  }
}

/// The stocks this build knows without asking the model.
///
/// One film and one paper, because that is what the app can develop with no
/// catalogue behind the shelf. The shelf is a shelf when the model answers;
/// this is what is on it when the model does not.
abstract final class Stocks {
  static const Stock vision = Stock(
    id: 'vision3_500t',
    short: 'VISION3 500T',
    label: 'KODAK VISION3 500T 5219/7219, ECN-2',
    process: FilmProcess.negative,
  );

  /// The film a new roll is developed as until a box is taken off the shelf.
  static const String defaultId = 'vision3_500t';

  /// The paper a roll is printed on when the shelf was not asked.
  static const String paper = 'fuji_crystal_archive_pearl';

  /// What that paper is called on a wall label, until the catalogue says.
  static const String paperShort = 'CRYSTAL ARCHIVE PEARL';

  /// The paper itself, for a roll developed with no catalogue behind the shelf.
  static const Stock crystal = Stock(
    id: paper,
    short: paperShort,
    label: 'FUJICOLOR CRYSTAL ARCHIVE DIGITAL PEARL PAPER, RA-4',
  );
}
