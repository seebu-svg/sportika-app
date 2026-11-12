import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/widgets/avatar_presets.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Editorial display type for the pre-auth flow: condensed, tight leading and
/// heavy weights, with italics reserved for the emotional half of a headline.
TextStyle authDisplay(
  double size, {
  Color color = Colors.white,
  bool italic = false,
  double height = .92,
  double letterSpacing = -1,
}) => TextStyle(
  fontFamily: 'Barlow Condensed',
  fontSize: size,
  height: height,
  fontWeight: FontWeight.w900,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  letterSpacing: letterSpacing,
  color: color,
);

/// Full-bleed sports photograph with a graceful editorial fallback. Reuses the
/// same credited photography as the rest of the app.
class AuthPhoto extends StatelessWidget {
  const AuthPhoto({
    super.key,
    this.sport = Sport.cricket,
    this.alignment = const Alignment(0, -.35),
  });

  final Sport sport;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      SportPhotography.forSport(sport),
      fit: BoxFit.cover,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      semanticLabel: '${sport.label} sports photography',
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _fallback(),
      errorBuilder: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(-.5, -.4),
        radius: 1.25,
        colors: [
          sportColor(sport).withValues(alpha: .34),
          SportikaColors.deepest,
        ],
      ),
    ),
    child: Center(
      child: Icon(
        sportGlyph(sport),
        size: 148,
        color: Colors.white.withValues(alpha: .055),
      ),
    ),
  );
}

/// Shared shell: full-bleed photograph fading into the app background, a brand
/// bar, scrolling editorial content, and a pinned action area so primary CTAs
/// never move between screens.
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.children,
    this.footer,
    this.sport = Sport.cricket,
    this.photoAlignment = const Alignment(0, -.35),
    this.showBack = false,
    this.onBack,
    this.stepLabel,
    this.brandSuffix,
    this.scroll = true,
    this.padding = const EdgeInsets.fromLTRB(24, 10, 24, 8),
  });

  final List<Widget> children;
  final Widget? footer;
  final Sport sport;
  final Alignment photoAlignment;
  final bool showBack;
  final VoidCallback? onBack;
  final String? stepLabel;
  final Widget? brandSuffix;
  final bool scroll;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );

    return Scaffold(
      backgroundColor: SportikaColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: AuthPhoto(sport: sport, alignment: photoAlignment),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x40061426),
                      Color(0xCC061426),
                      SportikaColors.background,
                      SportikaColors.background,
                    ],
                    stops: [0, .3, .58, .82],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 20, 0),
                  child: Row(
                    children: [
                      if (showBack)
                        _RoundIcon(
                          icon: Icons.arrow_back,
                          onTap: onBack,
                          tooltip: 'Back',
                        )
                      else
                        const BrandMark(size: 26),
                      const SizedBox(width: 10),
                      const Text(
                        'SPORTIKA',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.6,
                          color: SportikaColors.text,
                        ),
                      ),
                      const Spacer(),
                      ?brandSuffix,
                      if (stepLabel != null)
                        Text(
                          stepLabel!.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.7,
                            color: SportikaColors.textDim,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: scroll
                      ? SingleChildScrollView(
                          padding: EdgeInsets.zero,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          child: content,
                        )
                      : content,
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
                    child: footer,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: SportikaColors.deepest.withValues(alpha: .72),
        shape: const CircleBorder(side: BorderSide(color: Color(0x33FFFFFF))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            width: 38,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Small letterspaced kicker with a leading rule.
class AuthEyebrow extends StatelessWidget {
  const AuthEyebrow(
    this.text, {
    super.key,
    this.tone = SportikaColors.mint,
    this.rule = true,
  });

  final String text;
  final Color tone;
  final bool rule;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rule) ...[
          Container(width: 16, height: 1.5, color: tone),
          const SizedBox(width: 9),
        ],
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.3,
            color: tone,
          ),
        ),
      ],
    );
  }
}

/// Editorial headline. [accent] renders on its own italic line in the accent
/// tone so every screen reads with the same sporting voice.
class AuthHeadline extends StatelessWidget {
  const AuthHeadline(
    this.primary, {
    super.key,
    this.accent,
    this.size = 46,
    this.accentTone = SportikaColors.mint,
    this.color = Colors.white,
  });

  final String primary;
  final String? accent;
  final double size;
  final Color accentTone;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(primary, style: authDisplay(size, color: color)),
        if (accent != null)
          Text(
            accent!,
            style: authDisplay(size, color: accentTone, italic: true),
          ),
      ],
    );
  }
}

class AuthLead extends StatelessWidget {
  const AuthLead(this.text, {super.key, this.maxWidth = 360});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1.55,
          color: SportikaColors.textMuted,
        ),
      ),
    );
  }
}

