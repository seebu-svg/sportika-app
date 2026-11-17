import 'package:flutter/material.dart';
import 'package:sportika/features/matches/widgets/match_management_widgets.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Assigns, transfers or revokes the official scorer of one match.
///
/// A transfer is never a reset: the event log belongs to the match, so the new
/// scorer continues from the recorded score. Only the organizer can open this
/// sheet, and the database enforces the same rule.
Future<void> showMatchScorerSheet(
  BuildContext context, {
  required SportMatch match,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        SingleChildScrollView(child: _MatchScorerSheet(matchId: match.id)),
  );
}

class _MatchScorerSheet extends StatefulWidget {
  const _MatchScorerSheet({required this.matchId});

  final String matchId;

  @override
  State<_MatchScorerSheet> createState() => _MatchScorerSheetState();
}

class _MatchScorerSheetState extends State<_MatchScorerSheet> {
  final TextEditingController _search = TextEditingController();
  List<ProfileSummary>? _results;
  ProfileSummary? _picked;
  bool _searching = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    if (_busy || _searching) return;
    final profiles = context.read<ProfileModuleController>();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final found = await profiles.searchPlayers(_search.text);
      if (!mounted) return;
      setState(() => _results = found);
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _assign() async {
    final picked = _picked;
    if (picked == null) return;
    final matches = context.read<MatchController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await matches.assignScorer(widget.matchId, picked.id);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = matches.lastError;
      });
      return;
    }
    Navigator.of(context).pop();
    showSnack(context, '${picked.label} is the official scorer');
  }

  Future<void> _revoke() async {
    final matches = context.read<MatchController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await matches.revokeScorer(widget.matchId);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = matches.lastError;
      });
      return;
    }
    Navigator.of(context).pop();
    showSnack(context, 'The organizer will score this match');
  }

  @override
  Widget build(BuildContext context) {
    final match = context.watch<MatchController>().matchById(widget.matchId);
    final me = context.watch<SessionController>().currentAccount;
    if (match == null) {
      return const AppSheet(
        title: 'Official scorer',
        child: Text('This match is no longer available.'),
      );
    }
    final canManage =
        match.isOrganizer(me?.id) &&
        (match.status == FixtureStatus.upcoming ||
            match.status == FixtureStatus.live);
    final current = match.scorerId == null
        ? null
        : match.participantOf(match.scorerId)?.displayName ??
              context
                  .read<SessionController>()
                  .accountById(match.scorerId)
                  ?.displayName ??
              'Assigned scorer';

    return AppSheet(
      title: 'Official scorer',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MatchSheetIntro(
            icon: Icons.verified_user_outlined,
            title: current == null
                ? 'The organizer scores this match'
                : '$current scores this match',
            body: 'The scorer records play and submits the result. The organizer publishes it. Changing scorers preserves every entry.',
          ),
          if (!canManage)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: HelperText(
                'Scorer assignment is read-only for this match.',
              ),
            ),
          const SizedBox(height: SportikaSpacing.md),
          if (canManage) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    enabled: !_busy,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: const InputDecoration(
                      labelText: 'Find a registered player',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: SportikaSpacing.sm),
                GhostButton(
                  label: 'Search',
                  onPressed: _searching || _busy ? null : _runSearch,
                ),
              ],
            ),
            if (_searching) const LinearProgressIndicator(),
            if (_results != null) ...[
              const SizedBox(height: SportikaSpacing.sm),
              if (_results!.isEmpty)
                const HelperText('No member matched that search.')
              else
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (final player in _results!)
                        MatchMemberSearchTile(
                          player: player,
                          selected: _picked?.id == player.id,
                          note: match.scorerId == player.id
                              ? 'Current official scorer'
                              : null,
                          onTap: _busy || match.scorerId == player.id
                              ? null
                              : () => setState(() => _picked = player),
                        ),
                    ],
                  ),
                ),
            ],
            if (_picked != null) ...[
              const SizedBox(height: SportikaSpacing.sm),
              MatchSheetIntro(
                icon: Icons.check_circle_outline,
                title: _picked!.label,
                body: 'Selected as the next official scorer. Confirm below to assign.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: SportikaSpacing.md),
              InlineBanner(text: _error!, tone: SportikaColors.danger),
            ],
            const SizedBox(height: SportikaSpacing.md),
            PrimaryButton(
              label: match.scorerId == null
                  ? 'Assign official scorer'
                  : 'Transfer to this scorer',
              icon: Icons.assignment_ind_outlined,
              busy: _busy,
              onPressed: _busy || _picked == null ? null : _assign,
            ),
            if (match.scorerId != null && match.organizerId == me?.id) ...[
              const SizedBox(height: SportikaSpacing.sm),
              GhostButton(
                label: 'Let the organizer score',
                icon: Icons.person_outline,
                expand: true,
                onPressed: _busy ? null : _revoke,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
