import 'chart.dart';
import 'model.dart';
import 'roll.dart';

/// Give a roll the chart it was developed before the library could measure.
///
/// A chart is the stock and the development times, both of which the roll's
/// record already holds, so it can be filled in without developing anything
/// again. A roll that cannot be charted — the subprocess fallback, or a stock
/// the model no longer carries — comes back unchanged.
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
