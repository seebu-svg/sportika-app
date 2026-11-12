import 'package:sportika/shared/widgets/editorial.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';

/// Games board for the Discover tab: pickup matches you can find or manage.
class GamesTab extends StatefulWidget {
  const GamesTab({super.key});
  @override
  State<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<GamesTab> {
  Sport? sport;
  int tab = 0;
  String query = '', category = 'All Games';
  bool available = false;
  int? withinDays;
  double distance = 25;
  String status = 'Any';
  String myScope = 'All';
  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileController>();
    final games = context
        .read<GamesController>()
        .games
        .where(
          (g) =>
              (sport == null || g.sport == sport) &&
              (g.visibility == 'Public' ||
                  g.organizerId == state.currentAccount?.id ||
                  g.members.contains(state.currentAccount?.id)) &&
              (withinDays == null ||
                  g.at.isBefore(
                    DateTime.now().add(Duration(days: withinDays!)),
                  )) &&
              ((g.sport.index + 1) * 2.5 <= distance) &&
              (status == 'Any' || (status == 'Full' ? g.full : !g.full)) &&
              (tab != 1 ||
                  myScope == 'All' ||
                  (myScope == 'Organized'
                      ? g.organizerId == state.currentAccount?.id
                      : g.members.contains(state.currentAccount?.id))) &&
              (category == 'All Games' || g.category == category) &&
              (!available || !g.full) &&
              (tab != 1 ||
                  g.members.contains(state.currentAccount?.id) ||
                  g.organizerId == state.currentAccount?.id) &&
              '${g.title} ${g.venue} ${g.sport.label}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: FilterChipRow<int>(
            label: 'Game list',
            selected: tab,
            onChanged: (v) => setState(() => tab = v),
            choices: const [
              FilterChoice(0, 'Find Games'),
              FilterChoice(1, 'My Games'),
            ],
          ),
        ),
        if (tab == 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilterChipRow<String>(
              label: 'My games filter',
              padding: const EdgeInsets.symmetric(horizontal: 20),
              selected: myScope,
              onChanged: (v) => setState(() => myScope = v),
              choices: const [
                FilterChoice('All', 'All'),
                FilterChoice('Joined', 'Joined'),
                FilterChoice('Organized', 'Organized'),
              ],
            ),
          ),
        SportFilterBar(
          selected: sport,
          onChanged: (v) => setState(() => sport = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: 'Search games, sports or locations',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Filter games',
                onPressed: _showFilters,
                icon: Icon(
                  Icons.tune,
                  color: available ? SportikaColors.mint : null,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in ['All Games', 'Friendly', 'League', 'Tournament'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: c == category,
                    onSelected: (_) => setState(() => category = c),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: games.isEmpty
              ? const EmptyState(
                  title: 'No games found',
                  body:
                      'Try another sport or search, or create your own match.',
                  icon: Icons.sports,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: games.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => GameCard(game: games[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _showFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (_, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Find your next match',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                const Text('Date'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final days in [0, 7, 30])
                      ChoiceChip(
                        label: Text(days == 0 ? 'Any date' : 'Next $days days'),
                        selected: (withinDays ?? 0) == days,
                        onSelected: (_) =>
                            update(() => withinDays = days == 0 ? null : days),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Match status'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in ['Any', 'Open', 'Full'])
                      ChoiceChip(
                        label: Text(value),
                        selected: status == value,
                        onSelected: (_) => update(() => status = value),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available slots only'),
                  value: available,
                  onChanged: (v) => update(() => available = v),
                ),
                Text('Distance · ${distance.round()} km'),
                Slider(
                  value: distance,
                  min: 1,
                  max: 25,
                  divisions: 24,
                  onChanged: (v) => update(() => distance = v),
                ),
                const Text(
                  'Distances are fictional estimates from Clifton, Karachi.',
                  style: TextStyle(
                    fontSize: 11,
                    color: SportikaColors.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(sheet);
                    },
                    child: const Text('Show games'),
                  ),
                ),
                TextButton(
                  onPressed: () => update(() {
                    withinDays = null;
                    distance = 25;
                    status = 'Any';
                    available = false;
                  }),
                  child: const Text('Reset filters'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}

class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.game, this.openable = true});
  final bool openable;
  final CommunityGame game;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: openable
          ? () => pushRoute(
              context,
              AppRoute.gameDetail,
              args: GameDetailArgs(game),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SportPhoto(sport: game.sport, height: 164, radius: 0),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: SportikaColors.deepest.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sportGlyph(game.sport),
                        color: SportikaColors.mint,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        game.sport.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: game.full
                        ? SportikaColors.gold
                        : SportikaColors.mint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    game.full ? 'FULL' : 'OPEN TO JOIN',
                    style: const TextStyle(
                      color: SportikaColors.deepest,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${game.category.toUpperCase()}  /  ${game.format}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: SportikaColors.textMuted,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  game.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 16),
                _detail(
                  Icons.calendar_today_outlined,
                  '${dayLabel(game.at)} · ${timeLabel(game.at)}',
                ),
                const SizedBox(height: 9),
                _detail(Icons.location_on_outlined, game.venue),
                const SizedBox(height: 17),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: game.members.length / game.capacity,
                    minHeight: 3,
                    color: game.full
                        ? SportikaColors.gold
                        : SportikaColors.mint,
                    backgroundColor: SportikaColors.border,
                  ),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    const Icon(
                      Icons.group_outlined,
                      size: 15,
                      color: SportikaColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        game.full
                            ? 'All spots reserved'
                            : '${game.capacity - game.members.length} spots left · ${game.members.length} going',
                        style: const TextStyle(
                          fontSize: 11,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                    ),
                    if (openable) ...[
                      const Text(
                        'Match details',
                        style: TextStyle(
                          fontSize: 11,
                          color: SportikaColors.mint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: SportikaColors.mint,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _detail(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 14, color: SportikaColors.textMuted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: SportikaColors.textBody),
        ),
      ),
    ],
  );
}

class GameDetailScreen extends StatelessWidget {
  const GameDetailScreen({super.key, required this.game});
  final CommunityGame game;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfileController>();
    final joined = game.members.contains(state.currentAccount?.id);
    return Scaffold(
      appBar: AppBar(title: const Text('Match details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GameCard(game: game, openable: false),
          const SizedBox(height: 24),
          Text('Match overview', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(game.description),
          const SizedBox(height: 20),
          Text(
            'Organizer · ${context.read<SessionController>().accountById(game.organizerId)?.displayName ?? 'Sportika community'}',
          ),
          Text('Visibility · ${game.visibility}'),
          const SizedBox(height: 20),
          Text(
            'Players · ${game.members.length}/${game.capacity}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (var i = 0; i < game.members.length; i++)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(
                context
                        .read<SessionController>()
                        .accountById(game.members[i])
                        ?.displayName ??
                    context
                        .read<SessionController>()
                        .accounts[(i + 1) %
                            context.read<SessionController>().accounts.length]
                        .displayName,
              ),
              subtitle: Text(i == 0 ? 'Captain' : 'Confirmed player'),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: !joined && game.full
                ? null
                : () {
                    context.read<GamesController>().toggleGameJoin(game);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          joined
                              ? 'You left the match.'
                              : 'You’re in! Your spot is confirmed.',
                        ),
                      ),
                    );
                  },
            child: Text(
              joined
                  ? 'Leave match'
                  : game.full
                  ? 'Match full'
                  : 'Join match',
            ),
          ),
        ],
      ),
    );
  }
}

class CreateGameScreen extends StatefulWidget {
  const CreateGameScreen({super.key});
  @override
  State<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends State<CreateGameScreen> {
  final keyForm = GlobalKey<FormState>();
  final title = TextEditingController(),
      venue = TextEditingController(),
      capacity = TextEditingController(text: '22'),
      description = TextEditingController();
  Sport sport = Sport.cricket;
  String? format;
  String visibility = 'Public';
  DateTime date = DateTime.now().add(const Duration(days: 1));
  @override
  void dispose() {
    title.dispose();
    venue.dispose();
    capacity.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create match')),
    body: Form(
      key: keyForm,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'BRING YOUR PEOPLE. MAKE A MATCH.',
            style: TextStyle(
              color: SportikaColors.mint,
              letterSpacing: 1.5,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<Sport>(
            initialValue: sport,
            decoration: const InputDecoration(labelText: 'Sport'),
            items: Sport.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                .toList(),
            onChanged: (v) => setState(() {
              sport = v!;
              format = null;
              capacity.text = ['22', '4', '10', '4'][sport.index];
            }),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(sport),
            initialValue: format ?? SportEngines.formatsFor(sport).first,
            decoration: const InputDecoration(labelText: 'Match format'),
            items: SportEngines.formatsFor(sport)
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => format = v,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Match title'),
            validator: (v) => (v?.trim().length ?? 0) < 4
                ? 'Enter at least 4 characters'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: venue,
            decoration: const InputDecoration(labelText: 'Location / facility'),
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? 'Enter a location' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: capacity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Participant capacity',
            ),
            validator: (v) =>
                (int.tryParse(v ?? '') ?? 0) < 2 ||
                    (int.tryParse(v ?? '') ?? 0) > 100
                ? 'Choose 2–100 players'
                : null,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date and time'),
            subtitle: Text('$date'.substring(0, 16)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d == null || !context.mounted) return;
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(date),
              );
              if (t != null) {
                setState(
                  () =>
                      date = DateTime(d.year, d.month, d.day, t.hour, t.minute),
                );
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description and rules',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: visibility,
            decoration: const InputDecoration(labelText: 'Visibility'),
            items: [
              'Public',
              'Private',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => visibility = v!,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (!keyForm.currentState!.validate()) return;
              if (!date.isAfter(DateTime.now())) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Choose a future date and time.'),
                  ),
                );
                return;
              }
              final state = context.read<ProfileController>();
              context.read<GamesController>().publishGame(
                CommunityGame(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  title: title.text.trim(),
                  sport: sport,
                  venue: venue.text.trim(),
                  at: date,
                  capacity: int.parse(capacity.text),
                  organizerId: state.currentAccount!.id,
                  description: description.text.trim(),
                  visibility: visibility,
                  members: [state.currentAccount!.id],
                  format: format ?? SportEngines.formatsFor(sport).first,
                ),
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Match published. Let the game begin!'),
                ),
              );
            },
            child: const Text('Publish match'),
          ),
        ],
      ),
    ),
  );
}
