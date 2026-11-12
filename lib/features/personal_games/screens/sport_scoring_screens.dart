import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/personal_games/screens/personal_games_screen.dart';
import 'package:sportika/features/personal_games/screens/scorecard_screen.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';

/// All routes here resolve only the signed-in account's private scorecard.
PersonalMatch? privateMatch(BuildContext context, String id) {
  final state = context.watch<PersonalGamesController>();
  final match = state.personalById(id);
  return match?.ownerId == context.read<ProfileController>().currentAccount?.id
      ? match
      : null;
}

List<String> roster(PersonalMatch m, int side) =>
    (m.details['roster$side'] as List? ?? []).map((e) => e.toString()).toList();
const privateScoringNotice = InfoBanner(
  icon: Icons.lock_outline,
  text: 'Personal scoring · private to you. No organizer approval, official submission or comparison with another scorecard.',
);

List<String> sportScreens(Sport sport) => switch (sport) {
  Sport.cricket => [
    'Cricket match setup',
    'Toss & playing XI',
    'Live cricket scoring',
    'Batting scorecard',
    'Bowling scorecard',
    'Over history',
    'Innings summary',
    'Match result',
  ],
  Sport.padel => [
    'Padel match setup',
    'Singles / doubles player selection',
    'Live padel scoring',
    'Game & set tracker',
    'Tie-break scoring',
    'Match statistics',
    'Match result',
  ],
  Sport.futsal => [
    'Futsal match setup',
    'Team lineup',
    'Live futsal scoreboard',
    'Match timer & periods',
    'Goals, fouls & cards',
    'Match events timeline',
    'Match result',
  ],
  Sport.badminton => [
    'Badminton match setup',
    'Singles / doubles player selection',
    'Live badminton scoring',
    'Rally & point tracker',
    'Game / set progress',
    'Match statistics',
    'Match result',
  ],
};
void openSportScreen(BuildContext context, PersonalMatch m, int index) {
  if (index == 0 || index == 1) {
    openPersonal(
      context,
      SportMatchSetupScreen(id: m.id, playersOnly: index == 1),
    );
  } else if (index == 2) {
    openPersonal(
      context,
      ScorecardScreen(id: m.id, mode: ScorecardMode.personal),
    );
  } else {
    openPersonal(context, SportDetailScreen(id: m.id, index: index));
  }
}

class SportMatchCentreScreen extends StatelessWidget {
  const SportMatchCentreScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final m = privateMatch(context, id);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          m == null ? 'Match unavailable' : '${m.sport.label} match centre',
        ),
      ),
      body: m == null
          ? const EmptyState(
              title: 'Private game unavailable',
              icon: Icons.lock_outline,
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  m.sideNames.join(' vs '),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                privateScoringNotice,
                const SizedBox(height: 16),
                for (final e in sportScreens(m.sport).asMap().entries)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: sportColor(m.sport)
                            .withValues(alpha: .15),
                        child: Text('${e.key + 1}'),
                      ),
                      title: Text(e.value),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openSportScreen(context, m, e.key),
                    ),
                  ),
              ],
            ),
    );
  }
}

class SportMatchSetupScreen extends StatefulWidget {
  const SportMatchSetupScreen({
    super.key,
    required this.id,
    this.playersOnly = false,
    this.startAfterSave = false,
  });
  final String id;
  final bool playersOnly, startAfterSave;
  @override
  State<SportMatchSetupScreen> createState() => _SportMatchSetupScreenState();
}

