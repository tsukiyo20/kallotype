import 'dart:convert';

import 'package:flutter/services.dart';

/// The strip, as the model drew it.
///
/// Written by `kaloview` from `kallotype-view` and committed as an asset, so
/// that building the app needs no Rust toolchain. It is a rendering of the
/// model at a commit, not a second model: regenerate it with `just view`, never
/// edit it.
class StripData {
  const StripData({
    required this.stockId,
    required this.label,
    required this.note,
    required this.baseDensity,
    required this.referenceTimeMin,
    required this.frames,
  });

  /// The stock's id, as the CLI and the `.kalofilm` files spell it.
  final String stockId;

  /// The stock's label.
  final String label;

  /// The stock's note: what was measured, and what was borrowed.
  final String note;

  /// Base, fog and the orange mask, in status density, in the red, green and
  /// blue records. A densitometer reads this on top of a patch's dye.
  final List<double> baseDensity;

  /// The stock's reference development, in minutes.
  final double referenceTimeMin;

  /// The frames, in the order the model gave them.
  final List<StripFrame> frames;

  /// Where the asset lives, as `pubspec.yaml` declares it.
  static const String assetPath = 'assets/film_strip.json';

  /// Read the committed strip.
  static Future<StripData> load() async {
    final String text = await rootBundle.loadString(assetPath);
    return StripData.fromJson(json.decode(text) as Map<String, dynamic>);
  }

  /// Read a strip from the JSON the binary writes.
  factory StripData.fromJson(Map<String, dynamic> json) {
    return StripData(
      stockId: json['stock_id'] as String,
      label: json['label'] as String,
      note: json['note'] as String,
      baseDensity: _numbers(json['base_density']),
      referenceTimeMin: (json['reference_time_min'] as num).toDouble(),
      frames: <StripFrame>[
        for (final Object? frame in json['frames'] as List<Object?>)
          StripFrame.fromJson(frame as Map<String, dynamic>),
      ],
    );
  }
}

/// One frame: the same exposures as every other frame, developed once.
class StripFrame {
  const StripFrame({
    required this.minutes,
    required this.tempC,
    required this.gamma,
    required this.dMax,
    required this.patches,
  });

  /// How long this frame was in the developer.
  final double minutes;

  /// The developer's temperature, in °C.
  final double tempC;

  /// Contrast in the red, green and blue records.
  final List<double> gamma;

  /// The dye's density ceiling, in the red, green and blue records.
  final List<double> dMax;

  /// Dye density per patch, three numbers each, before the base is counted in.
  ///
  /// The strip is the model's drawing, not a densitometer reading; a roll the
  /// library developed carries the base in its chart, because the instrument
  /// sees it.
  final List<List<double>> patches;

  /// Read a frame from the JSON the binary writes.
  factory StripFrame.fromJson(Map<String, dynamic> json) {
    return StripFrame(
      minutes: (json['minutes'] as num).toDouble(),
      tempC: (json['temp_c'] as num).toDouble(),
      gamma: _numbers(json['gamma']),
      dMax: _numbers(json['d_max']),
      patches: <List<double>>[
        for (final Object? patch in json['patches'] as List<Object?>)
          _numbers((patch as Map<String, dynamic>)['dye_density']),
      ],
    );
  }
}

List<double> _numbers(Object? value) => <double>[
  for (final Object? number in value! as List<Object?>)
    (number! as num).toDouble(),
];
