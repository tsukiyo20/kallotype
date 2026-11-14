import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../lab/roll.dart';
import '../lab/stock.dart';

/// The words that are not the film's.
///
/// The film's own vocabulary never translates: `EI`, `C-41`, `GOLD 200`, a
/// temperature, a time. Everything a person reads as a label does — which is
/// most of this file. The English build is the Chinese build with fewer words
/// in it, so switching moves no layout.
class KalloStrings {
  const KalloStrings(this.zh);

  /// Whether the human layer is Chinese.
  final bool zh;

  static KalloStrings of(BuildContext context) =>
      Localizations.of<KalloStrings>(context, KalloStrings)!;

  static const LocalizationsDelegate<KalloStrings> delegate =
      _KalloStringsDelegate();

  static const List<Locale> supported = <Locale>[Locale('en'), Locale('zh')];

  // -- the places -----------------------------------------------------------

  String placeLabel(String name) => switch (name) {
    'shelf' => zh ? '架子' : 'Shelf',
    'table' => zh ? '台面' : 'Table',
    'workbench' => zh ? '工作台' : 'Workbench',
    'binder' => zh ? '活页夹' : 'Binder',
    'rack' => zh ? '晾片架' : 'Drying rack',
    _ => zh ? '观景台' : 'Gallery',
  };

  String get library => zh ? '资料库' : 'Library';

  // -- the studio -----------------------------------------------------------

  /// The two rooms, and the rack between them. The darkroom is where the work
  /// is made; the gallery is where it is looked at; the rack is where the paper
  /// goes when it comes out.
  String get darkroom => zh ? '暗房' : 'Darkroom';
  String get rack => zh ? '晾片架' : 'Drying rack';
  String get galleryRoom => zh ? '观景台' : 'Gallery';

  /// The three steps of the darkroom, in the order the work goes.
  String get selectStep => zh ? '选片' : 'Select';
  String get developStep => zh ? '显影' : 'Develop';
  String get printStep => zh ? '印相' : 'Print';

  String get settings => zh ? '设置' : 'Settings';
  String get thisStrip => zh ? '这一条' : 'THIS STRIP';
  String get noPhotographChosen => zh ? '还没选片' : 'nothing chosen';
  String get choosePhotoNote => zh
      ? '选一张照片。它会留在暗房里，胶片和相纸随后决定。'
      : 'Choose a photograph. It stays in the darkroom; the film and the paper come next.';
  String get originalNote => zh
      ? '照片还没有进显影液。先看它，再决定用什么胶片。'
      : 'The photograph before the developer. Look at it, then choose a film.';
  String get theOriginal => zh ? '原片' : 'ORIGINAL';
  String get changePhoto => zh ? '换一张' : 'Change';
  String get goDevelop => zh ? '去显影' : 'To the developer';
  String get metered => zh ? '自动测光' : 'Metered';
  String get exposure => zh ? '曝光' : 'EXPOSURE';

  /// The strip, and the one exposure every print on it shares.
  String get testStrip => zh ? '试片条' : 'TEST STRIP';
  String get testStripNote => zh
      ? '每按一次显影落一张，所有试片共用首张的相纸曝光。'
      : 'One print per development, all on the first print\'s paper exposure.';
  String get noTestPrints =>
      zh ? '还没有试片。拉时间，按显影。' : 'No prints yet. Choose a time and develop.';
  String get newStrip => zh ? '另起一条' : 'New strip';
  String stripCount(int count) =>
      zh ? '$count 张' : '$count print${count == 1 ? '' : 's'}';
  String get firstPrint => zh ? '首张' : 'First print';
  String get sameExposure => zh ? '同曝光' : 'One exposure';
  String get firstPrintWaiting => zh ? '首张待定' : 'the first print decides';
  String exposureOf(String clock) =>
      zh ? '同曝光 · $clock' : 'one exposure · $clock';
  String get removePrint => zh ? '移除这张' : 'Remove this print';
  String get materialsNote =>
      zh ? '换胶片或相纸会另起一条试片。' : 'A different film or paper starts a new strip.';
  String get temperatureNote => zh
      ? '温度也属于这条试片。换温度会另起一条，照片和材料留下。'
      : 'The temperature belongs to the strip too. Changing it starts a new strip; the photograph and materials stay.';