class _SportMatchSetupScreenState extends State<SportMatchSetupScreen> {
  final form = GlobalKey<FormState>();
  final names = [TextEditingController(), TextEditingController()];
  String discipline = 'doubles', decision = 'bat';
  int toss = 0;
  bool loaded = false;
  @override
  void dispose() {
    for (final c in names) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = privateMatch(context, widget.id);
    if (m == null) {
      return Scaffold(appBar: AppBar(title: const Text('Match unavailable')));
    }
    if (!loaded) {
      for (var i = 0; i < 2; i++) {
        names[i].text = roster(m, i).join('\n');
      }
      discipline =
          m.details['discipline'] ?? m.rules['discipline'] ?? 'doubles';
      toss = m.details['tossWinner'] ?? 0;
      decision = m.details['tossDecision'] ?? 'bat';
      loaded = true;
    }
    final cricket = m.sport == Sport.cricket;
    final racket = m.sport == Sport.padel || m.sport == Sport.badminton;
    final locked = m.events.isNotEmpty;
    final count = cricket
        ? 11
        : racket
        ? (discipline == 'singles' ? 1 : 2)
        : 5;
    return Scaffold(
      appBar: AppBar(
        title: Text(sportScreens(m.sport)[widget.playersOnly ? 1 : 0]),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${m.sport.label.toUpperCase()} / PERSONAL',
              style: TextStyle(
                color: sportColor(m.sport),
                letterSpacing: 1.8,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              m.sideNames.join(' vs '),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (!widget.playersOnly) ...[
              KeyValueRow('Format', m.formatLabel),
              InfoBanner(text: SportEngines.describeRules(m.sport, m.rules)),
              const SizedBox(height: 16),
            ],
            if (locked)
              const InfoBanner(
                text: 'Scoring has started. Setup is read-only to preserve recorded player attribution and match rules.',
              ),
            if (racket) ...[
              const SectionTitle('Discipline'),
              FilterChipRow<String>(
                label: 'Discipline',
                selected: discipline,
                enabled: !locked,
                onChanged: (v) => setState(() => discipline = v),
                choices: const [
                  FilterChoice('singles', 'Singles'),
                  FilterChoice('doubles', 'Doubles'),
                ],
              ),
              const SizedBox(height: 12),
              if (m.sport == Sport.padel)
                const Text(
                  'Singles is a recreational format. Both disciplines use the selected padel scoring format.',
                ),
            ],
            if (cricket) ...[
              const SectionTitle('Toss'),
              DropdownButtonFormField<int>(
                initialValue: toss,
                decoration: const InputDecoration(labelText: 'Toss winner'),
                items: [
                  for (var i = 0; i < 2; i++)
                    DropdownMenuItem(value: i, child: Text(m.sideNames[i])),
                ],
                onChanged: locked ? null : (v) => setState(() => toss = v!),
              ),
              const SizedBox(height: 12),
              FilterChipRow<String>(
                label: 'Toss decision',
                selected: decision,
                enabled: !locked,
                onChanged: (v) => setState(() => decision = v),
                choices: const [
                  FilterChoice('bat', 'Bat first'),
                  FilterChoice('bowl', 'Bowl first'),
                ],
              ),
              const SizedBox(height: 12),
            ],
            SectionTitle(
              cricket
                  ? 'Playing XI'
                  : racket
                  ? 'Select players'
                  : 'Starting five',
            ),
            Text(
              'Enter $count ${count == 1 ? 'player' : 'players'} per side, one name per line. Names must be unique within each side.',
            ),
            const SizedBox(height: 16),
            for (var side = 0; side < 2; side++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  controller: names[side],
                  readOnly: locked,
                  minLines: count > 2 ? 5 : count,
                  maxLines: count > 2 ? 12 : 3,
                  decoration: InputDecoration(
                    labelText: m.sideNames[side],
                    hintText: 'One player name per line',
                  ),
                  validator: (v) {
                    final list = parse(v ?? '');
                    if (list.length != count) {
                      return 'Enter exactly $count players';
                    }
                    if (list.map((n) => n.toLowerCase()).toSet().length !=
                        count) {
                      return 'Player names must be unique';
                    }
                    return null;
                  },
                ),
              ),
            if (!locked)
              TextButton.icon(
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Fill fictional demo players'),
                onPressed: () => setState(() {
                  for (var side = 0; side < 2; side++) {
                    names[side].text = List.generate(
                      count,
                      (i) => '${m.sideNames[side]} player ${i + 1}',
                    ).join('\n');
                  }
                }),
              ),
            const SizedBox(height: 16),
            privateScoringNotice,
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (!locked) {
                  if (!form.currentState!.validate()) return;
                  context.read<PersonalGamesController>().updatePersonalDetails(
                    m.id,
                    {
                      'roster0': parse(names[0].text),
                      'roster1': parse(names[1].text),
                      'discipline': discipline,
                      if (cricket) 'tossWinner': toss,
                      if (cricket) 'tossDecision': decision,
                      if (cricket)
                        'firstBat': decision == 'bat' ? toss : 1 - toss,
                      'sportSetupComplete': true,
                    },
                  );
                }
                if (widget.startAfterSave) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScorecardScreen(
                        id: m.id,
                        mode: ScorecardMode.personal,
                      ),
                    ),
                  );
                } else {
                  Navigator.pop(context);
                }
              },
              child: Text(
                widget.startAfterSave
                    ? 'Start private scoring'
                    : locked
                    ? 'Back to match'
                    : 'Save setup',
              ),
            ),
            if (widget.startAfterSave)
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ScorecardScreen(id: m.id, mode: ScorecardMode.personal),
                  ),
                ),
                child: const Text('Score without player attribution'),
              ),
          ],
        ),
      ),
    );
  }

  List<String> parse(String text) =>
      text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// An always-visible doorway into each sport's dedicated screens and tools.
