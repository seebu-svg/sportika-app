import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/features/profile/widgets/profile_sport_preferences.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Me → Sports preferences.
///
/// Reuses the sport cards from the setup journey: the same levels, the same
/// optional positions, and the same "I would rather not rank" answer, so an
/// edit can never produce a shape setup would not.
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

    final Widget body;
    if (snapshot != null) {
      body = _SportsPreferencesForm(
        key: ValueKey(
          snapshot.sports
              .map((s) => '${s.sport.key}:${s.level?.key}')
              .join(','),
        ),
        sports: snapshot.sports,
        busy: module.busy,
      );
    } else if (module.error != null) {
      body = ErrorState(
        title: 'Your sports could not be loaded',
        message: module.error,
        onRetry: module.refresh,
      );
    } else {
      body = const LoadingSkeleton(
        rows: 2,
        label: 'Loading sports preferences',
      );
    }

    return ScreenScaffold(
      title: 'Sports preferences',
      onRefresh: module.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Me',
            title: 'Sports preferences',
            subtitle:
                'Which sports you play, how often you compete, and where you '
                'like to be. One sport is enough.',
          ),
          body,
        ],
      ),
    );
  }
}

class _SportsPreferencesForm extends StatefulWidget {
  const _SportsPreferencesForm({
    super.key,
    required this.sports,
    required this.busy,
  });

  final List<ProfileSportPreference> sports;
  final bool busy;

  @override
  State<_SportsPreferencesForm> createState() => _SportsPreferencesFormState();
}

class _SportsPreferencesFormState extends State<_SportsPreferencesForm> {
  late final Set<Sport> _selected = {
    for (final preference in widget.sports) preference.sport,
  };
  late final Map<String, PlayingLevel> _levels = {
    for (final preference in widget.sports)
      if (preference.level != null) preference.sport.key: preference.level!,
  };
  late final Map<String, String> _positions = {
    for (final preference in widget.sports)
      if (preference.position != null && preference.position!.isNotEmpty)
        preference.sport.key: preference.position!,
  };
  late bool _skipped =
      widget.sports.isNotEmpty &&
      widget.sports.every((preference) => preference.level == null);
  String? _error;

  void _toggle(Sport sport) {
    setState(() {
      _error = null;
      if (!_selected.remove(sport)) {
        _selected.add(sport);
        _levels.putIfAbsent(sport.key, () => defaultLevelFor(sport));
      }
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_selected.isEmpty) {
      setState(() => _error = 'Choose at least one preferred sport.');
      return;
    }
    setState(() => _error = null);
    final ordered = Sport.values.where(_selected.contains);
    final module = context.read<ProfileModuleController>();
    try {
      await module.saveSportsPreferences([
        for (final sport in ordered)
          ProfileSportPreference(
            sport,
            level: _skipped
                ? null
                : (_levels[sport.key] ?? defaultLevelFor(sport)),
            position: _skipped ? null : _positions[sport.key],
          ),
      ]);
      if (!mounted) return;
      showSnack(context, 'Sports preferences saved');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      showSnack(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.busy;
    final ordered = Sport.values.where(_selected.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sport in Sport.values)
              AuthChoicePill(
                label: sport.label,
                tone: sportColor(sport),
                selected: _selected.contains(sport),
                onTap: () {
                  if (enabled) _toggle(sport);
                },
              ),
          ],
        ),
        const SectionHeader('Ranking'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            "I'd rather not rank my sports",
            style: SportikaType.bodyStrong,
          ),
          subtitle: const Text(
            'You keep your sports with no level or position. You can add them '
            'later.',
            style: SportikaType.caption,
          ),
          value: _skipped,
          onChanged: enabled
              ? (value) => setState(() => _skipped = value)
              : null,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        if (!_skipped)
          for (final sport in ordered) ...[
            ProfileSportPreferences(
              sport: sport,
              level: _levels[sport.key] ?? defaultLevelFor(sport),
              position: _positions[sport.key],
              onLevelChanged: enabled
                  ? (level) => setState(() => _levels[sport.key] = level)
                  : (_) {},
              onPositionChanged: enabled
                  ? (position) => setState(() {
                      if (position == null) {
                        _positions.remove(sport.key);
                      } else {
                        _positions[sport.key] = position;
                      }
                    })
                  : (_) {},
            ),
            const SizedBox(height: SportikaSpacing.md),
          ],
        if (_selected.isEmpty)
          const EmptyState(
            title: 'No sports chosen',
            body: 'Pick at least one sport to keep your profile complete.',
            icon: Icons.sports_outlined,
          ),
        if (_error != null) ...[
          InlineBanner(text: _error!, tone: SportikaColors.danger),
          const SizedBox(height: SportikaSpacing.md),
        ],
        PrimaryButton(
          label: 'Save sports',
          icon: Icons.check,
          busy: widget.busy,
          onPressed: widget.busy ? null : _save,
        ),
      ],
    );
  }
}
