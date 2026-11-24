import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Me -> Official Scoring Hub.
///
/// One universal Sportika account can score fixtures and organize tournaments.
/// Assignments are server-authoritative; local fixture state is synchronized
/// only after the server operation succeeds.
class ScorerAssignmentsScreen extends StatefulWidget {
  const ScorerAssignmentsScreen({super.key});

  @override
  State<ScorerAssignmentsScreen> createState() =>
      _ScorerAssignmentsScreenState();
}

enum _AssignmentView { mine, managed }

class _ScorerAssignmentsScreenState extends State<ScorerAssignmentsScreen> {
  final TextEditingController _search = TextEditingController();

  _AssignmentView _view = _AssignmentView.mine;

  bool _showWizard = false;
  int _step = 0;

  String? _tournamentId;
  String? _fixtureId;
  ProfileSummary? _selectedPlayer;
  List<ProfileSummary>? _candidates;

  bool _searching = false;
  bool _assigning = false;
  String? _actionId;

  String? _searchError;
  String? _assignmentError;
  String? _actionError;

  int _searchGeneration = 0;

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
    _searchGeneration++;
    _search.dispose();
    super.dispose();
  }

  void _resetSearch() {
    _searchGeneration++;
    _search.clear();
    _candidates = null;
    _selectedPlayer = null;
    _searchError = null;
    _searching = false;
  }

  void _selectTournament(String? id) {
    setState(() {
      _tournamentId = id;
      _fixtureId = null;
      _assignmentError = null;
      _step = id == null ? 0 : 1;
      _resetSearch();
    });
  }

  void _selectFixture(String? id) {
    setState(() {
      _fixtureId = id;
      _assignmentError = null;
      _step = id == null ? 1 : 2;
      _resetSearch();
    });
  }

  void _closeWizard() {
    if (_assigning) return;

    setState(() {
      _showWizard = false;
      _step = 0;
      _tournamentId = null;
      _fixtureId = null;
      _assignmentError = null;
      _resetSearch();
    });
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();

    if (query.length < 2) {
      setState(() {
        _searchError = 'Enter at least two characters.';
        _candidates = null;
        _selectedPlayer = null;
      });
      return;
    }

    final generation = ++_searchGeneration;

    setState(() {
      _searching = true;
      _searchError = null;
      _candidates = null;
      _selectedPlayer = null;
    });

    try {
      final results = await context
          .read<ProfileModuleController>()
          .searchPlayers(query);

      if (!mounted || generation != _searchGeneration) return;

      setState(() {
        _candidates = results;
      });
    } on ProfileModuleException catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _searchError = error.message);
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchError = 'Unable to search members. Please try again.';
      });
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<bool> _confirmAssignment(
    String tournamentName,
    String matchName,
    ProfileSummary player,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Assign official scorer?'),
            content: Text(
              'Tournament: $tournamentName\n'
              'Match: $matchName\n'
              'Scorer: ${player.label}\n\n'
              'The member must accept the assignment before '
              'acting as the official scorer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm assignment'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _assign({
    required String tournamentName,
    required String matchName,
  }) async {
    if (_assigning) return;

    final tournamentId = _tournamentId;
    final fixtureId = _fixtureId;
    final player = _selectedPlayer;

    if (tournamentId == null || fixtureId == null || player == null) {
      return;
    }

    final confirmed = await _confirmAssignment(
      tournamentName,
      matchName,
      player,
    );

    if (!confirmed || !mounted) return;

    final module = context.read<ProfileModuleController>();
    final fixtures = context.read<FixturesController>();

    setState(() {
      _assigning = true;
      _assignmentError = null;
    });

    var serverAssigned = false;

    try {
      await module.claimOrganizer(tournamentId);

      await module.assignScorer(
        tournamentId: tournamentId,
        fixtureId: fixtureId,
        scorerId: player.id,
      );

      serverAssigned = true;

      // Local synchronization is secondary to the server operation.
      try {
        if (fixtures.fixtureById(fixtureId) != null) {
          fixtures.assignScorer(fixtureId, player.id);
        }
      } catch (_) {
        // Do not misreport a successful server assignment as failed.
      }

      if (!mounted) return;

      showSnack(
        context,
        '${player.label} has been invited to score this match.',
      );

      _closeWizard();
    } on ProfileModuleException catch (error) {
      if (!mounted) return;

      setState(() {
        _assignmentError = serverAssigned
            ? 'Assignment succeeded, but the local match view '
                  'may need refreshing.'
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _assignmentError = serverAssigned
            ? 'Assignment succeeded. Refresh the match view '
                  'if it has not updated.'
            : 'Unable to assign the scorer. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _assigning = false);
      }
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _respond(ScorerAssignment assignment, bool accept) async {
    if (_actionId != null) return;

    if (!accept) {
      final confirmed = await _confirmAction(
        title: 'Decline assignment?',
        message: 'You will decline this official scoring responsibility.',
        actionLabel: 'Decline',
      );

      if (!confirmed || !mounted) return;
    }

    final module = context.read<ProfileModuleController>();

    setState(() {
      _actionId = assignment.id;
      _actionError = null;
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
      setState(() => _actionError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionError = 'Unable to update the assignment.';
      });
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  Future<void> _revoke(ScorerAssignment assignment) async {
    if (_actionId != null) return;

    final confirmed = await _confirmAction(
      title: 'Revoke scorer assignment?',
      message: 'This will remove the scorer from the selected fixture.',
      actionLabel: 'Revoke',
    );

    if (!confirmed || !mounted) return;

    final module = context.read<ProfileModuleController>();
    final fixtures = context.read<FixturesController>();

    setState(() {
      _actionId = assignment.id;
      _actionError = null;
    });

    try {
      await module.revokeScorer(
        tournamentId: assignment.tournamentId,
        fixtureId: assignment.fixtureId,
        scorerId: assignment.scorerId,
      );

      try {
        fixtures.removeScorer(assignment.fixtureId, assignment.scorerId);
      } catch (_) {
        // Server revocation remains authoritative.
      }

      if (!mounted) return;

      showSnack(context, 'Assignment revoked');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _actionError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionError = 'Unable to revoke the assignment.';
      });
    } finally {
      if (mounted) setState(() => _actionId = null);
    }
  }

  String _matchTitle(FixturesController fixtures, ScorerAssignment assignment) {
    final fixture = fixtures.fixtureById(assignment.fixtureId);

    if (fixture == null) {
      return 'Official match';
    }

    return '${fixture.home.label} vs ${fixture.away.label}';
  }

  String _matchSubtitle(
    FixturesController fixtures,
    ScorerAssignment assignment,
  ) {
    final fixture = fixtures.fixtureById(assignment.fixtureId);

    if (fixture == null) {
      return 'Fixture details unavailable';
    }

    final tournament = fixtures.tournamentOf(fixture);

    return '${tournament?.name ?? "Tournament"} · ${fixture.stage}';
  }

  @override
  Widget build(BuildContext context) {
    final module = context.watch<ProfileModuleController>();
    final me = context.watch<ProfileRepository>().currentAccount;
    final tournaments = context.watch<TournamentRepository>();
    final fixtureController = context.watch<FixturesController>();

    if (me == null) {
      return const ScreenScaffold(
        title: 'Official scoring',
        child: ErrorState(
          title: 'Signed out',
          message: 'Sign in again to manage official scoring.',
        ),
      );
    }

    final organized = tournaments.tournamentsForOrganizer(me.id);

    final assignments = module.assignments;

    final mine = assignments
        .where((assignment) => assignment.scorerId == me.id)
        .toList();

    final managed = assignments
        .where((assignment) => assignment.authorizedBy == me.id)
        .toList();

    final pending = mine
        .where(
          (assignment) => assignment.status == ScorerAssignmentStatus.assigned,
        )
        .length;

    final activeManaged = managed
        .where((assignment) => assignment.status.isActive)
        .length;

    final selectedList = _view == _AssignmentView.mine ? mine : managed;

    final pendingList = selectedList
        .where(
          (assignment) => assignment.status == ScorerAssignmentStatus.assigned,
        )
        .toList();

    final activeList = selectedList
        .where(
          (assignment) => assignment.status == ScorerAssignmentStatus.accepted,
        )
        .toList();

    final historyList = selectedList
        .where(
          (assignment) =>
              assignment.status == ScorerAssignmentStatus.declined ||
              assignment.status == ScorerAssignmentStatus.revoked,
        )
        .toList();

    final selectedTournament = organized
        .where((tournament) => tournament.id == _tournamentId)
        .toList();

    final tournamentName = selectedTournament.isEmpty
        ? 'Tournament'
        : selectedTournament.first.name;

    final eligibleFixtures = _tournamentId == null
        ? <Fixture>[]
        : fixtureController
              .fixturesFor(_tournamentId!)
              .where((fixture) => fixture.status != FixtureStatus.published)
              .toList();

    final selectedFixture = eligibleFixtures
        .where((fixture) => fixture.id == _fixtureId)
        .toList();

    final matchName = selectedFixture.isEmpty
        ? 'Match'
        : '${selectedFixture.first.home.label} vs '
              '${selectedFixture.first.away.label}';

    return ScreenScaffold(
      title: 'Official scoring',
      onRefresh: module.loadAssignments,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ScoringHubHero(),

          const SizedBox(height: SportikaSpacing.lg),

          _ScoringMetrics(
            assigned: mine.length,
            pending: pending,
            managing: activeManaged,
          ),

          const SizedBox(height: SportikaSpacing.lg),

          _AssignmentViewSelector(
            selected: _view,
            mineCount: mine.length,
            managedCount: managed.length,
            onChanged: (value) {
              setState(() => _view = value);
            },
          ),

          const SizedBox(height: SportikaSpacing.lg),

          if (module.assignmentsError != null)
            ErrorState(
              title: 'Assignments could not be loaded',
              message: module.assignmentsError,
              compact: true,
              onRetry: module.loadAssignments,
            ),

          if (module.assignmentsLoading)
            const LoadingSkeleton(
              rows: 3,
              label: 'Loading official assignments',
            )
          else ...[
            if (pendingList.isNotEmpty) ...[
              const SectionHeader('Pending Response'),

              for (final assignment in pendingList)
                Padding(
                  padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                  child: _AssignmentCard(
                    assignment: assignment,
                    matchTitle: _matchTitle(fixtureController, assignment),
                    matchSubtitle: _matchSubtitle(
                      fixtureController,
                      assignment,
                    ),
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
                  ),
                ),
            ],

            if (activeList.isNotEmpty) ...[
              SectionHeader(
                _view == _AssignmentView.mine
                    ? 'Your Official Matches'
                    : 'Active Appointments',
              ),

              for (final assignment in activeList)
                Padding(
                  padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                  child: _AssignmentCard(
                    assignment: assignment,
                    matchTitle: _matchTitle(fixtureController, assignment),
                    matchSubtitle: _matchSubtitle(
                      fixtureController,
                      assignment,
                    ),
                    mine: assignment.scorerId == me.id,
                    busy: _actionId == assignment.id,
                    onRevoke:
                        assignment.authorizedBy == me.id &&
                            assignment.scorerId != me.id
                        ? () => _revoke(assignment)
                        : null,
                  ),
                ),
            ],

            if (historyList.isNotEmpty) ...[
              const SectionHeader('Assignment History'),

              for (final assignment in historyList)
                Padding(
                  padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                  child: _AssignmentCard(
                    assignment: assignment,
                    matchTitle: _matchTitle(fixtureController, assignment),
                    matchSubtitle: _matchSubtitle(
                      fixtureController,
                      assignment,
                    ),
                    mine: assignment.scorerId == me.id,
                    busy: false,
                    compact: true,
                  ),
                ),
            ],

            if (selectedList.isEmpty)
              EmptyState(
                title: _view == _AssignmentView.mine
                    ? 'No official matches yet'
                    : 'No scorer appointments yet',
                body: _view == _AssignmentView.mine
                    ? 'When an organizer assigns you a match, '
                          'it will appear here.'
                    : 'Matches you assign to other scorers '
                          'will appear here.',
                icon: Icons.sports_score_outlined,
              ),
          ],

          if (_actionError != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: _actionError!, tone: SportikaColors.danger),
          ],

          const SizedBox(height: SportikaSpacing.lg),

          _AssignScorerEntry(
            expanded: _showWizard,
            enabled: organized.isNotEmpty,
            onTap: () {
              if (_assigning) return;
              setState(() {
                _showWizard = !_showWizard;
                if (!_showWizard) {
                  _step = 0;
                  _tournamentId = null;
                  _fixtureId = null;
                  _resetSearch();
                }
              });
            },
          ),

          if (organized.isEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            const InfoBanner(
              icon: Icons.emoji_events_outlined,
              text:
                  'Organize a tournament and generate fixtures '
                  'to assign official scorers.',
            ),
          ],

          if (_showWizard && organized.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.md),

            _AssignmentWizard(
              step: _step,
              tournaments: organized,
              fixtures: eligibleFixtures,
              tournamentId: _tournamentId,
              fixtureId: _fixtureId,
              search: _search,
              candidates: _candidates,
              selectedPlayer: _selectedPlayer,
              searching: _searching,
              assigning: _assigning,
              searchError: _searchError,
              assignmentError: _assignmentError,
              onTournamentChanged: _selectTournament,
              onFixtureChanged: _selectFixture,
              onSearch: _runSearch,
              onSearchChanged: () {
                _searchGeneration++;
                setState(() {
                  _candidates = null;
                  _selectedPlayer = null;
                  _searchError = null;
                  _searching = false;
                });
              },
              onPlayerSelected: (player) {
                setState(() => _selectedPlayer = player);
              },
              onAssign: () =>
                  _assign(tournamentName: tournamentName, matchName: matchName),
              onCancel: _closeWizard,
            ),
          ],

          const SizedBox(height: SportikaSpacing.lg),

          const InfoBanner(
            icon: Icons.verified_user_outlined,
            text:
                'Only the tournament organizer can assign an '
                'official scorer. The selected member must '
                'accept the assignment before scoring.',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HUB HERO
// ============================================================

class _ScoringHubHero extends StatelessWidget {
  const _ScoringHubHero();

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        gradient: SportikaGradients.sportCoin(theme.live),
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_score_outlined, color: theme.live),
              const SizedBox(width: SportikaSpacing.sm),
              Text(
                'SPORTIKA / MATCH OFFICIALS',
                style: SportikaType.micro.copyWith(color: theme.live),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.lg),
          const Text('OFFICIAL\nSCORING HUB', style: SportikaType.title),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            'Manage match responsibilities and scorer appointments.',
            style: SportikaType.body.copyWith(color: theme.textBody),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DASHBOARD METRICS
// ============================================================

class _ScoringMetrics extends StatelessWidget {
  const _ScoringMetrics({
    required this.assigned,
    required this.pending,
    required this.managing,
  });

  final int assigned;
  final int pending;
  final int managing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            value: assigned,
            label: 'MY MATCHES',
            icon: Icons.sports_score_outlined,
            tone: SportikaColors.blueBright,
          ),
        ),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: _MetricTile(
            value: pending,
            label: 'PENDING',
            icon: Icons.schedule_outlined,
            tone: SportikaColors.gold,
          ),
        ),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: _MetricTile(
            value: managing,
            label: 'MANAGING',
            icon: Icons.assignment_ind_outlined,
            tone: SportikaColors.mint,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.tone,
  });

  final int value;
  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SportikaSpacing.xs,
        vertical: SportikaSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, color: tone),
          const SizedBox(height: SportikaSpacing.sm),
          Text('$value', style: SportikaType.title),
          const SizedBox(height: SportikaSpacing.xxs),
          Text(
            label,
            style: SportikaType.micro,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VIEW SELECTOR
// ============================================================

class _AssignmentViewSelector extends StatelessWidget {
  const _AssignmentViewSelector({
    required this.selected,
    required this.mineCount,
    required this.managedCount,
    required this.onChanged,
  });

  final _AssignmentView selected;
  final int mineCount;
  final int managedCount;
  final ValueChanged<_AssignmentView> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Row(
      children: [
        Expanded(
          child: _ViewButton(
            label: 'My Matches',
            count: mineCount,
            selected: selected == _AssignmentView.mine,
            tone: theme.live,
            onTap: () => onChanged(_AssignmentView.mine),
          ),
        ),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: _ViewButton(
            label: 'Assigned by Me',
            count: managedCount,
            selected: selected == _AssignmentView.managed,
            tone: theme.live,
            onTap: () => onChanged(_AssignmentView.managed),
          ),
        ),
      ],
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Material(
      color: selected ? theme.surfaceElevated : theme.surfaceSunken,
      borderRadius: BorderRadius.circular(SportikaRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SportikaSpacing.sm,
            vertical: SportikaSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(color: selected ? tone : theme.borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: SportikaType.caption.copyWith(
                    color: selected ? theme.textBody : theme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: SportikaSpacing.xs),
              Text(
                '$count',
                style: SportikaType.caption.copyWith(
                  color: selected ? tone : theme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ASSIGNMENT CARD
// ============================================================

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.assignment,
    required this.matchTitle,
    required this.matchSubtitle,
    required this.mine,
    required this.busy,
    this.compact = false,
    this.onAccept,
    this.onDecline,
    this.onRevoke,
  });

  final ScorerAssignment assignment;
  final String matchTitle;
  final String matchSubtitle;
  final bool mine;
  final bool busy;
  final bool compact;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

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
              Icon(Icons.shield_outlined, color: tone),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: Text(
                  matchTitle,
                  style: SportikaType.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              StatusPill(assignment.status.label, color: tone),
            ],
          ),

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            matchSubtitle,
            style: SportikaType.caption.copyWith(color: theme.textMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (!compact) ...[
            const SizedBox(height: SportikaSpacing.md),

            Row(
              children: [
                const Text('RESPONSIBILITY', style: SportikaType.micro),
                const Spacer(),
                Text(
                  mine ? 'Official Scorer' : 'Organizer',
                  style: SportikaType.caption.copyWith(color: theme.textBody),
                ),
              ],
            ),
          ],

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
                    tone: theme.textMuted,
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
            const SizedBox(height: SportikaSpacing.md),
            GhostButton(
              label: 'Revoke Assignment',
              icon: Icons.person_remove_outlined,
              tone: SportikaColors.danger,
              onPressed: busy ? null : onRevoke,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// ASSIGN SCORER ENTRY
// ============================================================

class _AssignScorerEntry extends StatelessWidget {
  const _AssignScorerEntry({
    required this.expanded,
    required this.enabled,
    required this.onTap,
  });

  final bool expanded;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      onTap: enabled ? onTap : null,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            decoration: BoxDecoration(
              color: theme.surfaceSunken,
              borderRadius: BorderRadius.circular(SportikaRadius.control),
            ),
            child: Icon(Icons.person_add_alt_1_outlined, color: theme.live),
          ),
          const SizedBox(width: SportikaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assign an Official Scorer',
                  style: SportikaType.bodyStrong,
                ),
                const SizedBox(height: SportikaSpacing.xs),
                Text(
                  'Choose a tournament, fixture and member.',
                  style: SportikaType.caption.copyWith(color: theme.textMuted),
                ),
              ],
            ),
          ),
          Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.arrow_forward_rounded,
            color: theme.live,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ASSIGNMENT WIZARD
// ============================================================

class _AssignmentWizard extends StatelessWidget {
  const _AssignmentWizard({
    required this.step,
    required this.tournaments,
    required this.fixtures,
    required this.tournamentId,
    required this.fixtureId,
    required this.search,
    required this.candidates,
    required this.selectedPlayer,
    required this.searching,
    required this.assigning,
    required this.searchError,
    required this.assignmentError,
    required this.onTournamentChanged,
    required this.onFixtureChanged,
    required this.onSearch,
    required this.onSearchChanged,
    required this.onPlayerSelected,
    required this.onAssign,
    required this.onCancel,
  });

  final int step;
  final List<Tournament> tournaments;
  final List<Fixture> fixtures;
  final String? tournamentId;
  final String? fixtureId;
  final TextEditingController search;
  final List<ProfileSummary>? candidates;
  final ProfileSummary? selectedPlayer;
  final bool searching;
  final bool assigning;
  final String? searchError;
  final String? assignmentError;

  final ValueChanged<String?> onTournamentChanged;
  final ValueChanged<String?> onFixtureChanged;
  final VoidCallback onSearch;
  final VoidCallback onSearchChanged;
  final ValueChanged<ProfileSummary> onPlayerSelected;
  final VoidCallback onAssign;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'NEW SCORER APPOINTMENT',
                  style: SportikaType.bodyStrong.copyWith(color: theme.live),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: assigning ? null : onCancel,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          _WizardProgress(step: step),

          const SizedBox(height: SportikaSpacing.lg),

          const Text('01 / Choose Tournament', style: SportikaType.bodyStrong),

          const SizedBox(height: SportikaSpacing.sm),

          DropdownButtonFormField<String>(
            key: const ValueKey('scorer-tournament'),
            initialValue: tournamentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tournament'),
            items: [
              for (final tournament in tournaments)
                DropdownMenuItem(
                  value: tournament.id,
                  child: Text(
                    tournament.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: assigning ? null : onTournamentChanged,
          ),

          if (tournamentId != null) ...[
            const SizedBox(height: SportikaSpacing.lg),

            const Text('02 / Select Match', style: SportikaType.bodyStrong),

            const SizedBox(height: SportikaSpacing.sm),

            if (fixtures.isEmpty)
              const HelperText(
                'No eligible fixtures are available for this tournament.',
              )
            else
              DropdownButtonFormField<String>(
                key: ValueKey('fixture-$tournamentId'),
                initialValue: fixtureId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Fixture'),
                items: [
                  for (final fixture in fixtures)
                    DropdownMenuItem(
                      value: fixture.id,
                      child: Text(
                        '${fixture.stage} · '
                        '${fixture.home.label} vs ${fixture.away.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: assigning ? null : onFixtureChanged,
              ),
          ],

          if (fixtureId != null) ...[
            const SizedBox(height: SportikaSpacing.lg),

            const Text(
              '03 / Choose Official Scorer',
              style: SportikaType.bodyStrong,
            ),

            const SizedBox(height: SportikaSpacing.sm),

            TextField(
              controller: search,
              enabled: !assigning,
              textInputAction: TextInputAction.search,
              onChanged: (_) => onSearchChanged(),
              onSubmitted: (_) => onSearch(),
              decoration: InputDecoration(
                labelText: 'Search Sportika Members',
                hintText: 'Name or @handle',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: searching || assigning ? null : onSearch,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),

            if (searching) ...[
              const SizedBox(height: SportikaSpacing.sm),
              const LinearProgressIndicator(),
            ],

            if (searchError != null) ...[
              const SizedBox(height: SportikaSpacing.sm),
              InlineBanner(text: searchError!, tone: SportikaColors.danger),
            ],

            if (candidates != null) ...[
              const SizedBox(height: SportikaSpacing.md),

              if (candidates!.isEmpty)
                const HelperText('No members matched your search.')
              else
                for (final player in candidates!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
                    child: _ScorerCandidateTile(
                      player: player,
                      selected: selectedPlayer?.id == player.id,
                      enabled: !assigning,
                      onTap: () => onPlayerSelected(player),
                    ),
                  ),
            ],

            if (selectedPlayer != null) ...[
              const SizedBox(height: SportikaSpacing.md),

              InfoBanner(
                icon: Icons.check_circle_outline_rounded,
                text:
                    '${selectedPlayer!.label} selected as '
                    'the proposed official scorer.',
              ),
            ],
          ],

          if (assignmentError != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: assignmentError!, tone: SportikaColors.danger),
          ],

          const SizedBox(height: SportikaSpacing.lg),

          PrimaryButton(
            label: 'Send Scorer Assignment',
            icon: Icons.assignment_ind_outlined,
            busy: assigning,
            onPressed:
                assigning ||
                    tournamentId == null ||
                    fixtureId == null ||
                    selectedPlayer == null
                ? null
                : onAssign,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WIZARD PROGRESS
// ============================================================

class _WizardProgress extends StatelessWidget {
  const _WizardProgress({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Row(
      children: [
        for (var index = 0; index < 3; index++) ...[
          Expanded(
            child: Container(
              height: SportikaSpacing.xs,
              decoration: BoxDecoration(
                color: index <= step ? theme.live : theme.borderSubtle,
                borderRadius: BorderRadius.circular(SportikaRadius.control),
              ),
            ),
          ),
          if (index < 2) const SizedBox(width: SportikaSpacing.xs),
        ],
      ],
    );
  }
}

// ============================================================
// SCORER SEARCH RESULT
// ============================================================

class _ScorerCandidateTile extends StatelessWidget {
  const _ScorerCandidateTile({
    required this.player,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ProfileSummary player;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Material(
      color: selected ? theme.surfaceElevated : theme.surfaceSunken,
      borderRadius: BorderRadius.circular(SportikaRadius.control),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        child: Container(
          padding: const EdgeInsets.all(SportikaSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(
              color: selected ? theme.live : theme.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              const BrandedDefaultAvatar(size: 40),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.label,
                      style: SportikaType.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      player.city.isEmpty
                          ? '@${player.username}'
                          : '${player.city} · @${player.username}',
                      style: SportikaType.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? SportikaColors.mint : theme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