class SportLiveTools extends StatelessWidget {
  const SportLiveTools({super.key, required this.match});
  final PersonalMatch match;
  @override
  Widget build(BuildContext context) {
    final state = context.read<PersonalGamesController>();
    final p = state.progressOfPersonal(match);
    final cricket = match.sport == Sport.cricket;
    var batting = (p.state['batSide'] as int?) ?? -1;
    if (batting < 0) batting = match.details['firstBat'] ?? 0;
    if (p.statusLabel == 'Between innings') batting = 1 - batting;
    final bowl = 1 - batting;
    Widget select(String key, String label, List<String> options) {
      final value = match.details[key] as String?;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$key-${options.join()}-$value'),
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: '', child: Text('Unassigned')),
            for (final n in options)
              DropdownMenuItem(
                value: n,
                child: Text(n, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: match.status != PersonalMatchStatus.inProgress
              ? null
              : (v) => state.updatePersonalDetails(match.id, {key: v ?? ''}),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              sportGlyph(match.sport),
              color: sportColor(match.sport),
            ),
            title: Text('${match.sport.label} match centre'),
            subtitle: const Text('Setup, trackers, scorecards & result'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () =>
                openPersonal(context, SportMatchCentreScreen(id: match.id)),
          ),
        ),
        if (match.details['sportSetupComplete'] != true)
          TextButton(
            onPressed: () =>
                openPersonal(context, SportMatchSetupScreen(id: match.id)),
            child: const Text('Set up players & match details'),
          ),
        if (cricket && match.status != PersonalMatchStatus.completed) ...[
          Text(
            '${match.sideNames[batting]} batting · select players before each ball',
            style: const TextStyle(fontSize: 12),
          ),
          select('batter$batting', 'Striker', roster(match, batting)),
          select('bowler$bowl', 'Bowler', roster(match, bowl)),
          select('dismissal', 'Wicket type (for W)', const [
            'bowled',
            'caught',
            'lbw',
            'stumped',
            'hit wicket',
            'run out',
          ]),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Strike and bowler selection are manual. Unassigned deliveries remain in team totals.',
              style: TextStyle(fontSize: 11, color: SportikaColors.textMuted),
            ),
          ),
        ],
        if (match.sport == Sport.futsal) ...[
          FutsalClock(match: match),
          TextButton.icon(
            onPressed: () => openPersonal(
              context,
              SportDetailScreen(id: match.id, index: 4),
            ),
            icon: const Icon(Icons.style),
            label: const Text('Goals, fouls & cards'),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class FutsalClock extends StatefulWidget {
  const FutsalClock({super.key, required this.match});
  final PersonalMatch match;
  @override
  State<FutsalClock> createState() => _FutsalClockState();
}

class _FutsalClockState extends State<FutsalClock> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final p = context.read<PersonalGamesController>().progressOfPersonal(m);
    var elapsed = (p.state['periodElapsed'] as int?) ?? 0;
    final anchor = DateTime.tryParse(p.state['resumeAt'] ?? '');
    if (p.state['running'] == true && anchor != null) {
      elapsed += DateTime.now().difference(anchor).inSeconds.clamp(0, 86400);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'HALF ${p.state['half']} · ${p.statusLabel}',
              style: const TextStyle(fontSize: 11, letterSpacing: 1),
            ),
            Text(
              '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '${m.rules['halfMinutes']} minute periods · end each half manually',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class SportDetailScreen extends StatelessWidget {
  const SportDetailScreen({super.key, required this.id, required this.index});
  final String id;
  final int index;
  @override
  Widget build(BuildContext context) {
    final m = privateMatch(context, id);
    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Match unavailable')),
        body: const EmptyState(
          title: 'Private game unavailable',
          icon: Icons.lock_outline,
        ),
      );
    }
    final state = context.read<PersonalGamesController>();
    final p = state.progressOfPersonal(m);
    final title = sportScreens(m.sport)[index];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${m.sport.label.toUpperCase()} / ${m.status.label.toUpperCase()}',
            style: TextStyle(
              color: sportColor(m.sport),
              fontSize: 11,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            m.sideNames.join(' vs '),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (title == 'Match result') ...[
            Icon(
              p.isComplete ? Icons.emoji_events_outlined : Icons.sports_score,
              size: 64,
              color: SportikaColors.gold,
            ),
            const SizedBox(height: 16),
            Text(
              p.isComplete
                  ? p.resultLabel
                  : m.status == PersonalMatchStatus.completed
                  ? 'Game ended early'
                  : 'Match in progress',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (!p.isComplete)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No final winner inferred until the selected scoring rules are met.',
                ),
              ),
            for (final line in p.lines)
              KeyValueRow(line.label, '${line.value} ${line.sub ?? ''}'),
            for (final row in p.detailRows)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(row),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => openSportScreen(context, m, 2),
              child: const Text('View scorecard'),
            ),
          ] else if (m.sport == Sport.cricket)
            ..._cricket(context, m, p, index)
          else if (m.sport == Sport.futsal)
            ..._futsal(context, m, p, index)
          else
            ..._racket(context, m, p, index),
          const SizedBox(height: 24),
          privateScoringNotice,
        ],
      ),
    );
  }

  List<Widget> _cricket(
    BuildContext context,
    PersonalMatch m,
    MatchProgress p,
    int index,
  ) {
    final balls = cricketDeliveries(m);
    if (index == 3 || index == 4) {
      final batting = index == 3;
      return [
        const InfoBanner(
          text: 'Player figures come only from attributed deliveries. Unassigned entries remain visible; select striker and bowler on the live screen before recording each ball.',
        ),
        for (var side = 0; side < 2; side++) ...[
          SectionTitle(m.sideNames[side]),
          if (batting)
            cricketBattingTable(m, side, balls)
          else
            cricketBowlingTable(m, side, balls),
        ],
      ];
    }
    if (index == 5) {
      final overs = <String, List<CricketDelivery>>{};
      for (final b in balls) {
        overs
            .putIfAbsent('Innings ${b.innings} · Over ${b.over + 1}', () => [])
            .add(b);
      }
      return [
        if (overs.isEmpty)
          const EmptyState(
            title: 'Waiting for the first delivery',
            icon: Icons.sports_cricket,
          ),
        for (final over in overs.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    over.key,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in over.value)
                        Chip(
                          label: Text(b.label),
                          backgroundColor: b.wicket
                              ? SportikaColors.dangerSubtle
                              : SportikaColors.blueSubtle,
                        ),
                    ],
                  ),
                  Text(
                    '${over.value.fold<int>(0, (n, b) => n + b.total)} runs · ${over.value.where((b) => b.wicket).length} wickets',
                  ),
                ],
              ),
            ),
          ),
      ];
    }
    return [
      for (final line in p.lines)
        Card(
          child: ListTile(
            title: Text(line.label),
            trailing: Text(
              line.value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(line.sub ?? ''),
          ),
        ),
      for (final row in p.detailRows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(row),
        ),
      for (final chip in p.contextChips) Text(chip),
      if (balls.isEmpty)
        const EmptyState(
          title: 'No innings recorded yet',
          icon: Icons.sports_cricket,
        ),
      for (final innings in balls.map((b) => b.innings).toSet()) ...[
        SectionTitle('Innings $innings'),
        KeyValueRow(
          'Extras',
          '${balls.where((b) => b.innings == innings).fold<int>(0, (n, b) => n + b.extras)}',
        ),
        KeyValueRow(
          'Legal balls',
          '${balls.where((b) => b.innings == innings && b.legal).length}',
        ),
        KeyValueRow(
          'Boundaries',
          '${balls.where((b) => b.innings == innings && b.batRuns == 4).length} fours · ${balls.where((b) => b.innings == innings && b.batRuns == 6).length} sixes',
        ),
      ],
    ];
  }

  List<Widget> _racket(
    BuildContext context,
    PersonalMatch m,
    MatchProgress p,
    int index,
  ) {
    final padel = m.sport == Sport.padel;
    final progress = padel ? index == 3 : index == 4;
    final sets = padel
        ? (p.state['completedSets'] as List? ?? [])
        : (p.state['completedGames'] as List? ?? []);
    final current = p.state[padel ? 'games' : 'points'] as List? ?? [0, 0];
    if (progress) {
      return [
        Text(
          padel ? 'SET BY SET' : 'GAME BY GAME',
          style: const TextStyle(letterSpacing: 2, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _table(
          [(padel ? 'Set' : 'Game'), ...m.sideNames],
          [
            for (var i = 0; i < sets.length; i++)
              ['${i + 1}', '${sets[i][0]}', '${sets[i][1]}'],
            if (!p.isComplete) ['Current', '${current[0]}', '${current[1]}'],
          ],
        ),
        const SizedBox(height: 16),
        for (final line in p.lines)
          KeyValueRow(
            line.label,
            '${line.value} ${padel ? 'sets' : 'games'} won',
          ),
        for (final chip in p.contextChips)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(chip)),
        if (sets.isEmpty)
          const InfoBanner(
            text: 'No completed games or sets yet. Progress updates as points are recorded.',
          ),
      ];
    }
    if (padel && index == 4) {
      final active = p.state['inTiebreak'] == true;
      final tb = p.state['tiebreakPoints'] as List? ?? [0, 0];
      return [
        InfoBanner(
          icon: Icons.bolt,
          text: active ? 'Tie-break active. Win by two points.' : 'Tie-break starts automatically at 6–6. Continue normal scoring until then.',
        ),
        const SizedBox(height: 16),
        Text(
          '${tb[0]} – ${tb[1]}',
          style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        KeyValueRow(
          'Normal tie-break',
          '${m.rules['tiebreakPoints']} points, win by 2',
        ),
        KeyValueRow(
          'Deciding set',
          '${m.rules['finalSetTiebreakPoints']} points, win by 2',
        ),
        if (active && m.status == PersonalMatchStatus.inProgress)
          for (var side = 0; side < 2; side++)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FilledButton(
                onPressed: () =>
                    recordSportAction(context, m, p.actions.first, side),
                child: Text('Point · ${m.sideNames[side]}'),
              ),
            ),
        if (!active)
          TextButton(
            onPressed: () => openSportScreen(context, m, 2),
            child: const Text('Return to live scoring'),
          ),
        const SizedBox(height: 12),
        TextButton.icon(
          icon: const Icon(Icons.undo),
          onPressed: m.events.isEmpty
              ? null
              : () async {
                  if (await confirmPersonal(
                    context,
                    'Undo last point?',
                    'Recalculate the game and tie-break from recorded points.',
                    'Undo',
                  )) {
                    if (context.mounted) {
                      context.read<PersonalGamesController>().undoPersonalEvent(
                        m.id,
                      );
                    }
                  }
                },
          label: const Text('Undo last point'),
        ),
      ];
    }
    if (!padel && index == 3) {
      return [
        Text(
          '${current[0]} – ${current[1]}',
          style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        for (final chip in p.contextChips)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(chip),
          ),
        const InfoBanner(
          text: 'Every rally scores a point. Games to 21, win by two, capped at 30. The rally winner serves next.',
        ),
        const SizedBox(height: 16),
        if (m.status == PersonalMatchStatus.inProgress)
          for (var side = 0; side < 2; side++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton(
                onPressed: () =>
                    recordSportAction(context, m, p.actions.first, side),
                child: Text('Rally won · ${m.sideNames[side]}'),
              ),
            ),
        const SectionTitle('Rally history'),
        ..._pointHistory(m),
      ];
    }
    final points = m.events
        .where((e) => e['kind'] == (padel ? 'point' : 'rally'))
        .toList();
    final streak = [0, 0];
    var currentSide = -1, currentStreak = 0;
    for (final e in points) {
      final s = (e['side'] as int?) ?? 0;
      currentStreak = s == currentSide ? currentStreak + 1 : 1;
      currentSide = s;
      if (currentStreak > streak[s]) streak[s] = currentStreak;
    }
    return [
      _table(
        ['Recorded statistic', ...m.sideNames],
        [
          [
            '${padel ? 'Points' : 'Rallies'} won',
            for (var s = 0; s < 2; s++)
              '${points.where((e) => (e['side'] ?? 0) == s).length}',
          ],
          [
            'Share of ${padel ? 'points' : 'rallies'}',
            for (var s = 0; s < 2; s++)
              points.isEmpty
                  ? '—'
                  : '${(points.where((e) => (e['side'] ?? 0) == s).length * 100 / points.length).toStringAsFixed(1)}%',
          ],
          ['Longest streak', '${streak[0]}', '${streak[1]}'],
          [
            padel ? 'Sets won' : 'Games won',
            for (final line in p.lines) line.value,
          ],
        ],
      ),
      const SizedBox(height: 16),
      const InfoBanner(
        text: 'Statistics reflect recorded points only. Aces, winners and unforced errors are not inferred.',
      ),
    ];
  }

  List<Widget> _pointHistory(PersonalMatch m) {
    final events = m.events
        .where((e) => e['kind'] == 'rally' || e['kind'] == 'point')
        .toList();
    return [
      if (events.isEmpty)
        const EmptyState(title: 'No points yet', icon: Icons.sports_tennis),
      for (var i = events.length - 1; i >= 0; i--)
        ListTile(
          leading: Text('#${i + 1}'),
          title: Text(m.sideNames[(events[i]['side'] as int?) ?? 0]),
          subtitle: Text('Point won · ${events[i]['at']}'),
        ),
    ];
  }

  List<Widget> _futsal(
    BuildContext context,
    PersonalMatch m,
    MatchProgress p,
    int index,
  ) {
    if (index == 3) {
      return [
        FutsalClock(match: m),
        const SizedBox(height: 16),
        for (final row in p.detailRows) Text(row),
        const SizedBox(height: 16),
        if (m.status == PersonalMatchStatus.inProgress)
          for (final a in p.actions.where((a) => !a.pickSide))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton(
                onPressed: () async {
                  if (a.id == 'end_half' &&
                      !await confirmPersonal(
                        context,
                        'End this period?',
                        'Keep the current score and move to the next match phase.',
                        'End period',
                      )) {
                    return;
                  }
                  if (context.mounted) recordSportAction(context, m, a, null);
                },
                child: Text(a.label),
              ),
            ),
        const InfoBanner(
          text: 'Stop the clock during stoppages. Periods end when you confirm; the prototype does not end them automatically.',
        ),
      ];
    }
    final events = m.events
        .where(
          (e) => [
            'goal',
            'foul',
            'yellow_card',
            'red_card',
            'penalty',
          ].contains(e['kind']),
        )
        .toList();
    if (index == 4) {
      return [
        for (var side = 0; side < 2; side++) ...[
          SectionTitle(m.sideNames[side]),
          KeyValueRow(
            'Goals',
            '${events.where((e) => e['side'] == side && e['kind'] == 'goal').length}',
          ),
          KeyValueRow(
            'Accumulated fouls · half ${p.state['half']}',
            '${events.where((e) => e['side'] == side && e['kind'] == 'foul' && (e['data'] as Map)['half'] == (p.state['half'] as int) - 1).length}',
          ),
          KeyValueRow(
            'Cards',
            '${events.where((e) => e['side'] == side && e['kind'] == 'yellow_card').length} yellow · ${events.where((e) => e['side'] == side && e['kind'] == 'red_card').length} red',
          ),
          if (m.status == PersonalMatchStatus.inProgress &&
              ['running', 'paused'].contains(p.state['phase']))
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in ['goal', 'foul', 'yellow_card', 'red_card'])
                  OutlinedButton(
                    onPressed: () => _eventDialog(context, m, p, side, kind),
                    child: Text(kind.replaceAll('_', ' ')),
                  ),
              ],
            ),
        ],
        const SizedBox(height: 16),
        const InfoBanner(
          text: 'Fouls are counted separately per half. From the sixth accumulated foul, follow your chosen penalty procedure. Cards are recorded as events; substitutions and disciplinary enforcement are manual.',
        ),
      ];
    }
    return [
      if (m.events.isEmpty)
        const EmptyState(title: 'No match events yet', icon: Icons.timeline),
      for (final event in m.events.reversed)
        Card(
          child: ListTile(
            leading: Icon(
              event['kind'] == 'goal'
                  ? Icons.sports_soccer
                  : event['kind'] == 'clock'
                  ? Icons.timer_outlined
                  : Icons.style,
            ),
            title: Text(
              '${event['kind'].toString().replaceAll('_', ' ')}${event['side'] == null ? '' : ' · ${m.sideNames[event['side'] as int]}'}',
            ),
            subtitle: Text(
              '${(event['data'] as Map)['player'] ?? ''} ${(event['data'] as Map)['action'] ?? ''}\n${event['at']}',
            ),
            isThreeLine: true,
          ),
        ),
      TextButton(
        onPressed: () =>
            openPersonal(context, PersonalTimelineScreen(id: m.id)),
        child: const Text('Edit event history'),
      ),
    ];
  }

  Future<void> _eventDialog(
    BuildContext context,
    PersonalMatch m,
    MatchProgress p,
    int side,
    String kind,
  ) async {
    String player = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Record ${kind.replaceAll('_', ' ')}'),
        content: DropdownButtonFormField<String>(
          initialValue: '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Player'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Unassigned')),
            for (final n in roster(m, side))
              DropdownMenuItem(
                value: n,
                child: Text(n, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => player = v ?? '',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (save == true && context.mounted) {
      context.read<PersonalGamesController>().recordPersonalEvent(
        m.id,
        ScoringEvent(
          id: newId('ev'),
          kind: kind,
          side: side,
          data: {
            'half': (p.state['half'] as int) - 1,
            if (player.isNotEmpty) 'player': player,
          },
          at: DateTime.now(),
          byAccountId: context.read<SessionController>().currentAccount!.id,
        ),
      );
    }
  }
}

Future<void> recordSportAction(
  BuildContext context,
  PersonalMatch m,
  ScoreAction a,
  int? side,
) async {
  final state = context.read<PersonalGamesController>();
  final e = a.build(
    ActionContext(
      side: side,
      by: context.read<ProfileController>().currentAccount!.id,
    ),
  );
  state.recordPersonalEvent(m.id, e);
}

Widget _table(List<String> headings, List<List<String>> rows) =>
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        columns: [for (final h in headings) DataColumn(label: Text(h))],
        rows: [
          for (final row in rows)
            DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
        ],
      ),
    );