  /// The instrument panel's curves.
  String get filmCurve => zh ? '胶片' : 'FILM';
  String get paperCurve => zh ? '相纸' : 'PAPER';
  String get printCurve => zh ? '印相' : 'PRINT';
  String get printExposure => zh ? '印相曝光' : 'PRINT EXPOSURE';
  String get filters => zh ? '滤色片' : 'FILTERS';
  String get heatGlass => zh ? '隔热玻璃' : 'HEAT GLASS';
  String get noGlass => zh ? '无' : 'none';
  String get developing => zh ? '显影中…' : 'Developing…';
  String get redevelop => zh ? '重冲' : 'Re-develop';
  String get printAction => zh ? '印相' : 'Print';
  String get printNote => zh
      ? '成品按这张底片单独平衡，不是试片上的那一张。'
      : 'The finished print is balanced for this negative, not for the strip.';
  String get chooseFirstPrint => zh
      ? '先冲一张试片，再印成品。'
      : 'Develop a test print first; the finished print follows.';
  String get printQueued => zh ? '已印 · 去晾片架看看' : 'printed · look at the rack';
  String get goRack => zh ? '去晾片架' : 'To the drying rack';
  String get darkroomNote =>
      zh ? '一条试片，一种胶片，一张照片。' : 'One strip, one film, one photograph.';
  String get noPaperForFilm =>
      zh ? '这支胶片没有相纸可选。' : 'This film has no paper to choose.';

  /// What a roll is called on the pages that name it.
  ///
  /// The photograph, because that is what the roll is — there is one, so it
  /// does not need a number, and a name is what it had before it was film. A
  /// roll the model drew has no photograph: it is the strip that proves the
  /// sheet can be read at all, and it says so.
  String rollName(Roll roll) =>
      roll.name ?? (zh ? '模型的样片' : "The model's strip");

  String frames(int count) =>
      zh ? '$count 格' : '$count frame${count == 1 ? '' : 's'}';

  // -- the toolbar and the status bar ---------------------------------------

  String statusBar(int frame, String clock, String temp) => zh
      ? '第 $frame 格   ·   $clock   ·   $temp'
      : 'Frame $frame   ·   $clock   ·   $temp';

  // -- the inspector --------------------------------------------------------

  String get frame => zh ? '格' : 'FRAME';

  String ofFrames(int total) => zh ? '共 $total 格' : 'of $total';

  String get time => zh ? '时间' : 'Time';
  String get temperature => zh ? '温度' : 'Temperature';
  String get gamma => zh ? '伽马' : 'Gamma';
  String get dMax => zh ? '最大密度' : 'D max';
  String get tone => zh ? '影调' : 'TONE';
  String get develop => zh ? '显影' : 'Develop';

  /// The inspector's one action: the frame, on the bench, where it is one frame
  /// and not one of forty. It says what it does, not what a button on a table
  /// is expected to say.
  String get enlarge => zh ? '放大' : 'Enlarge';

  /// The glass on the table: a proof is read through one.
  String get loupe => zh ? '放大镜' : 'Loupe';

  // -- the shelf ------------------------------------------------------------

  String get newRoll => zh ? '新的一卷' : 'A new roll';

  String get newRollNote => zh
      ? '一张照片进显影液五次，出来一卷。同一格、五个时间——这条胶片唯一要证明的就是这件事。'
      : 'One photograph into the developer five times, and a roll comes out. The same frame at five times — which is the one thing a strip of film has to prove.';

