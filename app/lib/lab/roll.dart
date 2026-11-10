import 'dart:math' as math;
import 'dart:ui';

import '../film/strip_data.dart';

/// A roll: the thing you are carrying.
///
/// A frame is one exposure, one stock, one development. The roll is the unit
/// that holds them, and rolling it up is what the strip is; unrolling it is
/// what the contact sheet is.
class Roll {
  const Roll({
    required this.id,
    required this.stockId,
    required this.stockLabel,
    required this.baseDensity,
    required this.frames,
  });

  /// What you call it: `Roll 01`.
  final String id;

  /// The stock's id, as the CLI and the `.kalofilm` files spell it.
  final String stockId;

  /// The stock's label, as it would be printed on the box.
  final String stockLabel;

  /// Base, fog and the orange mask, in status density, per record.
  final List<double> baseDensity;

  final List<Frame> frames;

  /// Read the roll the model drew.
  ///
  /// The committed asset holds one stock developed five times, so the roll is
  /// the same exposure at five times rather than five different photographs —
  /// which is the one thing this product exists to show, and a good first roll
  /// to judge the sheet against.
  factory Roll.fromStrip(StripData strip, {String id = 'Roll 01'}) {
    return Roll(
      id: id,
      stockId: strip.stockId,
      stockLabel: strip.label,
      baseDensity: strip.baseDensity,
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
    required this.gamma,
    required this.dMax,
    required this.patches,
  });

  /// The frame's number on the roll, from one.
  final int number;

  /// How long this frame was in the developer.
  final double minutes;

  /// The developer's temperature, in °C.
  final double tempC;

  /// Contrast in the red, green and blue records.
  final List<double> gamma;

  /// The dye's density ceiling, in the red, green and blue records.
  final List<double> dMax;

  /// Dye density per patch, three numbers each — the nine-step wedge the model
  /// put through the curve.
  final List<List<double>> patches;

  factory Frame.fromStrip(int number, StripFrame frame) => Frame(
        number: number,
        minutes: frame.minutes,
        tempC: frame.tempC,
        gamma: frame.gamma,
        dMax: frame.dMax,
        patches: frame.patches,
      );

  /// `3:00`, `12:30` — the clock a darkroom timer would show.
  String get clock {
    final int whole = minutes.floor();
    final int tenths = ((minutes - whole) * 60).round();
    return '$whole:${tenths.toString().padLeft(2, '0')}';
  }

  /// The print: nine patches, each a colour.
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
  List<Color> printColours(Color paper) {
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
  /// draws.
  List<double> get toneCurve => <double>[
        for (final List<double> dye in patches)
          (dye[0] + dye[1] + dye[2]) / 3,
      ];

  static Color _print(List<double> dye, List<double> low, Color paper) {
    double through(int i) =>
        math.pow(10, -(dye[i] - low[i]) * 1.05).toDouble();
    return Color.from(
      alpha: 1.0,
      red: paper.r * through(0),
      green: paper.g * through(1),
      blue: paper.b * through(2),
    );
  }
}
