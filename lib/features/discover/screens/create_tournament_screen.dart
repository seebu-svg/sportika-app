import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Spec §4.1: create and publish a tournament with its sport, dates, entry
/// type, registration limit and match rules.
class CreateTournamentScreen extends StatefulWidget {
  const CreateTournamentScreen({super.key});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController(text: 'Karachi');
  final _fee = TextEditingController(text: 'PKR 1,500');

  Sport _sport = Sport.padel;
  TournamentFormat _format = TournamentFormat.knockout;
  late EntryType _entryType = SportEngines.defaultEntryType(_sport);
  late String _ruleFormat = SportEngines.formatsFor(_sport).first;
  late DateTime _starts = _defaultStart();
  late DateTime _ends = _starts.add(const Duration(days: 1));
  int _limit = 8;
  bool _publishNow = true;

  static DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 18);
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rules = SportEngines.rulesFor(_sport, _ruleFormat);
    final rulesSummary = SportEngines.describeRules(_sport, rules);

    return Scaffold(
      appBar: sportikaAppBar(
        'Create tournament',
        subtitle: 'Organizer · draft or publish',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (!state.canOrganize) ...[
            const InfoBanner(
              icon: Icons.lock_outline,
              tone: SportikaColors.gold,
              text:
                  'Organizer access is required to publish an event. You can still '
                  'prepare the draft.',
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tournament name',
              hintText: 'e.g. Clifton Padel Open',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _fee,
                  decoration: const InputDecoration(labelText: 'Entry fee'),
                ),
              ),
            ],
          ),
          const SectionTitle('Sport'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final sport in Sport.values)
                _Chip(
                  label: sport.label,
                  active: sport == _sport,
                  tone: sportColor(sport),
                  onTap: () => setState(() {
                    _sport = sport;
                    _entryType = SportEngines.defaultEntryType(sport);
                    _ruleFormat = SportEngines.formatsFor(sport).first;
                  }),
                ),
            ],
          ),
          const SectionTitle('Format'),
          Row(
            children: [
              for (final format in TournamentFormat.values)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _Chip(
                    label: format.label,
                    active: format == _format,
                    tone: SportikaColors.blueBright,
                    onTap: () => setState(() => _format = format),
                  ),
                ),
            ],
          ),
          const SectionTitle('Entries are'),
          Row(
            children: [
              for (final type in EntryType.values)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: _Chip(
                    label: type.label,
                    active: type == _entryType,
                    tone: SportikaColors.mint,
                    onTap: () => setState(() => _entryType = type),
                  ),
                ),
            ],
          ),
          const SectionTitle('Match rules'),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final format in SportEngines.formatsFor(_sport))
                _Chip(
                  label: format,
                  active: format == _ruleFormat,
                  tone: sportColor(_sport),
                  onTap: () => setState(() => _ruleFormat = format),
                ),
            ],
          ),
          const SizedBox(height: 10),
          InfoBanner(
            icon: Icons.rule,
            tone: sportColor(_sport),
            text: rulesSummary,
          ),
          const SectionTitle('Registration limit'),
          Wrap(
            spacing: 7,
            children: [
              for (final limit in const [4, 8, 16, 32])
                _Chip(
                  label: '$limit',
                  active: limit == _limit,
                  tone: SportikaColors.gold,
                  onTap: () => setState(() => _limit = limit),
                ),
            ],
          ),
          const SectionTitle('Schedule'),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Starts ${dateShort(_starts)}',
                  icon: Icons.event_outlined,
                  expand: true,
                  onPressed: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GhostButton(
                  label: 'Ends ${dateShort(_ends)}',
                  icon: Icons.event_available_outlined,
                  expand: true,
                  onPressed: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _publishNow,
              activeTrackColor: SportikaColors.mint,
              title: const Text(
                'Open registration immediately',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _publishNow
                    ? 'Players can enter as soon as you save.'
                    : 'Saved as a draft only you can see.',
                style: const TextStyle(
                  fontSize: 11,
                  color: SportikaColors.textMuted,
                ),
              ),
              onChanged: (v) => setState(() => _publishNow = v),
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: _publishNow ? 'Publish tournament' : 'Save draft',
            icon: _publishNow ? Icons.campaign_outlined : Icons.save_outlined,
            tone: _publishNow ? SportikaColors.mint : SportikaColors.blue,
            onPressed: () => _create(state, rulesSummary, rules),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _starts : _ends;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final value = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time?.hour ?? initial.hour,
      time?.minute ?? initial.minute,
    );
    setState(() {
      if (isStart) {
        _starts = value;
        if (!_ends.isAfter(_starts)) {
          _ends = _starts.add(const Duration(days: 1));
        }
      } else {
        _ends = value.isAfter(_starts)
            ? value
            : _starts.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _create(
    AppState state,
    String rulesSummary,
    Map<String, dynamic> rules,
  ) async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Give the tournament a name first', error: true);
      return;
    }
    if (!state.canOrganize) {
      showSnack(
        context,
        'Organizer access is required to publish',
        error: true,
      );
      return;
    }
    await state.createTournament(
      name: _name.text,
      city: _city.text.trim().isEmpty ? 'Karachi' : _city.text.trim(),
      sport: _sport,
      format: _format,
      entryType: _entryType,
      startsAt: _starts,
      endsAt: _ends,
      registrationLimit: _limit,
      entryFee: _fee.text.trim().isEmpty ? 'PKR 0' : _fee.text.trim(),
      rulesSummary: rulesSummary,
      rules: rules,
      publishNow: _publishNow,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(
      context,
      _publishNow ? '${_name.text.trim()} is open for entries' : 'Draft saved',
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? tone.withValues(alpha: 0.16)
              : SportikaColors.surfaceSunken,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? tone : SportikaColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? tone : SportikaColors.textBody,
          ),
        ),
      ),
    );
  }
}
