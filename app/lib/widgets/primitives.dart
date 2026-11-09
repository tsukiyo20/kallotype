import 'package:flutter/widgets.dart';

import '../design/scope.dart';
import '../design/tokens.dart';

/// Text, with the colour of where it is.
///
/// Every string in the app goes through here so that there is one place where a
/// text style can pick up an ink.
class KalloText extends StatelessWidget {
  const KalloText(
    this.data, {
    super.key,
    this.style,
    this.color,
    this.maxLines,
    this.textAlign,
  });

  final String data;
  final TextStyle? style;
  final Color? color;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;
    return Text(
      data,
      style: (style ?? KalloType.body).copyWith(color: color ?? colors.ink),
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// The only background in the product.
///
/// A thing is raised by being a little lighter than what is behind it, and by a
/// hairline — never by a shadow. `BoxShadow` appears in this app exactly once,
/// where it means light coming out of a light table.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    this.child,
    this.color,
    this.borderColor,
    this.radius = KalloRadius.sheet,
    this.padding,
    this.bordered = true,
  });

  final Widget? child;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: bordered
            ? Border.all(color: borderColor ?? colors.hairline, width: 1)
            : null,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
}

/// A one-device-pixel rule.
///
/// A logical pixel is not a hairline on a Retina screen: it is two of them, and
/// a one-logical-pixel border reads as a seam rather than as an edge.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.color, this.vertical = false});

  final Color? color;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;
    final double? ratio = MediaQuery.maybeOf(context)?.devicePixelRatio;
    final double thickness = 1 / (ratio ?? 1);

    return SizedBox(
      width: vertical ? thickness : double.infinity,
      height: vertical ? double.infinity : thickness,
      child: ColoredBox(color: color ?? colors.hairline),
    );
  }
}

/// A thing that can be pressed.
///
/// It has no ripple. A ripple is a simulation of a material that this product
/// is not made of; a press here is a change of density, which is what a press
/// means everywhere else in this app.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onPressed,
    this.radius = KalloRadius.sheet,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final KalloColors colors = KalloScope.of(context).colors;
    final bool enabled = widget.onPressed != null;

    Color background = colors.surface;
    if (enabled && _pressed) {
      background = Color.alphaBlend(
        colors.ink.withValues(alpha: 0.10),
        colors.surface,
      );
    } else if (enabled && _hovered) {
      background = Color.alphaBlend(
        colors.ink.withValues(alpha: 0.05),
        colors.surface,
      );
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: KalloMotion.instant,
          curve: KalloMotion.settleCurve,
          padding: widget.padding ??
              const EdgeInsets.symmetric(
                horizontal: KalloSpace.step3,
                vertical: KalloSpace.step2,
              ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: colors.hairline, width: 1),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