  String get photograph => zh ? '照片' : 'PHOTOGRAPH';
  String get choosePhoto => zh ? '选择照片…' : 'Choose a photograph…';
  String get noPhotograph => zh ? '还没选' : 'nothing chosen';
  String get film => zh ? '胶片' : 'FILM';
  String get developments => zh ? '显影时间' : 'DEVELOPMENTS';

  String developingOf(int done, int total) =>
      zh ? '显影 $done / $total' : 'developing $done of $total';

  String get noModel => zh
      ? '这台机器上找不到模型（kalo）。没有它，架上只能放着胶片，显不了影。'
      : 'No model on this machine (kalo). Without it the shelf can hold film, but nothing can be developed.';

  String get onTheTable => zh ? '在台面上' : 'on the table';
  String get openRoll => zh ? '打开' : 'Open';

  String get theShelf => zh ? '架上' : 'THE SHELF';

  /// What is on the shelf, counted. The papers are left out when there are
  /// none, which is what a shelf behind a model that does not carry them is.
  String shelfCount(int films, int papers) {
    final String film = zh ? '$films 支胶片' : '$films films';
    if (papers == 0) {
      return film;
    }
    return zh ? '$film · $papers 张相纸' : '$film · $papers papers';
  }

  /// Said when the model did not answer and the shelf holds its one film.
  String get shelfAlone => zh
      ? '模型没有应答，架上只有 app 自己带着的这一支。'
      : 'The model did not answer, so the shelf holds the one film this app carries.';

  /// A group of boxes on the shelf, and the chemistry they share.
  String processName(FilmProcess process) => switch (process) {
    FilmProcess.negative => zh ? '彩色负片' : 'COLOUR NEGATIVE',
    FilmProcess.reversal => zh ? '彩色反转片' : 'COLOUR REVERSAL',
    FilmProcess.monochrome => zh ? '黑白' : 'MONOCHROME',
  };

  /// What the chemistry means for the stages a roll goes through. The model's
  /// own sentence, in the app's words.
  String processNote(FilmProcess process) => switch (process) {
    FilmProcess.negative =>
      zh ? '负片 —— 显影、印相、扫描' : 'negative — developed, printed, scanned',
    FilmProcess.reversal =>
      zh ? '反转片 —— 胶片自己就是照片，没有印相' : 'reversal — the film is the picture',
    FilmProcess.monochrome =>
      zh ? '黑白 —— 一个记录，没有染料' : 'monochrome — one record, no dyes',
  };

  // -- the workbench --------------------------------------------------------

  String get printOut => zh ? '印' : 'Print';

  String get colourPaper => zh ? '彩色相纸' : 'COLOUR PAPER';
  String get silverPaper => zh ? '黑白相纸' : 'SILVER PAPER';

  /// Said where the papers would be, for a film whose print stage is skipped.
  String get noPaper => zh
      ? '反转片自己就是照片 —— 没有印相，也就没有相纸可选。'
      : 'A reversal is its own picture — no print, and so no paper to choose.';

  /// Said where the print button would be, for a film that has no print stage.
  String get noPrintStage => zh
      ? '反转片自己就是照片 —— 这一卷没有印相。'
      : 'A reversal is its own picture — there is no print to make here.';
  String get paper => zh ? '相纸' : 'PAPER';

  /// The bench's lamp: the frame as the wall will hang it. A proof, not a
  /// print — nothing is made, and nothing leaves the bench.
  String get proof => zh ? '打样' : 'Proof';
  String get printedOut => zh ? '印好了' : 'printed';
  String get printing => zh ? '正在印…' : 'Printing…';
  String get onTheRack => zh ? '已进晾片架' : 'on the rack';

  // -- the drying rack ------------------------------------------------------

  String printCount(int count) =>
      zh ? '$count 张' : '$count print${count == 1 ? '' : 's'}';
  String get rackEmpty => zh ? '晾片架是空的' : 'Nothing on the rack';
  String get rackEmptyNote => zh
      ? '在印相里按印，成品会挂到这里，等干了再进观景台。'
      : 'Print in the darkroom and it hangs here until it is dry.';

