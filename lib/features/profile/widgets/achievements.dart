import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/profile/widgets/passport_section.dart';
import 'package:sportika/features/profile/widgets/sporting_record.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The collectible identity of a milestone. Each kind maps to its own 3D medal
/// asset so no two milestones share a silhouette.
enum MedalKind {
  firstWhistle('first_whistle'),
  firstVictory('first_victory'),
  hatTrick('hat_trick'),
  squadBuilder('squad_builder'),
  entryList('entry_list'),
  multiSport('multi_sport'),
  seasonRegular('season_regular');

  const MedalKind(this.asset);
  final String asset;
}

/// A milestone with the evidence that unlocked it. [current] and [target] are
/// the real counts the record can prove, so a medal never claims more than the
/// athlete has actually done. [progress] only matters while the medal is locked.
@immutable
class Achievement {
  const Achievement({
    required this.title,
    required this.description,
    required this.kind,
    required this.current,
    required this.target,
    required this.unit,
    required this.unlocked,
  });

  final String title;
  final String description;
  final MedalKind kind;
  final int current;
  final int target;
  final String unit;
  final bool unlocked;

  double get progress => (current / target).clamp(0.0, 1.0).toDouble();

  String get assetPath => 'assets/images/medals/${kind.asset}.webp';

  /// A readout that matches the real count: "2 of 3 wins" while locked, and
  /// "4 official matches logged" once earned.
  String get progressLabel => unlocked
      ? '$current ${_unit(current)} logged'
      : '$current of $target ${_unit(target)}';

  String _unit(int n) => n == 1 ? unit : _plural(unit);

  static String _plural(String word) => switch (word) {
    'win' => 'wins',
    'official match' => 'official matches',
    'official win' => 'official wins',
    'team' => 'teams',
    'tournament' => 'tournaments',
    'sport' => 'sports',
    _ => '${word}s',
  };
}

/// Data-derived achievements. Nothing here is stored: every medal is recomputed
/// from the same official records the rest of the passport shows, so the list
/// cannot drift away from the profile. Personal, self-scored cards are not a
/// milestone - only provable official play is.
List<Achievement> achievementsFrom({
  required List<Fixture> official,
  required int wins,
  required int squadsLed,
  required int tournamentsEntered,
  required Set<Sport> sports,
}) {
  final played = official.length;
  return [
    Achievement(
      title: 'First whistle',
      description: 'Play your first official match',
      kind: MedalKind.firstWhistle,
      current: played,
      target: 1,
      unit: 'official match',
      unlocked: played >= 1,
    ),
    Achievement(
      title: 'Off the mark',
      description: 'Win your first official match',
      kind: MedalKind.firstVictory,
      current: wins,
      target: 1,
      unit: 'official win',
      unlocked: wins >= 1,
    ),
    Achievement(
      title: 'Hat-trick',
      description: 'Win three official matches',
      kind: MedalKind.hatTrick,
      current: wins,
      target: 3,
      unit: 'win',
      unlocked: wins >= 3,
    ),
    Achievement(
      title: 'Squad builder',
      description: 'Lead a team or pair',
      kind: MedalKind.squadBuilder,
      current: squadsLed,
      target: 1,
      unit: 'team',
      unlocked: squadsLed >= 1,
    ),
    Achievement(
      title: 'On the entry list',
      description: 'Enter a tournament',
      kind: MedalKind.entryList,
      current: tournamentsEntered,
      target: 1,
      unit: 'tournament',
      unlocked: tournamentsEntered >= 1,
    ),
    Achievement(
      title: 'Multi-sport',
      description: 'Play three different sports',
      kind: MedalKind.multiSport,
      current: sports.length,
      target: 3,
      unit: 'sport',
      unlocked: sports.length >= 3,
    ),
    Achievement(
      title: 'Season regular',
      description: 'Play five official matches',
      kind: MedalKind.seasonRegular,
      current: played,
      target: 5,
      unit: 'official match',
      unlocked: played >= 5,
    ),
  ];
}

/// The locked milestone the athlete is closest to, by real progress. Ties break
/// toward the smaller target so an almost-there single win beats a distant five.
Achievement? nextAchievement(List<Achievement> all) {
  final locked = all.where((a) => !a.unlocked).toList();
  if (locked.isEmpty) return null;
  locked.sort((a, b) {
    final byProgress = b.progress.compareTo(a.progress);
    if (byProgress != 0) return byProgress;
    return a.target.compareTo(b.target);
  });
  return locked.first;
}

