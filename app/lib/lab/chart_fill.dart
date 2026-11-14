import 'chart.dart';
import 'model.dart';
import 'roll.dart';

/// Give a roll the reading the library could not take when it was developed.
///
/// A chart is the stock and the development times, both of which the roll's
/// record already holds, so the strip can be read again without developing
/// anything. A roll that cannot be charted — the subprocess fallback, or a
/// stock the model no longer carries — comes back unchanged.
///
/// The test is [Frame.isMeasured], not [Frame.hasChart]: an old record holds
/// the curve the model drew, and it is replaced by the densitometer's reading.
/// A frame that is already measured is left alone.
Future<Roll> fillChart(Roll roll, Model model) async {
  if (roll.frames.every((Frame frame) => frame.isMeasured)) {
    return roll;
  }
  if (!model.available) {
    return roll;
  }
  final List<FilmChart>? chart;
  try {
    chart = await model.chart(
      stock: roll.stockId,
      times: <double>[for (final Frame frame in roll.frames) frame.minutes],
      tempC: roll.frames.first.tempC,
    );
  } catch (error) {
    Model.log('the chart could not be filled in: $error');
    return roll;
  }
  if (chart == null || chart.length != roll.frames.length) {
    return roll;
  }
  final List<Frame> frames = <Frame>[
    for (int i = 0; i < roll.frames.length; i++)
      Frame(
        number: roll.frames[i].number,
        minutes: roll.frames[i].minutes,
        tempC: roll.frames[i].tempC,
        image: roll.frames[i].image,
        gamma: chart[i].gamma,
        dMax: chart[i].dMax,
        patches: chart[i].patches,
        measured: true,
      ),
  ];
  return Roll(
    stockId: roll.stockId,
    stockLabel: roll.stockLabel,
    frames: frames,
    photo: roll.photo,
    paperId: roll.paperId,
    paperLabel: roll.paperLabel,
    spectral: roll.spectral,
    contact: roll.contact,
  );
}
