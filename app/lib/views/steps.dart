/// The three steps of the darkroom, in the order the work goes.
///
/// The photograph is chosen, developed and printed; each one has a page in the
/// same room. The two-letter marks are the film's own vocabulary and do not
/// translate — an edge code is an edge code in every language. Drying is not a
/// step: a print is finished when it leaves the enlarger, and the rack is a
/// place beside the darkroom, not another page of it.
enum DarkroomStep {
  select('01', 'SEL'),
  develop('02', 'DEV'),
  print('03', 'PRT');

  const DarkroomStep(this.code, this.mark);

  /// The number printed before the mark on the film's edge.
  final String code;

  /// The two-letter mark: `SEL`, `DEV`, `PRT`.
  final String mark;
}