/// Only the milestones the member has actually earned, shown as collectible
/// medals, plus the one they are closest to. A medal that cannot be proved from
/// a real record is never drawn unlocked.
class PassportAchievements extends StatelessWidget {
  const PassportAchievements({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<ProfileController>().currentAccount;
    if (me == null) return const SizedBox.shrink();

    final entries = context.watch<TournamentsController>().entries;
    final myEntryIds = entries
        .where((entry) => entry.memberAccountIds.contains(me.id))
        .map((entry) => entry.id)
        .toSet();
    final fixtures = context.watch<FixturesController>();
    final record = sportingRecordOf(
      fixtures: fixtures.fixtures,
      myEntryIds: myEntryIds,
    );
    final official = memberOfficialFixtures(
      fixtures: fixtures.fixtures,
      myEntryIds: myEntryIds,
    );
    final enteredTournaments = entries
        .where((entry) => entry.memberAccountIds.contains(me.id))
        .map((entry) => entry.tournamentId)
        .toSet();
    final sports = official
        .map((fixture) => fixtures.tournamentOf(fixture)?.sport)
        .whereType<Sport>()
        .toSet();

    final achievements = achievementsFrom(
      official: official,
      wins: record.wins,
      squadsLed: context.watch<TeamsController>().mySquads.length,
      tournamentsEntered: enteredTournaments.length,
      sports: sports,
    );
    final unlocked = achievements.where((a) => a.unlocked).toList();
    final next = nextAchievement(achievements);

    // Earned medals lead the showcase; if fewer than three are earned, the
    // nearest locked ones fill the shelf in their muted state.
    final showcase = <Achievement>[
      ...unlocked,
      ...achievements.where((a) => !a.unlocked),
    ].take(3).toList();

    return PassportSection(
      title: 'Achievements',
      detail: unlocked.isEmpty
          ? null
          : '${unlocked.length} of ${achievements.length} unlocked',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MedalCabinet(
            showcase: showcase,
            earned: unlocked.length,
            total: achievements.length,
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            _NextMilestoneCard(achievement: next),
          ],
        ],
      ),
    );
  }
}

/// The collectible shelf: a dimensional navy panel holding up to three medals.
class _MedalCabinet extends StatelessWidget {
  const _MedalCabinet({
    required this.showcase,
    required this.earned,
    required this.total,
  });

