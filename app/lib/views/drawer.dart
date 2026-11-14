import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../design/scope.dart';
import '../design/strings.dart';
import '../design/tokens.dart';
import '../lab/exports.dart';
import '../widgets/button.dart';
import '../widgets/segments.dart';

/// Settings, as a drawer in the bench.
///
/// A place you open, not a page you go to. One sheet, five pages: the first
/// says what the app is, the other four set something. The film's own words do
/// not change when the language does. Nothing here advertises a renderer the
/// app cannot switch or a sound it does not make.
class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({
    super.key,
    required this.locale,
    required this.onLocale,
    required this.spectral,
    required this.onSpectral,
    required this.export,
    required this.onClose,
  });

  /// What the user pinned, or null to follow the device.
  final Locale? locale;
  final ValueChanged<Locale?> onLocale;

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
  static const int _aboutTab = 0;

  List<String> _tabs(KalloStrings s) => <String>[
    s.tabAbout,
    s.tabLanguage,
    s.tabAppearance,
    s.tabPrints,
    s.tabColour,
  ];

  int _tab = _aboutTab;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.colorsOf(context);
    final KalloStrings s = KalloStrings.of(context);
    return Container(
      decoration: BoxDecoration(color: colors.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 52,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KalloSpace.step4,
                ),
                child: GestureDetector(
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
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(width: 196, child: _rail(colors)),
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
          if (_tab != _aboutTab)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KalloSpace.step4,
                vertical: KalloSpace.step2 + 2,
              ),
              child: Text(
                s.applyAtOnce,
                style: KalloType.data.copyWith(
                  fontSize: 10,
                  color: colors.inkFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rail(KalloColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KalloSpace.step3,
        KalloSpace.step2,
        KalloSpace.step3,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < _tabs(KalloStrings.of(context)).length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: KalloMotion.quick,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KalloSpace.step3 + 4,
                    vertical: KalloSpace.step2 + 3,
                  ),
                  decoration: BoxDecoration(
                    color: i == _tab ? colors.accentSoft : null,
                    borderRadius: BorderRadius.circular(KalloRadius.control),
                  ),
                  child: Text(
                    _tabs(KalloStrings.of(context))[i],
                    style: KalloType.caption.copyWith(
                      color: i == _tab ? colors.accent : colors.inkFaint,
                      letterSpacing: 1.2,
                    ),
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
        return _about(s, colors);
      case 1:
        return _language(s, colors);
      case 2:
        return _appearance(s, colors);
      case 3:
        return _prints(s, colors);
      default:
        return _colour(s, colors);
    }
  }

  void _openRepository() {
    unawaited(_launchRepository());
  }

  Future<void> _launchRepository() async {
    final Uri uri = Uri.parse(KalloInfo.repository);
    try {
      final bool opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        debugPrint('could not open $uri');
      }
    } on Object catch (error) {
      debugPrint('could not open $uri: $error');
    }
  }

  Widget _about(KalloStrings s, KalloColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/kallo-icon.png',
                width: 80,
                height: 80,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: KalloSpace.step5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  KalloInfo.name,
                  style: KalloType.title.copyWith(
                    fontSize: 24,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: KalloSpace.step1 + 2),
                Text(
                  s.appVersion(KalloInfo.version),
                  style: KalloType.data.copyWith(color: colors.inkFaint),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: KalloSpace.step6),
        _RepositoryLink(
          onTap: _openRepository,
          label: s.openRepository,
          colors: colors,
        ),
      ],
    );
  }

  Widget _colour(KalloStrings s, KalloColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          s.colour,
          style: KalloType.title.copyWith(fontSize: 22, color: colors.ink),
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
          style: KalloType.title.copyWith(fontSize: 22, color: colors.ink),
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
            style: KalloType.data.copyWith(
              fontSize: 10,
              color: colors.inkFaint,
            ),
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
          style: KalloType.title.copyWith(fontSize: 22, color: colors.ink),
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
            color: colors.fill,
            borderRadius: BorderRadius.circular(KalloRadius.control),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  export.label.isEmpty ? s.noFolder : export.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KalloType.data.copyWith(
                    color: export.label.isEmpty ? colors.inkFaint : colors.ink,
                  ),
                ),
              ),
              if (export.canChoose)
                KalloButton(label: s.choose, onTap: export.onChoose),
            ],
          ),
        ),
        if (export.onImport != null) ...<Widget>[
          const SizedBox(height: KalloSpace.step2),
          Align(
            alignment: Alignment.centerRight,
            child: KalloButton(label: s.importImages, onTap: export.onImport),
          ),
        ],
        if (export.missingPrints > 0 ||
            export.repairablePrints > 0) ...<Widget>[
          const SizedBox(height: KalloSpace.step3),
          Text(
            s.catalogIssues(export.missingPrints, export.repairablePrints),
            style: KalloType.small.copyWith(color: colors.inkMuted),
          ),
          if (export.onRepair != null &&
              export.repairablePrints > 0) ...<Widget>[
            const SizedBox(height: KalloSpace.step2),
            Align(
              alignment: Alignment.centerRight,
              child: KalloButton(
                label: s.repairMarkers,
                onTap: export.onRepair,
              ),
            ),
          ],
        ],
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
          style: KalloType.title.copyWith(fontSize: 22, color: colors.ink),
        ),
        const SizedBox(height: KalloSpace.step2),
        Text(
          s.followsDevice,
          style: KalloType.body.copyWith(color: colors.inkMuted),
        ),
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
            style: KalloType.data.copyWith(
              fontSize: 10,
              color: colors.inkFaint,
            ),
          ),
        ),
        const SizedBox(height: KalloSpace.step4),
      ],
    );
  }
}

/// The one link out of the app: GitHub's mark, the repository, and an arrow
/// that says the click leaves the window.
class _RepositoryLink extends StatefulWidget {
  const _RepositoryLink({
    required this.onTap,
    required this.label,
    required this.colors,
  });

  final VoidCallback onTap;
  final String label;
  final KalloColors colors;

  @override
  State<_RepositoryLink> createState() => _RepositoryLinkState();
}

class _RepositoryLinkState extends State<_RepositoryLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = widget.colors;
    final Color ink = _hover ? colors.ink : colors.inkMuted;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: KalloMotion.instant,
            width: 460,
            height: 62,
            padding: const EdgeInsets.symmetric(
              horizontal: KalloSpace.step4,
              vertical: KalloSpace.step2,
            ),
            decoration: BoxDecoration(
              color: _hover ? colors.fillStrong : colors.fill,
              borderRadius: BorderRadius.circular(KalloRadius.card),
            ),
            child: Row(
              children: <Widget>[
                Image.asset(
                  'assets/github-mark.png',
                  width: 20,
                  height: 20,
                  color: ink,
                  colorBlendMode: BlendMode.srcIn,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: KalloSpace.step3),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'GitHub',
                        style: KalloType.body.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'github.com/tsukiyo20/kallotype',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KalloType.data.copyWith(
                          fontSize: 11,
                          color: colors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: KalloSpace.step3),
                CustomPaint(
                  size: const Size(12, 12),
                  painter: _OutboundMark(ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutboundMark extends CustomPainter {
  const _OutboundMark(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(const Offset(2.5, 9.5), const Offset(9.5, 2.5), stroke);
    canvas.drawLine(const Offset(4.5, 2.5), const Offset(9.5, 2.5), stroke);
    canvas.drawLine(const Offset(9.5, 2.5), const Offset(9.5, 7.5), stroke);
  }

  @override
  bool shouldRepaint(_OutboundMark old) => old.colour != colour;
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
