import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Me → Official scorer assignments.
///
/// Two halves of one record: matches handed to the member, and matches the
/// member handed to someone else. The database only accepts an assignment from
/// the organizer who owns the match, which is why the panel first claims the
/// event and then names a fixture. Personal scorecards are deliberately absent.
class ScorerAssignmentsScreen extends StatefulWidget {
  const ScorerAssignmentsScreen({super.key});

  @override
  State<ScorerAssignmentsScreen> createState() =>
      _ScorerAssignmentsScreenState();
}

class _ScorerAssignmentsScreenState extends State<ScorerAssignmentsScreen> {
  final TextEditingController _search = TextEditingController();
  String? _tournamentId;
  String? _fixtureId;
  ProfileSummary? _selectedPlayer;
  List<ProfileSummary>? _candidates;
  bool _searching = false;
  bool _assigning = false;
  String? _actionId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileModuleController>().loadAssignments();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final players = await context
          .read<ProfileModuleController>()
          .searchPlayers(_search.text);
      if (!mounted) return;
      setState(() => _candidates = players);
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _assign() async {
    final tournamentId = _tournamentId;
    final fixtureId = _fixtureId;
    final player = _selectedPlayer;
    if (tournamentId == null || fixtureId == null || player == null) return;

    final module = context.read<ProfileModuleController>();
    final fixtures = context.read<FixturesController>();
    setState(() {
      _assigning = true;
      _error = null;
    });
    try {
      // First writer wins: claiming is what proves this member organizes the
      // event, and the assignment function refuses anyone who does not.
      await module.claimOrganizer(tournamentId);
      await module.assignScorer(
        tournamentId: tournamentId,
        fixtureId: fixtureId,
        scorerId: player.id,
      );
      // A device build also owns the fixture, so the scorer workspace has to
      // see the same assignment.
      if (fixtures.fixtureById(fixtureId) != null) {
        fixtures.assignScorer(fixtureId, player.id);
      }
      if (!mounted) return;
      showSnack(context, '${player.label} is assigned to this match');
      setState(() {
        _selectedPlayer = null;
        _candidates = null;
        _search.clear();
      });
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _respond(ScorerAssignment assignment, bool accept) async {
    final module = context.read<ProfileModuleController>();
    setState(() {
      _actionId = assignment.id;
      _error = null;
    });
    try {
      await module.respondToAssignment(
        assignmentId: assignment.id,
        accept: accept,
      );
      if (!mounted) return;
      showSnack(
        context,
        accept ? 'Assignment accepted' : 'Assignment declined',
      );
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  Future<void> _revoke(ScorerAssignment assignment) async {
    final module = context.read<ProfileModuleController>();
    final fixtures = context.read<FixturesController>();
    setState(() {
      _actionId = assignment.id;
      _error = null;
    });
    try {
      await module.revokeScorer(
        tournamentId: assignment.tournamentId,
        fixtureId: assignment.fixtureId,
        scorerId: assignment.scorerId,
      );
      fixtures.removeScorer(assignment.fixtureId, assignment.scorerId);
      if (!mounted) return;
      showSnack(context, 'Assignment revoked');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = context.watch<ProfileModuleController>();
    final me = context.watch<ProfileRepository>().currentAccount;
    final tournaments = context.watch<TournamentRepository>();
    if (me == null) {
      return const ScreenScaffold(
        title: 'Scorer assignments',
        child: ErrorState(
          title: 'Signed out',
          message: 'Sign in again to manage official scoring.',
        ),
      );
    }

    final organized = tournaments.tournamentsForOrganizer(me.id);
    final fixtures = _tournamentId == null
        ? const <Fixture>[]
        : context
              .watch<FixturesController>()
              .fixturesFor(_tournamentId!)
              .where((fixture) => fixture.status != FixtureStatus.published)
              .toList();

    return ScreenScaffold(
      title: 'Scorer assignments',
      onRefresh: module.loadAssignments,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Official scoring',
            title: 'Scorer assignments',
            subtitle:
                'A scorer counts a real fixture. Only the organizer of that '
                'match can hand it over, and the scorer has to accept.',
          ),
          if (module.assignmentsError != null)
            ErrorState(
              title: 'Assignments could not be loaded',
              message: module.assignmentsError,
              compact: true,
              onRetry: module.loadAssignments,
            ),
          if (module.assignmentsLoading)
            const LoadingSkeleton(rows: 2, label: 'Loading assignments')
          else ...[
            const SectionHeader('Your assignments'),
            if (module.assignments.isEmpty)
              const EmptyState(
                title: 'No official assignments',
                body:
                    'Matches you score, and matches you hand to someone else, '
                    'will be listed here.',
                icon: Icons.sports_score,
              ),
            for (final assignment in module.assignments)
              Padding(
                padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                child: _AssignmentCard(
                  assignment: assignment,
                  mine: assignment.scorerId == me.id,
                  busy: _actionId == assignment.id,
                  onAccept: assignment.scorerId == me.id
                      ? () => _respond(assignment, true)
                      : null,
                  onDecline: assignment.scorerId == me.id
                      ? () => _respond(assignment, false)
                      : null,
                  onRevoke:
                      assignment.authorizedBy == me.id &&
                          assignment.scorerId != me.id
                      ? () => _revoke(assignment)
                      : null,
                  matchLabel: _matchLabel(context, assignment),
                ),
              ),
          ],
          const SectionHeader('Hand a match to a scorer'),
          if (organized.isEmpty)
            const InfoBanner(
              icon: Icons.emoji_events_outlined,
              text:
                  'Organize a tournament with a generated draw to assign '
                  'official scorers.',
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _tournamentId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tournament'),
              items: [
                for (final tournament in organized)
                  DropdownMenuItem(
                    value: tournament.id,
                    child: Text(
                      tournament.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _assigning
                  ? null
                  : (value) => setState(() {
                      _tournamentId = value;
                      _fixtureId = null;
                      _error = null;
                    }),
            ),
            const SizedBox(height: SportikaSpacing.md),
            if (fixtures.isEmpty)
              const HelperText(
                'This tournament has no open fixture to hand over yet.',
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey(_tournamentId),
                initialValue: _fixtureId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Match'),
                items: [
                  for (final fixture in fixtures)
                    DropdownMenuItem(
                      value: fixture.id,
                      child: Text(
                        '${fixture.stage} · ${fixture.home.label} vs '
                        '${fixture.away.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _assigning
                    ? null
                    : (value) => setState(() => _fixtureId = value),
              ),
            const SizedBox(height: SportikaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                    decoration: const InputDecoration(
                      labelText: 'Find a member',
                      hintText: 'Name or @handle',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: SportikaSpacing.sm),
                GhostButton(
                  label: 'Search',
                  onPressed: _searching ? null : _runSearch,
                ),
              ],
            ),
            if (_searching) const LinearProgressIndicator(),
            if (_candidates != null) ...[
              const SizedBox(height: SportikaSpacing.sm),
              if (_candidates!.isEmpty)
                const HelperText('No member matched that search.')
              else
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (final player in _candidates!)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: Text(
                            player.label,
                            style: SportikaType.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            player.city.isEmpty
                                ? '@${player.username}'
                                : '${player.city} · @${player.username}',
                            style: SportikaType.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _selectedPlayer?.id == player.id
                              ? const Icon(
                                  Icons.check_circle,
                                  color: SportikaColors.mint,
                                  size: 20,
                                )
                              : null,
                          onTap: () => setState(() => _selectedPlayer = player),
                        ),
                    ],
                  ),
                ),
            ],
            if (_selectedPlayer != null) ...[
              const SizedBox(height: SportikaSpacing.sm),
              HelperText('Chosen: ${_selectedPlayer!.label}'),
            ],
            const SizedBox(height: SportikaSpacing.md),
            PrimaryButton(
              label: 'Assign scorer',
              icon: Icons.assignment_ind_outlined,
              busy: _assigning,
              onPressed:
                  _assigning ||
                      _tournamentId == null ||
                      _fixtureId == null ||
                      _selectedPlayer == null
                  ? null
                  : _assign,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: _error!, tone: SportikaColors.danger),
          ],
          const SizedBox(height: SportikaSpacing.md),
          const InfoBanner(
            icon: Icons.privacy_tip_outlined,
            text:
                'Personal scorecards are private and are never counted as '
                'official results. The scorer you choose must accept before '
                'they can open the match.',
          ),
        ],
      ),
    );
  }

  String _matchLabel(BuildContext context, ScorerAssignment assignment) {
    final fixture = context.read<FixturesController>().fixtureById(
      assignment.fixtureId,
    );
    if (fixture == null) {
      final id = assignment.fixtureId;
      return 'Match ${id.length > 8 ? id.substring(0, 8) : id}';
    }
    final tournament = context.read<FixturesController>().tournamentOf(fixture);
    return '${tournament?.name ?? 'Tournament'} · ${fixture.stage}';
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.assignment,
    required this.matchLabel,
    required this.mine,
    required this.busy,
    this.onAccept,
    this.onDecline,
    this.onRevoke,
  });

  final ScorerAssignment assignment;
  final String matchLabel;
  final bool mine;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final tone = switch (assignment.status) {
      ScorerAssignmentStatus.accepted => SportikaColors.mint,
      ScorerAssignmentStatus.assigned => SportikaColors.gold,
      ScorerAssignmentStatus.declined => SportikaColors.danger,
      ScorerAssignmentStatus.revoked => SportikaColors.textMuted,
    };
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  matchLabel,
                  style: SportikaType.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(assignment.status.label, color: tone),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mine ? 'You are the official scorer' : 'You assigned this match',
            style: SportikaType.caption,
          ),
          if (assignment.status == ScorerAssignmentStatus.assigned &&
              mine &&
              (onAccept != null || onDecline != null)) ...[
            const SizedBox(height: SportikaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'Decline',
                    expand: true,
                    tone: SportikaColors.textMuted,
                    onPressed: busy ? null : onDecline,
                  ),
                ),
                const SizedBox(width: SportikaSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Accept',
                    small: true,
                    tone: SportikaColors.mint,
                    busy: busy,
                    onPressed: busy ? null : onAccept,
                  ),
                ),
              ],
            ),
          ],
          if (onRevoke != null && assignment.status.isActive) ...[
            const SizedBox(height: SportikaSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: 'Revoke assignment',
                icon: Icons.person_remove_outlined,
                tone: SportikaColors.danger,
                onPressed: busy ? null : onRevoke,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
