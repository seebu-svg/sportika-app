import 'package:flutter/material.dart';
import 'package:sportika/shared/theme/theme.dart';

/// Premium segmented navigation for Sportika.
///
/// Features:
/// - Animated directional selection indicator
/// - Optional section icons and counts
/// - Responsive horizontal scrolling
/// - Keyboard and screen-reader accessibility
/// - Reduced-motion support
/// - Shared Sportika theme tokens only
class TeamSectionControl extends StatelessWidget {
  const TeamSectionControl({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.icons,
    this.counts,
    this.compact = false,
    this.scrollable = false,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  final List<IconData>? icons;
  final List<int>? counts;

  final bool compact;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = context.sportika;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final activeIndex = selected.clamp(0, labels.length - 1);

    final indicatorDuration = reduceMotion
        ? Duration.zero
        : SportikaMotion.indicator;

    final textDuration = reduceMotion ? Duration.zero : SportikaMotion.fast;

    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    // Scroll automatically for larger labels or many tabs.
    final useScroll = scrollable || labels.length > 3 || textScale > 1.3;

    const radius = BorderRadius.all(Radius.circular(SportikaRadius.control));

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: radius,
        border: Border.all(color: theme.borderSubtle),
      ),
      padding: const EdgeInsets.all(SportikaSpacing.xxs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (useScroll) {
            return _ScrollableTeamSections(
              labels: labels,
              icons: icons,
              counts: counts,
              activeIndex: activeIndex,
              onChanged: onChanged,
              compact: compact,
              textDuration: textDuration,
            );
          }

          final tabWidth = constraints.maxWidth / labels.length;

          return Stack(
            children: [
              // Animated floating selection surface.
              Positioned.fill(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedSlide(
                    duration: indicatorDuration,
                    curve: SportikaMotion.standard,
                    offset: Offset(activeIndex.toDouble(), 0),
                    child: SizedBox(
                      width: tabWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.surfaceElevated,
                          borderRadius: radius,
                          border: Border.all(color: SportikaColors.mintDeep),
                          boxShadow: [
                            BoxShadow(
                              color: theme.surfaceSunken.withValues(
                                alpha: SportikaOpacity.medium,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              Row(
                children: [
                  for (var index = 0; index < labels.length; index++)
                    Expanded(
                      child: _SectionTab(
                        label: labels[index],
                        icon: _iconAt(index),
                        count: _countAt(index),
                        selected: index == activeIndex,
                        compact: compact,
                        textDuration: textDuration,
                        onTap: () {
                          if (index != activeIndex) {
                            onChanged(index);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  IconData? _iconAt(int index) {
    if (icons == null || index >= icons!.length) {
      return null;
    }

    return icons![index];
  }

  int? _countAt(int index) {
    if (counts == null || index >= counts!.length) {
      return null;
    }

    return counts![index];
  }
}

/// Scrollable alternative for accessibility and narrow layouts.
class _ScrollableTeamSections extends StatelessWidget {
  const _ScrollableTeamSections({
    required this.labels,
    required this.icons,
    required this.counts,
    required this.activeIndex,
    required this.onChanged,
    required this.compact,
    required this.textDuration,
  });

  final List<String> labels;
  final List<IconData>? icons;
  final List<int>? counts;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final bool compact;
  final Duration textDuration;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Padding(
              padding: const EdgeInsets.only(right: SportikaSpacing.xs),
              child: AnimatedContainer(
                duration: textDuration,
                curve: SportikaMotion.standard,
                decoration: BoxDecoration(
                  color: index == activeIndex
                      ? theme.surfaceElevated
                      : SportikaColors.transparent,
                  borderRadius: BorderRadius.circular(SportikaRadius.control),
                  border: Border.all(
                    color: index == activeIndex
                        ? SportikaColors.mintDeep
                        : SportikaColors.transparent,
                  ),
                ),
                child: _SectionTab(
                  label: labels[index],
                  icon: icons != null && index < icons!.length
                      ? icons![index]
                      : null,
                  count: counts != null && index < counts!.length
                      ? counts![index]
                      : null,
                  selected: index == activeIndex,
                  compact: compact,
                  textDuration: textDuration,
                  onTap: () {
                    if (index != activeIndex) {
                      onChanged(index);
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// REUSABLE SECTION TAB
// -----------------------------------------------------------------------------

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.compact,
    required this.textDuration,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final int? count;

  final bool selected;
  final bool compact;

  final Duration textDuration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final foreground = selected ? SportikaColors.mint : theme.textBody;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: SportikaColors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(SportikaRadius.control),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? SportikaSpacing.xs : SportikaSpacing.sm,
                vertical: SportikaSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: SportikaIconSize.sm, color: foreground),
                    const SizedBox(width: SportikaSpacing.xs),
                  ],
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: textDuration,
                      curve: SportikaMotion.standard,
                      style: SportikaType.action.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (count != null && count! > 0) ...[
                    const SizedBox(width: SportikaSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SportikaSpacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? SportikaColors.mintSubtle
                            : theme.surfaceSunken,
                        borderRadius: BorderRadius.circular(
                          SportikaRadius.pill,
                        ),
                      ),
                      child: Text(
                        '$count',
                        style: SportikaType.caption.copyWith(color: foreground),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PREMIUM TEAM SEARCH FIELD
// -----------------------------------------------------------------------------

class TeamSearchField extends StatefulWidget {
  const TeamSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.onFilterPressed,
    this.onClear,
    this.searchLabel,
    this.filterCount = 0,
    this.autofocus = false,
    this.enabled = true,
    this.searching = false,
  });

  final TextEditingController controller;
  final String hint;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onFilterPressed;
  final VoidCallback? onClear;

  final String? searchLabel;
  final int filterCount;

  final bool autofocus;
  final bool enabled;
  final bool searching;

  @override
  State<TeamSearchField> createState() => _TeamSearchFieldState();
}

class _TeamSearchFieldState extends State<TeamSearchField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    widget.controller.clear();

    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final focused = _focusNode.hasFocus;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final hasText = widget.controller.text.isNotEmpty;

        return AnimatedContainer(
          duration: reduceMotion ? Duration.zero : SportikaMotion.fast,
          curve: SportikaMotion.standard,
          constraints: const BoxConstraints(minHeight: 54),
          decoration: BoxDecoration(
            color: focused ? theme.surfaceSunken : theme.surfaceElevated,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(
              color: focused ? SportikaColors.mintDeep : theme.borderSubtle,
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  textInputAction: TextInputAction.search,
                  style: SportikaType.body,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    labelText: widget.searchLabel,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: SportikaIconSize.md,
                      color: focused ? SportikaColors.mint : theme.textBody,
                    ),
                  ),
                ),
              ),

              // Search loading and clear action.
              if (widget.searching)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: SportikaSpacing.sm),
                  child: SizedBox(
                    width: SportikaIconSize.md,
                    height: SportikaIconSize.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SportikaColors.mint,
                    ),
                  ),
                )
              else if (hasText)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: widget.enabled ? _clearSearch : null,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: SportikaIconSize.md,
                  ),
                ),

              // Filter action remains visible while searching.
              if (widget.onFilterPressed != null)
                Padding(
                  padding: const EdgeInsets.only(right: SportikaSpacing.xs),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: 'Search filters',
                        onPressed: widget.enabled
                            ? widget.onFilterPressed
                            : null,
                        style: IconButton.styleFrom(
                          backgroundColor: theme.surfaceSunken,
                        ),
                        icon: const Icon(
                          Icons.tune_rounded,
                          size: SportikaIconSize.md,
                        ),
                      ),
                      if (widget.filterCount > 0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 17,
                              minHeight: 17,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: SportikaColors.mint,
                              borderRadius: BorderRadius.circular(
                                SportikaRadius.pill,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${widget.filterCount}',
                                style: SportikaType.caption.copyWith(
                                  color: theme.surfaceSunken,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              const SizedBox(width: SportikaSpacing.xs),
            ],
          ),
        );
      },
    );
  }
}
