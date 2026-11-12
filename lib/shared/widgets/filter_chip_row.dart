import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

/// One selectable option in a [FilterChipRow].
@immutable
class FilterChoice<T> {
  const FilterChoice(this.value, this.label, {this.icon, this.badge});

  final T value;
  final String label;
  final IconData? icon;
  final int? badge;
}

/// Horizontally scrollable filter row. Replaces the `SegmentedButton` rows and
/// ad-hoc chip tickers that overflowed below 360 dp: chips are forced to a
/// 48 dp touch target, the row never wraps, and it scrolls instead of clipping.
class FilterChipRow<T> extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.choices,
    required this.selected,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
    this.tone = SportikaColors.mint,
    this.label,
    this.enabled = true,
  });

  final List<FilterChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onChanged;
  final EdgeInsets padding;
  final Color tone;

  /// Accessibility label describing the group, e.g. "Filter by sport".
  final String? label;

  /// Disabled rows stay visible but read as unavailable, e.g. once scoring has
  /// locked a match's setup.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: choices.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final choice = choices[index];
          return _Chip(
            choice: choice,
            active: choice.value == selected,
            tone: tone,
            groupLabel: label,
            enabled: enabled,
            onTap: () => onChanged(choice.value),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.choice,
    required this.active,
    required this.tone,
    required this.onTap,
    this.groupLabel,
    this.enabled = true,
  });

  final FilterChoice<dynamic> choice;
  final bool active;
  final Color tone;
  final VoidCallback onTap;
  final String? groupLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? tone.withValues(alpha: 0.18)
        : SportikaColors.surfaceSunken;
    final border = active ? tone.withValues(alpha: 0.6) : SportikaColors.border;

    return Semantics(
      button: true,
      selected: active,
      enabled: enabled,
      label: groupLabel == null ? choice.label : '$groupLabel: ${choice.label}',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(SportikaRadius.pill),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(SportikaRadius.pill),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SportikaRadius.pill),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (choice.icon != null) ...[
                    Icon(
                      choice.icon,
                      size: 15,
                      color: active ? tone : SportikaColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    choice.label,
                    style: SportikaType.action.copyWith(
                      color: active ? tone : SportikaColors.textBody,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  if (choice.badge != null && choice.badge! > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${choice.badge}',
                      style: SportikaType.micro.copyWith(color: tone),
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

/// Sport filter built on [FilterChipRow]; the single place that maps
/// `Sport?` onto chips so Home, Live and Discover stay in sync.
class SportFilterRow extends StatelessWidget {
  const SportFilterRow({
    super.key,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.allLabel = 'All sports',
  });

  final Sport? selected;
  final ValueChanged<Sport?> onChanged;
  final EdgeInsets padding;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    return FilterChipRow<Sport?>(
      padding: padding,
      selected: selected,
      onChanged: onChanged,
      label: 'Filter by sport',
      choices: [
        FilterChoice<Sport?>(null, allLabel),
        for (final sport in Sport.values)
          FilterChoice<Sport?>(sport, sport.label),
      ],
    );
  }
}
