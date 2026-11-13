/// The four steps of the darkroom, in the order the work goes.
///
/// The photograph is chosen, developed, printed and dried; each one has a page
/// in the same room. The two-letter marks are the film's own vocabulary and do
/// not translate — an edge code is an edge code in every language.
enum DarkroomStep {
  select('01', 'SEL'),
  develop('02', 'DEV'),
  print('03', 'PRT'),
  dry('04', 'DRY');

  const DarkroomStep(this.code, this.mark);

  /// The number printed before the mark on the film's edge.
  final String code;

  /// The two-letter mark: `SEL`, `DEV`, `PRT`, `DRY`.
  final String mark;
}
