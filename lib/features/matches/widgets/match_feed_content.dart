import 'package:flutter/material.dart';

import 'package:sportika/features/matches/widgets/match_center_hero.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/match_scoreboard.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Read-only presentation data for official matches and tournament fixtures.
class MatchFeedItem {
  const MatchFeedItem({
    required this.title,
    required this.sport,
    required this.status,
    required this.date,
    required this.venue,
    required this.format,
    required this.sides,
    required this.result,
    required this.loadProgress,
    required this.onTap,
    this.paused = false,
    this.openToJoin = false,
  });

  final String title;
  final Sport sport;
  final FixtureStatus status;
  final DateTime date;
  final String venue;
  final String format;
  final List<String> sides;
  final OfficialResult? result;
  final MatchProgress Function()? loadProgress;
  final VoidCallback onTap;
  final bool paused;

  /// A public match with a free place, so the feed can advertise joining.
  final bool openToJoin;
}

/// One fixture in the feed. Photography, the scoreboard and the winner accent
/// all derive from the sport identity, so a card never carries its own palette.
class MatchFeedCard extends StatelessWidget {
  const MatchFeedCard({super.key, required this.item, this.featured = false});

  final MatchFeedItem item;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final live = item.status == FixtureStatus.live;
    final upcoming = item.status == FixtureStatus.upcoming;
    final showScore = !upcoming && item.status != FixtureStatus.cancelled;
    final result = showScore ? item.result : null;
    final progress = showScore && result == null
        ? item.loadProgress?.call()
        : null;
    final scores =
        result?.sideScores ?? progress?.scoreDisplay ?? const <String>[];
    final winner =
        result?.winnerIndex ??
        (progress?.isComplete == true ? progress!.winnerIndex : -1);
    final outcome =
        result?.headline ??
        (progress?.isComplete == true ? progress!.resultLabel : '');
    final contextLine = switch (progress) {
      MatchProgress(sport: Sport.padel) =>
        progress.contextChips.take(2).join(' · '),
      MatchProgress() => progress.headline,
      null => '',
    };
    final schedule = dateShort(item.date);
    final location = [
      if (item.venue.trim().isNotEmpty) item.venue,
      schedule,
    ].join(' · ');
    final identity = SportIdentities.of(item.sport);
    final meta = [
      if (upcoming && item.venue.trim().isNotEmpty) item.venue,
      if (!upcoming) location,
      if (item.format.trim().isNotEmpty) item.format,
    ].join(' · ');
    final radius = featured ? SportikaRadius.xl : SportikaRadius.lg;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: featured ? SportikaShadows.lifted : SportikaShadows.card,
      ),
      child: Material(
        color: SportikaColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: live
                ? identity.tone.withValues(alpha: .42)
                : SportikaColors.border,
          ),
        ),
        child: Stack(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: SportikaGradients.holographicSurface,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (featured)
                    _cover(context, identity: identity, schedule: schedule),
                  Padding(
                    padding: const EdgeInsets.all(SportikaSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!featured) ...[
                          _summary(identity),
                          const SizedBox(height: SportikaSpacing.md),
                        ],
                        if (upcoming) ...[
                          _MatchMeta(
                            icon: Icons.event_outlined,
                            text: schedule,
                            emphasized: true,
                          ),
                          const SizedBox(height: SportikaSpacing.sm),
                        ],
                        _board(
                          identity: identity,
                          scores: scores,
                          winner: winner,
                          large: featured,
                        ),
                        if (outcome.isNotEmpty) ...[
                          const SizedBox(height: SportikaSpacing.sm),
                          _outcome(outcome, live: live, tone: identity.tone),
                        ] else if (live &&
                            item.sport == Sport.futsal &&
                            progress != null) ...[
                          const SizedBox(height: SportikaSpacing.sm),
                          FutsalScoreboard(progress: progress),
                        ] else if (live && contextLine.isNotEmpty) ...[
                          const SizedBox(height: SportikaSpacing.sm),
                          Text(contextLine, style: SportikaType.caption),
                        ] else if (live && scores.isEmpty) ...[
                          const SizedBox(height: SportikaSpacing.sm),
                          const Text(
                            'Score not available yet',
                            style: SportikaType.caption,
                          ),
                        ],
                        const SizedBox(height: SportikaSpacing.sm),
                        const Divider(height: 1, color: SportikaColors.border),
                        const SizedBox(height: SportikaSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _MatchMeta(
                                icon: upcoming
                                    ? Icons.place_outlined
                                    : Icons.event_outlined,
                                text: meta,
                              ),
                            ),
                            const SizedBox(width: SportikaSpacing.xs),
                            const Icon(
                              Icons.chevron_right,
                              color: SportikaColors.textMuted,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (live)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: SportikaGradients.liveEdge(identity.tone),
                  ),
                ),
              ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: item.onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(SportIdentity identity) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _thumbnail(identity),
      const SizedBox(width: SportikaSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: SportikaSpacing.xs,
              runSpacing: SportikaSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _sportBadge(identity),
                _status(),
                if (item.openToJoin) _joinPill(),
              ],
            ),
            const SizedBox(height: SportikaSpacing.xs),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.titleMedium,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _cover(
    BuildContext context, {
    required SportIdentity identity,
    required String schedule,
  }) {
    final place = [
      if (item.venue.trim().isNotEmpty) item.venue,
      schedule,
    ].join(' · ');
    // The cover grows with the text scale so the chips and the title never
    // have to fight for the same fixed height.
    final scaler = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    return SizedBox(
      height: 176 + (scaler - 1) * 130,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MatchSportPhoto(sport: item.sport),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: SportikaGradients.heroSpotlight(identity.tone),
              ),
            ),
          ),
          BroadcastGraphics(tone: identity.tone, intensity: .55),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: SportikaGradients.feedTileScrim,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: SportikaSpacing.xxl,
              decoration: const BoxDecoration(
                gradient: SportikaGradients.cardCoverFade,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SportikaSpacing.md,
              SportikaSpacing.md,
              SportikaSpacing.md,
              SportikaSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: SportikaSpacing.xs,
                  runSpacing: SportikaSpacing.xs,
                  children: [
                    _GlassPlate(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SportikaSpacing.sm,
                        vertical: SportikaSpacing.xs,
                      ),
                      child: _sportBadge(identity),
                    ),
                    _GlassPlate(child: _status()),
                    if (item.openToJoin) _GlassPlate(child: _joinPill()),
                  ],
                ),
                const Spacer(),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SportikaType.display(
                    26,
                    height: .95,
                    letterSpacing: -.3,
                  ),
                ),
                if (place.isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xs),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 13,
                        color: SportikaColors.textBody,
                      ),
                      const SizedBox(width: SportikaSpacing.xs),
                      Expanded(
                        child: Text(
                          place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SportikaType.caption.copyWith(
                            color: SportikaColors.textBody,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _board({
    required SportIdentity identity,
    required List<String> scores,
    required int winner,
    required bool large,
  }) => Container(
    padding: const EdgeInsets.all(SportikaSpacing.xs),
    decoration: BoxDecoration(
      color: SportikaColors.surfaceSunken.withValues(
        alpha: SportikaOpacity.heavy,
      ),
      borderRadius: BorderRadius.circular(SportikaRadius.md),
      border: Border.all(color: SportikaColors.borderSubtle),
    ),
    child: Column(
      children: [
        for (var side = 0; side < 2; side++) ...[
          if (side != 0) const SizedBox(height: SportikaSpacing.xxs),
          _ScoreRow(
            name: item.sides.length > side && item.sides[side].trim().isNotEmpty
                ? item.sides[side]
                : 'Side ${side + 1}',
            score: scores.length > side ? scores[side] : '',
            winner: winner == side,
            identity: identity,
            large: large,
          ),
        ],
      ],
    ),
  );

  Widget _outcome(String outcome, {required bool live, required Color tone}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              live ? Icons.sensors : Icons.emoji_events_outlined,
              size: 14,
              color: live ? tone : SportikaColors.gold,
            ),
          ),
          const SizedBox(width: SportikaSpacing.xs),
          Expanded(
            child: Text(
              outcome,
              style: SportikaType.caption.copyWith(
                color: SportikaColors.textBody,
              ),
            ),
          ),
        ],
      );

  Widget _status() {
    final live = item.status == FixtureStatus.live;
    final tone = switch (item.status) {
      FixtureStatus.live => SportikaColors.mint,
      FixtureStatus.upcoming => SportikaColors.blueBright,
      FixtureStatus.published || FixtureStatus.walkover => SportikaColors.gold,
      _ => statusColor(item.status.key),
    };
    return StatusPill(
      live && item.paused ? 'Live · Paused' : item.status.label,
      color: tone,
      icon: live ? Icons.sensors : null,
    );
  }

  Widget _joinPill() => const StatusPill(
    'Open to join',
    color: SportikaColors.blueBright,
    icon: Icons.person_add_alt_1,
  );

  Widget _sportBadge(SportIdentity identity) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SportGlyph(
        sport: item.sport,
        size: SportikaIconSize.xs,
        color: identity.tone,
      ),
      const SizedBox(width: SportikaSpacing.xs),
      Text(
        identity.label,
        style: SportikaType.micro.copyWith(
          color: identity.tone,
          letterSpacing: .9,
        ),
      ),
    ],
  );

  Widget _thumbnail(SportIdentity identity) => ClipRRect(
    borderRadius: BorderRadius.circular(SportikaRadius.control),
    child: SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MatchSportPhoto(sport: item.sport, duotone: true),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SportikaRadius.control),
              border: Border.all(color: identity.tone.withValues(alpha: .24)),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Glass plate that keeps a badge legible over photography.
