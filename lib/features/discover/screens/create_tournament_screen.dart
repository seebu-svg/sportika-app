import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Single-page Sportika tournament builder.
///
/// Every draw option is available to any signed-in organizer; publishing
/// behaviour is unchanged.
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
  bool _submitting = false;

  static const _entryLadder = <int>[4, 8, 12, 16, 24, 32, 48, 64, 96, 128];

  /// Group counts a group-format draw can be split into.
  static const _groupCounts = <int>[1, 2, 3, 4];

  static DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 18);
  }

  @override
  void initState() {
    super.initState();
    _name.addListener(_updatePreview);
    _city.addListener(_updatePreview);
    _fee.addListener(_updatePreview);
  }

  void _updatePreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_updatePreview);
    _city.removeListener(_updatePreview);
    _fee.removeListener(_updatePreview);
    _name.dispose();
    _city.dispose();
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionController>();

    final rules = SportEngines.rulesFor(_sport, _ruleFormat);

    final rulesSummary = SportEngines.describeRules(_sport, rules);

    final page = const EdgeInsets.symmetric(horizontal: SportikaSpacing.lg);

    return Scaffold(
      appBar: sportikaAppBar(
        'Create tournament',
        subtitle: 'Sportika Organizer',
      ),

      // --------------------------------------------------------
      // SCROLLABLE FORM
      // --------------------------------------------------------
      body: SafeArea(
        bottom: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: SportikaSpacing.xxl),
          children: [
            // --------------------------------------------------
            // CINEMATIC SPORT HERO
            // --------------------------------------------------

            _TournamentBuilderHero(sport: _sport),

            Padding(
              padding: page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!state.canOrganize) ...[
                    const SizedBox(height: SportikaSpacing.lg),
                    const InfoBanner(
                      icon: Icons.lock_outline,
                      tone: SportikaColors.gold,
                      text:
                          'Sign in to publish a tournament. '
                          'You can still prepare the form.',
                    ),
                  ],

                  // --------------------------------------------
                  // 01. IDENTITY
                  // --------------------------------------------
                  _builderSection(
                    number: '01',
                    title: 'Tournament identity',
                    subtitle: 'Give your competition a name and location.',
                    child: Column(
                      children: [
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Tournament name',
                            hintText: 'e.g. Clifton Padel Open',
                            prefixIcon: Icon(Icons.emoji_events_outlined),
                          ),
                        ),
                        const SizedBox(height: SportikaSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _city,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'City',
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: SportikaSpacing.sm),
                            Expanded(
                              child: TextField(
                                controller: _fee,
                                decoration: const InputDecoration(
                                  labelText: 'Entry fee',
                                  prefixIcon: Icon(Icons.payments_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // --------------------------------------------
                  // 02. SPORT
                  // --------------------------------------------
                  _builderSection(
                    number: '02',
                    title: 'Choose your sport',
                    subtitle:
                        'Your sport determines the available match rules.',
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final gap = SportikaSpacing.sm;
                        final tileWidth = (constraints.maxWidth - gap) / 2;

                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final sport in Sport.values)
                              SizedBox(
                                width: tileWidth,
                                child: _SportSelectionTile(
                                  sport: sport,
                                  selected: sport == _sport,
                                  onTap: () {
                                    setState(() {
                                      _sport = sport;
                                      _entryType =
                                          SportEngines.defaultEntryType(sport);
                                      _ruleFormat = SportEngines.formatsFor(
                                        sport,
                                      ).first;
                                    });
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                  // --------------------------------------------
                  // 03. COMPETITION STRUCTURE
                  // --------------------------------------------
                  _builderSection(
                    number: '03',
                    title: 'Competition structure',
                    subtitle: 'Choose how the tournament will run.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            for (final format in TournamentFormat.values) ...[
                              if (format != TournamentFormat.values.first)
                                const SizedBox(width: SportikaSpacing.sm),
                              Expanded(
                                child: _FormatSelectionCard(
                                  title: format.label,
                                  description:
                                      format == TournamentFormat.knockout
                                      ? 'Elimination bracket'
                                      : 'Group-stage draw',
                                  icon: format == TournamentFormat.knockout
                                      ? Icons.account_tree_outlined
                                      : Icons.grid_view_rounded,
                                  selected: format == _format,
                                  onTap: () => setState(() => _format = format),
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: SportikaSpacing.lg),

                        const Text('ENTRY TYPE', style: SportikaType.label),

                        const SizedBox(height: SportikaSpacing.sm),

                        Wrap(
                          spacing: SportikaSpacing.sm,
                          runSpacing: SportikaSpacing.sm,
                          children: [
                            for (final type in EntryType.values)
                              _BuilderChip(
                                label: type.label,
                                active: type == _entryType,
                                tone: SportikaColors.mint,
                                onTap: () => setState(() => _entryType = type),
                              ),
                          ],
                        ),

                        const SizedBox(height: SportikaSpacing.lg),

                        const Text('MATCH RULES', style: SportikaType.label),

                        const SizedBox(height: SportikaSpacing.sm),

                        Wrap(
                          spacing: SportikaSpacing.sm,
                          runSpacing: SportikaSpacing.sm,
                          children: [
                            for (final format in SportEngines.formatsFor(
                              _sport,
                            ))
                              _BuilderChip(
                                label: format,
                                active: format == _ruleFormat,
                                tone: sportColor(_sport),
                                onTap: () =>
                                    setState(() => _ruleFormat = format),
                              ),
                          ],
                        ),

                        const SizedBox(height: SportikaSpacing.md),

                        InfoBanner(
                          icon: Icons.rule_outlined,
                          tone: sportColor(_sport),
                          text: rulesSummary,
                        ),
                      ],
                    ),
                  ),

                  // --------------------------------------------
                  // 04. REGISTRATION
                  // --------------------------------------------
                  _builderSection(
                    number: '04',
                    title: 'Registration',
                    subtitle: 'Set how many entries your competition accepts.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: SportikaSpacing.sm,
                          runSpacing: SportikaSpacing.sm,
                          children: [
                            for (final limit in _entryLadder)
                              _BuilderChip(
                                label: '$limit',
                                active: limit == _limit,
                                tone: SportikaColors.blueBright,
                                onTap: () => setState(() => _limit = limit),
                              ),
                          ],
                        ),

                        if (_format == TournamentFormat.group) ...[
                          const SizedBox(height: SportikaSpacing.lg),

                          const Text('GROUP DRAW', style: SportikaType.label),

                          const SizedBox(height: SportikaSpacing.sm),

                          Wrap(
                            spacing: SportikaSpacing.sm,
                            runSpacing: SportikaSpacing.sm,
                            children: [
                              for (final count in _groupCounts)
                                _BuilderChip(
                                  label:
                                      '$count ${count == 1 ? 'group' : 'groups'}',
                                  active: (_groupCount ?? 2) == count,
                                  tone: SportikaColors.gold,
                                  onTap: () =>
                                      setState(() => _groupCount = count),
                                ),
                            ],
                          ),
                        ],

                        const SizedBox(height: SportikaSpacing.lg),

                        const Text('QUICK PRESETS', style: SportikaType.label),

                        const SizedBox(height: SportikaSpacing.sm),

                        Wrap(
                          spacing: SportikaSpacing.sm,
                          runSpacing: SportikaSpacing.sm,
                          children: [
                            for (final preset in _presets)
                              _BuilderChip(
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
                    ),
                  ),

                  // --------------------------------------------
                  // 05. SCHEDULE
                  // --------------------------------------------
                  _builderSection(
                    number: '05',
                    title: 'Schedule',
                    subtitle: 'Choose when your tournament begins and ends.',
                    child: Row(
                      children: [
                        Expanded(
                          child: _DateSelectionCard(
                            label: 'STARTS',
                            date: dateShort(_starts),
                            icon: Icons.event_outlined,
                            onTap: () => _pickDate(isStart: true),
                          ),
                        ),
                        const SizedBox(width: SportikaSpacing.sm),
                        Expanded(
                          child: _DateSelectionCard(
                            label: 'ENDS',
                            date: dateShort(_ends),
                            icon: Icons.event_available_outlined,
                            onTap: () => _pickDate(isStart: false),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --------------------------------------------
                  // 06. REVIEW & PUBLISHING
                  // --------------------------------------------
                  _builderSection(
                    number: '06',
                    title: 'Review & publish',
                    subtitle: 'Check your competition before creating it.',
                    child: Column(
                      children: [
                        _TournamentSummary(
                          name: _name.text.trim(),
                          city: _city.text.trim(),
                          sport: _sport,
                          format: _format,
                          entryType: _entryType,
                          limit: _limit,
                          starts: _starts,
                          ends: _ends,
                          fee: _fee.text.trim(),
                        ),

                        const SizedBox(height: SportikaSpacing.md),

                        SurfaceCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SportikaSpacing.md,
                            vertical: SportikaSpacing.xs,
                          ),
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _publishNow,
                            activeTrackColor: SportikaColors.mint,
                            title: const Text(
                              'Open registration immediately',
                              style: SportikaType.bodyStrong,
                            ),
                            subtitle: Text(
                              _publishNow
                                  ? 'Players can enter once published.'
                                  : 'Save privately as a draft.',
                              style: SportikaType.caption,
                            ),
                            onChanged: _submitting
                                ? null
                                : (value) =>
                                      setState(() => _publishNow = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // --------------------------------------------------------
      // STICKY PUBLISH ACTION
      // --------------------------------------------------------
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            SportikaSpacing.lg,
            SportikaSpacing.md,
            SportikaSpacing.lg,
            SportikaSpacing.md,
          ),
          decoration: const BoxDecoration(
            color: SportikaColors.surface,
            border: Border(top: BorderSide(color: SportikaColors.borderSubtle)),
          ),
          child: _submitting
              ? const Center(
                  heightFactor: 1.8,
                  child: CircularProgressIndicator(color: SportikaColors.mint),
                )
              : PrimaryButton(
                  label: _publishNow ? 'Publish tournament' : 'Save draft',
                  icon: _publishNow
                      ? Icons.campaign_outlined
                      : Icons.save_outlined,
                  tone: _publishNow ? SportikaColors.mint : SportikaColors.blue,
                  onPressed: () => _create(state, rulesSummary, rules),
                ),
        ),
      ),
    );
  }

  // ============================================================
  // NUMBERED SECTION
  // ============================================================

  Widget _builderSection({
    required String number,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: SportikaSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(SportikaSpacing.sm),
                decoration: BoxDecoration(
                  color: SportikaColors.blueSubtle,
                  borderRadius: BorderRadius.circular(SportikaRadius.sm),
                ),
                child: Text(
                  number,
                  style: SportikaType.label.copyWith(
                    color: SportikaColors.blueBright,
                  ),
                ),
              ),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: SportikaType.titleMedium),
                    const SizedBox(height: SportikaSpacing.xs),
                    Text(subtitle, style: SportikaType.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          child,
        ],
      ),
    );
  }

  // ============================================================
  // DATE PICKER
  // ============================================================

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

  // ============================================================
  // CREATE TOURNAMENT
  // ============================================================

  Future<void> _create(
    SessionController state,
    String rulesSummary,
    Map<String, dynamic> rules,
  ) async {
    if (_submitting) return;

    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Give the tournament a name first', error: true);
      return;
    }

    if (!state.canOrganize) {
      showSnack(context, 'Sign in to publish', error: true);
      return;
    }

    if (!_ends.isAfter(_starts)) {
      showSnack(context, 'End date must be after start date', error: true);
      return;
    }

    setState(() => _submitting = true);

    try {
      await context.read<TournamentsController>().createTournament(
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
        rules: <String, dynamic>{...rules, 'groupCount': ?_groupCount},
        publishNow: _publishNow,
      );

      if (!mounted) return;

      final tournamentName = _name.text.trim();
      final published = _publishNow;

      Navigator.of(context).pop();

      showSnack(
        context,
        published ? '$tournamentName is open for entries' : 'Draft saved',
      );
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'Could not create tournament. Please try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

// ============================================================
// CINEMATIC BUILDER HERO
// ============================================================

class _TournamentBuilderHero extends StatelessWidget {
  const _TournamentBuilderHero({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SportikaSpacing.xxl * 6.5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SportPhoto(
            sport: sport,
            height: SportikaSpacing.xxl * 6.5,
            radius: 0,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: SportikaGradients.imageFadeStrong,
            ),
          ),
          Positioned(
            left: SportikaSpacing.lg,
            right: SportikaSpacing.lg,
            bottom: SportikaSpacing.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPORTIKA / ORGANIZER',
                  style: SportikaType.micro.copyWith(
                    color: SportikaColors.mint,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.sm),
                Text(
                  'Create your next\ncompetition.',
                  style: SportikaType.hero.copyWith(
                    color: SportikaColors.onAccent,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.sm),
                Text(
                  'Set the stage. Define the rules. '
                  'Bring players together.',
                  style: SportikaType.caption.copyWith(
                    color: SportikaColors.onAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SPORT SELECTION TILE
// ============================================================

class _SportSelectionTile extends StatelessWidget {
  const _SportSelectionTile({
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  final Sport sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);

    return Material(
      color: selected ? SportikaColors.blueSubtle : SportikaColors.surface,
      borderRadius: BorderRadius.circular(SportikaRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.card),
            border: Border.all(color: selected ? tone : SportikaColors.border),
          ),
          child: Column(
            children: [
              SportGlyph(sport: sport, size: SportikaIconSize.xl, color: tone),
              const SizedBox(height: SportikaSpacing.sm),
              Text(sport.label, style: SportikaType.bodyStrong),
              if (selected) ...[
                const SizedBox(height: SportikaSpacing.xs),
                Icon(
                  Icons.check_circle_rounded,
                  color: tone,
                  size: SportikaIconSize.sm,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FORMAT SELECTION CARD
// ============================================================

class _FormatSelectionCard extends StatelessWidget {
  const _FormatSelectionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SportikaColors.surface,
      borderRadius: BorderRadius.circular(SportikaRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.card),
        child: Container(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.card),
            border: Border.all(
              color: selected
                  ? SportikaColors.blueBright
                  : SportikaColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: selected
                    ? SportikaColors.blueBright
                    : SportikaColors.textMuted,
                size: SportikaIconSize.lg,
              ),
              const SizedBox(height: SportikaSpacing.md),
              Text(title, style: SportikaType.bodyStrong),
              const SizedBox(height: SportikaSpacing.xs),
              Text(description, style: SportikaType.caption),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DATE SELECTION CARD
// ============================================================

class _DateSelectionCard extends StatelessWidget {
  const _DateSelectionCard({
    required this.label,
    required this.date,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String date;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SportikaColors.surface,
      borderRadius: BorderRadius.circular(SportikaRadius.card),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: SportikaColors.blueBright),
              const SizedBox(height: SportikaSpacing.sm),
              Text(label, style: SportikaType.micro),
              const SizedBox(height: SportikaSpacing.xs),
              Text(date, style: SportikaType.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// TOURNAMENT LIVE SUMMARY
// ============================================================

class _TournamentSummary extends StatelessWidget {
  const _TournamentSummary({
    required this.name,
    required this.city,
    required this.sport,
    required this.format,
    required this.entryType,
    required this.limit,
    required this.starts,
    required this.ends,
    required this.fee,
  });

  final String name;
  final String city;
  final Sport sport;
  final TournamentFormat format;
  final EntryType entryType;
  final int limit;
  final DateTime starts;
  final DateTime ends;
  final String fee;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOURNAMENT PREVIEW',
            style: SportikaType.micro.copyWith(color: SportikaColors.mint),
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            name.isEmpty ? 'Your tournament name' : name,
            style: SportikaType.cardTitle,
          ),
          const SizedBox(height: SportikaSpacing.md),
          _summaryRow('Sport', sport.label),
          _summaryRow('Location', city.isEmpty ? 'Karachi' : city),
          _summaryRow('Format', format.label),
          _summaryRow('Entries', '$limit · ${entryType.label}'),
          _summaryRow('Schedule', '${dateShort(starts)} - ${dateShort(ends)}'),
          _summaryRow('Entry fee', fee.isEmpty ? 'PKR 0' : fee),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: SportikaType.caption)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: SportikaType.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SELECTABLE CHIP
// ============================================================

class _BuilderChip extends StatelessWidget {
  const _BuilderChip({
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
    return Material(
      color: active
          ? tone.withValues(alpha: SportikaOpacity.muted)
          : SportikaColors.surfaceSunken,
      borderRadius: BorderRadius.circular(SportikaRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SportikaSpacing.md,
            vertical: SportikaSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.pill),
            border: Border.all(color: active ? tone : SportikaColors.border),
          ),
          child: Text(
            label,
            style: SportikaType.label.copyWith(
              color: active ? tone : SportikaColors.textBody,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DRAW PRESETS
// ============================================================

class _TournamentPreset {
  const _TournamentPreset(this.label, this.format, this.limit, this.groups);

  final String label;
  final TournamentFormat format;
  final int limit;
  final int? groups;
}

const List<_TournamentPreset> _presets = [
  _TournamentPreset('16 · knock-out', TournamentFormat.knockout, 16, null),
  _TournamentPreset('24 · 3 groups', TournamentFormat.group, 24, 3),
  _TournamentPreset('64 · knock-out', TournamentFormat.knockout, 64, null),
  _TournamentPreset('128 · 4 groups', TournamentFormat.group, 128, 4),
];
