import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The words that are not the film's.
///
/// English is the film's language — `EI`, `C-41`, `TIME`, `DEVELOP` are printed
/// on the box and never translate — and everything else is the human layer,
/// which does. So the two locales differ in about twenty strings, the English
/// build is a subset of the Chinese one, and switching moves nothing.
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

  String noteFor(String place) => switch (place) {
        'shelf' => zh ? '胶片，和一个新卷' : 'stock, and a new roll',
        'table' => zh ? '这一卷，卷着或者展开' : 'the roll, rolled or unrolled',
        'binder' => zh ? '曲线和出处' : 'curves and provenance',
        'line' => zh ? '印出来的照片和队列' : 'prints, and the queue',
        _ => zh ? '语言、色彩、声音' : 'language, colour, sound',
      };

  // -- the drawer -----------------------------------------------------------

  String get drawer => 'DRAWER';
  String get close => 'CLOSE';

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

  String get appearance => zh ? '外观' : 'Appearance';
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
      ? 'Kallotype 0.2.0。字体是 IBM Plex，SIL OFL 1.1。模型在 Rust 里，这里是它的脸。'
      : 'Kallotype 0.2.0. Type is IBM Plex, SIL OFL 1.1. The model is in Rust; this is its face.';

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