  // -- the binder -----------------------------------------------------------

  String get binderNote => zh
      ? '这一卷的来历，和模型量到的数。'
      : 'Where this roll came from, and the numbers the model measured.';

  String get theFilm => zh ? '胶片' : 'THE FILM';
  String get thePaper => zh ? '相纸' : 'THE PAPER';
  String get measuredAndBorrowed => zh ? '量到的和借来的' : 'MEASURED AND BORROWED';
  String get reference => zh ? '参考显影' : 'Reference';
  String get source => zh ? '出处' : 'Source';

  /// Where in the sheet, and when it was read.
  String page(String page) => zh ? '第 $page 页' : 'page $page';
  String readOn(String date) => zh ? '取于 $date' : 'read $date';

  /// What a `[measured]` line admits to. The four words the catalogue's
  /// vocabulary has; an empty claim is a sentence the four cannot carry, and it
  /// is shown as it stands.
  String claim(String claim) => switch (claim) {
    'measured' => zh ? '量到' : 'measured',
    'borrowed' => zh ? '借来' : 'borrowed',
    'placeholder' => zh ? '占位' : 'placeholder',
    'none' => zh ? '没有' : 'none',
    _ => '',
  };

  /// A field of a stock's record. Technical, so it translates only where the
  /// Chinese has a word of its own for it.
  String field(String field) => switch (field) {
    'curves' => zh ? '曲线' : 'curves',
    'layers' => zh ? '感光层' : 'layers',
    'dyes' => zh ? '染料' : 'dyes',
    'mask' => zh ? '遮罩' : 'mask',
    'grain' => zh ? '颗粒' : 'grain',
    'cl_layer' => zh ? '抑制层' : 'CL layer',
    'white' => zh ? '白' : 'white',
    _ => field,
  };

  String get theRoll => zh ? '这一卷' : 'THE ROLL';
  String get theLadder => zh ? '显影梯度' : 'THE LADDER';
  String get theCurves => zh ? '曲线' : 'THE CURVES';
  String get theFiles => zh ? '文件' : 'THE FILES';
  String get rollFolder => zh ? '卷' : 'Roll';
  String get printsFolder => zh ? '印相' : 'Prints';

  String get noCurve => zh
      ? '这一卷是模型直接渲出来的：它交出像，不交出像背后的密度。等它肯把数给出来，曲线就回来了。'
      : 'This roll came out as pixels. The model writes a picture and not the densities behind it; the curves come back when it hands over the numbers.';

  // -- the gallery ----------------------------------------------------------

  /// The switch on the wall. Not the appearance's light: the room's.
  String get roomLight => zh ? '灯' : 'Light';

  /// Back to the wall, from a print looked at closely.
  String get back => zh ? '返回墙上' : 'Back to the wall';

  /// What a person is looking at: the file's pixels, and how much of them.
  String magnification(String size, String percent) =>
      zh ? '$size 像素   ·   $percent' : '$size pixels   ·   $percent';

  /// The one scale worth naming: one image pixel on one device pixel.
  String get actualPixels => zh ? '1:1' : '1:1';

  /// The finished product: the print as a 35 mm frame.
  String get exportFrame => zh ? '导出胶片边框' : 'Export film frame';
  String get exportingFrame => zh ? '正在导出…' : 'Exporting…';
  String get exportedFrame => zh ? '已导出 · Frames' : 'Exported · Frames';
  String get exportFailed => zh ? '导出失败' : 'Export failed';

  /// What the edge of the film is called, when the frame needs a name.
  String get filmFrame => zh ? '胶片边框' : 'FILM FRAME';

  // -- the drawer -----------------------------------------------------------

  String get drawer => zh ? '抽屉' : 'DRAWER';
  String get close => zh ? '关闭' : 'CLOSE';

