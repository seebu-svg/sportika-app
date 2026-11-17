import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/monetization.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/core/state/tournaments_controller.dart';

/// Spec §4.1: create and publish a tournament with its sport, dates, entry
/// type, registration limit and match rules.
///
/// The premium toolkit is layered on top of that form and never replaces it: the
/// free ceilings, the two-group draw and the sport's own rules are exactly what
/// this screen did before monetization existed. A bigger registration list, a
/// chosen group count and the quick presets are Organizer Pro, and the value is
/// only kept after `has_entitlement` confirms it - so a stale or edited client
/// still produces a free tournament rather than an unpaid premium one.
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
  int? _groupCount;
  bool _publishNow = true;

  /// Entry sizes the form offers. Everything at or under the free cap behaves
  /// as it always did; the rest is the premium ladder from the plan row.
  static const List<int> _entryLadder = [4, 8, 12, 16, 24, 32, 48, 64, 96, 128];

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
    final state = context.watch<SessionController>();
    final billing = context.watch<MonetizationController>();
    // Painting uses the snapshot; the value itself is confirmed against the
    // server in _create before it is stored.
    final premium = billing.hasPremiumAccountTools;
    final rules = SportEngines.rulesFor(_sport, _ruleFormat);
    final rulesSummary = SportEngines.describeRules(_sport, rules);

    return Scaffold(
      appBar: sportikaAppBar(
        'Create tournament',
        subtitle: 'Your tournament · draft or publish',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (!state.canOrganize) ...[
            const InfoBanner(
              icon: Icons.lock_outline,
              tone: SportikaColors.gold,
              text:
                  'Sign in to publish an event. You can still '
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
            runSpacing: 7,
            children: [
              for (final limit in _entrySteps(billing, premium: premium))
                _Chip(
                  label: '$limit',
                  active: limit == _limit,
                  tone: limit > billing.freeEntryCap
                      ? SportikaColors.gold
                      : SportikaColors.blueBright,
                  onTap: () => setState(() => _limit = limit),
                ),
              if (!premium)
                _LockedChip(
                  label: '${billing.premiumEntryCap} places',
                  onTap: () => pushRoute(context, AppRoute.pricing),
                ),
            ],
          ),
          if (!premium)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Free events go up to ${billing.freeEntryCap}. Organizer Pro '
                'raises the ceiling to ${billing.premiumEntryCap} and a '
                'tournament pass raises one existing event.',
                style: const TextStyle(
                  fontSize: 11,
                  color: SportikaColors.textMuted,
                ),
              ),
            ),
          if (_format == TournamentFormat.group) ...[
            const SectionTitle('Group draw'),
            if (premium && billing.premiumGroupCounts.isNotEmpty)
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final count in billing.premiumGroupCounts)
                    _Chip(
                      label: '$count ${count == 1 ? 'group' : 'groups'}',
                      // The engine's own default is two, so "2" is not a premium
                      // choice - it is what every group event already drew.
                      active: (_groupCount ?? 2) == count,
                      tone: SportikaColors.gold,
                      onTap: () => setState(() => _groupCount = count),
                    ),
                ],
              )
            else ...[
              const InfoBanner(
                icon: Icons.grid_view_outlined,
                tone: SportikaColors.blueBright,
                text: 'The draw splits confirmed entries into 2 groups.',
              ),
              if (!premium)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GhostButton(
                    label: 'Unlock 1 to 4 groups',
                    icon: Icons.lock_open_outlined,
                    tone: SportikaColors.gold,
                    expand: true,
                    onPressed: () => pushRoute(context, AppRoute.pricing),
                  ),
                ),
            ],
          ],
          if (premium && billing.offersPremiumPresets) ...[
            const SectionTitle('Quick presets'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final preset in _presetsFor(billing))
                  _Chip(
                    label: preset.label,
                    active:
                        _format == preset.format &&
                        _limit == preset.limit &&
                        (_groupCount ?? 2) == (preset.groups ?? 2),
                    tone: SportikaColors.mint,
                    onTap: () => setState(() {
                      _format = preset.format;
                      _limit = preset.limit;
                      _groupCount = preset.groups;
                    }),
                  ),
              ],
            ),
          ],
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
            onPressed: () => _create(state, billing, rulesSummary, rules),
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

  /// Entry sizes the form offers. Without the premium toolkit this is exactly
  /// the free ladder the form has always had; with it, the plan's ceiling
  /// extends the same ladder.
  List<int> _entrySteps(
    MonetizationController billing, {
    required bool premium,
  }) {
    final ceiling = premium ? billing.premiumEntryCap : billing.freeEntryCap;
    final steps = _entryLadder.where((step) => step <= ceiling).toList();
    // A plan with an unusual ceiling still has to leave something to tap.
    return steps.isEmpty ? const <int>[4] : steps;
  }

  /// The quick presets, trimmed to what the plan actually grants. A preset is a
  /// convenience over the same three controls, never a way past a limit.
  List<_TournamentPreset> _presetsFor(MonetizationController billing) =>
      _premiumPresets
          .where((preset) => preset.limit <= billing.premiumEntryCap)
          .where(
            (preset) =>
                preset.groups == null ||
                billing.premiumGroupCounts.contains(preset.groups),
          )
          .toList(growable: false);

  Future<void> _create(
    SessionController state,
    MonetizationController billing,
    String rulesSummary,
    Map<String, dynamic> rules,
  ) async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Give the tournament a name first', error: true);
      return;
    }
    if (!state.canOrganize) {
      showSnack(context, 'Sign in to publish', error: true);
      return;
    }

    // The form may be showing premium chips from a snapshot; the value is only
    // kept if PostgreSQL still agrees the account holds the toolkit. Anything
    // else falls back to the free shape, so a tournament is always creatable.
    final freeCap = billing.freeEntryCap;
    var limit = _limit;
    var groupCount = _groupCount;
    if (limit > freeCap || groupCount != null) {
      final allowed = await billing.verifyEntitlement(
        featureKey: BillingFeature.organizerPremium,
      );
      if (!allowed) {
        if (limit > freeCap) limit = freeCap;
        groupCount = null;
        if (mounted) {
          showSnack(
            context,
            'Saved within the free limits. Organizer Pro raises them.',
          );
        }
      }
      if (!mounted) return;
    }

    await context.read<TournamentsController>().createTournament(
      name: _name.text,
      city: _city.text.trim().isEmpty ? 'Karachi' : _city.text.trim(),
      sport: _sport,
      format: _format,
      entryType: _entryType,
      startsAt: _starts,
      endsAt: _ends,
      registrationLimit: limit,
      entryFee: _fee.text.trim().isEmpty ? 'PKR 0' : _fee.text.trim(),
      rulesSummary: rulesSummary,
      rules: <String, dynamic>{...rules, 'groupCount': ?groupCount},
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

/// One tap that fills in format, ceiling and draw size together. Only the
/// numbers the plan grants are ever offered.
class _TournamentPreset {
  const _TournamentPreset(this.label, this.format, this.limit, this.groups);

  final String label;
  final TournamentFormat format;
  final int limit;
  final int? groups;
}

const List<_TournamentPreset> _premiumPresets = [
  _TournamentPreset('16 · knock-out', TournamentFormat.knockout, 16, null),
  _TournamentPreset('24 · 3 groups', TournamentFormat.group, 24, 3),
  _TournamentPreset('64 · knock-out', TournamentFormat.knockout, 64, null),
  _TournamentPreset('128 · 4 groups', TournamentFormat.group, 128, 4),
];

/// A premium value the member cannot pick yet, offered as a way to read the
/// plan rather than as a control that changes the tournament.
class _LockedChip extends StatelessWidget {
  const _LockedChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: SportikaColors.surfaceSunken,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: SportikaColors.gold.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 13,
              color: SportikaColors.gold,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: SportikaColors.gold,
              ),
            ),
          ],
        ),
      ),
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