  final List<Achievement> showcase;
  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SportikaColors.surfaceAlt,
            SportikaColors.surface,
            SportikaColors.surfaceSunken,
          ],
        ),
        border: Border.all(color: SportikaColors.borderSubtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('MEDAL CABINET', style: SportikaType.micro),
              ),
              Text(
                '$earned of $total collected',
                style: SportikaType.micro.copyWith(
                  color: SportikaColors.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < showcase.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _MedalTile(achievement: showcase[i])),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One medal on the shelf. Pressing it lifts a soft light and scales it in,
/// then opens the achievement detail sheet.
class _MedalTile extends StatefulWidget {
  const _MedalTile({required this.achievement});

  final Achievement achievement;

  @override
  State<_MedalTile> createState() => _MedalTileState();
}

class _MedalTileState extends State<_MedalTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final tone = a.unlocked ? _medalTone(a.kind) : SportikaColors.textDim;
    return Semantics(
      button: true,
      label:
          '${a.title}. ${a.unlocked ? "Earned" : "Locked"}. '
          '${a.unlocked ? a.description : "Progress ${a.progressLabel}"}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('achievement-${a.kind.asset}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => showAchievementDetail(context, a),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _pressed ? .93 : 1,
                  duration: reduce ? Duration.zero : SportikaMotion.fast,
                  curve: SportikaMotion.standard,
                  child: _MedalCoin(achievement: a, size: 60, lit: _pressed),
                ),
                const SizedBox(height: 9),
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: SportikaType.bodyStrong.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  a.unlocked ? 'Earned' : 'Locked',
                  maxLines: 1,
                  style: SportikaType.micro.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
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

/// The nearest locked milestone, elevated into its own progress card.
class _NextMilestoneCard extends StatefulWidget {
  const _NextMilestoneCard({required this.achievement});

  final Achievement achievement;

  @override
  State<_NextMilestoneCard> createState() => _NextMilestoneCardState();
}

class _NextMilestoneCardState extends State<_NextMilestoneCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: 'Next milestone. ${a.title}. Progress ${a.progressLabel}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('next-milestone'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => showAchievementDetail(context, a),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: AnimatedScale(
            scale: _pressed ? .99 : 1,
            duration: reduce ? Duration.zero : SportikaMotion.fast,
            curve: SportikaMotion.standard,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    SportikaColors.surfaceAlt,
                    SportikaColors.surface,
                    SportikaColors.surfaceSunken,
                  ],
                ),
                border: Border.all(color: SportikaColors.borderSubtle),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 16,
                    offset: Offset(0, 9),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _MedalCoin(achievement: a, size: 58, lit: _pressed),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'NEXT MILESTONE',
                              style: SportikaType.micro,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              a.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SportikaType.bodyStrong.copyWith(
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              a.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SportikaType.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Progress', style: SportikaType.caption),
                      ),
                      Text(
                        a.progressLabel,
                        style: SportikaType.bodyStrong.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _MilestoneProgress(
                    value: a.progress,
                    tone: SportikaColors.gold,
                    animate: !reduce,
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

/// The medal's accent used for its rim light and status colour.
Color _medalTone(MedalKind kind) => switch (kind) {
  MedalKind.firstWhistle => SportikaColors.mint,
  MedalKind.firstVictory => SportikaColors.gold,
  MedalKind.hatTrick => const Color(0xFFE1A868),
  MedalKind.squadBuilder => SportikaColors.blueBright,
  MedalKind.entryList => const Color(0xFFC4894E),
  MedalKind.multiSport => SportikaColors.padel,
  MedalKind.seasonRegular => SportikaColors.gold,
};

// Rec.709 luminance matrix: a locked medal is shown fully desaturated.
const List<double> _greyscale = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// A single collectible medal: a lit navy display plate carrying the 3D asset,
/// with a lock badge and a desaturated finish while it is still unearned.
class _MedalCoin extends StatelessWidget {
  const _MedalCoin({
    required this.achievement,
    this.size = 64,
    this.lit = false,
  });

  final Achievement achievement;
  final double size;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final tone = a.unlocked ? _medalTone(a.kind) : SportikaColors.textDim;
    final duration = lit ? SportikaMotion.fast : SportikaMotion.base;

    final medal = Image.asset(
      a.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      opacity: AlwaysStoppedAnimation(a.unlocked ? 1.0 : .6),
      semanticLabel: a.title,
      errorBuilder: (_, _, _) => _FallbackMedal(tone: tone, size: size),
    );
    final shown = a.unlocked
        ? medal
        : ColorFiltered(
            colorFilter: const ColorFilter.matrix(_greyscale),
            child: medal,
          );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: duration,
            curve: SportikaMotion.standard,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-.3, -.4),
                radius: 1.15,
                colors: a.unlocked
                    ? const [SportikaColors.surfaceAlt, SportikaColors.deepest]
                    : const [
                        SportikaColors.surfaceSunken,
                        SportikaColors.deepest,
                      ],
              ),
              border: Border.all(
                color: tone.withValues(alpha: a.unlocked ? .45 : .22),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: lit ? .55 : .4),
                  blurRadius: lit ? 16 : 10,
                  offset: Offset(0, lit ? 5 : 3),
                ),
                BoxShadow(
                  color: tone.withValues(alpha: lit ? .4 : .2),
                  blurRadius: lit ? 20 : 14,
                  spreadRadius: .5,
                ),
              ],
            ),
          ),
          Padding(padding: EdgeInsets.all(size * .08), child: shown),
          if (!a.unlocked)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: SportikaColors.deepest.withValues(alpha: .9),
                  shape: BoxShape.circle,
                  border: Border.all(color: SportikaColors.borderSubtle),
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: size * .26,
                  color: SportikaColors.textDim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Painted stand-in if a medal asset ever fails to decode, so the passport
/// still reads as a collectible and a test never trips on a missing image.
class _FallbackMedal extends StatelessWidget {
  const _FallbackMedal({required this.tone, required this.size});

  final Color tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(size * .18),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-.3, -.4),
          colors: [tone, Color.lerp(tone, Colors.black, .55)!],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.military_tech_outlined,
          size: size * .4,
          color: Colors.white.withValues(alpha: .9),
        ),
      ),
    );
  }
}

/// A refined progress meter: a sunk track with a metallic fill and a soft
/// top-light, animated once (never looping) so it settles for layout tests.
class _MilestoneProgress extends StatelessWidget {
  const _MilestoneProgress({
    required this.value,
    required this.tone,
    this.animate = true,
  });

  final double value;
  final Color tone;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0).toDouble();
    Widget bar(double t) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final fill = (constraints.maxWidth * t)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          return ClipRRect(
            borderRadius: BorderRadius.circular(SportikaRadius.pill),
            child: SizedBox(
              height: 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF08182C),
                          SportikaColors.surfaceSunken,
                          Color(0x1FFFFFFF),
                        ],
                        stops: [0, .55, 1],
                      ),
                    ),
                  ),
                  if (fill > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: fill,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            SportikaRadius.pill,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(tone, Colors.white, .35)!,
                              tone,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tone.withValues(alpha: .35),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (!animate) return bar(target);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: SportikaMotion.slow,
      curve: SportikaMotion.standard,
      builder: (context, t, _) => bar(t),
    );
  }
}