class CricketDelivery {
  CricketDelivery(this.event, this.innings, this.over);
  final ScoringEvent event;
  final int innings, over;
  String get extra => event.data['extra'] ?? '';
  int get runs => (event.data['runs'] as num?)?.toInt() ?? 0;
  bool get legal => extra != 'wide' && extra != 'noball';
  bool get wicket => event.data['wicket'] == true;
  int get batRuns =>
      extra == 'bye' || extra == 'legbye' || extra == 'wide' ? 0 : runs;
  int get total => runs + (extra == 'wide' || extra == 'noball' ? 1 : 0);
  int get extras => total - batRuns;
  String get batter => event.data['batter'] ?? 'Unassigned';
  String get bowler => event.data['bowler'] ?? 'Unassigned';
  bool get bowlerWicket =>
      wicket &&
      event.data['dismissal'] != null &&
      event.data['dismissal'] != 'run out';
  String get label => wicket
      ? 'W'
      : extra == 'wide'
      ? 'Wd'
      : extra == 'noball'
      ? 'Nb'
      : extra == 'bye'
      ? 'B$runs'
      : extra == 'legbye'
      ? 'Lb$runs'
      : '$runs';
}

List<CricketDelivery> cricketDeliveries(PersonalMatch m) {
  final output = <CricketDelivery>[];
  final raw = <Map<String, dynamic>>[];
  var innings = 0, legal = 0;
  for (final event in m.events) {
    raw.add(event);
    if (event['kind'] != 'ball') continue;
    final p = SportEngines.progressOf(
      sport: m.sport,
      sides: m.sideNames,
      rules: m.rules,
      rawEvents: raw,
    );
    final next = p.state['innings'] as int;
    if (next != innings) {
      innings = next;
      legal = 0;
    }
    final b = CricketDelivery(
      ScoringEvent.fromJson(event),
      innings,
      legal ~/ 6,
    );
    output.add(b);
    if (b.legal) legal++;
  }
  return output;
}

