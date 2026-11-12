import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';
import 'package:sportika/app/routes.dart';

class PersonalGamesScreen extends StatefulWidget {
  const PersonalGamesScreen({super.key});
  @override
  State<PersonalGamesScreen> createState() => _PersonalGamesScreenState();
}

class _PersonalGamesScreenState extends State<PersonalGamesScreen> {
  String filter = 'All', query = '';
  Sport? sport;
  int days = 0;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PersonalGamesController>();
    final all = state.myPersonal;
    final games = all
        .where(
          (m) =>
              (sport == null || m.sport == sport) &&
              (filter == 'All' ||
                  (filter == 'Active' &&
                      m.status == PersonalMatchStatus.inProgress) ||
                  (filter == 'Paused' &&
                      m.status == PersonalMatchStatus.paused) ||
                  (filter == 'Completed' &&
                      m.status == PersonalMatchStatus.completed)) &&
              m.sideNames
                  .join(' ')
                  .toLowerCase()
                  .contains(query.toLowerCase()) &&
              (days == 0 ||
                  m.createdAt.isAfter(
                    DateTime.now().subtract(Duration(days: days)),
                  )),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My personal games'),
        actions: [
          IconButton(
            tooltip: 'Performance overview',
            icon: const Icon(Icons.insights),
            onPressed: () => pushRoute(context, AppRoute.personalPerformance),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'MAKE EVERY\nMOMENT COUNT.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          const InfoBanner(
            icon: Icons.lock_outline,
            text: 'Your private games and spectator scorecards. Never submitted to organizers or counted in official results.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => pushRoute(context, AppRoute.newPersonalMatch),
            icon: const Icon(Icons.add),
            label: const Text('Create personal game'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value:
                      '${all.where((m) => m.status == PersonalMatchStatus.inProgress).length}',
                  label: 'Active',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value:
                      '${all.where((m) => m.status == PersonalMatchStatus.paused).length}',
                  label: 'Paused',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value:
                      '${all.where((m) => m.status == PersonalMatchStatus.completed).length}',
                  label: 'Completed',
                ),
              ),
            ],
          ),
          const SectionTitle('Personal scoring dashboard'),
          Wrap(
            spacing: 8,
            children: [
              for (final f in ['All', 'Active', 'Paused', 'Completed'])
                ChoiceChip(
                  label: Text(f),
                  selected: filter == f,
                  onSelected: (_) => setState(() => filter = f),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              hintText: 'Search your game history',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          DropdownButton<Sport?>(
            value: sport,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: null, child: Text('All sports')),
              for (final s in Sport.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) => setState(() => sport = v),
          ),
          DropdownButton<int>(
            value: days,
            isExpanded: true,
            items: [
              for (final d in [0, 7, 30, 90])
                DropdownMenuItem(
                  value: d,
                  child: Text(d == 0 ? 'All time' : 'Last $d days'),
                ),
            ],
            onChanged: (v) => setState(() => days = v!),
          ),
          const SizedBox(height: 16),
          if (games.isEmpty)
            const EmptyState(
              title: 'No games here yet',
              body: 'Create a game or adjust your filters to find a private scorecard.',
              icon: Icons.sports_score,
            ),
          for (final m in games)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Icon(sportGlyph(m.sport)),
                title: Text(m.sideNames.join(' vs ')),
                subtitle: Text(
                  '${m.sport.label} · ${m.formatLabel}\n${m.status.label} · ${state.progressOfPersonal(m).headline}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => pushRoute(
                  context,
                  AppRoute.personalGameDetail,
                  args: PersonalMatchArgs(m.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PersonalGameDetailsScreen extends StatelessWidget {
  const PersonalGameDetailsScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PersonalGamesController>();
    final m = state.personalById(id);
    if (m == null ||
        m.ownerId != context.read<ProfileController>().currentAccount?.id) {
      return Scaffold(
        appBar: AppBar(title: const Text('Personal game')),
        body: const EmptyState(
          title: 'Game unavailable',
          icon: Icons.search_off,
        ),
      );
    }
    final p = state.progressOfPersonal(m);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          m.status == PersonalMatchStatus.completed
              ? 'Match result summary'
              : 'Personal game details',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            m.sideNames.join(' vs '),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(p.headline, style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            leading: Icon(sportGlyph(m.sport)),
            title: Text('${m.sport.label} match centre'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => pushRoute(
              context,
              AppRoute.personalMatchCentre,
              args: PersonalMatchArgs(m.id),
            ),
          ),
          KeyValueRow('Status', m.status.label),
          KeyValueRow('Format', '${m.sport.label} · ${m.formatLabel}'),
          KeyValueRow(
            'Created',
            m.createdAt.toLocal().toString().substring(0, 16),
          ),
          for (final k in ['venue', 'players', 'notes'])
            if ((m.details[k] ?? '').toString().isNotEmpty)
              KeyValueRow(k, m.details[k].toString()),
          if (m.status == PersonalMatchStatus.completed)
            InfoBanner(
              text: p.isComplete ? p.resultLabel : 'Ended early. Recorded scores retained; no winner inferred.',
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => pushRoute(
              context,
              AppRoute.scorecard,
              args: ScorecardArgs(id, ScorecardMode.personal),
            ),
            child: Text(
              m.status == PersonalMatchStatus.completed
                  ? 'Detailed scorecard'
                  : 'Open scoring',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timeline),
            title: const Text('Match timeline / score history'),
            onTap: () => pushRoute(
              context,
              AppRoute.personalTimeline,
              args: PersonalMatchArgs(id),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Match statistics'),
            onTap: () => pushRoute(
              context,
              AppRoute.personalStats,
              args: PersonalMatchArgs(id),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit game details'),
            onTap: () => pushRoute(
              context,
              AppRoute.personalEdit,
              args: PersonalEditArgs(m),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete game'),
            onTap: () async {
              final ok = await confirmPersonal(
                context,
                'Delete game?',
                'Permanently remove this private game and every scoring entry?',
                'Delete',
              );
              if (ok) {
                state.deletePersonalMatch(id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          const InfoBanner(
            icon: Icons.lock_outline,
            text: 'Personal records are private and do not affect official tournament results.',
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmPersonal(
  BuildContext context,
  String title,
  String body,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class EditPersonalGameScreen extends StatefulWidget {
  const EditPersonalGameScreen({super.key, required this.match});
  final PersonalMatch match;
  @override
  State<EditPersonalGameScreen> createState() => _EditPersonalGameScreenState();
}

class _EditPersonalGameScreenState extends State<EditPersonalGameScreen> {
  late final a = TextEditingController(text: widget.match.sideNames[0]),
      b = TextEditingController(text: widget.match.sideNames[1]),
      venue = TextEditingController(text: widget.match.details['venue'] ?? ''),
      notes = TextEditingController(text: widget.match.details['notes'] ?? ''),
      players = TextEditingController(
        text: widget.match.details['players'] ?? '',
      );
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final c in [a, b, venue, notes, players]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit game details')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final entry in [
            (a, 'Side A'),
            (b, 'Side B'),
            (venue, 'Venue'),
            (players, 'Players'),
            (notes, 'Game notes'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: entry.$1,
                decoration: InputDecoration(labelText: entry.$2),
                validator: (v) =>
                    [a, b].contains(entry.$1) && (v?.trim().isEmpty ?? true)
                    ? 'Enter a name'
                    : null,
              ),
            ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              if (a.text.trim().toLowerCase() == b.text.trim().toLowerCase()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Choose different side names.')),
                );
                return;
              }
              context.read<PersonalGamesController>().updatePersonalDetails(
                widget.match.id,
                {
                  'venue': venue.text,
                  'notes': notes.text,
                  'players': players.text,
                },
                sides: [a.text.trim(), b.text.trim()],
              );
              Navigator.pop(context);
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    ),
  );
}

class PersonalTimelineScreen extends StatelessWidget {
  const PersonalTimelineScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PersonalGamesController>();
    final m = state.personalById(id);
    if (m == null ||
        m.ownerId != context.read<ProfileController>().currentAccount?.id) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Match timeline')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const InfoBanner(
            text: 'Tap an entry to replace it with a scoring action. Later entries remain and the score is recalculated.',
          ),
          if (m.events.isEmpty)
            const EmptyState(title: 'No scores recorded', icon: Icons.timeline),
          for (var i = m.events.length - 1; i >= 0; i--)
            ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(m.events[i]['kind'].toString()),
              subtitle: Text(
                '${m.events[i]['side'] == null ? 'Match' : m.sideNames[(m.events[i]['side'] as num).toInt()]} · ${m.events[i]['at']}\n${m.events[i]['data']}',
              ),
              isThreeLine: true,
              onTap: () => _edit(context, state, m, i),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    PersonalGamesController state,
    PersonalMatch m,
    int index,
  ) async {
    // Offer actions valid immediately before this entry, rather than after the match.
    final original = m.events;
    final prefix = PersonalMatch(
      id: m.id,
      ownerId: m.ownerId,
      sport: m.sport,
      formatLabel: m.formatLabel,
      sideNames: m.sideNames,
      events: original.take(index).toList(),
      rules: m.rules,
      status: PersonalMatchStatus.inProgress,
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
    );
    final actions = state.progressOfPersonal(prefix).actions;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Edit score entry')),
            for (final action in actions)
              for (final side in action.pickSide ? [0, 1] : <int?>[null])
                ListTile(
                  title: Text(
                    '${action.label}${side == null ? '' : ' · ${m.sideNames[side]}'}',
                  ),
                  onTap: () {
                    state.replacePersonalEvent(
                      m.id,
                      index,
                      action.build(
                        ActionContext(
                          side: side,
                          by: context
                              .read<ProfileController>()
                              .currentAccount!
                              .id,
                        ),
                      ),
                    );
                    Navigator.pop(c);
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class PersonalStatsScreen extends StatelessWidget {
  const PersonalStatsScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PersonalGamesController>();
    final m = state.personalById(id);
    if (m == null ||
        m.ownerId != context.read<ProfileController>().currentAccount?.id) {
      return const SizedBox.shrink();
    }
    final p = state.progressOfPersonal(m);
    final counts = <String, int>{};
    for (final e in m.events) {
      counts.update(e['kind'].toString(), (v) => v + 1, ifAbsent: () => 1);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Match statistics')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(p.headline, style: Theme.of(context).textTheme.headlineSmall),
          for (final line in p.lines) KeyValueRow(line.label, line.value),
          for (final row in p.detailRows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(row),
            ),
          const SectionTitle('Recorded actions'),
          KeyValueRow('Total entries', '${m.events.length}'),
          for (final e in counts.entries) KeyValueRow(e.key, '${e.value}'),
          const InfoBanner(
            text: 'Statistics describe this private scorecard. Player-level performance is unavailable without attributed scoring entries.',
          ),
        ],
      ),
    );
  }
}

class PersonalPerformanceScreen extends StatelessWidget {
  const PersonalPerformanceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final games = context.watch<PersonalGamesController>().myPersonal;
    return Scaffold(
      appBar: AppBar(title: const Text('Personal performance overview')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const InfoBanner(
            text: 'Your recording activity, including spectator cards. These records do not establish player wins, rankings or official performance.',
          ),
          const SectionTitle('Personal game history'),
          KeyValueRow('Games recorded', '${games.length}'),
          KeyValueRow(
            'Completed',
            '${games.where((m) => m.status == PersonalMatchStatus.completed).length}',
          ),
          for (final sport in Sport.values)
            KeyValueRow(
              sport.label,
              '${games.where((m) => m.sport == sport).length} games',
            ),
          if (games.isEmpty)
            const EmptyState(
              title: 'Your story starts with a game',
              icon: Icons.insights,
            ),
        ],
      ),
    );
  }
}

class PersonalScoringSettingsScreen extends StatelessWidget {
  const PersonalScoringSettingsScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PersonalGamesController>();
    final m = state.personalById(id);
    if (m == null ||
        m.ownerId != context.read<ProfileController>().currentAccount?.id) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Scoring settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            title: const Text('Confirm before undo'),
            subtitle: const Text('Review before removing the last score.'),
            value: m.details['confirmUndo'] != false,
            onChanged: (v) =>
                state.updatePersonalDetails(id, {'confirmUndo': v}),
          ),
          const ListTile(
            leading: Icon(Icons.save_outlined),
            title: Text('Automatic saving'),
            subtitle: Text('Every entry is saved on this device.'),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Private scorecard'),
            subtitle: Text(
              'Organizer submission and official result updates are unavailable for personal games.',
            ),
          ),
        ],
      ),
    );
  }
}
