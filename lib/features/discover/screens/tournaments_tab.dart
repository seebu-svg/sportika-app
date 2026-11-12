import 'package:sportika/shared/widgets/editorial.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/features/discover/widgets/tournament_card.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/discover/screens/create_tournament_screen.dart';
import 'package:sportika/features/discover/screens/tournament_detail_screen.dart';

/// Tournaments board for the Discover tab: every event, filtered by sport, or
/// just the ones the account has entered.
class TournamentsTab extends StatefulWidget {
  const TournamentsTab({super.key});

  @override
  State<TournamentsTab> createState() => _TournamentsTabState();
}

class _TournamentsTabState extends State<TournamentsTab> {
  Sport? _sport;
  bool _mineOnly = false;
  bool _organized = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LocalSportikaRepository>();
    final all = state.filterTournaments(sport: _sport);
    final mine = state.filterTournaments(sport: _sport, myEntriesOnly: true);
    final items = _organized
        ? all.where((t) => t.organizerId == state.currentAccount?.id).toList()
        : _mineOnly
        ? mine
        : all;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              _ScopeChip(
                label: 'Discover',
                active: !_mineOnly && !_organized,
                onTap: () => setState(() {
                  _mineOnly = false;
                  _organized = false;
                }),
              ),
              const SizedBox(width: 8),
              _ScopeChip(
                label: 'My Events',
                active: _mineOnly && !_organized,
                onTap: () => setState(() {
                  _mineOnly = true;
                  _organized = false;
                }),
              ),
              const SizedBox(width: 8),
              _ScopeChip(
                label: 'Organized',
                active: _organized,
                onTap: () => setState(() => _organized = true),
              ),
            ],
          ),
        ),
        SportFilterBar(
          selected: _sport,
          onChanged: (s) => setState(() => _sport = s),
        ),
        Expanded(
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: EmptyState(
                    title: _mineOnly ? 'No entries yet' : 'No tournaments here',
                    body: _mineOnly
                        ? 'Register for an event and it will appear in this list.'
                        : 'Organizers publish new events from their dashboard.',
                    icon: Icons.emoji_events_outlined,
                    action: state.canOrganize && !_mineOnly
                        ? GhostButton(
                            label: 'Create a tournament',
                            icon: Icons.add,
                            onPressed: () => pushScreen(
                              context,
                              const CreateTournamentScreen(),
                            ),
                          )
                        : null,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    if (!_mineOnly && !_organized && items.isNotEmpty) ...[
                      EditorialBanner(
                        sport: items.first.sport,
                        eyebrow: 'FEATURED COMPETITION',
                        title: 'CHASE THE\nCHAMPIONSHIP.',
                        subtitle: items.first.name,
                        accent: SportikaColors.gold,
                        action: 'Explore tournament',
                        onAction: () => pushScreen(
                          context,
                          TournamentDetailScreen(id: items.first.id),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'THE COMPETITION CALENDAR',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w800,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final tournament in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TournamentCard(
                          tournament: tournament,
                          trailing: _hasEntry(state, tournament)
                              ? const StatusPill(
                                  'Entered',
                                  color: SportikaColors.mint,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  bool _hasEntry(LocalSportikaRepository state, Tournament tournament) {
    final me = state.currentAccount?.id;
    if (me == null) return false;
    return state
        .entriesFor(tournament.id)
        .any(
          (e) =>
              e.memberAccountIds.contains(me) &&
              e.status != EntryStatus.withdrawn,
        );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? SportikaColors.blueSubtle
              : SportikaColors.surfaceSunken,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? SportikaColors.blue : SportikaColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? SportikaColors.blueBright : SportikaColors.textBody,
          ),
        ),
      ),
    );
  }
}
