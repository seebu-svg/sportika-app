import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/features/profile/widgets/profile_sport_preferences.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

// ============================================================
// SPORTS PREFERENCES SCREEN
// ============================================================

class SportsPreferencesScreen extends StatefulWidget {
  const SportsPreferencesScreen({super.key});

  @override
  State<SportsPreferencesScreen> createState() =>
      _SportsPreferencesScreenState();
}

class _SportsPreferencesScreenState extends State<SportsPreferencesScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileModuleController>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final module = context.watch<ProfileModuleController>();
    final snapshot = module.snapshot;

    Widget body;

    if (snapshot != null) {
      body = _SportsPreferencesForm(sports: snapshot.sports, busy: module.busy);
    } else if (module.error != null) {
      body = ErrorState(
        title: 'Your sports could not be loaded',
        message: module.error,
        onRetry: module.refresh,
      );
    } else {
      body = const LoadingSkeleton(
        rows: 3,
        label: 'Loading your athlete identity',
      );
    }

    return ScreenScaffold(
      title: 'Sports preferences',
      onRefresh: module.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SportsStudioHero(),
          const SizedBox(height: SportikaSpacing.lg),
          body,
        ],
      ),
    );
  }
}

// ============================================================
// SPORTS STUDIO HERO
// ============================================================

