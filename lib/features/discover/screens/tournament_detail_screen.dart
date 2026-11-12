import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/navigation/navigation.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/live/screens/results_review_screen.dart';
import 'package:sportika/features/discover/screens/tournament_sections.dart';

/// Tournament page: rules, registration, organizer tools, fixtures, bracket or
/// table, and the entry list.
class TournamentDetailScreen extends StatefulWidget {
  const TournamentDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tournament = state.tournamentById(widget.id);
    if (tournament == null) {
      return Scaffold(
        appBar: sportikaAppBar('Tournament'),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: EmptyState(
            title: 'Tournament not found',
            icon: Icons.search_off,
          ),
        ),
      );
    }

    final me = state.currentAccount;
    final isOwner = me != null && tournament.organizerId == me.id;
    final fixtures = state.fixturesFor(tournament.id);
    final entries = state.entriesFor(tournament.id);
    final pendingEntries = state.pendingEntriesFor(tournament.id);
    final reviewCount = isOwner
        ? state.fixturesAwaitingReview
              .where((f) => f.tournamentId == tournament.id)
              .length
        : 0;
    final myEntry = state.myEntryFor(tournament.id);

    return Scaffold(
      appBar: sportikaAppBar(
        tournament.name,
        subtitle:
            '${tournament.sport.label} · ${tournament.format.label} · '
            '${tournament.city}',
        actions: [
          if (isOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              color: SportikaColors.surfaceElevated,
              onSelected: (value) {
                switch (value) {
                  case 'open':
                    state.setTournamentStatus(
                      tournament.id,
                      TournamentStatus.open,
                    );
                    showSnack(context, 'Registration is open');
                  case 'complete':
                    state.setTournamentStatus(
                      tournament.id,
                      TournamentStatus.completed,
                    );
                    showSnack(context, 'Tournament marked completed');
                  case 'draw':
                    _generateDraw(context, state, tournament);
                }
              },
              itemBuilder: (_) => [
                if (tournament.status == TournamentStatus.draft)
                  const PopupMenuItem(
                    value: 'open',
                    child: Text('Open registration'),
                  ),
                if (tournament.status != TournamentStatus.completed)
                  const PopupMenuItem(
                    value: 'complete',
                    child: Text('Mark completed'),
                  ),
                if (fixtures.isEmpty)
                  const PopupMenuItem(
                    value: 'draw',
                    child: Text('Publish draw'),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          _HeaderCard(tournament: tournament, entryCount: entries.length),
          if (myEntry != null) ...[
            const SizedBox(height: 10),
            _MyEntryCard(entry: myEntry, tournament: tournament),
          ] else if (state.canRegisterFor(tournament)) ...[
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Register for this tournament',
              icon: Icons.how_to_reg_outlined,
              tone: SportikaColors.mint,
              onPressed: () => _register(context, tournament),
            ),
          ] else if (tournament.status == TournamentStatus.open) ...[
            const SizedBox(height: 10),
            const InfoBanner(
              icon: Icons.group_off_outlined,
              tone: SportikaColors.gold,
              text: 'Registration is full for this event.',
            ),
          ],
          if (isOwner) ...[
            const SectionTitle('Organizer tools'),
            SurfaceCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          value: '${pendingEntries.length}',
                          label: 'Entries to review',
                          tone: SportikaColors.gold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatTile(
                          value: '$reviewCount',
                          label: 'Results to publish',
                          tone: SportikaColors.mint,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatTile(
                          value: '${fixtures.length}',
                          label: 'Fixtures',
                          tone: SportikaColors.blueBright,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (fixtures.isEmpty)
                    PrimaryButton(
                      label: 'Publish draw & fixtures',
                      icon: Icons.account_tree_outlined,
                      small: true,
                      tone: SportikaColors.mint,
                      onPressed: () =>
                          _generateDraw(context, state, tournament),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: GhostButton(
                            label: 'Review results',
                            icon: Icons.fact_check_outlined,
                            expand: true,
                            onPressed: () => pushScreen(
                              context,
                              ResultsReviewScreen(
                                tournamentId: tournament.id,
                                highlightId: state
                                    .fixturesAwaitingReview
                                    .firstOrNull
                                    ?.id,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GhostButton(
                            label: 'Entries',
                            icon: Icons.people_outline,
                            expand: true,
                            onPressed: () => setState(() => _tab = 2),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _SectionSwitcher(
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
            labels: [
              'Fixtures',
              tournament.format == TournamentFormat.group ? 'Table' : 'Bracket',
              'Entries',
            ],
            counts: [fixtures.length, 0, entries.length],
          ),
          const SizedBox(height: 6),
          if (_tab == 0) TournamentFixturesSection(tournament: tournament),
          if (_tab == 1) TournamentBracket(tournament: tournament),
          if (_tab == 2)
            TournamentEntriesSection(
              tournament: tournament,
              canManage: isOwner,
            ),
        ],
      ),
    );
  }

  Future<void> _generateDraw(
    BuildContext context,
    AppState state,
    Tournament tournament,
  ) async {
    final count = await state.generateDraw(tournament.id);
    if (!context.mounted) return;
    showSnack(
      context,
      count == 0
          ? 'Confirm at least two entries before publishing a draw'
          : 'Draw published · $count fixtures created and scorers notified',
      error: count == 0,
    );
  }

  Future<void> _register(BuildContext context, Tournament tournament) async {
    final state = context.read<AppState>();

    if (tournament.entryType == EntryType.individual) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Register for ${tournament.name}?'),
          content: const Text(
            'Your entry goes to the organizer for confirmation. You will be notified '
            'when they decide.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Register'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await state.submitEntry(tournamentId: tournament.id);
      if (context.mounted) showSnack(context, 'Entry submitted for review');
      return;
    }

    final squads = state.squadsFor(tournament.sport, tournament.entryType);
    String? selected = squads.firstOrNull?.id;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: SportikaColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => AppSheet(
          title: 'Register ${tournament.entryType.label.toLowerCase()}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const InfoBanner(
                icon: Icons.info_outline,
                text: 'Entries are reviewed by the organizer before they appear in the draw.',
              ),
              const SizedBox(height: 12),
              if (squads.isEmpty)
                Text(
                  'You have no ${tournament.entryType.label.toLowerCase()} for '
                  '${tournament.sport.label} yet.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: SportikaColors.textMuted,
                  ),
                )
              else
                for (final squad in squads)
                  InkWell(
                    onTap: () => setSheetState(() => selected = squad.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            selected == squad.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: selected == squad.id
                                ? SportikaColors.mint
                                : SportikaColors.textDim,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  squad.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: SportikaColors.text,
                                  ),
                                ),
                                Text(
                                  squad.memberAccountIds
                                      .map(
                                        (id) => state
                                            .accountById(id)
                                            ?.displayName
                                            .split(' ')
                                            .first,
                                      )
                                      .whereType<String>()
                                      .join(' · '),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: SportikaColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 14),
              if (squads.isEmpty)
                GhostButton(
                  label: 'Open Teams to create one',
                  icon: Icons.groups_outlined,
                  expand: true,
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    openHomeTab(context, 3);
                  },
                )
              else
                PrimaryButton(
                  label: 'Submit entry',
                  icon: Icons.send_rounded,
                  tone: SportikaColors.mint,
                  onPressed: selected == null
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || selected == null) return;
    await state.submitEntry(tournamentId: tournament.id, squadId: selected);
    if (context.mounted) showSnack(context, 'Entry submitted for review');
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.tournament, required this.entryCount});

  final Tournament tournament;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final confirmed = context.watch<AppState>().confirmedCountFor(tournament);
    final limit = tournament.registrationLimit;
    final fill = limit == 0 ? 0.0 : (confirmed / limit).clamp(0.0, 1.0);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SportTag(tournament.sport),
              const SizedBox(width: 8),
              StatusPill(
                tournament.status.label,
                color: statusColor(tournament.status.key),
                icon: statusIcon(tournament.status.key),
              ),
              const Spacer(),
              Text(
                tournament.entryFee,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: SportikaColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tournament.name,
            style: const TextStyle(
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: SportikaColors.text,
            ),
          ),
          const SizedBox(height: 6),
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
                '${dayLabel(tournament.startsAt)} – ${dayLabel(tournament.endsAt)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: SportikaColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fill,
              minHeight: 6,
              backgroundColor: SportikaColors.borderSubtle,
              valueColor: const AlwaysStoppedAnimation(SportikaColors.mint),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$confirmed of $limit confirmed',
                style: const TextStyle(
                  fontSize: 11,
                  color: SportikaColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${tournament.entryType.label} entries',
                style: const TextStyle(
                  fontSize: 11,
                  color: SportikaColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 6),
          KeyValueRow('Format', tournament.formatLabel),
          KeyValueRow('Match rules', tournament.matchRules),
          KeyValueRow('Total entries', '$entryCount'),
        ],
      ),
    );
  }
}

class _MyEntryCard extends StatelessWidget {
  const _MyEntryCard({required this.entry, required this.tournament});

  final Entry entry;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final tone = statusColor(entry.status.key);

    return SurfaceCard(
      borderColor: tone.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your entry · ${entry.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: SportikaColors.text,
                  ),
                ),
              ),
              StatusPill(entry.status.label, color: tone),
            ],
          ),
          if (entry.decisionNote != null && entry.decisionNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              entry.decisionNote!,
              style: const TextStyle(
                fontSize: 11.5,
                color: SportikaColors.textMuted,
              ),
            ),
          ],
          if (entry.status == EntryStatus.pending ||
              (entry.status == EntryStatus.confirmed &&
                  tournament.status == TournamentStatus.open)) ...[
            const SizedBox(height: 9),
            GhostButton(
              label: 'Withdraw entry',
              icon: Icons.logout,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: () {
                state.withdrawEntry(entry.id);
                showSnack(context, 'Entry withdrawn');
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionSwitcher extends StatelessWidget {
  const _SectionSwitcher({
    required this.value,
    required this.onChanged,
    required this.labels,
    required this.counts,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final List<String> labels;
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SportikaColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: value == i
                        ? SportikaColors.surfaceAlt
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: value == i
                          ? SportikaColors.borderStrong
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: value == i
                              ? SportikaColors.text
                              : SportikaColors.textMuted,
                        ),
                      ),
                      if (counts[i] > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${counts[i]}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: value == i
                                ? SportikaColors.blueBright
                                : SportikaColors.textDim,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
