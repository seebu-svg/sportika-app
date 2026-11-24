import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Premium player identity screen.
///
/// Frontend-only redesign:
/// - Athlete Passport hero
/// - Verified performance statistics
/// - Sport identity tiles
/// - Team membership cards
/// - Recent official fixtures
///
/// Uses existing Sportika theme, controllers and routes.
class PlayerProfileScreen extends StatelessWidget {
  const PlayerProfileScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context) {
    final account = context.watch<SessionController>().accountById(accountId);

    if (account == null) {
      return ScreenScaffold(
        title: 'Player',
        child: ErrorState(
          title: 'Player not found',
          message: 'This account is no longer part of the community.',
          retryLabel: 'Go back',
          onRetry: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    final profile = context.watch<ProfileController>();
    final teamsController = context.watch<TeamsController>();
    final tournaments = context.watch<TournamentsController>();

    final teams = teamsController.squadsOf(account.id);
    final sports = profile.sportsPlayedBy(account.id);

    // Copy before sorting so controller-owned data is not mutated.
    final appearances = [...profile.appearancesOf(account.id)]
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

    final entryIds = tournaments.entries
        .where((entry) => entry.memberAccountIds.contains(account.id))
        .map((entry) => entry.id)
        .toSet();

    // Count only published results where the player's
    // actual tournament entry belongs to a fixture side.
    //
    // Never assume a player is on the away side simply
    // because they are not on the home side.
    var played = 0;
    var wins = 0;
    var losses = 0;
    var draws = 0;

    for (final fixture in appearances) {
      final result = fixture.result;
      if (result == null) continue;

      final isHome = entryIds.contains(fixture.home.entryId);
      final isAway = entryIds.contains(fixture.away.entryId);

      // Skip ambiguous or unmatched fixtures.
      if (isHome == isAway) continue;

      played++;

      if (result.winnerIndex < 0) {
        draws++;
      } else {
        final playerSide = isHome ? 0 : 1;

        if (result.winnerIndex == playerSide) {
          wins++;
        } else {
          losses++;
        }
      }
    }

    return ScreenScaffold(
      title: 'Athlete Passport',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==================================================
          // ATHLETE IDENTITY HERO
          // ==================================================

          _AthletePassportHero(
            accountName: account.displayName,
            handle: account.handle,
            city: account.city,
            bio: account.bio,
            avatar: AccountAvatar(account: account, size: 88),
          ),

          const SizedBox(height: SportikaSpacing.lg),

          // ==================================================
          // CAREER RECORD
          // ==================================================
          const _ProfileSectionHeading(
            title: 'Career record',
            subtitle: 'Official published results',
            icon: Icons.query_stats_outlined,
          ),

          const SizedBox(height: SportikaSpacing.md),

          _AthleteRecordStrip(
            played: played,
            wins: wins,
            losses: losses,
            draws: draws,
          ),

          const SizedBox(height: SportikaSpacing.xl),

          // ==================================================
          // SPORTS IDENTITY
          // ==================================================
          _ProfileSectionHeading(
            title: 'Sports identity',
            subtitle: sports.isEmpty
                ? 'No sports recorded'
                : '${sports.length} sports',
            icon: Icons.sports_outlined,
          ),

          const SizedBox(height: SportikaSpacing.md),

          if (sports.isEmpty)
            const _ProfileCompactEmpty(
              icon: Icons.sports_outlined,
              title: 'No sports yet',
              description: 'This athlete has not selected a sport.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 600 ? 3 : 2;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sports.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: SportikaSpacing.sm,
                    mainAxisSpacing: SportikaSpacing.sm,
                    childAspectRatio: 1.35,
                  ),
                  itemBuilder: (context, index) {
                    return _AthleteSportCard(sport: sports[index]);
                  },
                );
              },
            ),

          const SizedBox(height: SportikaSpacing.xl),

          // ==================================================
          // TEAMS & SQUADS
          // ==================================================
          _ProfileSectionHeading(
            title: 'Teams & squads',
            subtitle: teams.isEmpty
                ? 'No team memberships'
                : '${teams.length} memberships',
            icon: Icons.groups_outlined,
          ),

          const SizedBox(height: SportikaSpacing.md),

          if (teams.isEmpty)
            const _ProfileCompactEmpty(
              icon: Icons.groups_outlined,
              title: 'No squads yet',
              description: 'Team and pair memberships will appear here.',
            )
          else
            for (final team in teams) ...[
              SurfaceCard(
                onTap: () => pushRoute(
                  context,
                  AppRoute.teamDetail,
                  args: TeamDetailArgs(team.id),
                ),
                child: Row(
                  children: [
                    _TeamSportIdentity(sport: team.sport),

                    const SizedBox(width: SportikaSpacing.md),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SportikaType.bodyStrong,
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '${team.sport.label} · '
                            '${team.size} players',
                            style: SportikaType.caption,
                          ),

                          if (team.ownerId == account.id) ...[
                            const SizedBox(height: SportikaSpacing.sm),
                            const StatusPill(
                              'Captain',
                              color: SportikaColors.gold,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: SportikaSpacing.sm),

                    const Icon(
                      Icons.chevron_right_rounded,
                      color: SportikaColors.textMuted,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: SportikaSpacing.sm),
            ],

          const SizedBox(height: SportikaSpacing.xl),

          // ==================================================
          // RECENT OFFICIAL MATCHES
          // ==================================================
          _ProfileSectionHeading(
            title: 'Recent matches',
            subtitle: appearances.isEmpty
                ? 'Official match history'
                : '${appearances.length} official fixtures',
            icon: Icons.history_outlined,
          ),

          const SizedBox(height: SportikaSpacing.md),

          if (appearances.isEmpty)
            const _ProfileCompactEmpty(
              icon: Icons.sports_score_outlined,
              title: 'No official matches',
              description:
                  'This athlete has no official fixture '
                  'appearances yet.',
            )
          else
            for (final fixture in appearances.take(5)) ...[
              officialFixtureTile(
                context,
                fixture,
                onTap: () => pushRoute(
                  context,
                  AppRoute.fixtureDetail,
                  args: FixtureDetailArgs(fixture.id),
                ),
              ),

              const SizedBox(height: SportikaSpacing.sm),
            ],

          if (appearances.length > 5) ...[
            const SizedBox(height: SportikaSpacing.sm),

            const Text(
              'Showing the 5 most recent fixtures',
              style: SportikaType.caption,
            ),
          ],

          const SizedBox(height: SportikaSpacing.xxl),
        ],
      ),
    );
  }
}

