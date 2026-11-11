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
        'line' => zh ? '晾片绳' : 'Line',
        _ => zh ? '观景台' : 'Gallery',
      };

  String get library => zh ? '资料库' : 'Library';

  /// What a roll is called on the pages that name it.
  ///
  /// The photograph, because that is what the roll is — there is one, so it
  /// does not need a number, and a name is what it had before it was film. A
  /// roll the model drew has no photograph: it is the strip that proves the
  /// sheet can be read at all, and it says so.
  String rollName(Roll roll) =>
      roll.name ?? (zh ? '模型的样片' : "The model's strip");

  String frames(int count) => zh ? '$count 格' : '$count frame${count == 1 ? '' : 's'}';

  // -- the toolbar and the status bar ---------------------------------------

  String statusBar(int frame, String clock, String temp) =>
      zh ? '第 $frame 格   ·   $clock   ·   $temp' : 'Frame $frame   ·   $clock   ·   $temp';

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
  String get onTheLine => zh ? '已进晾片绳' : 'on the line';

  // -- the line -------------------------------------------------------------

  String printCount(int count) => zh ? '$count 张' : '$count print${count == 1 ? '' : 's'}';
  String get lineEmpty => zh ? '晾片绳是空的' : 'Nothing on the line';
  String get lineEmptyNote =>
      zh ? '在工作台上按印，印相会挂到这里，等干了再看。' : 'Print a frame on the workbench and it hangs here until you look at it.';

  // -- the binder -----------------------------------------------------------

  String get binderNote =>
      zh ? '这一卷的来历，和模型量到的数。' : 'Where this roll came from, and the numbers the model measured.';

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
      ? '印相是文件。模型把它写出来，观景台挂出这个文件夹里的每一张——app 自己一张都不带。'
      : 'A print is a file. The model writes it out, the gallery hangs whatever is in this folder, and the app carries none of them itself.';

  String get folder => zh ? '文件夹' : 'Folder';
  String get choose => zh ? '选择…' : 'Choose…';
  String get useDefault => zh ? '用回默认位置' : 'Use the default';
  String get noFolder => zh ? '这台设备上还没有位置' : 'No folder on this device yet';

  /// Said where the platform does not let an app pick, which is every phone.
  String get fixedFolder => zh
      ? '手机上 app 不能挑文件夹。这里是系统给的位置：在「文件」里打开它，放进去什么，墙上就挂什么。'
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
