import 'package:sportika/shared/widgets/editorial.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/app/routes.dart';

class NewPersonalMatchScreen extends StatefulWidget {
  const NewPersonalMatchScreen({super.key, this.sport});
  final Sport? sport;
  @override
  State<NewPersonalMatchScreen> createState() => _NewPersonalMatchScreenState();
}

class _NewPersonalMatchScreenState extends State<NewPersonalMatchScreen> {
  int step = 0;
  late Sport sport = widget.sport ?? Sport.cricket;
  late String format = SportEngines.formatsFor(sport).first;
  final a = TextEditingController(),
      b = TextEditingController(),
      venue = TextEditingController(),
      notes = TextEditingController(),
      players = TextEditingController();
  final form = GlobalKey<FormState>();

  /// Set when the current step is not satisfied yet. The wizard never advances
  /// silently: the reason stays on screen until the gap is closed.
  String? _error;
  static const titles = [
    'Create personal game',
    'Select sport',
    'Game setup',
    'Add players / teams',
    'Game details & rules',
    'Review & start game',
  ];
  @override
  void dispose() {
    for (final c in [a, b, venue, notes, players]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> discard() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard game?'),
          content: const Text('Your unfinished setup will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      if (step > 0) {
        setState(() => step--);
      } else if (await discard() && context.mounted) {
        Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(title: Text(titles[step])),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'PERSONAL GAMES  /  ${step + 1} OF 6',
              style: const TextStyle(fontSize: 11, letterSpacing: 1.5),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: (step + 1) / 6),
            if (_error != null) ...[
              const SizedBox(height: 12),
              InlineBanner(
                icon: Icons.error_outline,
                tone: SportikaColors.danger,
                text: _error!,
              ),
            ],
            const SizedBox(height: 24),
            if (step == 0) ...[
              const Icon(Icons.sports_score, size: 72),
              const SizedBox(height: 24),
              Text(
                'Your game. Every point.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Set up a friendly match or keep your own spectator scorecard. Choose a sport, add your sides and start recording.',
              ),
            ],
            if (step == 1) ...[
              for (final s in Sport.values)
                Card(
                  child: ListTile(
                    selected: sport == s,
                    trailing: sport == s
                        ? const Icon(Icons.check_circle)
                        : null,
                    title: Text(s.label),
                    leading: Icon(sportGlyph(s)),
                    onTap: () => setState(() {
                      sport = s;
                      format = SportEngines.formatsFor(sport).first;
                    }),
                  ),
                ),
            ],
            if (step == 2) ...[
              const SectionTitle('Match format'),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in SportEngines.formatsFor(sport))
                    ChoiceChip(
                      label: Text(f),
                      selected: f == format,
                      onSelected: (_) => setState(() => format = f),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: venue,
                decoration: const InputDecoration(
                  labelText: 'Venue (optional)',
                  hintText: 'Court, ground or neighbourhood',
                ),
              ),
            ],
            if (step == 3) ...[
              TextFormField(
                controller: a,
                decoration: const InputDecoration(
                  labelText: 'Side A / player / team',
                ),
                validator: validateSide,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: b,
                decoration: const InputDecoration(
                  labelText: 'Side B / player / team',
                ),
                validator: (v) {
                  final error = validateSide(v);
                  return error ??
                      (v!.trim().toLowerCase() == a.text.trim().toLowerCase()
                          ? 'Choose different names'
                          : null);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: players,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Player roster (optional)',
                  hintText: 'One name per line; local notes only',
                ),
              ),
            ],
            if (step == 4) ...[
              InfoBanner(
                text: SportEngines.describeRules(
                  sport,
                  SportEngines.rulesFor(sport, format),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: notes,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Game notes / house rules',
                  helperText:
                      'Notes do not change the selected scoring format.',
                ),
              ),
            ],
            if (step == 5) ...[
              Text(
                '${a.text} vs ${b.text}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              KeyValueRow('Sport', sport.label),
              KeyValueRow('Format', format),
              KeyValueRow(
                'Venue',
                venue.text.isEmpty ? 'Not specified' : venue.text,
              ),
              if (players.text.isNotEmpty) KeyValueRow('Roster', players.text),
              if (notes.text.isNotEmpty) KeyValueRow('Notes', notes.text),
              InfoBanner(
                text: SportEngines.describeRules(
                  sport,
                  SportEngines.rulesFor(sport, format),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const InfoBanner(
              icon: Icons.lock_outline,
              text: 'Private to you. Never submitted to organizers and never used for official tournament results.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: Icon(step == 5 ? Icons.play_arrow : Icons.arrow_forward),
              label: Text(step == 5 ? 'Start game' : 'Continue'),
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final blocker = _blocker();
                if (blocker != null) {
                  setState(() => _error = blocker);
                  return;
                }
                if (step < 5) {
                  setState(() {
                    _error = null;
                    step++;
                  });
                  return;
                }
                final state = context.read<PersonalGamesController>();
                final m = state.startPersonalMatch(
                  sport: sport,
                  format: format,
                  sideA: a.text,
                  sideB: b.text,
                );
                state.updatePersonalDetails(m.id, {
                  'venue': venue.text,
                  'notes': notes.text,
                  'players': players.text,
                });
                pushReplacementRoute(
                  context,
                  AppRoute.personalSetup,
                  args: PersonalSetupArgs(m.id, startAfterSave: true),
                );
              },
            ),
            if (step > 0)
              TextButton(
                onPressed: () => setState(() {
                  _error = null;
                  step--;
                }),
                child: const Text('Back'),
              ),
          ],
        ),
      ),
    ),
  );

  /// Why the current step cannot advance, or null when it can. Only the step
  /// being shown is judged, so an untouched later step never blocks the wizard.
  String? _blocker() {
    switch (step) {
      case 2:
        if (format.trim().isEmpty) return 'Choose a match format to continue.';
      case 3:
        if (a.text.trim().isEmpty || b.text.trim().isEmpty) {
          return 'Name both sides before continuing.';
        }
        if (a.text.trim().toLowerCase() == b.text.trim().toLowerCase()) {
          return 'Side A and side B need different names.';
        }
    }
    return null;
  }

  String? validateSide(String? v) =>
      v == null || v.trim().isEmpty ? 'Enter a player or team name' : null;
}