// ============================================================
// ATHLETE PASSPORT HERO
// ============================================================

class _AthletePassportHero extends StatelessWidget {
  const _AthletePassportHero({
    required this.accountName,
    required this.handle,
    required this.city,
    required this.bio,
    required this.avatar,
  });

  final String accountName;
  final String handle;
  final String city;
  final String bio;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SportikaRadius.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SportikaColors.cardSurface,
          border: Border.all(color: SportikaColors.borderSubtle),
          borderRadius: BorderRadius.circular(SportikaRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----------------------------------------------
            // ART-DIRECTED PASSPORT COVER
            // ----------------------------------------------

            SizedBox(
              height: 132,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          SportikaColors.blueBright.withValues(alpha: 0.35),
                          SportikaColors.cardSurface,
                          SportikaColors.mint.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),

                  Positioned(
                    right: -30,
                    top: -45,
                    child: Icon(
                      Icons.sports_outlined,
                      size: 190,
                      color: SportikaColors.mint.withValues(alpha: 0.10),
                    ),
                  ),

                  Positioned(
                    right: 18,
                    bottom: 12,
                    child: Icon(
                      Icons.bolt_rounded,
                      size: 68,
                      color: SportikaColors.blueBright.withValues(alpha: 0.24),
                    ),
                  ),

                  Positioned(
                    left: SportikaSpacing.lg,
                    top: SportikaSpacing.lg,
                    child: Text(
                      'SPORTIKA / ATHLETE',
                      style: SportikaType.caption.copyWith(
                        color: SportikaColors.text,
                        fontWeight: SportikaFontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),

                  Positioned(
                    left: SportikaSpacing.lg,
                    bottom: SportikaSpacing.lg,
                    child: Text(
                      'ATHLETE\nPASSPORT',
                      style: SportikaType.title.copyWith(
                        height: 0.95,
                        fontWeight: SportikaFontWeight.extraBold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ----------------------------------------------
            // PLAYER IDENTITY
            // ----------------------------------------------
            Padding(
              padding: const EdgeInsets.all(SportikaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: SportikaColors.mint,
                            width: 2,
                          ),
                        ),
                        child: avatar,
                      ),

                      const SizedBox(width: SportikaSpacing.md),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accountName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SportikaType.title,
                            ),

                            if (handle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('@$handle', style: SportikaType.caption),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: SportikaSpacing.md),

                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: SportikaSpacing.md,
                    runSpacing: SportikaSpacing.sm,
                    children: [
                      const StatusPill(
                        'Sportika member',
                        color: SportikaColors.blueBright,
                      ),

                      if (city.trim().isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: SportikaColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(city, style: SportikaType.caption),
                          ],
                        ),
                    ],
                  ),

                  if (bio.trim().isNotEmpty) ...[
                    const SizedBox(height: SportikaSpacing.md),

                    Text(bio, style: SportikaType.body),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// OFFICIAL CAREER RECORD
// ============================================================

class _AthleteRecordStrip extends StatelessWidget {
  const _AthleteRecordStrip({
    required this.played,
    required this.wins,
    required this.losses,
    required this.draws,
  });

  final int played;
  final int wins;
  final int losses;
  final int draws;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _RecordMetric(
                value: '$played',
                label: 'Played',
                icon: Icons.sports_score_outlined,
                tone: SportikaColors.blueBright,
              ),
            ),

            const SizedBox(width: SportikaSpacing.sm),

            Expanded(
              child: _RecordMetric(
                value: '$wins',
                label: 'Wins',
                icon: Icons.emoji_events_outlined,
                tone: SportikaColors.mint,
              ),
            ),

            const SizedBox(width: SportikaSpacing.sm),

            Expanded(
              child: _RecordMetric(
                value: '$losses',
                label: 'Losses',
                icon: Icons.trending_down_outlined,
                tone: SportikaColors.textMuted,
              ),
            ),
          ],
        ),

        if (draws > 0) ...[
          const SizedBox(height: SportikaSpacing.sm),

          Row(
            children: [
              const Icon(
                Icons.balance_outlined,
                size: 16,
                color: SportikaColors.gold,
              ),

              const SizedBox(width: 6),

              Text(
                '$draws drawn ${draws == 1 ? 'match' : 'matches'}',
                style: SportikaType.caption,
              ),
            ],
          ),
        ],

        if (played > 0) ...[
          const SizedBox(height: SportikaSpacing.md),

          _WinRateIndicator(wins: wins, played: played),
        ],
      ],
    );
  }
}

