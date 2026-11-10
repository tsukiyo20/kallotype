import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
        'binder' => zh ? '活页夹' : 'Binder',
        _ => zh ? '晾片绳' : 'Line',
      };

  String get library => zh ? '资料库' : 'Library';
  String get rolls => zh ? '胶卷' : 'Rolls';

  /// `Roll 01` in English, `第 01 卷` in Chinese.
  String rollName(int number) {
    final String padded = number.toString().padLeft(2, '0');
    return zh ? '第 $padded 卷' : 'Roll $padded';
  }

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

  // -- the drawer -----------------------------------------------------------

  String get drawer => zh ? '抽屉' : 'DRAWER';
  String get close => zh ? '关闭' : 'CLOSE';

  String get tabLanguage => zh ? '语言' : 'LANGUAGE';
  String get tabAppearance => zh ? '外观' : 'APPEARANCE';
  String get tabColour => zh ? '色彩' : 'COLOUR';
  String get tabPerformance => zh ? '性能' : 'PERFORMANCE';
  String get tabSound => zh ? '声音' : 'SOUND';
  String get tabAbout => zh ? '关于' : 'ABOUT';

  String get language => zh ? '语言' : 'Language';
  String get followsDevice =>
      zh ? '跟随系统，除非你在这里把它钉住。' : 'Follows your device unless you pin it here.';
  String get interfaceLanguage => zh ? '界面语言' : 'Interface language';
  String get system => zh ? '跟随系统' : 'System';
  String get technicalTerms => zh ? '技术词' : 'Technical terms';
  String get keepEnglish =>
      zh ? '中文旁边保留实验室的英文' : "Keep the lab's English beside the Chinese";
  String get numbers => zh ? '数字' : 'Numbers';
  String get decimalPoint => zh ? '小数点' : 'Decimal point';
  String get neverRounded => zh
      ? '密度、曝光和时间从不为了显示而取整。'
      : 'Density, exposure and time are never rounded for display.';

  String deviceLine(String tag) => zh ? '设备：$tag' : 'device: $tag';

  String get appearance => zh ? '外观' : 'Appearance';
  String get appearanceLabel => zh ? '界面外观' : 'Appearance';
  String get light => zh ? '浅色' : 'Light';
  String get dark => zh ? '深色' : 'Dark';
  String systemLine(String value) => zh ? '系统：$value' : 'system: $value';
  String get appearanceNote => zh
      ? '动效只有三种词汇：光、液体、机械。系统要求减弱动效时，它们全部退成淡入。'
      : 'Motion has three vocabularies: light, liquid, mechanism. When the system asks for less, all three become a fade.';

  String get colour => zh ? '色彩' : 'Colour';
  String get colourNote => zh
      ? '模型只输出 sRGB，显示交给系统管理。宽色域是显示器的本事，不是我们的。'
      : 'The model writes sRGB and the system manages the display. Wide gamut is the screen\'s business, not ours.';

  String get performance => zh ? '性能' : 'Performance';
  String get performanceNote => zh
      ? '六端都跑 Impeller，没有可切换的渲染器。这台机器上是 Metal。'
      : 'Impeller on all six platforms. There is no renderer to switch. On this machine it is Metal.';

  String get sound => zh ? '声音' : 'Sound';
  String get soundNote => zh
      ? '默认关。打开之后，你听到的第一声是计时器。'
      : 'Off by default. When you turn it on, the first thing you hear is the timer.';

  String get about => zh ? '关于' : 'About';
  String get aboutNote => zh
      ? 'Kallotype 0.2.0。字体是 Inter 和 Noto Sans SC。模型在 Rust 里，这里是它的脸。'
      : 'Kallotype 0.2.0. Type is Inter and Noto Sans SC. The model is in Rust; this is its face.';

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
