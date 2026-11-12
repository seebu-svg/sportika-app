import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/official_result.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Organizer actions on a fixture, shared by the fixture page, the organizer
/// dashboard and the review queue so the workflow is identical everywhere.

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => child,
  );
}

/// Publishes the folded event log. A second publish is recorded as a
/// correction that keeps the previous result and the stated reason (spec §4.5).
Future<void> publishFixture(BuildContext context, Fixture fixture) async {
  final state = context.read<AppState>();
  if (fixture.result == null && fixture.events.isEmpty) {
    showSnack(
      context,
      'Record scoring entries or a walkover first',
      error: true,
    );
    return;
  }

  final progress = state.progressOfFixture(fixture);
  final preview = OfficialResults.fromProgress(
    progress,
    publishedById: 'preview',
  );
  final isCorrection = fixture.result != null;
  final reason = TextEditingController();

  final confirmed = await _sheet<bool>(
    context,
    AppSheet(
      title: isCorrection ? 'Publish a correction' : 'Publish official result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SurfaceCard(
            fillColor: SportikaColors.surfaceSunken,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.headline,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: SportikaColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  progress.scoreDisplay.join('  ·  '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: SportikaColors.textMuted,
                  ),
                ),
                if (isCorrection) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Previous result',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                      color: SportikaColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${fixture.result!.headline} · ${fixture.result!.sideScores.join(' : ')}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: SportikaColors.textBody,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (isCorrection) ...[
            TextField(
              controller: reason,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason for the correction',
                hintText: 'e.g. Third goal was credited to the wrong side',
              ),
            ),
            const SizedBox(height: 12),
          ],
          InfoBanner(
            icon: Icons.account_tree_outlined,
            tone: SportikaColors.mint,
            text: isCorrection
                ? 'The previous result stays in the audit trail. Brackets and tables '
                      'recalculate the moment you publish.'
                : 'Publishing is the only action that advances a bracket or updates a table.',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Cancel',
                  expand: true,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: isCorrection ? 'Publish correction' : 'Publish result',
                  small: true,
                  tone: SportikaColors.mint,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) {
    reason.dispose();
    return;
  }

  state.publishOfficialResult(
    fixture.id,
    correctionReason: isCorrection ? reason.text : null,
  );
  reason.dispose();
  if (context.mounted) {
    showSnack(
      context,
      isCorrection ? 'Correction published' : 'Official result published',
    );
  }
}

Future<void> recordWalkoverFor(BuildContext context, Fixture fixture) async {
  final state = context.read<AppState>();
  final reason = TextEditingController();
  final sides = [state.sideLabel(fixture, 0), state.sideLabel(fixture, 1)];

  final winner = await _sheet<int>(
    context,
    AppSheet(
      title: 'Record a walkover',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const InfoBanner(
            icon: Icons.info_outline,
            tone: SportikaColors.gold,
            text:
                'A walkover publishes immediately and advances the bracket the same '
                'way a played result does.',
          ),
          const SizedBox(height: 14),
          const Text(
            'Who advances?',
            style: TextStyle(fontSize: 12, color: SportikaColors.textMuted),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < sides.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: sides[i],
                  small: true,
                  tone: i == 0 ? SportikaColors.blue : SportikaColors.mint,
                  onPressed: () => Navigator.pop(context, i),
                ),
              ),
            ),
          TextField(
            controller: reason,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'e.g. Opponent did not arrive',
            ),
          ),
        ],
      ),
    ),
  );

  if (winner == null) {
    reason.dispose();
    return;
  }
  state.recordWalkover(fixture.id, winner, reason.text);
  reason.dispose();
  if (context.mounted) showSnack(context, 'Walkover recorded');
}

