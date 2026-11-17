import 'package:provider/provider.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:sportika/features/matches/widgets/team_match_logo.dart';

import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Shared fixture identity and scoreboard for discovery and match heroes.
class MatchVsCard extends StatelessWidget {
  const MatchVsCard({
    super.key,
    required this.match,
    this.progress,
    this.showScore = false,
    this.dense = false,
    this.onTap,
  });

  final SportMatch match;

  /// Formatted live scores; a recorded result takes precedence.
  final MatchProgress? progress;
  final bool showScore;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sides = match.sideLabels;
    final scored = showScore && match.status != FixtureStatus.upcoming;
    final radius = BorderRadius.circular(
      dense ? SportikaRadius.md : SportikaRadius.xl,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Give formatted cricket and racket scores the full card width when
        // the identity columns would otherwise become too narrow.
        final narrow =
            constraints.maxWidth < 380 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2;
        final inset = dense || narrow ? SportikaSpacing.md : SportikaSpacing.xl;
        final faceSize = dense ? 44.0 : (narrow ? 56.0 : 72.0);
        Widget identity(int side) => _Identity(
          participants: match.sport == Sport.badminton
              ? match.participantsOnSide(side)
              : const [],
          name: sides.length > side && sides[side].trim().isNotEmpty
              ? sides[side]
              : (side == 0 ? 'Side A' : 'Side B'),
          teamId: _teamId(side),
          sport: match.sport,
          faceSize: faceSize,
          dense: dense,
          meta: _metaFor(side),
        );
        final scoreboard = _Scoreboard(
          first: _scoreFor(0),
          second: _scoreFor(1),
          dense: dense,
          stacked: !narrow,
        );

        return Material(
          color: SportikaColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: const BorderSide(color: SportikaColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(inset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SportTag(match.sport, compact: true),
                      const SizedBox(width: SportikaSpacing.sm),
                      Expanded(
                        child: Text(
                          match.formatLabel.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SportikaType.micro,
                        ),
                      ),
                      const SizedBox(width: SportikaSpacing.xs),
                      Text(
                        match.isLive
                            ? 'LIVE'
                            : match.status.label.toUpperCase(),
                        style: SportikaType.micro.copyWith(
                          color: match.isLive
                              ? SportikaColors.mint
                              : SportikaColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: dense ? SportikaSpacing.md : SportikaSpacing.xl,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: identity(0)),
                      if (scored && !narrow)
                        Expanded(child: scoreboard)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SportikaSpacing.sm,
                          ),
                          child: Text(
                            scored ? '—' : 'VS',
                            style: SportikaType.label.copyWith(
                              color: SportikaColors.textDim,
                            ),
                          ),
                        ),
                      Expanded(child: identity(1)),
                    ],
                  ),
                  if (scored && narrow) ...[
                    const SizedBox(height: SportikaSpacing.md),
                    scoreboard,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _metaFor(int side) {
    final roster = match.participantsOnSide(side).length;
    if (roster > 1) return '$roster confirmed players';
    if (roster == 1) return '1 confirmed player';
    return 'No confirmed players';
  }

  String? _teamId(int side) {
    final ids = match.rules['teamIds'];
    return ids is List && ids.length > side ? ids[side] as String? : null;
  }

  String? _scoreFor(int side) {
    if (match.result != null && match.result!.sideScores.length > side) {
      return match.result!.sideScores[side];
    }
    final p = progress;
    if (p == null || p.scoreDisplay.length <= side) return null;
    final value = p.scoreDisplay[side];
    return value.isEmpty ? null : value;
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.name,
    required this.sport,
    required this.faceSize,
    required this.dense,
    this.participants = const [],
    this.teamId,
    this.meta,
  });

  final List<MatchParticipant> participants;
  final String name;
  final String? teamId;
  final Sport sport;
  final double faceSize;
  final bool dense;
  final String? meta;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: faceSize,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: participants.isEmpty
                ? TeamMatchLogo(
                    teamId: teamId,
                    name: name,
                    color: sportColor(sport),
                    size: faceSize,
                  )
                : _PlayerGroup(
                    participants: participants,
                    size: faceSize,
                    sport: sport,
                  ),
          ),
        ),
      ),
      const SizedBox(height: SportikaSpacing.sm),
      Tooltip(
        message: name,
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: dense ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: dense ? SportikaType.bodyStrong : SportikaType.headline,
        ),
      ),
      if (meta != null) ...[
        const SizedBox(height: SportikaSpacing.xs),
        Text(
          meta!,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: dense ? SportikaType.micro : SportikaType.caption,
        ),
      ],
    ],
  );
}

/// A stable doubles silhouette, with a count for any additional players.
class _PlayerGroup extends StatelessWidget {
  const _PlayerGroup({
    required this.participants,
    required this.size,
    required this.sport,
  });
  final List<MatchParticipant> participants;
  final double size;
  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final avatarSize = participants.length == 1 ? size : size * .78;
    final step = avatarSize * .72;
    final visible = participants.take(2).toList();
    final count = visible.length + (participants.length > 2 ? 1 : 0);
    return Semantics(
      label: participants.map((p) => p.displayName).join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: avatarSize + step * (count - 1),
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < count; i++)
                PositionedDirectional(
                  start: i * step,
                  child: Container(
                    padding: const EdgeInsets.all(SportikaSpacing.xs / 3),
                    decoration: const BoxDecoration(
                      color: SportikaColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: i < visible.length
                        ? Builder(
                            builder: (context) {
                              final player = visible[i];
                              final account = context
                                  .watch<SessionController>()
                                  .accountById(player.profileId);
                              return PlayerAvatar(
                                initials: initialsOf(player.displayName),
                                photoUrl: account?.photoUrl,
                                photoPath: account?.photoPath,
                                size: avatarSize - SportikaSpacing.xs * 2 / 3,
                                color: sportColor(sport),
                              );
                            },
                          )
                        : CircleAvatar(
                            radius:
                                (avatarSize - SportikaSpacing.xs * 2 / 3) / 2,
                            backgroundColor: SportikaColors.surfaceAlt,
                            child: Text(
                              '+${participants.length - visible.length}',
                              style: SportikaType.caption,
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.first,
    required this.second,
    required this.dense,
    required this.stacked,
  });
  final String? first;
  final String? second;
  final bool dense;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    Widget score(String? value) => Text(
      value ?? '—',
      textAlign: TextAlign.center,
      style: dense ? SportikaType.score : SportikaType.hero,
    );
    return Semantics(
      label: 'Score: ${first ?? 'unavailable'} to ${second ?? 'unavailable'}',
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.all(
            dense ? SportikaSpacing.sm : SportikaSpacing.md,
          ),
          decoration: BoxDecoration(
            color: SportikaColors.surfaceSunken,
            borderRadius: BorderRadius.circular(SportikaRadius.sm),
            border: Border.all(color: SportikaColors.borderSubtle),
          ),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    score(first),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: SportikaSpacing.xs,
                      ),
                      child: Divider(height: 1),
                    ),
                    score(second),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: score(first)),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: SportikaSpacing.sm,
                      ),
                      child: Text('—', style: SportikaType.caption),
                    ),
                    Expanded(child: score(second)),
                  ],
                ),
        ),
      ),
    );
  }
}