/// Numbered progress rail used by both halves of the flow.
class AuthStepRail extends StatelessWidget {
  const AuthStepRail({
    super.key,
    required this.current,
    required this.labels,
    this.tone = SportikaColors.mint,
  });

  final int current;
  final List<String> labels;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: i <= current ? tone : SportikaColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '0${i + 1}',
                    style: TextStyle(
                      fontFamily: 'Barlow Condensed',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: i <= current ? tone : SportikaColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    labels[i].toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: i <= current
                          ? SportikaColors.textBody
                          : SportikaColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Underline form field: no boxes, one rule that warms to mint on focus.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.obscure = false,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.maxLength,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.labelAction,
    this.initialValue,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final TextInputType? keyboardType;
  final bool obscure;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final int? maxLength;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final Widget? labelAction;
  final String? initialValue;
  final bool enabled;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  TextEditingController? _internal;
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _revealed = false;

  TextEditingController get _controller =>
      widget.controller ??
      (_internal ??= TextEditingController(text: widget.initialValue));

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focused != _focus.hasFocus) {
        setState(() => _focused = _focus.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final ruleColor = hasError
        ? SportikaColors.danger
        : _focused
        ? SportikaColors.mint
        : SportikaColors.borderStrong;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: hasError
                      ? SportikaColors.danger
                      : SportikaColors.textDim,
                ),
              ),
            ),
            if (widget.labelAction != null) widget.labelAction!,
          ],
        ),
        const SizedBox(height: 2),
        TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: widget.enabled,
          obscureText: widget.obscure && !_revealed,
          obscuringCharacter: '•',
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          autofillHints: widget.autofillHints,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          cursorColor: SportikaColors.mint,
          cursorWidth: 1.5,
          style: const TextStyle(
            fontSize: 15.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: SportikaColors.text,
          ),
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
            hintText: widget.hint,
            hintStyle: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              color: SportikaColors.textDim,
            ),
            suffixIcon: widget.obscure
                ? IconButton(
                    splashRadius: 18,
                    tooltip: _revealed ? 'Hide password' : 'Show password',
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: SportikaColors.textDim,
                    ),
                    onPressed: () => setState(() => _revealed = !_revealed),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: hasError || _focused ? 1.6 : 1,
          color: ruleColor,
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 12,
                  color: SportikaColors.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.errorText!,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: SportikaColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Primary CTA: blue for action, 54pt tall, arrow on the trailing edge.
class AuthAction extends StatelessWidget {
  const AuthAction({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.icon = Icons.arrow_forward,
    this.tone = SportikaColors.blue,
    this.ghost = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final Color tone;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final foreground = ghost ? Colors.white : Colors.white;
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: Material(
        color: ghost
            ? Colors.white.withValues(alpha: .04)
            : enabled
            ? tone
            : tone.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: ghost
                  ? Border.all(color: SportikaColors.borderStrong)
                  : null,
              gradient: ghost || !enabled
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tone, Color.lerp(tone, Colors.white, .14)!],
                    ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: foreground.withValues(alpha: enabled ? 1 : .7),
                    ),
                  ),
                ),
                if (busy)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else if (icon != null)
                  Icon(
                    icon,
                    size: 19,
                    color: foreground.withValues(alpha: enabled ? 1 : .7),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthLink extends StatelessWidget {
  const AuthLink(
    this.label, {
    super.key,
    this.onTap,
    this.tone = SportikaColors.mint,
    this.align = TextAlign.left,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final Color tone;
  final TextAlign align;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: tone,
        padding: const EdgeInsets.symmetric(vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: align == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .2,
            ),
          ),
          if (icon != null) ...[const SizedBox(width: 4), Icon(icon, size: 14)],
        ],
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, this.label = 'OR'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: SportikaColors.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
              color: SportikaColors.textDim,
            ),
          ),
        ),
        const Expanded(child: Divider(color: SportikaColors.borderSubtle)),
      ],
    );
  }
}

class AuthCheckbox extends StatelessWidget {
  const AuthCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tone = SportikaColors.mint,
    this.error = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color tone;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 22,
        width: 22,
        decoration: BoxDecoration(
          color: value ? tone : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: value
                ? tone
                : error
                ? SportikaColors.danger
                : SportikaColors.borderStrong,
            width: 1.4,
          ),
        ),
        child: value
            ? Icon(Icons.check, size: 15, color: SportikaColors.deepest)
            : null,
      ),
    );
  }
}