Future<void> editFixtureSchedule(BuildContext context, Fixture fixture) async {
  final state = context.read<AppState>();
  final venue = TextEditingController(text: fixture.venue);
  var date = fixture.scheduledAt;

  final saved = await _sheet<bool>(
    context,
    StatefulBuilder(
      builder: (sheetContext, setSheetState) => AppSheet(
        title: 'Fixture details',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: venue,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Venue'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: dateShort(date),
                    icon: Icons.schedule,
                    expand: true,
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: date,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 30),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked == null) return;
                      if (!sheetContext.mounted) return;
                      final time = await showTimePicker(
                        context: sheetContext,
                        initialTime: TimeOfDay.fromDateTime(date),
                      );
                      setSheetState(() {
                        date = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          time?.hour ?? date.hour,
                          time?.minute ?? date.minute,
                        );
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const InfoBanner(
              icon: Icons.notifications_active_outlined,
              text: 'Everyone entered in the tournament is notified about the change.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'Cancel',
                    expand: true,
                    onPressed: () => Navigator.pop(sheetContext, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Save',
                    small: true,
                    onPressed: () => Navigator.pop(sheetContext, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (saved != true) {
    venue.dispose();
    return;
  }
  state.updateFixtureSchedule(
    fixture.id,
    scheduledAt: date,
    venue: venue.text.trim().isEmpty ? null : venue.text.trim(),
  );
  venue.dispose();
  if (context.mounted) {
    showSnack(context, 'Fixture updated and players notified');
  }
}

Future<void> assignScorerSheet(BuildContext context, Fixture fixture) async {
  final state = context.read<AppState>();
  final me = state.currentAccount;
  final candidates = state.accounts
      .where((a) => a.has(UserRole.scorer) || a.id == me?.id)
      .toList();

  await _sheet<void>(
    context,
    AppSheet(
      title: 'Scorers for this fixture',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const InfoBanner(
              icon: Icons.swap_horiz,
              text:
                  'Swapping a scorer mid-match transfers access. Recorded entries '
                  'carry over to the new scorer.',
            ),
            const SizedBox(height: 12),
            for (final account in candidates)
              _ScorerRow(
                account: account,
                assigned: fixture.scorerAccountIds.contains(account.id),
                onAssign: () {
                  state.assignScorer(fixture.id, account.id);
                  setSheetState(() {});
                },
                onRemove: () {
                  state.removeScorer(fixture.id, account.id);
                  setSheetState(() {});
                },
                onTransfer: () async {
                  final target = await _pickTransferTarget(
                    sheetContext,
                    candidates,
                    account.id,
                  );
                  if (target == null) return;
                  state.replaceScorer(fixture.id, account.id, target);
                  setSheetState(() {});
                },
              ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _pickTransferTarget(
  BuildContext context,
  List<Account> candidates,
  String fromId,
) {
  return _sheet<String>(
    context,
    AppSheet(
      title: 'Transfer scoring access',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final account in candidates.where((a) => a.id != fromId))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: account.displayName,
                  small: true,
                  tone: SportikaColors.mint,
                  onPressed: () => Navigator.pop(context, account.id),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ScorerRow extends StatelessWidget {
  const _ScorerRow({
    required this.account,
    required this.assigned,
    required this.onAssign,
    required this.onRemove,
    required this.onTransfer,
  });

  final Account account;
  final bool assigned;
  final VoidCallback onAssign;
  final VoidCallback onRemove;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AccountAvatar(account: account, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SportikaColors.text,
                  ),
                ),
                Text(
                  account.roles.map((r) => r.label).join(' · '),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (assigned) ...[
            IconButton(
              tooltip: 'Transfer access',
              onPressed: onTransfer,
              icon: const Icon(
                Icons.swap_horiz,
                size: 18,
                color: SportikaColors.blueBright,
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: SportikaColors.danger,
              ),
            ),
          ] else
            TextButton(onPressed: onAssign, child: const Text('Assign')),
        ],
      ),
    );
  }
}

Future<void> raiseDisputeFor(BuildContext context, Fixture fixture) async {
  final state = context.read<AppState>();
  final note = TextEditingController();
  final sent = await _sheet<bool>(
    context,
    AppSheet(
      title: 'Dispute this result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const InfoBanner(
            icon: Icons.gavel,
            tone: SportikaColors.danger,
            text:
                'The tournament organizer reviews disputes. The published result '
                'stays live until they decide.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What looks wrong?',
              hintText: 'e.g. The second set finished 7-5, not 6-4',
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: note,
            builder: (_, value, _) => PrimaryButton(
              label: 'Send to organizer',
              icon: Icons.send_rounded,
              tone: SportikaColors.danger,
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
    ),
  );

  if (sent != true) {
    note.dispose();
    return;
  }
  state.raiseDispute(fixture.id, note.text);
  note.dispose();
  if (context.mounted) {
    showSnack(context, 'Dispute sent to the tournament organizer');
  }
}

Future<void> resolveDisputeFor(BuildContext context, Fixture fixture) async {
  final state = context.read<AppState>();
  final note = TextEditingController();
  final uphold = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Resolve dispute'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fixture.disputeNote ?? 'No detail given.',
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note to the player'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Request change'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Result stands'),
        ),
      ],
    ),
  );

  if (uphold == null) {
    note.dispose();
    return;
  }
  state.resolveDispute(fixture.id, upholdResult: uphold, note: note.text);
  note.dispose();
  if (context.mounted) showSnack(context, 'Dispute closed');
}