class _GlassPlate extends StatelessWidget {
  const _GlassPlate({
    required this.child,
    this.padding = const EdgeInsets.all(2),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: SportikaColors.glass,
      borderRadius: BorderRadius.circular(SportikaRadius.pill),
      border: Border.all(color: SportikaColors.overlayHairline),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.name,
    required this.score,
    required this.winner,
    required this.identity,
    required this.large,
  });

  final String name;
  final String score;
  final bool winner;
  final SportIdentity identity;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      SportikaSpacing.xs,
      SportikaSpacing.xs,
      SportikaSpacing.sm,
      SportikaSpacing.xs,
    ),
    decoration: BoxDecoration(
      gradient: winner ? SportikaGradients.winnerFill : null,
      borderRadius: BorderRadius.circular(SportikaRadius.sm),
      border: winner
          ? Border.all(color: SportikaColors.gold.withValues(alpha: .28))
          : null,
    ),
    child: Row(
      children: [
        if (winner) ...[
          Container(
            width: 2,
            height: large ? 26 : 22,
            decoration: BoxDecoration(
              gradient: SportikaGradients.winnerRule,
              borderRadius: BorderRadius.circular(SportikaRadius.pill),
            ),
          ),
          const SizedBox(width: SportikaSpacing.xs),
        ],
        PlayerAvatar(
          initials: initialsOf(name),
          gradient: identity.gradient,
          ink: identity.onTone,
          ring: winner ? SportikaColors.gold : identity.tone,
          size: large ? 32 : 26,
        ),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          flex: 5,
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.bodyStrong.copyWith(
              color: winner ? SportikaColors.gold : SportikaColors.text,
            ),
          ),
        ),
        if (winner)
          const Padding(
            padding: EdgeInsets.only(left: SportikaSpacing.xs),
            child: Icon(
              Icons.emoji_events,
              size: 13,
              color: SportikaColors.gold,
              semanticLabel: 'Winner',
            ),
          ),
        if (score.trim().isNotEmpty) ...[
          const SizedBox(width: SportikaSpacing.sm),
          Flexible(
            flex: 4,
            child: Text(
              score,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: (large ? SportikaType.score : SportikaType.scoreSmall)
                  .copyWith(
                    color: winner ? SportikaColors.gold : SportikaColors.text,
                  ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _MatchMeta extends StatelessWidget {
  const _MatchMeta({
    required this.icon,
    required this.text,
    this.emphasized = false,
  });

  final IconData icon;
  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 15, color: SportikaColors.textMuted),
        const SizedBox(width: SportikaSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: emphasized ? SportikaType.bodyStrong : SportikaType.caption,
          ),
        ),
      ],
    );
  }
}
