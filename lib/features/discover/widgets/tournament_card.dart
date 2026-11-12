import 'package:sportika/shared/widgets/editorial.dart';

import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/features/discover/screens/tournament_detail_screen.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Tournament summary card shared by Home, Tournaments and the organizer lists.
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
    final tone = sportColor(tournament.sport);
    final dates =
        '${dayLabel(tournament.startsAt)} – ${dayLabel(tournament.endsAt)}';

    return SurfaceCard(
      onTap:
          onTap ??
          () => pushScreen(context, TournamentDetailScreen(id: tournament.id)),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SportPhoto(sport: tournament.sport, height: 156),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SportTag(tournament.sport, compact: true),
              StatusPill(
                tournament.status.label,
                color: statusColor(tournament.status.key),
                icon: statusIcon(tournament.status.key),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 9),
          Text(
            tournament.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: SportikaColors.text,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 12,
                color: SportikaColors.textDim,
              ),
              const SizedBox(width: 3),
              Text(
                tournament.city,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: SportikaColors.textMuted,
                ),
              ),
              const Dot(),
              Text(
                dates,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: SportikaColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _meta(tone, Icons.account_tree_outlined, tournament.format.label),
              _meta(tone, Icons.people_outline, tournament.entryType.label),
              _meta(tone, Icons.payments_outlined, tournament.entryFee),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(Color tone, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: tone),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: SportikaColors.textMuted,
        ),
      ),
    ],
  );
}
