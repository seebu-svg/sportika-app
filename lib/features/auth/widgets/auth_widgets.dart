import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/profile_avatar.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Editorial display type for the pre-auth flow: condensed, tight leading and
/// heavy weights, with italics reserved for the emotional half of a headline.
TextStyle authDisplay(
  double size, {
  Color color = SportikaColors.text,
  bool italic = false,
  double height = .92,
  double letterSpacing = -1,
}) => SportikaType.display(
  size,
  color: color,
  italic: italic,
  height: height,
  letterSpacing: letterSpacing,
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
    // Same asset-first contract as `SportPhoto`: the bundled photograph is the
    // offline path, the credited remote photo is only the fallback.
    final viewport = MediaQuery.sizeOf(context);
    // Cover needs enough pixels for the height as well as the width. Otherwise
    // a wide photograph decoded at phone width looks soft in portrait.
    final aspect = switch (sport) {
      Sport.cricket => 1200 / 616,
      Sport.padel => 1200 / 901,
      Sport.futsal => 1200 / 800,
      Sport.badminton => 1200 / 801,
    };
    final coverWidth = viewport.width > viewport.height * aspect
        ? viewport.width
        : viewport.height * aspect;
    final decodeWidth = (coverWidth * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 1200);
    final semanticLabel = '${sport.label} sports photography';
    return RepaintBoundary(
      child: Image.asset(
        'assets/images/sports/${sport.name}.jpg',
        fit: BoxFit.cover,
        alignment: alignment,
        cacheWidth: decodeWidth,
        semanticLabel: semanticLabel,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Image.network(
          SportPhotography.forSport(sport),
          fit: BoxFit.cover,
          alignment: alignment,
          cacheWidth: decodeWidth,
          semanticLabel: semanticLabel,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _fallback(),
          errorBuilder: (_, _, _) => _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: SportikaGradients.sportFallback(sportColor(sport)),
    ),
    child: Center(
      child: Icon(
        sportGlyph(sport),
        size: 148,
        color: SportikaColors.onAccent.withValues(alpha: .055),
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
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final media = MediaQuery.of(context);
    // Typing shrinks the viewport. Dock the action area above the keyboard only
    // when the remaining space still fits it with enlarged text; on short
    // viewports the footer stays inside the scroll view instead.
    final visibleHeight =
        media.size.height -
        media.padding.top -
        media.padding.bottom -
        media.viewInsets.bottom;
    final dockFooter =
        footer != null && media.viewInsets.bottom > 0 && visibleHeight >= 420;
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (flow.inlineError != null) ...[
            Semantics(
              liveRegion: true,
              child: AuthNotice(
                flow.inlineError!,
                tone: SportikaColors.danger,
                icon: Icons.error_outline,
              ),
            ),
            const SizedBox(height: 16),
          ],
          AbsorbPointer(
            absorbing: flow.busy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: SportikaColors.transparent,
        systemNavigationBarColor: SportikaColors.background,
      ),
      child: Scaffold(
        backgroundColor: SportikaColors.background,
        body: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: SportikaType.bodyFamily),
          child: Stack(
            children: [
              Positioned.fill(
                child: AuthPhoto(sport: sport, alignment: photoAlignment),
              ),
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: SportikaGradients.authPhotoScrim,
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
                              fontWeight: SportikaFontWeight.black,
                              letterSpacing: 2.6,
                              color: SportikaColors.text,
                            ),
                          ),
                          const Spacer(),
                          ?brandSuffix,
                          if (stepLabel != null)
                            Flexible(
                              child: Text(
                                stepLabel!.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: SportikaFontWeight.extraBold,
                                  letterSpacing: 1.7,
                                  color: SportikaColors.textDim,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: 560,
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: AutofillGroup(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        content,
                                        if (footer != null && !dockFooter)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              24,
                                              16,
                                              24,
                                              14,
                                            ),
                                            child: footer,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ),
                    // With the keyboard up the primary action stays reachable
                    // without scrolling past the fields. The action block is
                    // capped and scrollable so enlarged text cannot overflow a
                    // short viewport.
                    if (footer != null && dockFooter)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: media.size.height * .3,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                          child: footer,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        color: SportikaColors.glass,
        shape: const CircleBorder(
          side: BorderSide(color: SportikaColors.overlay),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            width: 48,
            child: Icon(icon, size: 18, color: SportikaColors.onAccent),
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
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: SportikaType.micro.copyWith(color: tone, letterSpacing: 2.3),
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
    this.color = SportikaColors.text,
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
        style: SportikaType.body.copyWith(
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
                      borderRadius: BorderRadius.circular(SportikaRadius.xxs),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '0${i + 1}',
                    style: TextStyle(
                      fontFamily: SportikaType.displayFamily,
                      fontSize: 12,
                      fontWeight: SportikaFontWeight.extraBold,
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
                      fontWeight: SportikaFontWeight.extraBold,
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
    this.readOnly = false,
    this.onTap,
    this.filledStyle = false,
    this.trailing,
  });

  final String label;
  final bool filledStyle;
  final Widget? trailing;
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
  final bool readOnly;
  final VoidCallback? onTap;

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
  void didUpdateWidget(covariant AuthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.errorText != null && oldWidget.errorText != widget.errorText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
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
                widget.filledStyle ? widget.label : widget.label.toUpperCase(),
                style: TextStyle(
                  fontSize: widget.filledStyle ? 12 : 9,
                  fontWeight: SportikaFontWeight.extraBold,
                  letterSpacing: widget.filledStyle ? 0 : 1.8,
                  color: hasError
                      ? SportikaColors.danger
                      : SportikaColors.textDim,
                ),
              ),
            ),
            if (widget.labelAction != null) widget.labelAction!,
          ],
        ),
        SizedBox(height: widget.filledStyle ? 8 : 2),
        TextField(
          controller: _controller,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          focusNode: _focus,
          enabled: widget.enabled && !context.watch<AuthFlowController>().busy,
          enableSuggestions: !widget.obscure,
          autocorrect:
              !widget.obscure &&
              widget.keyboardType != TextInputType.emailAddress,
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
            fontWeight: SportikaFontWeight.semibold,
            color: SportikaColors.text,
          ),
          decoration: InputDecoration(
            counterText: widget.filledStyle && widget.maxLines > 1 ? null : '',
            isDense: true,
            filled: widget.filledStyle,
            fillColor: SportikaColors.surface,
            border: widget.filledStyle
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      SportikaRadius.thumbnail,
                    ),
                    borderSide: BorderSide(color: ruleColor),
                  )
                : InputBorder.none,
            enabledBorder: widget.filledStyle
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      SportikaRadius.thumbnail,
                    ),
                    borderSide: const BorderSide(color: SportikaColors.border),
                  )
                : InputBorder.none,
            focusedBorder: widget.filledStyle
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      SportikaRadius.thumbnail,
                    ),
                    borderSide: BorderSide(color: ruleColor, width: 1.4),
                  )
                : InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: widget.filledStyle ? 16 : 0,
              vertical: widget.filledStyle ? 16 : 11,
            ),
            hintText: widget.hint,
            labelText: widget.label,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            hintStyle: const TextStyle(
              fontSize: 15.5,
              fontWeight: SportikaFontWeight.medium,
              color: SportikaColors.textDim,
            ),
            suffixIcon:
                widget.trailing ??
                (widget.obscure
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
                    : null),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 48,
            ),
          ),
        ),
        if (!widget.filledStyle)
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
    final loading = busy || context.watch<AuthFlowController>().busy;
    final enabled = onPressed != null && !loading;
    final foreground = SportikaColors.onAccent;
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label, please wait' : label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: SizedBox(
          width: double.infinity,
          child: Material(
            color: ghost
                ? SportikaColors.onAccent.withValues(
                    alpha: SportikaOpacity.whisper,
                  )
                : enabled
                ? tone
                : tone.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(SportikaRadius.button),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(SportikaRadius.button),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SportikaRadius.button),
                  border: ghost
                      ? Border.all(color: SportikaColors.borderStrong)
                      : null,
                  gradient: ghost || !enabled
                      ? null
                      : SportikaGradients.accentFill(tone),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: SportikaType.bodyFamily,
                          fontSize: 13.5,
                          fontWeight: SportikaFontWeight.extraBold,
                          letterSpacing: 1.1,
                          color: foreground.withValues(alpha: enabled ? 1 : .7),
                        ),
                      ),
                    ),
                    if (loading)
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SportikaColors.onAccent,
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
      onPressed: context.watch<AuthFlowController>().busy ? null : onTap,
      style: TextButton.styleFrom(
        foregroundColor: tone,
        padding: const EdgeInsets.symmetric(vertical: 6),
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        alignment: align == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: SportikaFontWeight.bold,
                letterSpacing: .2,
              ),
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
              fontWeight: SportikaFontWeight.extraBold,
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
    return Semantics(
      label: 'Accept terms and privacy',
      child: Checkbox(
        value: value,
        onChanged: context.watch<AuthFlowController>().busy
            ? null
            : (next) => onChanged(next ?? false),
        activeColor: tone,
        checkColor: SportikaColors.deepest,
        isError: error,
        side: BorderSide(
          color: error ? SportikaColors.danger : SportikaColors.borderStrong,
        ),
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
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SportikaRadius.lg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SportikaRadius.lg),
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
      borderRadius: BorderRadius.circular(SportikaRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 11 : 14,
            vertical: dense ? 6 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.pill),
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
              fontWeight: SportikaFontWeight.bold,
              color: selected ? tone : SportikaColors.textBody,
            ),
          ),
        ),
      ),
    );
  }
}