Widget cricketBattingTable(
  PersonalMatch m,
  int side,
  List<CricketDelivery> balls,
) {
  final own = balls.where((b) => b.event.side == side).toList();
  final names = {...roster(m, side), ...own.map((b) => b.batter)};
  return _table(
    ['Batter', 'R', 'B', '4s', '6s', 'SR', 'Dismissal'],
    [
      for (final name in names)
        _batRow(name, own.where((b) => b.batter == name).toList()),
    ],
  );
}

List<String> _batRow(String name, List<CricketDelivery> balls) {
  final runs = balls.fold<int>(0, (n, b) => n + b.batRuns);
  final faced = balls.where((b) => b.legal).length;
  final wickets = balls.where((b) => b.wicket);
  return [
    name,
    '$runs',
    '$faced',
    '${balls.where((b) => b.batRuns == 4).length}',
    '${balls.where((b) => b.batRuns == 6).length}',
    faced == 0 ? '—' : (runs * 100 / faced).toStringAsFixed(1),
    wickets.isEmpty
        ? (balls.isEmpty ? 'Yet to bat' : 'Not out')
        : wickets.last.event.data['dismissal'] ?? 'Unspecified',
  ];
}

Widget cricketBowlingTable(
  PersonalMatch m,
  int side,
  List<CricketDelivery> balls,
) {
  final own = balls.where((b) => b.event.side == 1 - side).toList();
  final names = {...roster(m, side), ...own.map((b) => b.bowler)};
  return _table(
    ['Bowler', 'O', 'R', 'W', 'Econ'],
    [
      for (final name in names)
        _bowlRow(name, own.where((b) => b.bowler == name).toList()),
    ],
  );
}

List<String> _bowlRow(String name, List<CricketDelivery> balls) {
  final legal = balls.where((b) => b.legal).length;
  final runs = balls.fold<int>(
    0,
    (n, b) => n + (b.extra == 'bye' || b.extra == 'legbye' ? 0 : b.total),
  );
  return [
    name,
    '${legal ~/ 6}.${legal % 6}',
    '$runs',
    '${balls.where((b) => b.bowlerWicket).length}',
    legal == 0 ? '—' : (runs * 6 / legal).toStringAsFixed(2),
  ];
}
