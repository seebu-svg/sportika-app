import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';

// ============================================================
// CARD PRESENTATION
// ============================================================

enum TeamCardVariant { compact, featured }

// ============================================================
// ATHLETE PASSPORT CARD
// ============================================================

class TeamPlayerCard extends StatelessWidget {
  const TeamPlayerCard({
    super.key,
    required this.account,
    required this.sports,
    required this.appearances,
    required this.teams,
    required this.isMe,
    required this.onTap,
    this.variant = TeamCardVariant.compact,
  });

  final Account account;
  final List<Sport> sports;
  final int appearances;
  final int teams;
  final bool isMe;
  final VoidCallback onTap;
  final TeamCardVariant variant;

  @override
  Widget build(BuildContext context) {
    return variant == TeamCardVariant.featured
        ? _buildFeatured(context)
        : _buildCompact(context);
  }

  // ----------------------------------------------------------
  // COMPACT DISCOVERY CARD
  // ----------------------------------------------------------

  Widget _buildCompact(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(SportikaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AthleteAvatar(
                  account: account,
                  size: SportikaSpacing.xxxl + SportikaSpacing.md,
                ),
                const SizedBox(width: SportikaSpacing.md),
                Expanded(
                  child: _AthleteIdentity(
                    account: account,
                    isMe: isMe,
                    featured: false,
                  ),
                ),
                const SizedBox(width: SportikaSpacing.xs),
                const _OpenArrow(),
              ],
            ),
            const SizedBox(height: SportikaSpacing.md),
            _AthleteStats(
              appearances: appearances,
              teams: teams,
              sports: sports.length,
            ),
            const SizedBox(height: SportikaSpacing.md),
            Row(
              children: [
                Expanded(child: _SportsSummary(sports: sports)),
                const SizedBox(width: SportikaSpacing.sm),
                Text(
                  'View Passport',
                  style: SportikaType.action.copyWith(color: theme.live),
                ),
                const SizedBox(width: SportikaSpacing.xs),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: SportikaIconSize.sm,
                  color: theme.live,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // FEATURED ATHLETE CARD
  // ----------------------------------------------------------

  Widget _buildFeatured(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Editorial athlete identity panel.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SportikaSpacing.lg),
            decoration: BoxDecoration(
              gradient: SportikaGradients.sportCoin(theme.live),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SportikaRadius.control),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPORTIKA / ATHLETE PASSPORT',
                  style: SportikaType.micro.copyWith(color: theme.live),
                ),
                const SizedBox(height: SportikaSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _AthleteAvatar(
                      account: account,
                      size: SportikaSpacing.xxxl * 2,
                    ),
                    const SizedBox(width: SportikaSpacing.md),
                    Expanded(
                      child: _AthleteIdentity(
                        account: account,
                        isMe: isMe,
                        featured: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AthleteStats(
                  appearances: appearances,
                  teams: teams,
                  sports: sports.length,
                ),
                const SizedBox(height: SportikaSpacing.md),
                _SportsSummary(sports: sports),
                const SizedBox(height: SportikaSpacing.md),
                _CardAction(label: 'View Athlete Passport', tone: theme.live),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ATHLETE AVATAR
// ============================================================

class _AthleteAvatar extends StatelessWidget {
  const _AthleteAvatar({required this.account, required this.size});

  final Account account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AccountAvatar(
          account: account,
          size: size,
          ring: theme.live.withValues(alpha: SportikaOpacity.medium),
        ),
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surfaceSunken,
              shape: BoxShape.circle,
              border: Border.all(color: theme.borderSubtle),
            ),
            child: Padding(
              padding: const EdgeInsets.all(SportikaSpacing.xxs),
              child: Icon(
                Icons.sports_rounded,
                size: SportikaIconSize.sm,
                color: theme.live,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ATHLETE IDENTITY
// ============================================================

class _AthleteIdentity extends StatelessWidget {
  const _AthleteIdentity({
    required this.account,
    required this.isMe,
    required this.featured,
  });

  final Account account;
  final bool isMe;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          featured ? 'ATHLETE PROFILE' : 'SPORTIKA ATHLETE',
          style: SportikaType.micro.copyWith(color: theme.live),
        ),
        const SizedBox(height: SportikaSpacing.xxs),
        Text(
          account.displayName,
          style: featured ? SportikaType.title : SportikaType.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: SportikaSpacing.xs),
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: SportikaIconSize.sm,
              color: theme.textMuted,
            ),
            const SizedBox(width: SportikaSpacing.xxs),
            Expanded(
              child: Text(
                account.city.trim().isEmpty
                    ? 'Location not provided'
                    : account.city,
                style: SportikaType.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (isMe) ...[
          const SizedBox(height: SportikaSpacing.xs),
          Text(
            'YOUR PROFILE',
            style: SportikaType.micro.copyWith(color: theme.live),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// ATHLETE STATS
// ============================================================

class _AthleteStats extends StatelessWidget {
  const _AthleteStats({
    required this.appearances,
    required this.teams,
    required this.sports,
  });

  final int appearances;
  final int teams;
  final int sports;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: const BorderRadius.all(
          Radius.circular(SportikaRadius.control),
        ),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: SportikaSpacing.sm,
          horizontal: SportikaSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: _PlayerMetric(value: appearances, label: 'MATCHES'),
            ),
            _MetricDivider(),
            Expanded(
              child: _PlayerMetric(value: teams, label: 'TEAMS'),
            ),
            _MetricDivider(),
            Expanded(
              child: _PlayerMetric(value: sports, label: 'SPORTS'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerMetric extends StatelessWidget {
  const _PlayerMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: SportikaType.scoreSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: SportikaSpacing.xxs),
        Text(
          label,
          style: SportikaType.micro,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: SportikaBorder.hairline,
      height: SportikaSpacing.xxl,
      color: context.sportika.borderSubtle,
    );
  }
}

// ============================================================
// SPORTS SUMMARY
// ============================================================

class _SportsSummary extends StatelessWidget {
  const _SportsSummary({required this.sports});

  final List<Sport> sports;

  @override
  Widget build(BuildContext context) {
    if (sports.isEmpty) {
      return const Text('New to Sportika', style: SportikaType.caption);
    }

    final visible = sports.take(2).toList();
    final remaining = sports.length - visible.length;

    return Wrap(
      spacing: SportikaSpacing.xs,
      runSpacing: SportikaSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final sport in visible) SportTag(sport, compact: true),
        if (remaining > 0) _OverflowTag(count: remaining),
      ],
    );
  }
}

class _OverflowTag extends StatelessWidget {
  const _OverflowTag({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.sm,
        vertical: SportikaSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
      ),
      child: Text(
        '+$count',
        style: SportikaType.micro.copyWith(color: theme.textBody),
      ),
    );
  }
}

// ============================================================
// SQUAD IDENTITY CARD
// ============================================================

class TeamSquadCard extends StatelessWidget {
  const TeamSquadCard({
    super.key,
    required this.squad,
    required this.members,
    required this.onTap,
    this.variant = TeamCardVariant.compact,
  });

  final Squad squad;
  final List<Account?> members;
  final VoidCallback onTap;
  final TeamCardVariant variant;

  @override
  Widget build(BuildContext context) {
    return variant == TeamCardVariant.featured
        ? _buildFeatured(context)
        : _buildCompact(context);
  }

  // ----------------------------------------------------------
  // COMPACT SQUAD CARD
  // ----------------------------------------------------------

  Widget _buildCompact(BuildContext context) {
    final tone = sportColor(squad.sport);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(SportikaSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                _SquadCrest(
                  squad: squad,
                  tone: tone,
                  size: SportikaSpacing.xxxl + SportikaSpacing.md,
                ),
                const SizedBox(width: SportikaSpacing.md),
                Expanded(
                  child: _SquadIdentity(squad: squad, tone: tone),
                ),
                const SizedBox(width: SportikaSpacing.xs),
                const _OpenArrow(),
              ],
            ),
            const SizedBox(height: SportikaSpacing.md),
            _SquadRosterSummary(squad: squad, members: members, tone: tone),
            const SizedBox(height: SportikaSpacing.md),
            _CardAction(label: 'Explore Squad', tone: tone),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // FEATURED SQUAD CARD
  // ----------------------------------------------------------

  Widget _buildFeatured(BuildContext context) {
    final tone = sportColor(squad.sport);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SportikaSpacing.lg),
            decoration: BoxDecoration(
              gradient: SportikaGradients.sportCoin(tone),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SportikaRadius.control),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPORTIKA / SQUAD IDENTITY',
                  style: SportikaType.micro.copyWith(color: tone),
                ),
                const SizedBox(height: SportikaSpacing.lg),
                Row(
                  children: [
                    _SquadCrest(
                      squad: squad,
                      tone: tone,
                      size: SportikaSpacing.xxxl * 2,
                    ),
                    const SizedBox(width: SportikaSpacing.md),
                    Expanded(
                      child: _SquadIdentity(
                        squad: squad,
                        tone: tone,
                        featured: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            child: Column(
              children: [
                _SquadRosterSummary(squad: squad, members: members, tone: tone),
                const SizedBox(height: SportikaSpacing.md),
                _CardAction(label: 'Explore Squad', tone: tone),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SQUAD CREST
// ============================================================

class _SquadCrest extends StatelessWidget {
  const _SquadCrest({
    required this.squad,
    required this.tone,
    required this.size,
  });

  final Squad squad;
  final Color tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: SportikaGradients.sportCoin(tone),
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(
          color: tone.withValues(alpha: SportikaOpacity.medium),
        ),
      ),
      child: Center(
        child: SportGlyph(
          sport: squad.sport,
          color: tone,
          size: SportikaIconSize.lg,
        ),
      ),
    );
  }
}

// ============================================================
// SQUAD IDENTITY
// ============================================================

class _SquadIdentity extends StatelessWidget {
  const _SquadIdentity({
    required this.squad,
    required this.tone,
    this.featured = false,
  });

  final Squad squad;
  final Color tone;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SPORTIKA SQUAD', style: SportikaType.micro.copyWith(color: tone)),
        const SizedBox(height: SportikaSpacing.xxs),
        Text(
          squad.name,
          style: featured ? SportikaType.title : SportikaType.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: SportikaSpacing.xs),
        Text(
          '${squad.sport.label} · ${squad.type.label}',
          style: SportikaType.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ============================================================
// SQUAD ROSTER SUMMARY
// ============================================================

class _SquadRosterSummary extends StatelessWidget {
  const _SquadRosterSummary({
    required this.squad,
    required this.members,
    required this.tone,
  });

  final Squad squad;
  final List<Account?> members;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${squad.size}', style: SportikaType.scoreSmall),
                const SizedBox(height: SportikaSpacing.xxs),
                Text(
                  squad.size == 1 ? 'SQUAD MEMBER' : 'SQUAD MEMBERS',
                  style: SportikaType.micro,
                ),
              ],
            ),
          ),
          if (members.isNotEmpty)
            _SquadAvatarStack(members: members, tone: tone),
        ],
      ),
    );
  }
}

// ============================================================
// SQUAD AVATAR STACK
// ============================================================

class _SquadAvatarStack extends StatelessWidget {
  const _SquadAvatarStack({required this.members, required this.tone});

  final List<Account?> members;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final visible = members.take(4).toList();
    final remaining = members.length - visible.length;

    final avatarSize = SportikaSpacing.xxl;
    final overlap = SportikaSpacing.sm;
    final step = avatarSize - overlap;

    final totalItems = visible.length + (remaining > 0 ? 1 : 0);

    final width = avatarSize + (totalItems - 1) * step;

    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            PositionedDirectional(
              start: i * step,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.surfaceSunken,
                    width: SportikaBorder.hairline,
                  ),
                ),
                child: visible[i] == null
                    ? PlayerAvatar(initials: '?', size: avatarSize, color: tone)
                    : AccountAvatar(account: visible[i]!, size: avatarSize),
              ),
            ),
          if (remaining > 0)
            PositionedDirectional(
              start: visible.length * step,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.surfaceAlt,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.borderSubtle),
                ),
                child: Text(
                  '+$remaining',
                  style: SportikaType.micro.copyWith(color: theme.textBody),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// SHARED CARD ACTION
// ============================================================

class _CardAction extends StatelessWidget {
  const _CardAction({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.md,
        vertical: SportikaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: SportikaType.action.copyWith(color: tone),
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            size: SportikaIconSize.md,
            color: tone,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// NAVIGATION INDICATOR
// ============================================================

class _OpenArrow extends StatelessWidget {
  const _OpenArrow();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.arrow_outward_rounded,
      size: SportikaIconSize.md,
      color: context.sportika.textMuted,
    );
  }
}