/// Selectable card used for account types, sports and levels.
class AuthSelectCard extends StatelessWidget {
  const AuthSelectCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.tone = SportikaColors.mint,
    this.padding = const EdgeInsets.all(14),
    this.semanticLabel,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final Color tone;
  final EdgeInsets padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected
            ? tone.withValues(alpha: .10)
            : SportikaColors.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? tone : SportikaColors.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Small selection pill for play style and level.
class AuthChoicePill extends StatelessWidget {
  const AuthChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone = SportikaColors.mint,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? tone.withValues(alpha: .16)
          : SportikaColors.surfaceSunken,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 11 : 14,
            vertical: dense ? 6 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: .7)
                  : SportikaColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
              color: selected ? tone : SportikaColors.textBody,
            ),
          ),
        ),
      ),
    );
  }
}

/// Six-box OTP entry with auto-advance and paste support.
class AuthOtpInput extends StatefulWidget {
  const AuthOtpInput({
    super.key,
    required this.onChanged,
    required this.onCompleted,
    this.error = false,
    this.value = '',
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  final bool error;
  final String value;

  @override
  State<AuthOtpInput> createState() => _AuthOtpInputState();
}

class _AuthOtpInputState extends State<AuthOtpInput> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    for (final node in _nodes) {
      node.addListener(_handleFocus);
    }
  }

  void _handleFocus() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AuthOtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value.isEmpty && oldWidget.value.isNotEmpty) {
      for (final c in _controllers) {
        c.clear();
      }
      _nodes.first.requestFocus();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _handle(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      _controllers[index].text = '';
      widget.onChanged(_value());
      return;
    }
    if (digits.length > 1) {
      for (var i = 0; i < 6; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final last = math.min(digits.length, 6) - 1;
      _nodes[last].requestFocus();
      if (digits.length >= 6) FocusScope.of(context).unfocus();
    } else {
      _controllers[index].text = digits;
      if (index < 5) _nodes[index + 1].requestFocus();
    }
    final value = _value();
    widget.onChanged(value);
    if (value.length == 6) {
      FocusScope.of(context).unfocus();
      widget.onCompleted(value);
    }
  }

  String _value() => _controllers.map((c) => c.text).join();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 6; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final focused = _nodes[i].hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 58,
                  decoration: BoxDecoration(
                    color: SportikaColors.surfaceSunken.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.error
                          ? SportikaColors.danger
                          : focused
                          ? SportikaColors.mint
                          : SportikaColors.border,
                      width: focused || widget.error ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _nodes[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    cursorColor: SportikaColors.mint,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) => _handle(i, value),
                    style: authDisplay(
                      24,
                      color: SportikaColors.text,
                      height: 1,
                      letterSpacing: 1,
                    ),
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Circular avatar preview; initials instead of a photo upload.
class AuthAvatar extends StatelessWidget {
  const AuthAvatar({
    super.key,
    required this.initials,
    this.avatarId = 'midnight',
    this.size = 88,
    this.showRing = true,
  });

  final String initials;
  final String avatarId;
  final double size;
  final bool showRing;

  @override
  Widget build(BuildContext context) {
    final option = avatarOptionFor(avatarId);
    return Container(
      height: size,
      width: size,
      padding: EdgeInsets.all(showRing ? 3 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: option.colors.first.withValues(alpha: .55),
          width: 1.2,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: option.colors,
          ),
        ),
        child: Center(
          child: Text(
            initials.toUpperCase(),
            style: authDisplay(
              size * .36,
              color: option.ink,
              height: 1,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline notice for neutral, positive or error copy.
class AuthNotice extends StatelessWidget {
  const AuthNotice(
    this.text, {
    super.key,
    this.tone = SportikaColors.mint,
    this.icon = Icons.check_circle_outline,
  });

  final String text;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: .32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: SportikaColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label/value line for the setup summary card.
class AuthSummaryRow extends StatelessWidget {
  const AuthSummaryRow(this.label, this.value, {super.key, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: SportikaColors.textDim,
                height: 1.6,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: tone ?? SportikaColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin editorial rule with an optional inline label.
class AuthRule extends StatelessWidget {
  const AuthRule({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return const Divider(color: SportikaColors.borderSubtle, height: 1);
    }
    return Row(
      children: [
        const Expanded(child: Divider(color: SportikaColors.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label!.toUpperCase(),
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: SportikaColors.textDim,
            ),
          ),
        ),
        const Expanded(child: Divider(color: SportikaColors.borderSubtle)),
      ],
    );
  }
}

/// Footer microcopy clarifying prototype behaviour.
class AuthMicro extends StatelessWidget {
  const AuthMicro(this.text, {super.key, this.icon = Icons.lock_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 12, color: SportikaColors.textDim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: SportikaColors.textDim,
            ),
          ),
        ),
      ],
    );
  }
}