/// One accessible OTP field supports paste, autofill and normal backspace.
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
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant AuthOtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    enabled: !context.watch<AuthFlowController>().busy,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    autofillHints: const [AutofillHints.oneTimeCode],
    autocorrect: false,
    enableSuggestions: false,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ],
    textAlign: TextAlign.center,
    style: authDisplay(28, height: 1.3, letterSpacing: 12),
    decoration: InputDecoration(
      labelText: 'Six-digit code',
      hintText: '000000',
      errorText: widget.error ? 'Check the code and try again.' : null,
      filled: true,
      fillColor: SportikaColors.surfaceSunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SportikaRadius.md),
      ),
    ),
    onChanged: (value) {
      widget.onChanged(value);
      if (value.length == 6) widget.onCompleted(value);
    },
  );
}

/// Circular avatar preview; the branded default portrait until a photo is
/// imported.
class AuthAvatar extends StatelessWidget {
  const AuthAvatar({
    super.key,
    required this.initials,
    this.avatarId = 'midnight',
    this.size = 88,
    this.showRing = true,
    this.photoPath,
    this.photoUrl,
    this.figure,
  });

  final String initials;
  final String avatarId;
  final double size;
  final bool showRing;

  /// The imported picture, when the player has one. Anything the profile photo
  /// store did not issue falls back to the branded default portrait.
  final String? photoPath;

  /// The uploaded copy, shown when this device has no local file.
  final String? photoUrl;

  /// Which default portrait to draw while no picture is set.
  final DefaultAvatarFigure? figure;

  @override
  Widget build(BuildContext context) {
    return ProfileAvatar(
      initials: initials,
      avatarId: avatarId,
      photoPath: photoPath,
      photoUrl: photoUrl,
      size: size,
      showRing: showRing,
      figure: figure,
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
        borderRadius: BorderRadius.circular(SportikaRadius.control),
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
                fontWeight: SportikaFontWeight.extraBold,
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
                fontWeight: SportikaFontWeight.semibold,
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
              fontWeight: SportikaFontWeight.extraBold,
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
