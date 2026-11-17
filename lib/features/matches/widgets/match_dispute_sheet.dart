import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Raises and answers disputes on one match's official result.
///
/// Mirrors `raise_match_dispute` / `resolve_match_dispute` (migration 0014): a
/// result has to exist, any member of the match may challenge it, a member may
/// only have one live dispute at a time, and the organizer answers with
/// `underReview`, `resolved` or `rejected`. Nothing here is gated on an
/// entitlement — challenging a result is free, like scoring and publishing one.
///
/// A dispute never rewrites the score: the organizer corrects a published result
/// through the correction flow, and the dispute records why.
Future<void> showMatchDisputeSheet(
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
        SingleChildScrollView(child: _MatchDisputeSheet(matchId: match.id)),
  );
}

class _MatchDisputeSheet extends StatefulWidget {
  const _MatchDisputeSheet({required this.matchId});

  final String matchId;

  @override
  State<_MatchDisputeSheet> createState() => _MatchDisputeSheetState();
}

class _MatchDisputeSheetState extends State<_MatchDisputeSheet> {
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _resolution = TextEditingController();

  /// The dispute whose answer is being written, or null.
  String? _answering;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _resolution.dispose();
    super.dispose();
  }

  Future<void> _raise() async {
    final matches = context.read<MatchController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final dispute = await matches.raiseDispute(widget.matchId, _reason.text);
    if (!mounted) return;
    if (dispute == null) {
      setState(() {
        _busy = false;
        _error = matches.lastError;
      });
      return;
    }
    _reason.clear();
    setState(() => _busy = false);
    showSnack(context, 'Dispute raised. The organizer can answer it here.');
  }

  Future<void> _answer(String disputeId, MatchDisputeStatus status) async {
    final matches = context.read<MatchController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final dispute = await matches.resolveDispute(
      widget.matchId,
      disputeId,
      status: status,
      resolution: status == MatchDisputeStatus.underReview
          ? null
          : _resolution.text,
    );
    if (!mounted) return;
    if (dispute == null) {
      setState(() {
        _busy = false;
        _error = matches.lastError;
      });
      return;
    }
    _resolution.clear();
    setState(() {
      _busy = false;
      _answering = null;
    });
    showSnack(
      context,
      status == MatchDisputeStatus.underReview
          ? 'Marked as under review.'
          : 'Dispute ${status.key}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MatchController>();
    final match = controller.matchById(widget.matchId);
    final me = context.watch<SessionController>().currentAccount;
    if (match == null) {
      return const AppSheet(
        title: 'Result disputes',
        child: Text('This match is no longer available.'),
      );
    }

    final disputes = controller.disputesOf(widget.matchId);
    final canResolve = match.canResolveDispute(me?.id);
    final myLiveDispute = disputes.any(
      (d) => d.raisedById == me?.id && d.status.isOpen,
    );
    final canRaise =
        match.hasResult && match.canDispute(me?.id) && !myLiveDispute;
    final reason = _reason.text.trim();

    return AppSheet(
      title: 'Result disputes',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HelperText(
            'A dispute records that a member disagrees with the official result. '
            'The organizer answers it; changing the score itself is a result '
            'correction, which keeps the original on record.',
          ),
          const SizedBox(height: SportikaSpacing.md),
          if (disputes.isEmpty)
            const HelperText('No dispute has been raised on this result.')
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final dispute in disputes) ...[
                      _DisputeCard(
                        dispute: dispute,
                        canResolve: canResolve,
                        answering: _answering == dispute.id,
                        busy: _busy,
                        resolution: _resolution,
                        onAnswer: () => setState(() => _answering = dispute.id),
                        onCancel: () => setState(() {
                          _answering = null;
                          _resolution.clear();
                        }),
                        onSubmit: (status) => _answer(dispute.id, status),
                      ),
                      const SizedBox(height: SportikaSpacing.sm),
                    ],
                  ],
                ),
              ),
            ),
          if (myLiveDispute) ...[
            const SizedBox(height: SportikaSpacing.sm),
            const HelperText(
              'You already have a live dispute on this match. The organizer has '
              'to answer it before you can raise another.',
            ),
          ],
          if (canRaise) ...[
            const SizedBox(height: SportikaSpacing.md),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'What is wrong with this result?',
                hintText: 'At least 5 characters. Be specific about the score.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: SportikaSpacing.sm),
            PrimaryButton(
              label: 'Raise dispute',
              icon: Icons.gavel_outlined,
              busy: _busy,
              onPressed: _busy || reason.length < 5 ? null : _raise,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: _error!, tone: SportikaColors.danger),
          ],
        ],
      ),
    );
  }
}

