import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Premium Sportika squad builder.
///
/// Frontend-only redesign. Existing squad creation, player selection,
/// validation, controller integration, and navigation are preserved.
class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key, this.sport});

  final Sport? sport;

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();

  late Sport _sport = widget.sport ?? Sport.padel;
  late EntryType _type = _entryTypeFor(_sport);

  final Set<String> _members = {};

  String? _error;
  bool _saving = false;

  static EntryType _entryTypeFor(Sport sport) => switch (sport) {
    Sport.cricket || Sport.futsal => EntryType.team,
    Sport.padel || Sport.badminton => EntryType.pair,
  };

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_name.text.trim().length < 3) {
      return 'Give your squad a name of at least 3 characters.';
    }

    if (_members.isEmpty) {
      return _type == EntryType.pair
          ? 'Select one partner to complete your pair.'
          : 'Select at least one player to start your team.';
    }

    if (_type == EntryType.pair && _members.length > 1) {
      return 'A pair supports one selected partner.';
    }

    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;

    final problem = _validate();

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      final teams = context.read<TeamsController>();

      final squad = teams.createSquad(
        name: _name.text.trim(),
        sport: _sport,
        type: _type,
        memberIds: _members.toList(),
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      showSnack(context, '${squad.name} created');

      pushRoute(context, AppRoute.teamDetail, args: TeamDetailArgs(squad.id));
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = 'Unable to create squad. Please try again.';
      });
    }
  }

  void _changeSport(Sport sport) {
    if (_sport == sport) return;

    final nextType = _entryTypeFor(sport);

    // Never silently discard selected players.
    if (nextType == EntryType.pair && _members.length > 1) {
      _confirmFormatChange(
        onConfirm: () {
          setState(() {
            _sport = sport;
            _type = nextType;
            _members.clear();
            _error = null;
          });
        },
      );
      return;
    }

    setState(() {
      _sport = sport;
      _type = nextType;
      _error = null;
    });
  }

  void _changeType(EntryType type) {
    if (_type == type) return;

    if (type == EntryType.pair && _members.length > 1) {
      _confirmFormatChange(
        onConfirm: () {
          setState(() {
            _type = type;
            _members.clear();
            _error = null;
          });
        },
      );
      return;
    }

    setState(() {
      _type = type;
      _error = null;
    });
  }

  Future<void> _confirmFormatChange({required VoidCallback onConfirm}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change squad format?'),
        content: const Text(
          'A pair can contain only one selected partner. '
          'Changing the format will clear your current roster.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep roster'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear & continue'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      onConfirm();
    }
  }

  Account _placeholderAccount(String id) => Account(
    id: id,
    displayName: 'Player',
    email: '',
    city: '',
    roles: const [UserRole.player],
  );

  @override
  Widget build(BuildContext context) {
    final teams = context.watch<TeamsController>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final term = _search.text.trim().toLowerCase();

    final candidates = teams.accounts
        .where((account) => !_members.contains(account.id))
        .where(
          (account) =>
              term.isEmpty ||
              '${account.displayName} ${account.city}'.toLowerCase().contains(
                term,
              ),
        )
        .toList();

    final limit = _type == EntryType.pair ? 1 : null;
    final rosterFull = limit != null && _members.length >= limit;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('CREATE SQUAD', style: SportikaType.action),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: SportikaSpacing.md),
            child: Center(
              child: Text(
                'TEAM BUILDER',
                style: SportikaType.caption.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  SportikaSpacing.md,
                  SportikaSpacing.sm,
                  SportikaSpacing.md,
                  SportikaSpacing.lg,
                ),
                children: [
                  _SquadHero(sport: _sport, type: _type),

                  const SizedBox(height: SportikaSpacing.lg),

                  _BuilderSection(
                    number: '01',
                    title: 'Squad identity',
                    subtitle: 'Give your team a name worth remembering.',
                    child: _SquadIdentity(
                      controller: _name,
                      sport: _sport,
                      onChanged: () {
                        setState(() => _error = null);
                      },
                    ),
                  ),

                  const SizedBox(height: SportikaSpacing.lg),

                  _BuilderSection(
                    number: '02',
                    title: 'Choose your sport',
                    subtitle: 'Select the game your squad represents.',
                    child: _SportSelector(
                      selected: _sport,
                      onChanged: _changeSport,
                    ),
                  ),

                  const SizedBox(height: SportikaSpacing.lg),

                  _BuilderSection(
                    number: '03',
                    title: 'Squad format',
                    subtitle: 'Choose how your players compete.',
                    child: _FormatSelector(
                      selected: _type,
                      onChanged: _changeType,
                    ),
                  ),

                  const SizedBox(height: SportikaSpacing.lg),

                  _BuilderSection(
                    number: '04',
                    title: 'Assemble your roster',
                    subtitle: _type == EntryType.pair
                        ? 'Choose your playing partner.'
                        : 'Build your lineup from the community.',
                    trailing: _members.isEmpty
                        ? null
                        : TextButton(
                            onPressed: () {
                              setState(() {
                                _members.clear();
                                _error = null;
                              });
                            },
                            child: const Text('Clear'),
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RosterSummary(count: _members.length, type: _type),

                        const SizedBox(height: SportikaSpacing.md),

                        AnimatedSize(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeInOut,
                          child: _members.isEmpty
                              ? _EmptyRoster(type: _type)
                              : Wrap(
                                  spacing: SportikaSpacing.sm,
                                  runSpacing: SportikaSpacing.sm,
                                  children: [
                                    for (final id in _members)
                                      _SelectedPlayer(
                                        key: ValueKey(id),
                                        account: teams.accounts.firstWhere(
                                          (account) => account.id == id,
                                          orElse: () => _placeholderAccount(id),
                                        ),
                                        onRemove: () {
                                          setState(() {
                                            _members.remove(id);
                                            _error = null;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                        ),

                        const SizedBox(height: SportikaSpacing.lg),

                        const Text('FIND PLAYERS', style: SportikaType.action),

                        const SizedBox(height: SportikaSpacing.sm),

                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search by name or city',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () {
                                      _search.clear();
                                      setState(() {});
                                    },
                                  ),
                          ),
                        ),

                        const SizedBox(height: SportikaSpacing.md),

                        if (rosterFull)
                          const Padding(
                            padding: EdgeInsets.only(
                              bottom: SportikaSpacing.md,
                            ),
                            child: _InfoStrip(
                              icon: Icons.check_circle_outline_rounded,
                              text:
                                  'Your pair is complete. Remove '
                                  'the selected partner to choose another.',
                            ),
                          ),

                        if (candidates.isEmpty)
                          const EmptyState(
                            title: 'No players found',
                            body: 'Try another name or city.',
                            icon: Icons.person_search_outlined,
                          )
                        else
                          ...candidates.map(
                            (player) => _CandidateRow(
                              key: ValueKey(player.id),
                              player: player,
                              disabled: rosterFull,
                              onAdd: () {
                                setState(() {
                                  _members.add(player.id);
                                  _error = null;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: SportikaSpacing.md),
                    InlineBanner(
                      text: _error!,
                      tone: SportikaColors.danger,
                      icon: Icons.error_outline_rounded,
                    ),
                  ],

                  const SizedBox(height: SportikaSpacing.lg),
                ],
              ),
            ),

            // Sticky primary action stays visible during roster browsing.
            Container(
              padding: const EdgeInsets.fromLTRB(
                SportikaSpacing.md,
                SportikaSpacing.sm,
                SportikaSpacing.md,
                SportikaSpacing.md,
              ),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_sport.label, style: SportikaType.caption),
                      Text(
                        _type == EntryType.pair
                            ? '${_members.length}/1 partner'
                            : '${_members.length} players selected',
                        style: SportikaType.caption.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SportikaSpacing.sm),
                  PrimaryButton(
                    label: 'Create squad',
                    icon: Icons.arrow_forward_rounded,
                    tone: SportikaColors.mint,
                    busy: _saving,
                    onPressed: _saving ? null : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// BRANDED HERO
// -----------------------------------------------------------------------------

class _SquadHero extends StatelessWidget {
  const _SquadHero({required this.sport, required this.type});

  final Sport sport;
  final EntryType type;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 172),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: .30),
            colors.surfaceContainerHighest,
            colors.surface,
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .22)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -38,
            top: -55,
            child: Icon(
              _sportIcon(sport),
              size: 210,
              color: colors.primary.withValues(alpha: .11),
            ),
          ),
          Positioned(
            right: 24,
            bottom: -45,
            child: Icon(
              Icons.shield_outlined,
              size: 155,
              color: colors.onSurface.withValues(alpha: .045),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(SportikaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPORTIKA  /  TEAM BUILDER',
                  style: SportikaType.caption.copyWith(
                    color: colors.primary,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.md),
                Text(
                  'BUILD YOUR\nSQUAD.',
                  style: SportikaType.action.copyWith(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.sm),
                Text(
                  'Your team. Your identity. Your game.',
                  style: SportikaType.caption.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.md),
                Wrap(
                  spacing: SportikaSpacing.sm,
                  children: [
                    _HeroTag(icon: _sportIcon(sport), label: sport.label),
                    _HeroTag(
                      icon: Icons.groups_rounded,
                      label: type == EntryType.pair ? 'Pair' : 'Team',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.primary),
          const SizedBox(width: 5),
          Text(label, style: SportikaType.caption),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SECTION HEADER
// -----------------------------------------------------------------------------

class _BuilderSection extends StatelessWidget {
  const _BuilderSection({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String number;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: SportikaSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(SportikaRadius.sm),
              ),
              child: Text(
                number,
                style: SportikaType.action.copyWith(color: colors.primary),
              ),
            ),
            const SizedBox(width: SportikaSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: SportikaType.bodyStrong.copyWith(fontSize: 17),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: SportikaType.caption.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: SportikaSpacing.md),
        child,
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// SQUAD IDENTITY
// -----------------------------------------------------------------------------

class _SquadIdentity extends StatelessWidget {
  const _SquadIdentity({
    required this.controller,
    required this.sport,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Sport sport;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(SportikaRadius.md),
                ),
                child: Icon(
                  Icons.shield_rounded,
                  size: 37,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final name = controller.text.trim();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Your squad name' : name,
                          style: SportikaType.bodyStrong.copyWith(
                            fontSize: 17,
                            color: name.isEmpty
                                ? colors.onSurfaceVariant
                                : colors.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${sport.label} squad',
                          style: SportikaType.caption,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              labelText: 'Squad name',
              hintText: 'e.g. Karachi Strikers',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SPORT SELECTOR
// -----------------------------------------------------------------------------

class _SportSelector extends StatelessWidget {
  const _SportSelector({required this.selected, required this.onChanged});

  final Sport selected;
  final ValueChanged<Sport> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = SportikaSpacing.sm;
        final itemWidth = (constraints.maxWidth - spacing * 3) / 4;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final sport in Sport.values)
              SizedBox(
                width: itemWidth,
                child: _SportCard(
                  sport: sport,
                  selected: selected == sport,
                  onTap: () => onChanged(sport),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  final Sport sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '${sport.label} sport',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SportikaRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(
              vertical: SportikaSpacing.md,
              horizontal: 3,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: .14)
                  : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(SportikaRadius.md),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: selected ? 1.12 : 1,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(
                    _sportIcon(sport),
                    size: 28,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    sport.label,
                    style: SportikaType.caption.copyWith(
                      color: selected ? colors.primary : colors.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _sportIcon(Sport sport) => switch (sport) {
  Sport.cricket => Icons.sports_cricket_rounded,
  Sport.padel => Icons.sports_tennis_rounded,
  Sport.futsal => Icons.sports_soccer_rounded,
  Sport.badminton => Icons.sports_tennis_rounded,
};

// -----------------------------------------------------------------------------
// FORMAT SELECTOR
// -----------------------------------------------------------------------------

class _FormatSelector extends StatelessWidget {
  const _FormatSelector({required this.selected, required this.onChanged});

  final EntryType selected;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FormatCard(
            title: 'Pair',
            subtitle: 'You + 1 partner',
            icon: Icons.people_alt_rounded,
            selected: selected == EntryType.pair,
            onTap: () => onChanged(EntryType.pair),
          ),
        ),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: _FormatCard(
            title: 'Team',
            subtitle: 'Multiple players',
            icon: Icons.groups_rounded,
            selected: selected == EntryType.team,
            onTap: () => onChanged(EntryType.team),
          ),
        ),
      ],
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SportikaRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(SportikaSpacing.md),
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: .12)
                  : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(SportikaRadius.md),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 24,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    const Spacer(),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 19,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: SportikaSpacing.md),
                Text(title, style: SportikaType.bodyStrong),
                const SizedBox(height: 4),
                Text(subtitle, style: SportikaType.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ROSTER
// -----------------------------------------------------------------------------

class _RosterSummary extends StatelessWidget {
  const _RosterSummary({required this.count, required this.type});

  final int count;
  final EntryType type;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final isPair = type == EntryType.pair;

    return Row(
      children: [
        Icon(Icons.groups_outlined, size: 18, color: colors.primary),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: Text(
            isPair ? 'PARTNER SELECTION' : 'TEAM ROSTER',
            style: SportikaType.action,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SportikaSpacing.sm,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(SportikaRadius.pill),
          ),
          child: Text(
            isPair ? '$count / 1' : '$count selected',
            style: SportikaType.caption.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}

class _EmptyRoster extends StatelessWidget {
  const _EmptyRoster({required this.type});

  final EntryType type;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.person_add_alt_1_rounded, size: 34, color: colors.primary),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            type == EntryType.pair
                ? 'Your partner slot is waiting'
                : 'Your roster starts here',
            style: SportikaType.bodyStrong,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          const Text(
            'Search the community below to add players.',
            style: SportikaType.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SelectedPlayer extends StatelessWidget {
  const _SelectedPlayer({
    super.key,
    required this.account,
    required this.onRemove,
  });

  final Account account;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.all(SportikaSpacing.sm),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: colors.primary.withValues(alpha: .35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconAction(
              icon: Icons.close_rounded,
              label: 'Remove ${account.displayName}',
              size: 17,
              tone: colors.primary,
              onPressed: onRemove,
            ),
          ),
          AccountAvatar(account: account, size: 46),
          const SizedBox(height: SportikaSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              account.displayName,
              style: SportikaType.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'PLAYER',
            style: SportikaType.caption.copyWith(color: colors.primary),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PLAYER DISCOVERY
// -----------------------------------------------------------------------------

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    super.key,
    required this.player,
    required this.disabled,
    required this.onAdd,
  });

  final Account player;
  final bool disabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SportikaSpacing.md,
          vertical: SportikaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(SportikaRadius.md),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: [
            AccountAvatar(account: player, size: 44),
            const SizedBox(width: SportikaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.displayName,
                    style: SportikaType.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          player.city.isEmpty
                              ? 'Location unavailable'
                              : player.city,
                          style: SportikaType.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: SportikaSpacing.sm),
            IconAction(
              icon: disabled
                  ? Icons.lock_outline_rounded
                  : Icons.add_circle_rounded,
              label: disabled
                  ? 'Partner slot full'
                  : 'Add ${player.displayName}',
              size: 25,
              tone: disabled ? colors.onSurfaceVariant : colors.primary,
              onPressed: disabled ? null : onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(color: colors.primary.withValues(alpha: .20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 19),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(child: Text(text, style: SportikaType.caption)),
        ],
      ),
    );
  }
}
