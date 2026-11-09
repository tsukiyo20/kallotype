import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';
import '../film/film.dart';
import '../widgets/primitives.dart';

/// The screen this design language is judged by.
///
/// It is not a mock of a real screen; it is the smallest thing that can hold
/// every decision: two environments, the type scale, the material palette, the
/// primitives, and a strip of film whose five frames differ only in how long
/// they were developed.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  static const List<double> _minutes = <double>[3, 6, 9, 12, 15];
  static const List<String> _numbers = <String>['12', '12A', '13', '13A', '14'];

  static final List<FilmFrame> _frames = <FilmFrame>[
    for (int i = 0; i < _minutes.length; i++)
      FilmFrame(
        gamma: gammaAt(_minutes[i]),
        number: _numbers[i],
        minutes: _minutes[i],
      ),
  ];

  KalloEnvironment _environment = KalloEnvironment.lightTable;
  int _selected = 2;

  @override
  Widget build(BuildContext context) {
    final double target =
        _environment == KalloEnvironment.lightTable ? 1.0 : 0.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: KalloMotion.slow,
      curve: KalloMotion.settleCurve,
      builder: (BuildContext context, double t, Widget? child) {
        final KalloColors colors = KalloColors.lerp(
          KalloColors.darkroom,
          KalloColors.lightTable,
          t,
        );
        return KalloScope(
          colors: colors,
          environment: _environment,
          child: ColoredBox(
            color: colors.ground,
            child: _GalleryBody(
              frames: _frames,
              selected: _selected,
              onSelect: (int index) => setState(() => _selected = index),
              environment: _environment,
              onEnvironment: (KalloEnvironment next) =>
                  setState(() => _environment = next),
            ),
          ),
        );
      },
    );
  }
}

class _GalleryBody extends StatelessWidget {
  const _GalleryBody({
    required this.frames,
    required this.selected,
    required this.onSelect,
    required this.environment,
    required this.onEnvironment,
  });

  final List<FilmFrame> frames;
  final int selected;
  final ValueChanged<int> onSelect;
  final KalloEnvironment environment;
  final ValueChanged<KalloEnvironment> onEnvironment;

  @override
  Widget build(BuildContext context) {
    final FilmFrame frame = frames[selected];
    const EdgeInsets padding = EdgeInsets.fromLTRB(
      KalloSpace.step5,
      KalloSpace.step4,
      KalloSpace.step5,
      KalloSpace.step5,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // A short page in a tall window should sit in the middle of it, not
        // pile up against the top and leave the floor empty.
        final double floor =
            math.max(0, constraints.maxHeight - padding.vertical);

        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: floor),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Header(
                      environment: environment,
                      onEnvironment: onEnvironment,
                    ),
                    const SizedBox(height: KalloSpace.step5),
                    _Section(
                      label: 'THE STRIP',
                      child: _StripBlock(
                        frames: frames,
                        selected: selected,
                        onSelect: onSelect,
                      ),
                    ),
                    const SizedBox(height: KalloSpace.step4),
                    _Readout(frame: frame),
                    const SizedBox(height: KalloSpace.step5),
                    const _Section(label: 'TYPE', child: _Specimen()),
                    const SizedBox(height: KalloSpace.step5),
                    const _Section(label: 'MATERIAL', child: _Swatches()),
                    const SizedBox(height: KalloSpace.step5),
                    _Section(label: 'PRIMITIVES', child: _Primitives()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.environment, required this.onEnvironment});

  final KalloEnvironment environment;
  final ValueChanged<KalloEnvironment> onEnvironment;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            KalloText(
              'KALLOTYPE',
              style: KalloType.caption,
              color: colors.accent,
            ),
            const SizedBox(height: KalloSpace.step2),
            KalloText('观片台', style: KalloType.display),
            const SizedBox(height: KalloSpace.step1),
            KalloText(
              'one frame, developed five ways',
              style: KalloType.data,
              color: colors.inkMuted,
            ),
          ],
        ),
        const Spacer(),
        _EnvironmentSwitch(
          environment: environment,
          onEnvironment: onEnvironment,
        ),
      ],
    );
  }
}

class _EnvironmentSwitch extends StatelessWidget {
  const _EnvironmentSwitch({
    required this.environment,
    required this.onEnvironment,
  });

