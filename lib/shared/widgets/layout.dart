import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

/// Shared page frame: safe area, clamped text scale, and a single content column
/// that never grows past [sportikaMaxContentWidth]. Every pushed screen builds
/// on this so padding, back behaviour and refresh gestures stay identical.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
    this.scrollable = true,
    this.onRefresh,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.centerTitle = false,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final EdgeInsets padding;
  final bool scrollable;
  final Future<void> Function()? onRefresh;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    final scrollPhysics = onRefresh == null
        ? null
        : const AlwaysScrollableScrollPhysics();

    Widget body;
    if (!scrollable) {
      body = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: sportikaMaxContentWidth),
          child: content,
        ),
      );
    } else {
      final list = ListView(
        physics: scrollPhysics,
        padding: EdgeInsets.zero,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: sportikaMaxContentWidth,
              ),
              child: content,
            ),
          ),
        ],
      );
      body = onRefresh == null
          ? list
          : RefreshIndicator(onRefresh: onRefresh!, child: list);
    }

    return ClampedTextScale(
      child: Scaffold(
        appBar: title == null
            ? null
            : AppBar(
                title: Text(title!, style: titleTextStyle),
                centerTitle: centerTitle,
                actions: actions,
                titleTextStyle: titleTextStyle,
              ),
        body: SafeArea(child: body),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }

  /// App bar titles were previously styled ad hoc per screen.
  static const TextStyle titleTextStyle = TextStyle(
    fontFamily: SportikaType.displayFamily,
    fontSize: 21,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.4,
    color: SportikaColors.text,
  );
}

/// Large in-page header used by root tabs and full-screen forms that do not use
/// an [AppBar]. Keeps the eyebrow/title/subtitle rhythm consistent.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.only(bottom: 16),
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(eyebrow!.toUpperCase(), style: SportikaType.label),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      title,
                      style: SportikaType.hero,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 8),
                Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: SportikaType.caption),
          ],
        ],
      ),
    );
  }
}

/// Group heading inside a page, optionally with a trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(0, 22, 0, 12),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: SportikaType.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 40),
                foregroundColor: SportikaColors.blueBright,
              ),
              child: Text(action!, style: SportikaType.action),
            ),
        ],
      ),
    );
  }
}

/// Wraps a scrollable body in a [RefreshIndicator] while preserving the
/// always-scrollable physics a short page needs to accept the gesture.
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: SportikaColors.mint,
      backgroundColor: SportikaColors.surface,
      child: child,
    );
  }
}

/// Icon-only affordance with the label screen readers need. Icon buttons used
/// to be bare [IconButton]s with no tooltip or semantic label.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.badge,
    this.tone = SportikaColors.textBody,
    this.size = 20,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Widget? badge;
  final Color tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      height: 44,
      width: 44,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onPressed,
          radius: 22,
          child: Semantics(
            button: true,
            label: label,
            child: Icon(icon, size: size, color: tone),
          ),
        ),
      ),
    );
    if (badge == null) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(right: 4, top: 4, child: badge!),
      ],
    );
  }
}

/// Muted helper line under a field or control.
class HelperText extends StatelessWidget {
  const HelperText(this.text, {super.key, this.tone = SportikaColors.textDim});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: SportikaType.caption.copyWith(color: tone));
}
