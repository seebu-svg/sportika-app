import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The actions a member can take on a match right now.
///
/// Every button mirrors one RPC from migrations 0007, 0013 and 0014: the bar
/// only offers what the server would accept for this status and this role, so a
/// refusal is the exception rather than the normal path. The widgets stay dumb —
/// the detail screen owns confirmation dialogs and the busy flag.
class MatchLifecycleBar extends StatelessWidget {
  const MatchLifecycleBar({
    super.key,
    required this.match,
    required this.accountId,
    this.busy = false,
    this.compact = false,
    this.onStart,
    this.onScore,
    this.onPause,
    this.onResume,
    this.onSubmit,
    this.onPublish,
    this.onCorrect,
    this.onWalkover,
    this.onRetire,
    this.onDispute,
    this.onCancel,
    this.onInvite,
    this.onAssignScorer,
    this.onRespond,
    this.onJoinSide,
    this.onLeave,
  });

  final SportMatch match;
  final String? accountId;
  final bool busy;
  final bool compact;

  final VoidCallback? onStart;
  final VoidCallback? onScore;

  /// `pause_match` / `resume_match`: only the organizer or the official scorer,
  /// and only while the match is live.
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  final VoidCallback? onSubmit;
  final VoidCallback? onPublish;
  final VoidCallback? onCorrect;
  final VoidCallback? onWalkover;

  /// `retire_match`: a badminton match that will not reach the winning game.
  /// The scorer or the organizer names the winner and gives a reason, and the
  /// partial score comes from the rally log.
  final VoidCallback? onRetire;

  /// `raise_match_dispute`: any member of the match, once a result exists.
  /// Never gated on an entitlement.
  final VoidCallback? onDispute;

  final VoidCallback? onCancel;
  final VoidCallback? onInvite;
  final VoidCallback? onAssignScorer;

  /// Accepts or declines the invitation. Only used while the member is still
  /// `invited`.
  final void Function(bool accept)? onRespond;

  /// `join_match`: a public match, before kick-off, for somebody who is not
  /// already in it. The side is 0 or 1.
  final void Function(int side)? onJoinSide;

  /// `leave_match`: the caller is on the match and may still walk away.
  final VoidCallback? onLeave;

  bool get _isOrganizer => match.organizerId == accountId;
  bool get _canScore =>
      match.canScore(accountId) &&
      (match.status == FixtureStatus.upcoming ||
          match.status == FixtureStatus.live) &&
      match.status != FixtureStatus.cancelled;

  /// A spectator on a public match that has not started can take a free place.
  bool get _canJoin =>
      onJoinSide != null &&
      match.isOpenToJoin &&
      !_isOrganizer &&
      match.participantOf(accountId)?.status !=
          MatchParticipantStatus.accepted &&
      match.participantOf(accountId)?.status != MatchParticipantStatus.invited;

  /// Somebody who is on the match may leave it, unless they organize it.
  bool get _canLeave =>
      onLeave != null &&
      match.isOpenToJoin &&
      !_isOrganizer &&
      match.participantOf(accountId)?.status == MatchParticipantStatus.accepted;