class _SportsStudioHero extends StatelessWidget {
  const _SportsStudioHero();

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        gradient: SportikaGradients.sportCoin(theme.live),
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                color: theme.live,
                size: SportikaIconSize.md,
              ),
              const SizedBox(width: SportikaSpacing.xs),
              Text(
                'ATHLETE IDENTITY / SPORTS',
                style: SportikaType.micro.copyWith(color: theme.live),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.lg),
          const Text('YOUR SPORTS.\nYOUR GAME.', style: SportikaType.title),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            'Build your multi-sport identity. Choose the games you play '
            'and customize how you compete.',
            style: SportikaType.body.copyWith(color: theme.textBody),
          ),
          const SizedBox(height: SportikaSpacing.md),
          Wrap(
            spacing: SportikaSpacing.sm,
            runSpacing: SportikaSpacing.sm,
            children: [
              for (final sport in Sport.values) _HeroSportGlyph(sport: sport),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSportGlyph extends StatelessWidget {
  const _HeroSportGlyph({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);
    final theme = context.sportika;

    return Container(
      width: SportikaSpacing.xxxl,
      height: SportikaSpacing.xxxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(
          color: tone.withValues(alpha: SportikaOpacity.medium),
        ),
      ),
      child: SportGlyph(sport: sport, color: tone, size: SportikaIconSize.md),
    );
  }
}

// ============================================================
// SPORTS PREFERENCES FORM
// ============================================================

class _SportsPreferencesForm extends StatefulWidget {
  const _SportsPreferencesForm({required this.sports, required this.busy});

  final List<ProfileSportPreference> sports;
  final bool busy;

  @override
  State<_SportsPreferencesForm> createState() => _SportsPreferencesFormState();
}

class _SportsPreferencesFormState extends State<_SportsPreferencesForm> {
  late Set<Sport> _selected;
  late Map<String, PlayingLevel> _levels;
  late Map<String, String> _positions;
  late bool _skipped;

  final Set<Sport> _expanded = {};

  String? _error;
  bool _saving = false;

  late String _savedSignature;

  @override
  void initState() {
    super.initState();
    _initialize(widget.sports);
  }

  @override
  void didUpdateWidget(covariant _SportsPreferencesForm oldWidget) {
    super.didUpdateWidget(oldWidget);

    final incoming = _signature(widget.sports);

    if (incoming != _savedSignature && !_dirty && !_saving) {
      _initialize(widget.sports);
    }
  }

  void _initialize(List<ProfileSportPreference> sports) {
    _selected = {for (final preference in sports) preference.sport};

    _levels = {
      for (final preference in sports)
        if (preference.level != null) preference.sport.key: preference.level!,
    };

    _positions = {
      for (final preference in sports)
        if (preference.position != null && preference.position!.isNotEmpty)
          preference.sport.key: preference.position!,
    };

    _skipped =
        sports.isNotEmpty &&
        sports.every((preference) => preference.level == null);

    _savedSignature = _signature(sports);
    _expanded.clear();
    _error = null;
  }

  List<ProfileSportPreference> get _draft {
    return [
      for (final sport in Sport.values.where(_selected.contains))
        ProfileSportPreference(
          sport,
          level: _skipped
              ? null
              : (_levels[sport.key] ?? defaultLevelFor(sport)),
          position: _skipped ? null : _positions[sport.key],
        ),
    ];
  }

  String _signature(List<ProfileSportPreference> preferences) {
    final ordered = [...preferences]
      ..sort((a, b) => a.sport.key.compareTo(b.sport.key));

    return ordered
        .map(
          (preference) =>
              '${preference.sport.key}:'
              '${preference.level?.key ?? "-"}:'
              '${preference.position ?? "-"}',
        )
        .join('|');
  }

  bool get _dirty => _signature(_draft) != _savedSignature;

  bool get _enabled => !widget.busy && !_saving;

  void _toggle(Sport sport) {
    if (!_enabled) return;

    setState(() {
      _error = null;

      if (!_selected.remove(sport)) {
        _selected.add(sport);
        _levels.putIfAbsent(sport.key, () => defaultLevelFor(sport));
      } else {
        _expanded.remove(sport);
      }
    });
  }

  void _toggleExpanded(Sport sport) {
    setState(() {
      if (!_expanded.remove(sport)) {
        _expanded.add(sport);
      }
    });
  }

  Future<void> _save() async {
    if (!_enabled || !_dirty) return;

    FocusScope.of(context).unfocus();

    if (_selected.isEmpty) {
      setState(() {
        _error = 'Choose at least one preferred sport.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final draft = _draft;
    final module = context.read<ProfileModuleController>();

    try {
      await module.saveSportsPreferences(draft);

      if (!mounted) return;

      setState(() {
        _savedSignature = _signature(draft);
        _saving = false;
      });

      showSnack(context, 'Sports preferences saved');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message;
        _saving = false;
      });

      showSnack(context, error.message, error: true);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to save your sports preferences. Try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final selectedSports = Sport.values.where(_selected.contains).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ------------------------------------------------------
        // SPORT SELECTION
        // ------------------------------------------------------

        Row(
          children: [
            const Expanded(
              child: Text(
                'Choose your sports',
                style: SportikaType.titleMedium,
              ),
            ),
            _SelectionCount(count: _selected.length),
          ],
        ),

        const SizedBox(height: SportikaSpacing.xs),

        Text(
          'Select every sport you actively play.',
          style: SportikaType.caption.copyWith(color: theme.textMuted),
        ),

        const SizedBox(height: SportikaSpacing.md),

        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 560 ? 4 : 2;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: Sport.values.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: SportikaSpacing.sm,
                mainAxisSpacing: SportikaSpacing.sm,
                childAspectRatio: columns == 4 ? 1.25 : 1.4,
              ),
              itemBuilder: (context, index) {
                final sport = Sport.values[index];

                return _SportSelectionCard(
                  sport: sport,
                  selected: _selected.contains(sport),
                  enabled: _enabled,
                  onTap: () => _toggle(sport),
                );
              },
            );
          },
        ),

        const SizedBox(height: SportikaSpacing.lg),

        // ------------------------------------------------------
        // OPTIONAL RANKING
        // ------------------------------------------------------
        const Text('Playing level & position', style: SportikaType.titleMedium),

        const SizedBox(height: SportikaSpacing.xs),

        Text(
          'Personalize how you play each selected sport.',
          style: SportikaType.caption.copyWith(color: theme.textMuted),
        ),

        const SizedBox(height: SportikaSpacing.md),

        _SkipRankingCard(
          value: _skipped,
          enabled: _enabled,
          onChanged: (value) {
            setState(() {
              _skipped = value;
              _error = null;
            });
          },
        ),

        const SizedBox(height: SportikaSpacing.md),

        if (!_skipped)
          for (final sport in selectedSports) ...[
            _ExpandableSportPreferences(
              sport: sport,
              level: _levels[sport.key] ?? defaultLevelFor(sport),
              position: _positions[sport.key],
              expanded: _expanded.contains(sport),
              enabled: _enabled,
              onExpanded: () => _toggleExpanded(sport),
              onLevelChanged: (level) {
                setState(() {
                  _levels[sport.key] = level;
                });
              },
              onPositionChanged: (position) {
                setState(() {
                  if (position == null) {
                    _positions.remove(sport.key);
                  } else {
                    _positions[sport.key] = position;
                  }
                });
              },
            ),
            const SizedBox(height: SportikaSpacing.sm),
          ],

        if (_selected.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SportikaSpacing.md),
            child: InlineBanner(
              text: 'Choose at least one sport to complete your profile.',
              tone: SportikaColors.danger,
            ),
          ),

        if (_error != null) ...[
          const SizedBox(height: SportikaSpacing.md),
          InlineBanner(text: _error!, tone: SportikaColors.danger),
        ],

        const SizedBox(height: SportikaSpacing.lg),

        // ------------------------------------------------------
        // SAVE ACTION
        // ------------------------------------------------------
        Container(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          decoration: BoxDecoration(
            color: theme.surfaceElevated,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(color: theme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    color: theme.live,
                    size: SportikaIconSize.md,
                  ),
                  const SizedBox(width: SportikaSpacing.xs),
                  Expanded(
                    child: Text(
                      '${_selected.length} '
                      '${_selected.length == 1 ? "sport" : "sports"} selected',
                      style: SportikaType.bodyStrong,
                    ),
                  ),
                  if (_dirty)
                    Text(
                      'UNSAVED CHANGES',
                      style: SportikaType.micro.copyWith(color: theme.live),
                    ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.md),
              PrimaryButton(
                label: 'Save Changes',
                icon: Icons.check_rounded,
                busy: widget.busy || _saving,
                onPressed: _enabled && _dirty && _selected.isNotEmpty
                    ? _save
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SPORT SELECTION CARD
// ============================================================

class _SportSelectionCard extends StatelessWidget {
  const _SportSelectionCard({
    required this.sport,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Sport sport;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final tone = sportColor(sport);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      selected: selected,
      label: sport.label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : SportikaMotion.fast,
        curve: SportikaMotion.standard,
        decoration: BoxDecoration(
          gradient: selected ? SportikaGradients.sportCoin(tone) : null,
          color: selected ? null : theme.surfaceElevated,
          borderRadius: BorderRadius.circular(SportikaRadius.control),
          border: Border.all(
            color: selected ? tone : theme.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: SportikaColors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            child: Padding(
              padding: const EdgeInsets.all(SportikaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SportGlyph(
                        sport: sport,
                        color: tone,
                        size: SportikaIconSize.lg,
                      ),
                      const Spacer(),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected ? tone : theme.textMuted,
                        size: SportikaIconSize.md,
                      ),
                    ],
                  ),
                  Text(
                    sport.label,
                    style: SportikaType.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SELECTION COUNT
// ============================================================

class _SelectionCount extends StatelessWidget {
  const _SelectionCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Text(
        '$count selected',
        style: SportikaType.caption.copyWith(color: theme.live),
      ),
    );
  }
}

// ============================================================
// OPTIONAL RANKING CARD
// ============================================================

class _SkipRankingCard extends StatelessWidget {
  const _SkipRankingCard({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SportikaSpacing.md,
          vertical: SportikaSpacing.xs,
        ),
        secondary: Icon(Icons.tune_rounded, color: theme.textMuted),
        title: const Text(
          'Skip playing levels',
          style: SportikaType.bodyStrong,
        ),
        subtitle: const Text(
          'Keep your sports without a level or position. '
          'You can add them later.',
          style: SportikaType.caption,
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

// ============================================================
// EXPANDABLE SPORT PREFERENCES
// ============================================================

class _ExpandableSportPreferences extends StatelessWidget {
  const _ExpandableSportPreferences({
    required this.sport,
    required this.level,
    required this.position,
    required this.expanded,
    required this.enabled,
    required this.onExpanded,
    required this.onLevelChanged,
    required this.onPositionChanged,
  });

  final Sport sport;
  final PlayingLevel level;
  final String? position;
  final bool expanded;
  final bool enabled;
  final VoidCallback onExpanded;
  final ValueChanged<PlayingLevel> onLevelChanged;
  final ValueChanged<String?> onPositionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final tone = sportColor(sport);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceElevated,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: expanded ? tone : theme.borderSubtle),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: enabled ? onExpanded : null,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            child: Padding(
              padding: const EdgeInsets.all(SportikaSpacing.md),
              child: Row(
                children: [
                  SportGlyph(
                    sport: sport,
                    color: tone,
                    size: SportikaIconSize.lg,
                  ),
                  const SizedBox(width: SportikaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sport.label, style: SportikaType.bodyStrong),
                        const SizedBox(height: SportikaSpacing.xxs),
                        Text(
                          position == null || position!.isEmpty
                              ? level.label
                              : '${level.label} · $position',
                          style: SportikaType.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : SportikaMotion.fast,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: theme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: reduceMotion ? Duration.zero : SportikaMotion.fast,
            curve: SportikaMotion.standard,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SportikaSpacing.md,
                      0,
                      SportikaSpacing.md,
                      SportikaSpacing.md,
                    ),
                    child: ProfileSportPreferences(
                      sport: sport,
                      level: level,
                      position: position,
                      onLevelChanged: enabled ? onLevelChanged : (_) {},
                      onPositionChanged: enabled ? onPositionChanged : (_) {},
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
