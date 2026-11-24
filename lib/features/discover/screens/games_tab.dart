import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/widgets.dart';

// ============================================================
// SHARED UI
// ============================================================

class _GameSectionHeading extends StatelessWidget {
  const _GameSectionHeading({
    required this.number,
    required this.title,
    this.subtitle,
  });

  final String number;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(SportikaSpacing.sm),
            decoration: BoxDecoration(
              color: SportikaColors.blueSubtle,
              borderRadius: BorderRadius.circular(SportikaRadius.sm),
            ),
            child: Text(
              number,
              style: SportikaType.label.copyWith(
                color: SportikaColors.blueBright,
              ),
            ),
          ),
          const SizedBox(width: SportikaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SportikaType.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(subtitle!, style: SportikaType.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameInfoRow extends StatelessWidget {
  const _GameInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: SportikaIconSize.sm, color: SportikaColors.textMuted),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.caption.copyWith(
              color: SportikaColors.textBody,
            ),
          ),
        ),
      ],
    );
  }
}

class _GameStatusPill extends StatelessWidget {
  const _GameStatusPill({required this.full});

  final bool full;

  @override
  Widget build(BuildContext context) {
    final tone = full ? SportikaColors.gold : SportikaColors.mint;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: SportikaOpacity.muted),
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        border: Border.all(
          color: tone.withValues(alpha: SportikaOpacity.muted),
        ),
      ),
      child: Text(
        full ? 'FULL' : 'OPEN TO JOIN',
        style: SportikaType.micro.copyWith(color: tone),
      ),
    );
  }
}

class _GameCapacity extends StatelessWidget {
  const _GameCapacity({required this.game});

  final CommunityGame game;

  @override
  Widget build(BuildContext context) {
    final count = game.members.length;
    final capacity = game.capacity;
    final remaining = capacity > count ? capacity - count : 0;

    final progress = capacity > 0
        ? (count / capacity).clamp(0.0, 1.0).toDouble()
        : 0.0;

    final tone = game.full ? SportikaColors.gold : SportikaColors.mint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(SportikaRadius.pill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: SportikaSpacing.xs,
            color: tone,
            backgroundColor: SportikaColors.border,
          ),
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Row(
          children: [
            const Icon(
              Icons.groups_outlined,
              size: SportikaIconSize.sm,
              color: SportikaColors.textMuted,
            ),
            const SizedBox(width: SportikaSpacing.xs),
            Expanded(
              child: Text(
                game.full ? 'All spots reserved' : '$remaining spots left',
                style: SportikaType.caption,
              ),
            ),
            Text('$count / $capacity', style: SportikaType.label),
          ],
        ),
      ],
    );
  }
}