/// Opens the elegant detail sheet for one medal: its finish, what it proves,
/// and the actual progress behind it.
Future<void> showAchievementDetail(BuildContext context, Achievement a) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SportikaColors.surfaceElevated,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
      side: BorderSide(color: SportikaColors.border),
    ),
    sheetAnimationStyle: reduce
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: SportikaMotion.base,
            reverseDuration: SportikaMotion.fast,
          ),
    builder: (sheetContext) => _AchievementDetailSheet(achievement: a),
  );
}

class _AchievementDetailSheet extends StatelessWidget {
  const _AchievementDetailSheet({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final tone = a.unlocked ? _medalTone(a.kind) : SportikaColors.textDim;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MedalCoin(achievement: a, size: 96),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusPill(a.unlocked ? 'Earned' : 'Locked', color: tone),
                      const SizedBox(height: 8),
                      Text(
                        a.title,
                        style: SportikaType.title.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(a.description, style: SportikaType.caption),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text('ACTUAL PROGRESS', style: SportikaType.label),
                ),
                Text(
                  a.progressLabel,
                  style: SportikaType.bodyStrong.copyWith(fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MilestoneProgress(
              value: a.progress,
              tone: a.unlocked ? SportikaColors.mint : SportikaColors.gold,
              animate: !reduce,
            ),
            const SizedBox(height: 16),
            Text(
              a.unlocked
                  ? 'This medal is earned from your official published results '
                        'and cannot be added by hand.'
                  : 'Keep playing official matches. Sportika unlocks this '
                        'automatically the moment your record proves it.',
              style: SportikaType.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-sport appearances and win rate, computed from the same official fixtures
/// the journey list shows. Renders nothing while there is none.
class SportStatisticsCard extends StatelessWidget {
  const SportStatisticsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<ProfileController>().currentAccount;
    if (me == null) return const SizedBox.shrink();
    final entries = context.watch<TournamentsController>().entries;
    final myEntryIds = entries
        .where((entry) => entry.memberAccountIds.contains(me.id))
        .map((entry) => entry.id)
        .toSet();
    final fixtures = context.watch<FixturesController>();
    final official = memberOfficialFixtures(
      fixtures: fixtures.fixtures,
      myEntryIds: myEntryIds,
    );

    final rows = <Sport, ({int played, int won})>{};
    for (final fixture in official) {
      final sport = fixtures.tournamentOf(fixture)?.sport;
      if (sport == null || fixture.result == null) continue;
      final current = rows[sport] ?? (played: 0, won: 0);
      final won = outcomeOf(fixture, myEntryIds) == SportingOutcome.win;
      rows[sport] = (
        played: current.played + 1,
        won: current.won + (won ? 1 : 0),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    final ordered = rows.entries.toList()
      ..sort((a, b) => b.value.played.compareTo(a.value.played));

    return PassportSection(
      title: 'Sports performance',
      detail: 'Official results by sport',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < ordered.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _SportPanel(
              sport: ordered[i].key,
              played: ordered[i].value.played,
              won: ordered[i].value.won,
            ),
          ],
        ],
      ),
    );
  }
}

/// One sport as a dimensional panel: real matches, real wins, real win rate.
class _SportPanel extends StatelessWidget {
  const _SportPanel({
    required this.sport,
    required this.played,
    required this.won,
  });

  final Sport sport;
  final int played;
  final int won;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);
    final winRate = played == 0 ? null : (won * 100 / played).round();
    final ratio = played == 0 ? 0.0 : (won / played).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SportikaColors.surfaceAlt, SportikaColors.surface],
        ),
        border: Border.all(color: SportikaColors.borderSubtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SportCoin(sport: sport, tone: tone),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sport.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.bodyStrong.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$won of $played ${played == 1 ? "match" : "matches"} won',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  winRate == null ? '—' : '$winRate%',
                  style: SportikaType.score.copyWith(fontSize: 24, color: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MilestoneProgress(value: ratio, tone: tone, animate: false),
        ],
      ),
    );
  }
}

/// The sport's glyph set in a small metallic coin, matching the passport chips.
class _SportCoin extends StatelessWidget {
  const _SportCoin({required this.sport, required this.tone});

  final Sport sport;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      width: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone.withValues(alpha: .22), SportikaColors.surfaceSunken],
        ),
        border: Border.all(color: tone.withValues(alpha: .4)),
      ),
      child: Center(
        child: SportGlyph(sport: sport, size: 18, color: tone),
      ),
    );
  }
}