class _RecordMetric extends StatelessWidget {
  const _RecordMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tone),

          const SizedBox(height: SportikaSpacing.md),

          Text(
            value,
            style: SportikaType.title.copyWith(
              color: tone,
              fontWeight: SportikaFontWeight.extraBold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.caption,
          ),
        ],
      ),
    );
  }
}

class _WinRateIndicator extends StatelessWidget {
  const _WinRateIndicator({required this.wins, required this.played});

  final int wins;
  final int played;

  @override
  Widget build(BuildContext context) {
    final rate = played == 0 ? 0.0 : wins / played;
    final percentage = (rate * 100).round();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Official win rate', style: SportikaType.bodyStrong),

              const Spacer(),

              Text(
                '$percentage%',
                style: SportikaType.bodyStrong.copyWith(
                  color: SportikaColors.mint,
                ),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 7,
              backgroundColor: SportikaColors.borderSubtle,
              valueColor: const AlwaysStoppedAnimation<Color>(
                SportikaColors.mint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SPORTS IDENTITY CARD
// ============================================================

class _AthleteSportCard extends StatelessWidget {
  const _AthleteSportCard({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);

    return ClipRRect(
      borderRadius: BorderRadius.circular(SportikaRadius.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SportikaColors.cardSurface,
          border: Border.all(color: SportikaColors.borderSubtle),
          borderRadius: BorderRadius.circular(SportikaRadius.card),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tone.withValues(alpha: 0.28),
                    SportikaColors.cardSurface,
                  ],
                ),
              ),
            ),

            Positioned(
              right: -12,
              top: -10,
              child: Icon(
                sportGlyph(sport),
                size: 100,
                color: tone.withValues(alpha: 0.14),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(SportikaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(sportGlyph(sport), color: tone, size: 26),

                  Text(
                    sport.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.bodyStrong,
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

// ============================================================
// TEAM SPORT IDENTITY
// ============================================================

class _TeamSportIdentity extends StatelessWidget {
  const _TeamSportIdentity({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SportikaRadius.card),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Icon(sportGlyph(sport), color: tone, size: 25),
    );
  }
}

// ============================================================
// SECTION HEADING
// ============================================================

class _ProfileSectionHeading extends StatelessWidget {
  const _ProfileSectionHeading({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: SportikaColors.mint, size: 22),

        const SizedBox(width: SportikaSpacing.sm),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SportikaType.title),

              const SizedBox(height: 4),

              Text(subtitle, style: SportikaType.caption),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// COMPACT EMPTY STATE
// ============================================================

class _ProfileCompactEmpty extends StatelessWidget {
  const _ProfileCompactEmpty({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SportikaColors.textMuted, size: 24),

          const SizedBox(width: SportikaSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SportikaType.bodyStrong),

                const SizedBox(height: 4),

                Text(description, style: SportikaType.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
