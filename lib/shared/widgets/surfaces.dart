import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';

/// The three surface styles the design system recognises.
///
/// Keeping the vocabulary small is deliberate: every card in the app is either
/// an everyday surface, one that must read above its neighbours, or a signature
/// brand surface. Anything else becomes visual noise.
enum SportikaSurfaceStyle {
  /// Solid navy card for lists, forms and everyday content.
  standard,

  /// Stronger contrast, a hairline border and a soft shadow for important
  /// widgets.
  elevated,

  /// Branded artwork, atmosphere and controlled glow for the athlete passport,
  /// match heroes and featured tournaments.
  signature,
}

/// A themed surface. Screens pick a [style] and a sport [tone]; the decoration,
/// border and elevation are resolved from the active theme.
class SportikaSurface extends StatelessWidget {
  const SportikaSurface({
    super.key,
    required this.child,
    this.style = SportikaSurfaceStyle.standard,
    this.tone,
    this.padding = const EdgeInsets.all(16),
    this.radius = SportikaRadius.lg,
    this.onTap,
    this.margin,
    this.fillColor,
    this.borderColor,
    this.boxShadow,
  });

  final Widget child;
  final SportikaSurfaceStyle style;

  /// Sport identity tint for signature surfaces. Defaults to the brand blue.
  final Color? tone;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsets? margin;

  /// Explicit overrides used by legacy call sites. When set they win over the
  /// style decoration so callers can still paint a one-off fill.
  final Color? fillColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final accent = tone ?? theme.brand;

    Color? fill;
    LinearGradient? gradient;
    Color border = borderColor ?? theme.border;
    List<BoxShadow>? shadow = boxShadow;

    if (fillColor != null) {
      fill = fillColor;
    } else {
      switch (style) {
        case SportikaSurfaceStyle.standard:
          fill = theme.surface;
          shadow = boxShadow;
        case SportikaSurfaceStyle.elevated:
          gradient = theme.elevatedGradient;
          border = borderColor ?? theme.borderStrong;
          shadow = boxShadow ?? theme.cardShadow;
        case SportikaSurfaceStyle.signature:
          gradient = SportikaGradients.signatureSurfaceFor(accent);
          border = borderColor ?? accent.withValues(alpha: .42);
          shadow = boxShadow ?? theme.liftedShadow;
      }
    }

    final borderRadius = BorderRadius.circular(radius);

    Widget body = Padding(padding: padding, child: child);
    if (style == SportikaSurfaceStyle.signature && fillColor == null) {
      // Atmospheric light from the top-right corner, behind the content.
      body = Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: SportikaGradients.heroSpotlight(accent),
                ),
              ),
            ),
          ),
          body,
        ],
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: fill,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(
          color: border,
          width: style == SportikaSurfaceStyle.standard
              ? SportikaBorder.hairline
              : SportikaBorder.rule,
        ),
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: onTap, borderRadius: borderRadius, child: body),
        ),
      ),
    );
  }
}

/// Controlled glassmorphism for floating overlays and panels docked over
/// photography. Blur and tint come from [SportikaGlass] so every frosted
/// surface in the app matches.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = SportikaRadius.xl,
    this.blurSigma = SportikaGlass.blurSigma,
    this.strong = false,
    this.borderColor,
    this.margin,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double blurSigma;

  /// Heavier tint for panels carrying long-form copy.
  final bool strong;
  final Color? borderColor;
  final EdgeInsets? margin;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? theme.glassBorder),
        boxShadow: boxShadow ?? theme.elevatedShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: strong ? theme.glassStrong : theme.glass,
              gradient: SportikaGradients.glassPanel,
              border: const Border(
                top: BorderSide(color: SportikaGlass.highlight),
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Press feedback shared by buttons and tappable cards.
///
/// Uses a [Listener] rather than a gesture recognizer so the child's own
/// [InkWell] keeps ownership of the tap. The scale is small and short: the
/// control acknowledges the press instead of bouncing.
class SportikaPressable extends StatefulWidget {
  const SportikaPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = SportikaMotion.pressScale,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<SportikaPressable> createState() => _SportikaPressableState();
}

class _SportikaPressableState extends State<SportikaPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: SportikaMotion.pressDuration(context),
        curve: SportikaMotion.standard,
        child: widget.child,
      ),
    );
  }
}