class _GameSportBadge extends StatelessWidget {
  const _GameSportBadge({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: SportikaColors.deepest.withValues(alpha: SportikaOpacity.strong),
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(sportGlyph(sport), color: tone, size: SportikaIconSize.sm),
          const SizedBox(width: SportikaSpacing.xs),
          Text(
            sport.label.toUpperCase(),
            style: SportikaType.micro.copyWith(color: SportikaColors.onAccent),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// GAMES DISCOVERY
// ============================================================

class GamesTab extends StatefulWidget {
  const GamesTab({super.key});

  @override
  State<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<GamesTab> {
  Sport? sport;
  int tab = 0;
  String query = '';
  String category = 'All Games';
  bool available = false;
  int? withinDays;
  String status = 'Any';
  String myScope = 'All';

  int get _activeFilters =>
      (withinDays != null ? 1 : 0) +
      (status != 'Any' ? 1 : 0) +
      (available ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    final allGames = context.watch<GamesController>().games;
    final accountId = profile.currentAccount?.id;
    final now = DateTime.now();

    final games = allGames.where((game) {
      final isOrganizer = game.organizerId == accountId;
      final isMember = accountId != null && game.members.contains(accountId);

      if (game.visibility != 'Public' && !isOrganizer && !isMember) {
        return false;
      }

      if (tab == 1 && !isOrganizer && !isMember) {
        return false;
      }

      if (tab == 1 && myScope == 'Organized' && !isOrganizer) {
        return false;
      }

      if (tab == 1 && myScope == 'Joined' && !isMember) {
        return false;
      }

      if (sport != null && game.sport != sport) {
        return false;
      }

      if (category != 'All Games' && game.category != category) {
        return false;
      }

      if (withinDays != null) {
        final end = now.add(Duration(days: withinDays!));
        if (game.at.isBefore(now) || game.at.isAfter(end)) {
          return false;
        }
      }

      if (status == 'Open' && game.full) return false;
      if (status == 'Full' && !game.full) return false;
      if (available && game.full) return false;

      final searchable = '${game.title} ${game.venue} ${game.sport.label}'
          .toLowerCase();

      return searchable.contains(query.trim().toLowerCase());
    }).toList()..sort((a, b) => a.at.compareTo(b.at));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SportikaSpacing.lg,
            SportikaSpacing.md,
            SportikaSpacing.lg,
            SportikaSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilterChipRow<int>(
                label: 'Game list',
                selected: tab,
                onChanged: (value) => setState(() => tab = value),
                choices: const [
                  FilterChoice(0, 'Find Games'),
                  FilterChoice(1, 'My Games'),
                ],
              ),

              if (tab == 1) ...[
                const SizedBox(height: SportikaSpacing.sm),
                FilterChipRow<String>(
                  label: 'My games filter',
                  selected: myScope,
                  onChanged: (value) => setState(() => myScope = value),
                  choices: const [
                    FilterChoice('All', 'All'),
                    FilterChoice('Joined', 'Joined'),
                    FilterChoice('Organized', 'Organized'),
                  ],
                ),
              ],

              const SizedBox(height: SportikaSpacing.md),

              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  hintText: 'Search games or locations',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Advanced filters',
                    onPressed: _showFilters,
                    icon: Icon(
                      Icons.tune_rounded,
                      color: _activeFilters > 0
                          ? SportikaColors.mint
                          : SportikaColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        SportFilterBar(
          selected: sport,
          onChanged: (value) => setState(() => sport = value),
        ),

        SizedBox(
          height: SportikaSpacing.xxl * 1.5,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: SportikaSpacing.lg),
            children: [
              for (final value in const [
                'All Games',
                'Friendly',
                'League',
                'Tournament',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: SportikaSpacing.sm),
                  child: ChoiceChip(
                    label: Text(value),
                    selected: category == value,
                    onSelected: (_) => setState(() => category = value),
                  ),
                ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            SportikaSpacing.lg,
            SportikaSpacing.sm,
            SportikaSpacing.lg,
            SportikaSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tab == 0 ? 'Available games' : 'My games',
                  style: SportikaType.titleMedium,
                ),
              ),
              Text('${games.length} found', style: SportikaType.caption),
            ],
          ),
        ),

        Expanded(
          child: games.isEmpty
              ? EmptyState(
                  title: 'No games found',
                  body:
                      _activeFilters > 0 ||
                          sport != null ||
                          query.isNotEmpty ||
                          category != 'All Games'
                      ? 'Try adjusting your filters or search.'
                      : 'There are no games to show yet.',
                  icon: Icons.sports_outlined,
                )
              : ListView.separated(
                  key: PageStorageKey<String>('sportika-games-$tab'),
                  padding: const EdgeInsets.fromLTRB(
                    SportikaSpacing.lg,
                    0,
                    SportikaSpacing.lg,
                    SportikaSpacing.xl,
                  ),
                  itemCount: games.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: SportikaSpacing.md),
                  itemBuilder: (context, index) => GameCard(game: games[index]),
                ),
        ),
      ],
    );
  }

  Future<void> _showFilters() async {
    var draftDays = withinDays;
    var draftStatus = status;
    var draftAvailable = available;

    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SportikaColors.surfaceElevated,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SportikaRadius.xl),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              SportikaSpacing.lg,
              SportikaSpacing.lg,
              SportikaSpacing.lg,
              MediaQuery.viewInsetsOf(context).bottom + SportikaSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter games', style: SportikaType.titleMedium),
                  const SizedBox(height: SportikaSpacing.lg),

                  const Text('DATE', style: SportikaType.label),
                  const SizedBox(height: SportikaSpacing.sm),
                  Wrap(
                    spacing: SportikaSpacing.sm,
                    children: [
                      for (final days in const [0, 7, 30])
                        ChoiceChip(
                          label: Text(
                            days == 0 ? 'Any date' : 'Next $days days',
                          ),
                          selected: (draftDays ?? 0) == days,
                          onSelected: (_) =>
                              update(() => draftDays = days == 0 ? null : days),
                        ),
                    ],
                  ),