  @override
  Widget build(BuildContext context) {
    final invite = match.participantOf(accountId);
    final awaitingAnswer =
        invite != null && invite.status == MatchParticipantStatus.invited;

    final buttons = <Widget>[];
    final moreOptions = <Widget>[];

    if (awaitingAnswer && onRespond != null) {
      buttons
        ..add(
          PrimaryButton(
            label: 'Accept invitation',
            icon: Icons.check_circle_outline,
            tone: SportikaColors.mint,
            busy: busy,
            onPressed: () {
              if (!busy) onRespond!(true);
            },
          ),
        )
        ..add(
          GhostButton(
            label: 'Decline',
            icon: Icons.close,
            tone: SportikaColors.danger,
            expand: true,
            onPressed: busy ? null : () => onRespond!(false),
          ),
        );
    }

    if (!awaitingAnswer) {
      switch (match.status) {
        case FixtureStatus.upcoming:
          if (_canJoin) {
            buttons.addAll(_joinButtons(match));
          }
          if (_canLeave) {
            moreOptions.add(
              GhostButton(
                label: 'Leave match',
                icon: Icons.logout,
                tone: SportikaColors.danger,
                expand: true,
                onPressed: busy ? null : onLeave,
              ),
            );
          }
          if (_canScore && onStart != null) {
            buttons.add(
              PrimaryButton(
                label: 'Start match',
                icon: Icons.play_arrow_rounded,
                busy: busy,
                onPressed: () {
                  if (!busy) onStart!();
                },
              ),
            );
          }
          if (_isOrganizer) {
            if (onInvite != null) {
              buttons.add(
                GhostButton(
                  label: 'Invite players',
                  icon: Icons.person_add_alt,
                  expand: true,
                  onPressed: busy ? null : onInvite,
                ),
              );
            }
            if (onAssignScorer != null) {
              buttons.add(
                GhostButton(
                  label: match.scorerId == null
                      ? 'Assign official scorer'
                      : 'Change official scorer',
                  icon: Icons.assignment_ind_outlined,
                  expand: true,
                  onPressed: busy ? null : onAssignScorer,
                ),
              );
            }
            if (onCancel != null) {
              moreOptions.add(
                GhostButton(
                  label: 'Cancel match',
                  icon: Icons.block,
                  tone: SportikaColors.danger,
                  expand: true,
                  onPressed: busy ? null : onCancel,
                ),
              );
            }
          }
        case FixtureStatus.live:
          if (_canScore) {
            if (onScore != null) {
              buttons.add(
                PrimaryButton(
                  label: 'Open scoring workspace',
                  icon: Icons.sports_score,
                  tone: SportikaColors.mint,
                  busy: busy,
                  onPressed: () {
                    if (!busy) onScore!();
                  },
                ),
              );
            }
            // A paused match offers Resume instead of Pause: the server accepts
            // either call, but a button that does nothing is worse than no button.
            if (match.isPaused && onResume != null) {
              buttons.add(
                GhostButton(
                  label: 'Resume scoring',
                  icon: Icons.play_circle_outline,
                  expand: true,
                  onPressed: busy ? null : onResume,
                ),
              );
            } else if (!match.isPaused && onPause != null) {
              buttons.add(
                GhostButton(
                  label: 'Pause scoring',
                  icon: Icons.pause_circle_outline,
                  expand: true,
                  onPressed: busy ? null : onPause,
                ),
              );
            }
            if (onSubmit != null) {
              buttons.add(
                GhostButton(
                  label: 'End match and submit',
                  icon: Icons.flag_outlined,
                  expand: true,
                  onPressed: busy ? null : onSubmit,
                ),
              );
            }
          }
          if (_isOrganizer && onWalkover != null) {
            moreOptions.add(
              GhostButton(
                label: 'Record walkover',
                icon: Icons.handshake_outlined,
                expand: true,
                onPressed: busy ? null : onWalkover,
              ),
            );
          }
          if (match.sport == Sport.badminton && onRetire != null) {
            moreOptions.add(
              GhostButton(
                label: 'Retire / concede',
                icon: Icons.flag_outlined,
                expand: true,
                onPressed: busy ? null : onRetire,
              ),
            );
          }
        case FixtureStatus.submitted:
          if (_isOrganizer) {
            if (onPublish != null) {
              buttons.add(
                PrimaryButton(
                  label: 'Publish result',
                  icon: Icons.verified_outlined,
                  tone: SportikaColors.gold,
                  busy: busy,
                  onPressed: () {
                    if (!busy) onPublish!();
                  },
                ),
              );
            }
            if (onCorrect != null) {
              buttons.add(
                GhostButton(
                  label: 'Correct before publishing',
                  icon: Icons.edit_note,
                  expand: true,
                  onPressed: busy ? null : onCorrect,
                ),
              );
            }
          }
          _addDisputeButton(moreOptions);
        case FixtureStatus.published:
          if (_isOrganizer && onCorrect != null) {
            moreOptions.add(
              GhostButton(
                label: 'Correct result',
                icon: Icons.edit_note,
                expand: true,
                onPressed: busy ? null : onCorrect,
              ),
            );
          }
          _addDisputeButton(moreOptions);
        case FixtureStatus.walkover:
          _addDisputeButton(moreOptions);
        case FixtureStatus.cancelled:
          break;
      }
    }

    // Every viewer sees the pause, not just the scorer: a match that looks live
    // but is not accepting points has to say so.
    final paused = match.isPaused && match.status == FixtureStatus.live;

    final primary = buttons.whereType<PrimaryButton>().firstOrNull;
    final secondary = buttons.where((button) => button != primary).toList();
    final role = _isOrganizer
        ? 'Organizer'
        : match.canScore(accountId)
        ? 'Official scorer'
        : awaitingAnswer
        ? 'Invited player'
        : match.participantOf(accountId)?.status ==
              MatchParticipantStatus.accepted
        ? 'Player'
        : 'Spectator';
    final (heading, description, icon, tone) = awaitingAnswer
        ? (
            'You’re invited',
            'Accept to confirm your place in the lineup.',
            Icons.mark_email_unread_outlined,
            SportikaColors.blueBright,
          )
        : switch (match.status) {
            FixtureStatus.upcoming => (
              'Ready to play',
              _canScore
                  ? 'Start when both sides are ready.'
                  : _fallbackNote(false),
              Icons.event_outlined,
              SportikaColors.blueBright,
            ),
            FixtureStatus.live when paused => (
              'Match paused',
              _pausedNote(),
              Icons.pause_circle_outline,
              SportikaColors.gold,
            ),
            FixtureStatus.live => (
              'Match in progress',
              _canScore
                  ? 'Record the action and submit the result when play ends.'
                  : _fallbackNote(false),
              Icons.sports_score,
              SportikaColors.mint,
            ),
            FixtureStatus.submitted => (
              'Result ready for review',
              _isOrganizer
                  ? 'Review the submitted score, then publish the result.'
                  : _fallbackNote(false),
              Icons.fact_check_outlined,
              SportikaColors.gold,
            ),
            FixtureStatus.published => (
              'Result published',
              _fallbackNote(false),
              Icons.verified_outlined,
              SportikaColors.mint,
            ),
            FixtureStatus.walkover => (
              'Walkover recorded',
              _fallbackNote(false),
              Icons.handshake_outlined,
              SportikaColors.gold,
            ),
            FixtureStatus.cancelled => (
              'Match cancelled',
              _fallbackNote(false),
              Icons.event_busy_outlined,
              SportikaColors.textMuted,
            ),
          };
    final result = match.result;
    if (compact) {
      final actions = [...buttons, ...moreOptions];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(role, style: SportikaType.caption),
          const SizedBox(height: SportikaSpacing.sm),
          if (actions.isEmpty) Text(description, style: SportikaType.body),
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: AbsorbPointer(absorbing: busy, child: action),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        color: SportikaColors.surface,
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        border: Border.all(color: SportikaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('MATCH ACTION CENTER', style: SportikaType.label),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Flexible(
                child: Text(
                  role,
                  textAlign: TextAlign.end,
                  style: SportikaType.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tone),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(child: Text(heading, style: SportikaType.headline)),
            ],
          ),
          const SizedBox(height: SportikaSpacing.xs),
          Text(description, style: SportikaType.body),
          if (!awaitingAnswer && result != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            Container(
              padding: const EdgeInsets.all(SportikaSpacing.md),
              decoration: BoxDecoration(
                color: SportikaColors.surfaceSunken,
                borderRadius: BorderRadius.circular(SportikaRadius.md),
              ),
              child: Text(result.headline, style: SportikaType.bodyStrong),
            ),
          ],
          if (primary != null) ...[
            const SizedBox(height: SportikaSpacing.lg),
            // Keep the callback present while blocking interaction during work.
            AbsorbPointer(
              absorbing: busy,
              child: Semantics(enabled: !busy, child: primary),
            ),
          ],
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.sm),
            _actionGroup(secondary),
          ],
          if (moreOptions.isNotEmpty) ...[
            const SizedBox(height: SportikaSpacing.lg),
            const Divider(),
            const SizedBox(height: SportikaSpacing.md),
            const Text('More Options', style: SportikaType.bodyStrong),
            const SizedBox(height: SportikaSpacing.sm),
            _actionGroup(moreOptions),
          ],
        ],
      ),
    );
  }

  Widget _actionGroup(List<Widget> actions) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 440 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.2;
      final width = twoColumns
          ? (constraints.maxWidth - SportikaSpacing.sm) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: SportikaSpacing.sm,
        runSpacing: SportikaSpacing.sm,
        children: [
          for (final action in actions) SizedBox(width: width, child: action),
        ],
      );
    },
  );

  /// `join_match` is the only way into a public match without an invitation, so
  /// both sides get a button. A full side stays visible but disabled, with the
  /// reason on the label: a side that silently disappears reads as a bug.
  List<Widget> _joinButtons(SportMatch match) => [
    for (final side in [0, 1])
      PrimaryButton(
        label: match.isSideFull(side)
            ? 'Join side ${_sideLetter(side)} · side full'
            : 'Join side ${_sideLetter(side)}',
        icon: Icons.person_add_alt_1,
        tone: SportikaColors.mint,
        onPressed: match.isSideFull(side)
            ? null
            : () {
                if (!busy) onJoinSide!(side);
              },
      ),
  ];

  String _sideLetter(int side) => side == 0 ? 'A' : 'B';

  /// A result exists from `submitted` onwards, which is exactly when the server
  /// starts accepting a dispute.
  void _addDisputeButton(List<Widget> buttons) {
    if (onDispute == null || !match.canDispute(accountId)) return;
    final live = match.disputes.any((d) => d.status.isOpen);
    buttons.add(
      GhostButton(
        label: live ? 'View disputes' : 'Dispute result',
        icon: Icons.gavel_outlined,
        expand: true,
        onPressed: busy ? null : onDispute,
      ),
    );
  }

  String _pausedNote() {
    final reason = match.pauseReason;
    return reason == null || reason.isEmpty
        ? 'Scoring is paused. The organizer or the official scorer can resume it.'
        : 'Scoring is paused: $reason';
  }

  String _fallbackNote(bool awaitingAnswer) {
    if (awaitingAnswer) {
      return 'Waiting for the organizer to confirm your place.';
    }
    return switch (match.status) {
      FixtureStatus.submitted =>
        'The scorer has submitted this result. The organizer publishes it.',
      FixtureStatus.published => 'This result is final and published.',
      FixtureStatus.cancelled => 'This match was cancelled by the organizer.',
      FixtureStatus.walkover => 'This match was settled as a walkover.',
      FixtureStatus.live =>
        'Only the organizer or the assigned official scorer can record scores.',
      FixtureStatus.upcoming => 'Only the organizer or the assigned official scorer can start this match.',
    };
  }
}