  final KalloEnvironment environment;
  final ValueChanged<KalloEnvironment> onEnvironment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SwitchItem(
          label: 'DARKROOM',
          active: environment == KalloEnvironment.darkroom,
          onTap: () => onEnvironment(KalloEnvironment.darkroom),
        ),
        const SizedBox(width: KalloSpace.step3),
        _SwitchItem(
          label: 'LIGHT TABLE',
          active: environment == KalloEnvironment.lightTable,
          onTap: () => onEnvironment(KalloEnvironment.lightTable),
        ),
      ],
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedDefaultTextStyle(
          duration: KalloMotion.quick,
          curve: KalloMotion.settleCurve,
          style: KalloType.caption.copyWith(
            color: active ? colors.accent : colors.inkFaint,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: KalloSpace.step1),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The strip, and what it is telling us
// ---------------------------------------------------------------------------

class _StripBlock extends StatelessWidget {
  const _StripBlock({
    required this.frames,
    required this.selected,
    required this.onSelect,
  });

  final List<FilmFrame> frames;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The strip is as wide as the room it is in, up to 168 points tall.
        // Five frames across 38 mm of pitch is 188 mm of film, so the height
        // follows from the width rather than the other way round.
        final double span = frames.length * kPitchMm - kGapMm;
        final double fitted =
            constraints.maxWidth / (span <= 0 ? 1 : span) * kFilmWidthMm;
        final double height =
            math.max(48.0, math.min(168.0, fitted)).toDouble();
        final FilmMetrics m = FilmMetrics.forHeight(height, frames.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The film is the artifact; the UI does the labelling.
            Row(
              children: <Widget>[
                for (int i = 0; i < frames.length; i++) ...<Widget>[
                  SizedBox(
                    width: m.frameWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        KalloText(
                          frames[i].number,
                          style: KalloType.data,
                          color: i == selected ? colors.ink : colors.inkFaint,
                        ),
                        const SizedBox(height: KalloSpace.step0),
                        KalloText(
                          formatMinutes(frames[i].minutes),
                          style: KalloType.data,
                          color:
                              i == selected ? colors.accent : colors.inkMuted,
                        ),
                      ],
                    ),
                  ),
                  if (i < frames.length - 1) SizedBox(width: m.gap),
                ],
              ],
            ),
            const SizedBox(height: KalloSpace.step2),
            FilmStrip(
              frames: frames,
              height: height,
              selected: selected,
              onSelect: onSelect,
            ),
          ],
        );
      },
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.frame});

  final FilmFrame frame;

  @override
  Widget build(BuildContext context) {
    final double dMax = negativeDensity(0.55, frame.gamma);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Cell(
            label: 'DEVELOPED',
            value: formatMinutes(frame.minutes),
            note: '20 °C · C-41',
          ),
          const SizedBox(width: KalloSpace.step3),
          _Cell(
            label: 'CONTRAST',
            value: frame.gamma.toStringAsFixed(2),
            note: 'γ at 18 % grey',
          ),
          const SizedBox(width: KalloSpace.step3),
          _Cell(
            label: 'D MAX',
            value: dMax.toStringAsFixed(2),
            note: 'status density',
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.note});

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return Expanded(
      child: Surface(
        padding: const EdgeInsets.all(KalloSpace.step3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            KalloText(label, style: KalloType.caption, color: colors.inkFaint),
            const SizedBox(height: KalloSpace.step2),
            KalloText(value, style: KalloType.display),
            const SizedBox(height: KalloSpace.step1),
            KalloText(note, style: KalloType.data, color: colors.inkMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The rest of the language
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Hairline(),
        const SizedBox(height: KalloSpace.step3),
        KalloText(label, style: KalloType.caption, color: colors.inkFaint),
        const SizedBox(height: KalloSpace.step3),
        child,
      ],
    );
  }
}

class _Specimen extends StatelessWidget {
  const _Specimen();

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        KalloText('9:00', style: KalloType.display),
        const SizedBox(height: KalloSpace.step1),
        KalloText(
          'Developed nine minutes at twenty degrees',
          style: KalloType.title,
        ),
        const SizedBox(height: KalloSpace.step2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: KalloText(
            'A negative is not a look. It is a measurement of how much light '
            'reached each grain, and of how long the grains were allowed to '
            'grow. Time is a dimension of the image, not a preset.',
            style: KalloType.body,
            color: colors.inkMuted,
          ),
        ),
        const SizedBox(height: KalloSpace.step3),
        KalloText(
          'MEASURED · VISION3 500T',
          style: KalloType.caption,
          color: colors.inkFaint,
        ),
        const SizedBox(height: KalloSpace.step2),
        const KalloText(
          'γ 1.342   Dmax 2.71   EV +0.30   C-41 20.0 °C',
          style: KalloType.data,
        ),
      ],
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches();

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return Wrap(
      spacing: KalloSpace.step2,
      runSpacing: KalloSpace.step3,
      children: <Widget>[
        _Swatch(label: 'ground', color: colors.ground),
        _Swatch(label: 'surface', color: colors.surface),
        _Swatch(label: 'raised', color: colors.surfaceRaised),
        _Swatch(label: 'ink', color: colors.ink),
        _Swatch(label: 'ink muted', color: colors.inkMuted),
        _Swatch(label: 'ink faint', color: colors.inkFaint),
        _Swatch(label: 'accent', color: colors.accent),
        _Swatch(label: 'film base', color: colors.filmBase),
        _Swatch(label: 'film clear', color: colors.filmClear),
        _Swatch(label: 'film dense', color: colors.filmDense),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return SizedBox(
      width: 84,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(KalloRadius.film),
              border: Border.all(color: colors.hairline, width: 1),
            ),
          ),
          const SizedBox(height: KalloSpace.step2),
          KalloText(label, style: KalloType.caption, color: colors.inkFaint),
        ],
      ),
    );
  }
}

class _Primitives extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Pressable(
          onPressed: () {},
          child: KalloText(
            'DEVELOP',
            style: KalloType.caption,
            color: colors.ink,
          ),
        ),
        const SizedBox(width: KalloSpace.step2),
        Pressable(
          child: KalloText(
            'UNAVAILABLE',
            style: KalloType.caption,
            color: colors.inkFaint,
          ),
        ),
        const Spacer(),
        KalloText(
          'pressable · hairline · surface',
          style: KalloType.data,
          color: colors.inkFaint,
        ),
      ],
    );
  }
}
