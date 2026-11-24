import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Compact competition identity; sport photography is the existing fallback
/// because the tournament model carries no uploaded banner/logo reference.
class TournamentCard extends StatelessWidget {
  const TournamentCard({
    super.key,
    required this.tournament,
    this.onTap,
    this.trailing,
  });
  final Tournament tournament;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final confirmed = context.watch<TournamentsController>().confirmedCountFor(
      tournament,
    );
    final full = confirmed >= tournament.registrationLimit;
    final registration = tournament.status == TournamentStatus.open
        ? (full ? 'Registration full' : 'Registration open')
        : tournament.status.label;
    return SurfaceCard(
      onTap:
          onTap ??
          () => pushRoute(
            context,
            AppRoute.tournamentDetail,
            args: TournamentDetailArgs(tournament.id),
          ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: SportPhoto(
                  sport: tournament.sport,
                  height: 76,
                  radius: 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tournament.sport.label.toUpperCase(),
                      style: SportikaType.micro.copyWith(
                        color: sportColor(tournament.sport),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tournament.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.hero.copyWith(fontSize: 23),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tournament.city,
                      style: SportikaType.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                registration,
                color: tournament.status == TournamentStatus.open && !full
                    ? SportikaColors.mint
                    : statusColor(tournament.status.key),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${dayLabel(tournament.startsAt)} – ${dayLabel(tournament.endsAt)}',
            style: SportikaType.caption,
          ),
          const SizedBox(height: 6),
          Text(
            '${tournament.format.label} · ${tournament.entryType.label} · ${tournament.entryFee}',
            style: SportikaType.caption,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.groups_outlined,
                size: 16,
                color: SportikaColors.gold,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$confirmed / ${tournament.registrationLimit} confirmed entries',
                  style: SportikaType.caption,
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: SportikaColors.blueBright,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