                  const SizedBox(height: SportikaSpacing.lg),

                  const Text('AVAILABILITY', style: SportikaType.label),
                  const SizedBox(height: SportikaSpacing.sm),
                  Wrap(
                    spacing: SportikaSpacing.sm,
                    children: [
                      for (final value in const ['Any', 'Open', 'Full'])
                        ChoiceChip(
                          label: Text(value),
                          selected: draftStatus == value,
                          onSelected: (_) => update(() => draftStatus = value),
                        ),
                    ],
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Available slots only',
                      style: SportikaType.bodyStrong,
                    ),
                    value: draftAvailable,
                    activeTrackColor: SportikaColors.mint,
                    onChanged: (value) => update(() => draftAvailable = value),
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: const Text('Show games'),
                    ),
                  ),

                  Center(
                    child: TextButton(
                      onPressed: () => update(() {
                        draftDays = null;
                        draftStatus = 'Any';
                        draftAvailable = false;
                      }),
                      child: const Text('Reset filters'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || apply != true) return;

    setState(() {
      withinDays = draftDays;
      status = draftStatus;
      available = draftAvailable;
    });
  }
}

// ============================================================
// PREMIUM GAME CARD
// ============================================================

class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.game, this.openable = true});

  final CommunityGame game;
  final bool openable;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openable
            ? () => pushRoute(
                context,
                AppRoute.gameDetail,
                args: GameDetailArgs(game),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: SportikaSpacing.xxl * 3.2,
                    height: SportikaSpacing.xxl * 3.6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        SportikaRadius.thumbnail,
                      ),
                      child: SportPhoto(
                        sport: game.sport,
                        height: SportikaSpacing.xxl * 3.6,
                        radius: 0,
                      ),
                    ),
                  ),

                  const SizedBox(width: SportikaSpacing.md),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          game.sport.label.toUpperCase(),
                          style: SportikaType.micro.copyWith(
                            color: sportColor(game.sport),
                          ),
                        ),

                        const SizedBox(height: SportikaSpacing.xs),

                        Text(
                          game.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SportikaType.cardTitle,
                        ),

                        const SizedBox(height: SportikaSpacing.sm),

                        _GameInfoRow(
                          icon: Icons.calendar_today_outlined,
                          text: '${dayLabel(game.at)} · ${timeLabel(game.at)}',
                        ),

                        const SizedBox(height: SportikaSpacing.xs),

                        _GameInfoRow(
                          icon: Icons.location_on_outlined,
                          text: game.venue,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: SportikaSpacing.md),

              Row(
                children: [
                  _GameStatusPill(full: game.full),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: Text(
                      '${game.category} · ${game.format}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: SportikaType.caption,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: SportikaSpacing.md),

              _GameCapacity(game: game),

              if (openable) ...[
                const SizedBox(height: SportikaSpacing.md),
                const Divider(color: SportikaColors.borderSubtle),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'View game',
                      style: SportikaType.label.copyWith(
                        color: SportikaColors.mint,
                      ),
                    ),
                    const SizedBox(width: SportikaSpacing.xs),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: SportikaIconSize.sm,
                      color: SportikaColors.mint,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ROSTER MEMBER
// ============================================================

class _GameMemberTile extends StatelessWidget {
  const _GameMemberTile({
    required this.accountId,
    required this.index,
    required this.isOrganizer,
  });

  final String accountId;
  final int index;
  final bool isOrganizer;

  @override
  Widget build(BuildContext context) {
    final account = context.watch<SessionController>().accountById(accountId);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: account == null
          ? const BrandedDefaultAvatar(size: 40)
          : AccountAvatar(account: account, size: 40),
      title: Text(
        account?.displayName ?? 'Sportika player',
        style: SportikaType.bodyStrong,
      ),
      subtitle: Text(
        isOrganizer ? 'Organizer' : 'Confirmed player',
        style: SportikaType.caption,
      ),
      trailing: isOrganizer
          ? const Icon(Icons.verified_outlined, color: SportikaColors.mint)
          : null,
    );
  }
}

// ============================================================
// GAME DETAIL SCREEN
// ============================================================

class GameDetailScreen extends StatelessWidget {
  const GameDetailScreen({super.key, required this.game});

  final CommunityGame game;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    final controller = context.watch<GamesController>();

    // Resolve the latest game instead of relying on
    // the navigation-time snapshot.
    final matches = controller.games.where((item) => item.id == game.id);

    final current = matches.isNotEmpty ? matches.first : game;

    final accountId = profile.currentAccount?.id;

    final joined = accountId != null && current.members.contains(accountId);

    final organizer = context.watch<SessionController>().accountById(
      current.organizerId,
    );

    final canJoin = accountId != null && (joined || !current.full);

    return Scaffold(
      appBar: sportikaAppBar('Game details', subtitle: current.sport.label),

      body: ListView(
        padding: const EdgeInsets.only(bottom: SportikaSpacing.xxl),
        children: [
          // ----------------------------------------------------
          // CINEMATIC COVER
          // ----------------------------------------------------

          SizedBox(
            height: SportikaSpacing.xxl * 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SportPhoto(
                  sport: current.sport,
                  height: SportikaSpacing.xxl * 6,
                  radius: 0,
                ),

                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: SportikaGradients.imageFadeStrong,
                  ),
                ),

                Positioned(
                  left: SportikaSpacing.lg,
                  right: SportikaSpacing.lg,
                  bottom: SportikaSpacing.lg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GameSportBadge(sport: current.sport),

                      const SizedBox(height: SportikaSpacing.sm),

                      Text(
                        current.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.hero.copyWith(
                          color: SportikaColors.onAccent,
                        ),
                      ),

                      const SizedBox(height: SportikaSpacing.sm),

                      _GameStatusPill(full: current.full),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(SportikaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ----------------------------------------------
                // ESSENTIALS
                // ----------------------------------------------

                const _GameSectionHeading(
                  number: '01',
                  title: 'Match essentials',
                ),

                SurfaceCard(
                  child: Column(
                    children: [
                      _GameInfoRow(
                        icon: Icons.calendar_today_outlined,
                        text:
                            '${dayLabel(current.at)} · ${timeLabel(current.at)}',
                      ),
                      const SizedBox(height: SportikaSpacing.md),
                      _GameInfoRow(
                        icon: Icons.location_on_outlined,
                        text: current.venue,
                      ),
                      const SizedBox(height: SportikaSpacing.md),
                      _GameInfoRow(
                        icon: Icons.sports_outlined,
                        text: '${current.category} · ${current.format}',
                      ),
                      const SizedBox(height: SportikaSpacing.md),
                      _GameInfoRow(
                        icon: Icons.visibility_outlined,
                        text: current.visibility,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: SportikaSpacing.xl),

                // ----------------------------------------------
                // CAPACITY
                // ----------------------------------------------
                _GameSectionHeading(
                  number: '02',
                  title: 'Player availability',
                  subtitle: '${current.members.length} confirmed participants',
                ),

                SurfaceCard(child: _GameCapacity(game: current)),

                const SizedBox(height: SportikaSpacing.xl),

                // ----------------------------------------------
                // ORGANIZER
                // ----------------------------------------------
                const _GameSectionHeading(number: '03', title: 'Organizer'),

                SurfaceCard(
                  child: Row(
                    children: [
                      organizer == null
                          ? const BrandedDefaultAvatar(size: 44)
                          : AccountAvatar(account: organizer, size: 44),
                      const SizedBox(width: SportikaSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              organizer?.displayName ?? 'Sportika community',
                              style: SportikaType.bodyStrong,
                            ),
                            const Text(
                              'Match organizer',
                              style: SportikaType.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: SportikaSpacing.xl),

                // ----------------------------------------------
                // DESCRIPTION
                // ----------------------------------------------
                const _GameSectionHeading(
                  number: '04',
                  title: 'Match overview',
                ),

                Text(
                  current.description.trim().isEmpty
                      ? 'No additional match details provided.'
                      : current.description,
                  style: SportikaType.bodyStrong,
                ),

                const SizedBox(height: SportikaSpacing.xl),

                // ----------------------------------------------
                // ROSTER
                // ----------------------------------------------
                _GameSectionHeading(
                  number: '05',
                  title: 'Confirmed players',
                  subtitle:
                      '${current.members.length} / ${current.capacity} players',
                ),

                SurfaceCard(
                  child: Column(
                    children: [
                      for (final (index, memberId) in current.members.indexed)
                        _GameMemberTile(
                          accountId: memberId,
                          index: index,
                          isOrganizer: memberId == current.organizerId,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // --------------------------------------------------------
      // STICKY JOIN ACTION
      // --------------------------------------------------------
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(SportikaSpacing.lg),
          decoration: const BoxDecoration(
            color: SportikaColors.surface,
            border: Border(top: BorderSide(color: SportikaColors.borderSubtle)),
          ),
          child: FilledButton.icon(
            onPressed: !canJoin
                ? null
                : () {
                    controller.toggleGameJoin(current);

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          joined
                              ? 'You left the match.'
                              : 'Your spot is confirmed.',
                        ),
                      ),
                    );
                  },
            icon: Icon(joined ? Icons.logout_rounded : Icons.sports_rounded),
            label: Text(
              joined
                  ? 'Leave match'
                  : current.full
                  ? 'Match full'
                  : 'Join match',
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CREATE GAME SCREEN
// ============================================================

class CreateGameScreen extends StatefulWidget {
  const CreateGameScreen({super.key});

  @override
  State<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends State<CreateGameScreen> {
  final keyForm = GlobalKey<FormState>();

  final title = TextEditingController();
  final venue = TextEditingController();
  final capacity = TextEditingController(text: '22');
  final description = TextEditingController();

  Sport sport = Sport.cricket;
  String? format;
  String visibility = 'Public';

  DateTime date = DateTime.now().add(const Duration(days: 1));

  bool publishing = false;

  @override
  void dispose() {
    title.dispose();
    venue.dispose();
    capacity.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: sportikaAppBar('Create game', subtitle: 'Sportika community'),

      body: Form(
        key: keyForm,
        child: ListView(
          padding: const EdgeInsets.only(bottom: SportikaSpacing.xxl),
          children: [
            // --------------------------------------------------
            // CINEMATIC HERO
            // --------------------------------------------------

            SizedBox(
              height: SportikaSpacing.xxl * 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SportPhoto(
                    sport: sport,
                    height: SportikaSpacing.xxl * 5,
                    radius: 0,
                  ),

                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: SportikaGradients.imageFadeStrong,
                    ),
                  ),

                  Positioned(
                    left: SportikaSpacing.lg,
                    right: SportikaSpacing.lg,
                    bottom: SportikaSpacing.lg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SPORTIKA / CREATE',
                          style: SportikaType.micro.copyWith(
                            color: SportikaColors.mint,
                          ),
                        ),
                        const SizedBox(height: SportikaSpacing.sm),
                        Text(
                          'Bring your people.\nMake a match.',
                          style: SportikaType.hero.copyWith(
                            color: SportikaColors.onAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(SportikaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --------------------------------------------
                  // SPORT & FORMAT
                  // --------------------------------------------

                  const _GameSectionHeading(
                    number: '01',
                    title: 'Sport & format',
                    subtitle: 'Choose the sport and match rules.',
                  ),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final gap = SportikaSpacing.sm;
                      final width = (constraints.maxWidth - gap) / 2;

                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final item in Sport.values)
                            SizedBox(
                              width: width,
                              child: _CreateSportTile(
                                sport: item,
                                selected: sport == item,
                                onTap: () => setState(() {
                                  sport = item;
                                  format = null;

                                  capacity.text = const [
                                    '22',
                                    '4',
                                    '10',
                                    '4',
                                  ][item.index];
                                }),
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  DropdownButtonFormField<String>(
                    key: ValueKey(sport),
                    initialValue:
                        format ?? SportEngines.formatsFor(sport).first,
                    decoration: const InputDecoration(
                      labelText: 'Match format',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    items: SportEngines.formatsFor(sport)
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => format = value),
                  ),

                  const SizedBox(height: SportikaSpacing.xl),

                  // --------------------------------------------
                  // GAME IDENTITY
                  // --------------------------------------------
                  const _GameSectionHeading(
                    number: '02',
                    title: 'Game identity',
                    subtitle: 'Help players recognize your game.',
                  ),

                  TextFormField(
                    controller: title,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Match title',
                      prefixIcon: Icon(Icons.edit_note_outlined),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 4
                        ? 'Enter at least 4 characters'
                        : null,
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  TextFormField(
                    controller: venue,
                    decoration: const InputDecoration(
                      labelText: 'Location / facility',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter a location'
                        : null,
                  ),

                  const SizedBox(height: SportikaSpacing.xl),

                  // --------------------------------------------
                  // SCHEDULE & CAPACITY
                  // --------------------------------------------
                  const _GameSectionHeading(
                    number: '03',
                    title: 'Schedule & players',
                    subtitle: 'Choose when and how many can join.',
                  ),

                  SurfaceCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.calendar_month_outlined,
                        color: SportikaColors.blueBright,
                      ),
                      title: const Text(
                        'Match date & time',
                        style: SportikaType.bodyStrong,
                      ),
                      subtitle: Text(
                        '${dayLabel(date)} · ${timeLabel(date)}',
                        style: SportikaType.caption,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _pickDate,
                    ),
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  TextFormField(
                    controller: capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Participant capacity',
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    validator: (value) {
                      final count = int.tryParse(value ?? '') ?? 0;

                      if (count < 2 || count > 100) {
                        return 'Choose 2 to 100 players';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: SportikaSpacing.xl),

                  // --------------------------------------------
                  // GAME SETTINGS
                  // --------------------------------------------
                  const _GameSectionHeading(
                    number: '04',
                    title: 'Game settings',
                    subtitle: 'Add rules and choose visibility.',
                  ),

                  TextFormField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description and rules',
                      alignLabelWithHint: true,
                    ),
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  DropdownButtonFormField<String>(
                    initialValue: visibility,
                    decoration: const InputDecoration(
                      labelText: 'Visibility',
                      prefixIcon: Icon(Icons.visibility_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Public', child: Text('Public')),
                      DropdownMenuItem(
                        value: 'Private',
                        child: Text('Private'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => visibility = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // --------------------------------------------------------
      // STICKY PUBLISH ACTION
      // --------------------------------------------------------
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(SportikaSpacing.lg),
          decoration: const BoxDecoration(
            color: SportikaColors.surface,
            border: Border(top: BorderSide(color: SportikaColors.borderSubtle)),
          ),
          child: FilledButton.icon(
            onPressed: publishing ? null : _publish,
            icon: publishing
                ? const SizedBox(
                    width: SportikaIconSize.sm,
                    height: SportikaIconSize.sm,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.campaign_outlined),
            label: Text(publishing ? 'Publishing...' : 'Publish game'),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
    );

    if (time == null || !mounted) return;

    setState(() {
      date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _publish() async {
    if (publishing) return;

    if (!keyForm.currentState!.validate()) return;

    if (!date.isAfter(DateTime.now())) {
      showSnack(context, 'Choose a future date and time.', error: true);
      return;
    }

    final account = context.read<ProfileController>().currentAccount;

    if (account == null) {
      showSnack(context, 'Sign in to publish a game.', error: true);
      return;
    }

    setState(() => publishing = true);

    try {
      context.read<GamesController>().publishGame(
        CommunityGame(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title.text.trim(),
          sport: sport,
          venue: venue.text.trim(),
          at: date,
          capacity: int.parse(capacity.text),
          organizerId: account.id,
          description: description.text.trim(),
          visibility: visibility,
          members: [account.id],
          format: format ?? SportEngines.formatsFor(sport).first,
        ),
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      // The previous screen can react to the successful
      // publication through its controller listener.
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'Could not publish the game. Try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => publishing = false);
      }
    }
  }
}

// ============================================================
// SPORT SELECTION TILE
// ============================================================

class _CreateSportTile extends StatelessWidget {
  const _CreateSportTile({
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  final Sport sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);

    return Material(
      color: selected ? SportikaColors.blueSubtle : SportikaColors.surface,
      borderRadius: BorderRadius.circular(SportikaRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.card),
        child: Container(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.card),
            border: Border.all(color: selected ? tone : SportikaColors.border),
          ),
          child: Column(
            children: [
              Icon(sportGlyph(sport), color: tone, size: SportikaIconSize.lg),
              const SizedBox(height: SportikaSpacing.sm),
              Text(sport.label, style: SportikaType.bodyStrong),
              if (selected) ...[
                const SizedBox(height: SportikaSpacing.xs),
                Icon(
                  Icons.check_circle_rounded,
                  color: tone,
                  size: SportikaIconSize.sm,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