/// One dispute: who raised it, why, the answer, and the organizer's controls.
class _DisputeCard extends StatelessWidget {
  const _DisputeCard({
    required this.dispute,
    required this.canResolve,
    required this.answering,
    required this.busy,
    required this.resolution,
    required this.onAnswer,
    required this.onCancel,
    required this.onSubmit,
  });

  final MatchDispute dispute;
  final bool canResolve;
  final bool answering;
  final bool busy;
  final TextEditingController resolution;
  final VoidCallback onAnswer;
  final VoidCallback onCancel;
  final void Function(MatchDisputeStatus status) onSubmit;

  @override
  Widget build(BuildContext context) {
    final sessions = context.read<SessionController>();
    final raisedBy =
        sessions.accountById(dispute.raisedById)?.displayName ?? 'A member';
    final answeredBy = dispute.resolvedById == null
        ? null
        : sessions.accountById(dispute.resolvedById!)?.displayName ??
              'The organizer';
    final tone = switch (dispute.status) {
      MatchDisputeStatus.open => SportikaColors.gold,
      MatchDisputeStatus.underReview => SportikaColors.blueBright,
      MatchDisputeStatus.resolved => SportikaColors.mint,
      MatchDisputeStatus.rejected => SportikaColors.textMuted,
    };
    final answer = resolution.text.trim();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_outlined, size: 16, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_statusLabel(dispute.status)} · $raisedBy',
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(dispute.reason, style: SportikaType.body),
          if (dispute.resolution != null) ...[
            const SizedBox(height: 6),
            Text(
              'Answer${answeredBy == null ? '' : ' from $answeredBy'}: '
              '${dispute.resolution}',
              style: SportikaType.caption,
            ),
          ],
          const SizedBox(height: 6),
          Text(_raisedAtLabel(dispute.raisedAt), style: SportikaType.caption),
          if (canResolve && dispute.status.isOpen && !answering) ...[
            const SizedBox(height: SportikaSpacing.sm),
            GhostButton(
              label: 'Answer this dispute',
              icon: Icons.rate_review_outlined,
              expand: true,
              onPressed: busy ? null : onAnswer,
            ),
          ],
          if (canResolve && answering) ...[
            const SizedBox(height: SportikaSpacing.sm),
            TextField(
              controller: resolution,
              minLines: 2,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Resolution',
                hintText:
                    'Required to resolve or reject (3 to 500 characters).',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: SportikaSpacing.sm),
            PrimaryButton(
              label: 'Resolve',
              icon: Icons.check_circle_outline,
              tone: SportikaColors.mint,
              busy: busy,
              onPressed: busy || answer.length < 3
                  ? null
                  : () => onSubmit(MatchDisputeStatus.resolved),
            ),
            const SizedBox(height: SportikaSpacing.sm),
            GhostButton(
              label: 'Reject',
              icon: Icons.cancel_outlined,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: busy || answer.length < 3
                  ? null
                  : () => onSubmit(MatchDisputeStatus.rejected),
            ),
            const SizedBox(height: SportikaSpacing.sm),
            GhostButton(
              label: 'Mark under review',
              icon: Icons.hourglass_top_outlined,
              expand: true,
              onPressed: busy
                  ? null
                  : () => onSubmit(MatchDisputeStatus.underReview),
            ),
            const SizedBox(height: SportikaSpacing.sm),
            GhostButton(
              label: 'Cancel',
              icon: Icons.close,
              expand: true,
              onPressed: busy ? null : onCancel,
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(MatchDisputeStatus status) => switch (status) {
    MatchDisputeStatus.open => 'Open',
    MatchDisputeStatus.underReview => 'Under review',
    MatchDisputeStatus.resolved => 'Resolved',
    MatchDisputeStatus.rejected => 'Rejected',
  };

  String _raisedAtLabel(DateTime at) {
    final local = at.toLocal();
    final date =
        '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    return 'Raised $date · ${timeLabel(local)}';
  }
}
