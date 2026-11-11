import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/exports.dart';
import '../widgets/button.dart';
import '../widgets/segments.dart';

/// Settings, as a drawer in the bench.
///
/// A place you open, not a page you go to. Seven cards on one sheet of paper,
/// and the film's own words are the ones that do not change when the language
/// does.
class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({
    super.key,
    required this.locale,
    required this.onLocale,
    required this.technicalTerms,
    required this.onTechnicalTerms,
    required this.spectral,
    required this.onSpectral,
    required this.export,
    required this.onClose,
  });

  /// What the user pinned, or null to follow the device.
  final Locale? locale;
  final ValueChanged<Locale?> onLocale;
  final bool technicalTerms;
  final ValueChanged<bool> onTechnicalTerms;

  /// The path a new roll is developed through, and the way to change it.
  final bool spectral;
  final ValueChanged<bool> onSpectral;

  /// Where prints come from, and whether this platform lets a person say.
  final ExportSetting export;

  final VoidCallback onClose;

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  List<String> _tabs(KalloStrings s) => <String>[
        s.tabLanguage,
        s.tabAppearance,
        s.tabPrints,
        s.tabColour,
        s.tabPerformance,
        s.tabSound,
        s.tabAbout,
      ];

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: KalloSpace.step3),
              child: Row(
                children: <Widget>[
                  Text(
                    s.drawer,
                    style: KalloType.caption.copyWith(
                      color: colors.inkFaint,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClose,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(KalloSpace.step2),
                      child: Text(
                        s.close,
                        style: KalloType.caption.copyWith(color: colors.inkMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: colors.hairline),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(width: 190, child: _rail(colors)),
                Container(width: 1, color: colors.hairline),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      KalloSpace.step4 - 4,
                      KalloSpace.step4 - 6,
                      KalloSpace.step4,
                      KalloSpace.step4,
                    ),
                    // A drawer opened on a 27-inch display should still read
                    // as a page, not as two columns a metre apart.
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: _page(s, colors),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: colors.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KalloSpace.step3,
              vertical: KalloSpace.step2 + 2,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  s.applyAtOnce,
                  style: KalloType.data.copyWith(
                    fontSize: 10,
                    color: colors.inkFaint,
                  ),
                ),
                const Spacer(),
                Text(
                  'v0.2.0',
                  style: KalloType.data.copyWith(
                    fontSize: 10,
                    color: colors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rail(KalloColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KalloSpace.step3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < _tabs(KalloStrings.of(context)).length; i++)
            GestureDetector(
              onTap: () => setState(() => _tab = i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KalloSpace.step3 + 4,
                  vertical: KalloSpace.step2 + 2,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: i == _tab ? colors.accent : const Color(0x00000000),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  _tabs(KalloStrings.of(context))[i],
                  style: KalloType.caption.copyWith(
                    color: i == _tab ? colors.ink : colors.inkFaint,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _page(KalloStrings s, KalloColors colors) {
    switch (_tab) {
      case 0:
        return _language(s, colors);
      case 1:
        return _appearance(s, colors);
      case 2:
        return _prints(s, colors);
      case 3:
        return _colour(s, colors);
      case 4:
        return _statement(s.performance, s.performanceNote, colors);
      case 5:
        return _statement(s.sound, s.soundNote, colors);
      default:
        return _statement(s.about, s.aboutNote, colors);
    }
  }

  Widget _colour(KalloStrings s, KalloColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          s.colour,
          style: KalloType.title.copyWith(fontSize: 26, color: colors.ink),
        ),
        const SizedBox(height: KalloSpace.step2),
        SizedBox(
          width: 460,
          child: Text(
            s.colourNote,
            style: KalloType.body.copyWith(color: colors.inkMuted),
          ),
        ),
        const SizedBox(height: KalloSpace.step5),
        _Label(s.path, colors),
        const SizedBox(height: KalloSpace.step2),
        KalloSegments(
          options: <String>[s.scalarPath, s.spectralPath],
          selected: widget.spectral ? 1 : 0,
          onSelect: (int i) => widget.onSpectral(i == 1),
        ),
        const SizedBox(height: KalloSpace.step3),
        SizedBox(
          width: 460,
          child: Text(
            s.spectralNote,
            style: KalloType.small.copyWith(color: colors.inkMuted),
          ),
        ),
      ],
    );
  }

  Widget _statement(String title, String body, KalloColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: KalloType.title.copyWith(fontSize: 26, color: colors.ink)),
        const SizedBox(height: KalloSpace.step3),
        SizedBox(
          width: 460,
          child: Text(
            body,
            style: KalloType.body.copyWith(color: colors.inkMuted),
          ),
        ),
      ],
    );
  }

  Widget _appearance(KalloStrings s, KalloColors colors) {
    final KalloScope scope = KalloScope.of(context);
    final String system =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark
            ? s.dark
            : s.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          s.appearance,
          style: KalloType.title.copyWith(fontSize: 26, color: colors.ink),
        ),
        const SizedBox(height: KalloSpace.step2),
        SizedBox(
          width: 460,
          child: Text(
            s.appearanceNote,
            style: KalloType.body.copyWith(color: colors.inkMuted),
          ),
        ),
        const SizedBox(height: KalloSpace.step5),
        _Label(s.appearanceLabel, colors),
        const SizedBox(height: KalloSpace.step2),
        KalloSegments(
          options: <String>[s.system, s.light, s.dark],
          selected: switch (scope.pinned) {
            null => 0,
            Brightness.light => 1,
            Brightness.dark => 2,
          },
          onSelect: (int i) => scope.onPin(switch (i) {
            1 => Brightness.light,
            2 => Brightness.dark,
            _ => null,
          }),
        ),
        const SizedBox(height: KalloSpace.step2 + 2),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            s.systemLine(system),
            style: KalloType.data.copyWith(fontSize: 10, color: colors.inkFaint),
          ),
        ),
      ],
    );
  }

  Widget _prints(KalloStrings s, KalloColors colors) {
    final ExportSetting export = widget.export;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          s.prints,
          style: KalloType.title.copyWith(fontSize: 26, color: colors.ink),
        ),
        const SizedBox(height: KalloSpace.step2),
        SizedBox(
          width: 460,
          child: Text(
            s.printsNote,
            style: KalloType.body.copyWith(color: colors.inkMuted),
          ),
        ),
        const SizedBox(height: KalloSpace.step5),
        _Label(s.folder, colors),
        const SizedBox(height: KalloSpace.step2),
        Container(
          constraints: const BoxConstraints(maxWidth: 460),
          height: 34,
          padding: const EdgeInsets.only(left: KalloSpace.step3, right: 3),
          decoration: BoxDecoration(
            color: colors.ground,
            borderRadius: BorderRadius.circular(KalloRadius.control),
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  export.label.isEmpty ? s.noFolder : export.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KalloType.data.copyWith(
                    color: export.label.isEmpty
                        ? colors.inkFaint
                        : colors.ink,
                  ),
                ),
              ),
              if (export.canChoose)
                KalloButton(label: s.choose, onTap: export.onChoose),
            ],
          ),
        ),
        if (export.custom && export.onReset != null) ...<Widget>[
          const SizedBox(height: KalloSpace.step2),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 460,
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: export.onReset,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    s.useDefault,
                    style: KalloType.small.copyWith(color: colors.inkMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (!export.canChoose) ...<Widget>[
          const SizedBox(height: KalloSpace.step4),
          SizedBox(
            width: 460,
            child: Text(
              s.fixedFolder,
              style: KalloType.small.copyWith(color: colors.inkFaint),
            ),
          ),
        ],
      ],
    );
  }

  Widget _language(KalloStrings s, KalloColors colors) {
    final String device = WidgetsBinding.instance.platformDispatcher.locale
        .toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          s.language,
          style: KalloType.title.copyWith(fontSize: 26, color: colors.ink),
        ),
        const SizedBox(height: KalloSpace.step2),
        Text(s.followsDevice, style: KalloType.body.copyWith(color: colors.inkMuted)),
        const SizedBox(height: KalloSpace.step4),
        _Label(s.interfaceLanguage, colors),
        const SizedBox(height: KalloSpace.step2),
        KalloSegments(
          options: <String>[s.system, '中文', 'English'],
          selected: widget.locale == null
              ? 0
              : (widget.locale!.languageCode == 'zh' ? 1 : 2),
          onSelect: (int i) => widget.onLocale(switch (i) {
            1 => const Locale('zh'),
            2 => const Locale('en'),
            _ => null,
          }),
        ),
        const SizedBox(height: KalloSpace.step2 + 2),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            s.deviceLine(device),
            style: KalloType.data.copyWith(fontSize: 10, color: colors.inkFaint),
          ),
        ),
        const SizedBox(height: KalloSpace.step4 - 8),
        Container(height: 1, color: colors.hairline),
        const SizedBox(height: KalloSpace.step3 + 4),
        _Label(s.technicalTerms, colors),
        const SizedBox(height: KalloSpace.step2 + 2),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                s.keepEnglish,
                style: KalloType.body.copyWith(color: colors.ink),
              ),
            ),
            _Toggle(
              on: widget.technicalTerms,
              onChanged: widget.onTechnicalTerms,
              colors: colors,
            ),
          ],
        ),
        const SizedBox(height: KalloSpace.step2),
        Row(
          children: <Widget>[
            Text('显影', style: KalloType.body.copyWith(color: colors.inkMuted)),
            const SizedBox(width: KalloSpace.step2),
            Text(
              widget.technicalTerms ? 'DEVELOP   ·   EI 200   ·   C-41' : 'EI 200   ·   C-41',
              style: KalloType.data.copyWith(
                fontSize: 11,
                color: colors.inkFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: KalloSpace.step4 - 8),
        Container(height: 1, color: colors.hairline),
        const SizedBox(height: KalloSpace.step3 + 4),
        _Label(s.numbers, colors),
        const SizedBox(height: KalloSpace.step2 + 2),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                s.decimalPoint,
                style: KalloType.body.copyWith(color: colors.ink),
              ),
            ),
            Text(
              '1.24   ·   −0.05',
              style: KalloType.data.copyWith(color: colors.inkMuted),
            ),
          ],
        ),
        const SizedBox(height: KalloSpace.step4 - 8),
        Container(height: 1, color: colors.hairline),
        const SizedBox(height: KalloSpace.step3 + 4),
        SizedBox(
          width: 460,
          child: Text(
            s.neverRounded,
            style: KalloType.body.copyWith(color: colors.inkMuted),
          ),
        ),
        const SizedBox(height: KalloSpace.step4),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.colors);

  final String text;
  final KalloColors colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: KalloType.caption.copyWith(color: colors.inkFaint),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.on,
    required this.onChanged,
    required this.colors,
  });

  final bool on;
  final ValueChanged<bool> onChanged;
  final KalloColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!on),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: KalloMotion.quick,
        curve: KalloMotion.enter,
        width: 34,
        height: 18,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: on ? colors.accent : colors.hairline,
          borderRadius: BorderRadius.circular(9),
        ),
        child: AnimatedAlign(
          duration: KalloMotion.quick,
          curve: KalloMotion.enter,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
      ),
    );
  }
}
