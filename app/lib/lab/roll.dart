import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show Color;

import '../film/strip_data.dart';
import 'clock.dart';
import 'stock.dart';

/// A roll: the thing you are carrying.
///
/// A frame is one exposure, one stock, one development. The roll is the unit
/// that holds them, and rolling it up is what the strip is; unrolling it is
/// what the contact sheet is.
class Roll {
  const Roll({
    required this.number,
    required this.stockId,
    required this.stockLabel,
    required this.frames,
    this.photo,
    this.paperId,
    this.paperLabel,
  });

  /// Which roll it is, from one. What it is called is the interface's business
  /// — `Roll 01` in English, `第 01 卷` in Chinese.
  final int number;

  /// The stock's id, as the CLI and the `.kalofilm` files spell it.
  final String stockId;

  /// The stock's label, as it would be printed on the box.
  final String stockLabel;

  /// The photograph this roll was developed from, when the app developed it.
  /// A roll the model drew has none: it is a chart, not a picture.
  final String? photo;

  /// The paper the frames were printed on, when the shelf chose one. A roll
  /// from before the choice has none, and prints on the app's paper.
  ///
  /// It belongs to the roll rather than to the print because every frame on the
  /// bench is already a print: the model renders each one through the paper,
  /// so the paper is a fact about the roll and not a setting of the viewer.
  final String? paperId;

  /// The paper's label, for a catalogue that cannot name it.
  final String? paperLabel;

  /// The paper a print of this roll is made on.
  String get paper => paperId ?? Stocks.paper;

  /// What that paper is called on a wall label.
  ///
  /// Resolved against the shelf when it has the paper, and against the record
  /// when it does not — a roll is allowed to be older than the app's catalogue.
  String paperName(Catalogue catalogue) =>
      catalogue.paper(paper)?.short ?? paperLabel ?? Stocks.paperShort;

  final List<Frame> frames;

  /// Read the roll the model drew.
  ///
  /// The committed asset holds one stock developed five times, so the roll is
  /// the same exposure at five times rather than five different photographs —
  /// which is the one thing this product exists to show, and a good first roll
  /// to judge the sheet against.
  factory Roll.fromStrip(StripData strip, {int number = 1}) {
    return Roll(
      number: number,
      stockId: strip.stockId,
      stockLabel: strip.label,
      frames: <Frame>[
        for (int i = 0; i < strip.frames.length; i++)
          Frame.fromStrip(i + 1, strip.frames[i]),
      ],
    );
  }
}

/// One frame: what was in the camera, and how long it was in the developer.
class Frame {
  const Frame({
    required this.number,
    required this.minutes,
    required this.tempC,
    this.gamma,
    this.dMax,
    this.patches,
    this.image,
  });

  /// The frame's number on the roll, from one.
  final int number;

  /// How long this frame was in the developer.
  final double minutes;

  /// The developer's temperature, in °C.
  final double tempC;

  /// Contrast in the red, green and blue records.
  final List<double>? gamma;

  /// The dye's density ceiling, in the red, green and blue records.
  final List<double>? dMax;

  /// Dye density per patch, three numbers each — the nine-step wedge the model
  /// put through the curve.
  ///
  /// Null for a frame the app developed: `kalo render` writes pixels, and the
  /// curves behind them are not a thing a command line prints. A chart with
  /// four rows missing is better than a chart with four rows invented.
  final List<List<double>>? patches;

  /// The print the model made of this frame, at the size the bench shows.
  final ui.Image? image;

  factory Frame.fromStrip(int number, StripFrame frame) => Frame(
        number: number,
        minutes: frame.minutes,
        tempC: frame.tempC,
        gamma: frame.gamma,
        dMax: frame.dMax,
        patches: frame.patches,
      );

  /// `3:00`, `12:30` — the clock a darkroom timer would show.
  String get clock => darkroomClock(minutes);

  /// Whether this frame can be charted: a roll the model drew has the wedge's
  /// densities, and a roll the app developed has pictures instead.
  bool get isMeasured => patches != null;

  /// The print: nine patches, each a colour. Null when there is no chart.
  ///
  /// Density is optical, so ten to the minus it is the light that got through.
  /// Each frame is printed for its own highlights, the way a printer exposes
  /// for the thin part of the negative: subtract the frame's minimum density
  /// before turning it into light. That is what makes the sheet show the thing
  /// it exists to show — the same wedge, nine minutes apart, with more contrast
  /// at longer times and not merely more darkness.
  ///
  /// The real print solve — the enlarger, the paper, the reflectance — belongs
  /// to the model and is not guessed here.
  List<Color>? printColours(Color paper) {
    final List<List<double>>? patches = this.patches;
    if (patches == null) {
      return null;
    }
    final List<double> low = <double>[
      for (int channel = 0; channel < 3; channel++)
        patches
            .map((List<double> patch) => patch[channel])
            .reduce((double a, double b) => math.min(a, b)),
    ];
    return <Color>[
      for (final List<double> dye in patches) _print(dye, low, paper),
    ];
  }

  /// Density at each patch, averaged over the records: what the card's curve
  /// draws. Null when there is no chart to draw.
  List<double>? get toneCurve {
    final List<List<double>>? patches = this.patches;
    if (patches == null) {
      return null;
    }
    return <double>[
      for (final List<double> dye in patches) (dye[0] + dye[1] + dye[2]) / 3,
    ];
  }

  static Color _print(List<double> dye, List<double> low, Color paper) {
    double through(int i) => math.pow(10, -(dye[i] - low[i]) * 1.05).toDouble();
    return Color.from(
      alpha: 1.0,
      red: paper.r * through(0),
      green: paper.g * through(1),
      blue: paper.b * through(2),
    );
  }
}