  String get tabLanguage => zh ? '语言' : 'LANGUAGE';
  String get tabAppearance => zh ? '外观' : 'APPEARANCE';
  String get tabPrints => zh ? '印相' : 'PRINTS';
  String get tabColour => zh ? '色彩' : 'COLOUR';
  String get tabAbout => zh ? '关于' : 'ABOUT';

  String get language => zh ? '语言' : 'Language';
  String get followsDevice =>
      zh ? '跟随系统，除非你在这里把它钉住。' : 'Follows your device unless you pin it here.';
  String get interfaceLanguage => zh ? '界面语言' : 'Interface language';
  String get system => zh ? '跟随系统' : 'System';
  String deviceLine(String tag) => zh ? '设备：$tag' : 'device: $tag';

  String get appearance => zh ? '外观' : 'Appearance';
  String get appearanceLabel => zh ? '界面外观' : 'Appearance';
  String get light => zh ? '浅色' : 'Light';
  String get dark => zh ? '深色' : 'Dark';
  String systemLine(String value) => zh ? '系统：$value' : 'system: $value';
  // -- prints ---------------------------------------------------------------

  String get prints => zh ? '印相' : 'Prints';

  String get printsNote => zh
      ? '印相是文件。模型把它写出来，观景台把每一张放进胶片边框；导出的成品在 Frames/ 里。app 自己一张都不带。'
      : 'A print is a file. The model writes it out, the gallery frames whatever is in this folder, and the framed exports go in Frames/. The app carries none of them itself.';

  String get folder => zh ? '文件夹' : 'Folder';
  String get choose => zh ? '选择…' : 'Choose…';
  String get useDefault => zh ? '用回默认位置' : 'Use the default';
  String get noFolder => zh ? '这台设备上还没有位置' : 'No folder on this device yet';

  /// Said where the platform does not let an app pick, which is every phone.
  String get fixedFolder => zh
      ? '手机上 app 不能挑文件夹。这里是系统给的位置：在「文件」里打开它，放进去什么，观景台就挂什么。'
      : 'A phone does not let an app choose a folder. This one is the system\'s: open it in Files, and whatever you put there is on the wall.';

  // -- colour ---------------------------------------------------------------

  String get colour => zh ? '色彩' : 'Colour';
  String get path => zh ? '路径' : 'PATH';
  String get scalarPath => zh ? '逐通道' : 'Per channel';
  String get spectralPath => zh ? '光谱' : 'Spectral';

  /// What choosing the spectral path does, and what it changes.
  String get spectralNote => zh
      ? '71 个波长：曝光、印相、扫描都走光谱，而不是逐通道。图会变淡——染料串色是真的，不是滤镜。'
      : 'Seventy-one wavelengths through exposure, print and scan, instead of one number per channel. The image goes more muted: dye crosstalk is real, not a filter.';
  String get colourNote => zh
      ? '模型只输出 sRGB，显示交给系统管理。宽色域是显示器的本事，不是我们的。'
      : 'The model writes sRGB and the system manages the display. Wide gamut is the screen\'s business, not ours.';

  String get about => zh ? '关于' : 'About';
  String get aboutNote => zh
      ? 'Kallotype。字体是 Inter 和 Noto Sans SC。模型在 Rust 里，这里是它的脸。'
      : 'Kallotype. Type is Inter and Noto Sans SC. The model is in Rust; this is its face.';

  String get applyAtOnce =>
      zh ? '设置立即生效，不重启。' : 'Settings apply at once. Nothing restarts.';
}

class _KalloStringsDelegate extends LocalizationsDelegate<KalloStrings> {
  const _KalloStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'zh';

  @override
  Future<KalloStrings> load(Locale locale) => SynchronousFuture<KalloStrings>(
    KalloStrings(locale.languageCode == 'zh'),
  );

  @override
  bool shouldReload(_KalloStringsDelegate old) => false;
}
