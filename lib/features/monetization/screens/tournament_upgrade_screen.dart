import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/env.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';
import 'package:sportika/features/monetization/widgets/billing_widgets.dart';
import 'package:sportika/shared/models/monetization.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// One tournament, one pass, one pending transfer.
///
/// The screen never decides that anything was paid. It shows the reference the
/// member carries to their bank app, then re-reads the server on demand: only a
/// purchase row that comes back `paid` flips this page to the unlocked state. A
/// demo build gets one clearly labelled extra action that runs the same state
/// machine the operator would, so the flow is demonstrable without pretending a
/// release build can pay.
class TournamentUpgradeScreen extends StatefulWidget {
  const TournamentUpgradeScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  State<TournamentUpgradeScreen> createState() =>
      _TournamentUpgradeScreenState();
}

class _TournamentUpgradeScreenState extends State<TournamentUpgradeScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) showSnack(context, done);
    } on MonetizationException catch (error) {
      if (mounted) showSnack(context, error.message, error: true);
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'Something went wrong. Nothing was charged.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(BillingPlan plan) => _run(
    () => context.read<MonetizationController>().startPurchase(
      planCode: plan.code,
      targetKind: PurchaseTargetKind.tournament,
      targetId: widget.tournamentId,
    ),
    done: 'Payment request created. Send the transfer, then check the status.',
  );

  Future<void> _refresh() =>
      _run(() => context.read<MonetizationController>().refresh());

  Future<void> _simulate(String purchaseId) => _run(
    () =>
        context.read<MonetizationController>().simulateVerification(purchaseId),
    done: 'Operator verified the payment.',
  );

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<MonetizationController>();
    final tournament = context.watch<TournamentsController>().tournamentById(
      widget.tournamentId,
    );

    if (tournament == null) {
      return const ScreenScaffold(
        title: 'Tournament pass',
        child: EmptyState(
          title: 'Tournament not found',
          body: 'It may have been deleted from this device.',
          icon: Icons.search_off,
        ),
      );
    }

    final account = context.watch<ProfileController>().currentAccount;
    final isOwner = account != null && tournament.organizerId == account.id;
    final premium = billing.canUsePremiumTournament(tournament.id);
    final plan = billing.planFor(BillingStream.tournamentPass);
    final purchase = billing.purchaseForTournament(tournament.id);

    return ScreenScaffold(
      title: 'Tournament pass',
      onRefresh: billing.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            eyebrow: 'Premium tools',
            title: tournament.name,
            subtitle:
                'A pass unlocks the premium toolkit for this one event. '
                'Entries, official scoring and results keep working exactly '
                'as they do today.',
          ),
          if (!isOwner) ...[
            const InlineBanner(
              icon: Icons.lock_outline,
              tone: SportikaColors.danger,
              text:
                  'Only the organizer of this tournament can unlock it. '
                  'Nothing was charged.',
            ),
          ] else if (premium) ...[
            _UnlockedPanel(
              tournamentName: tournament.name,
              source: billing.premiumSourceFor(tournament.id),
              entryCap: billing.entryCapFor(tournament.id),
            ),
          ] else if (purchase != null &&
              purchase.status == PaymentStatus.pending) ...[
            PendingPurchasePanel(
              purchase: purchase,
              instructions: plan?.paymentInstructions ?? '',
              busy: _busy,
              onRefresh: _refresh,
              onSimulate: AppEnv.demoMode ? () => _simulate(purchase.id) : null,
            ),
          ] else if (plan == null) ...[
            ErrorState(
              title: 'The pass is not available right now',
              message:
                  billing.error ??
                  'The plan catalogue could not be read. Nothing was charged.',
              onRetry: billing.refresh,
            ),
          ] else ...[
            if (purchase != null && purchase.status != PaymentStatus.paid) ...[
              _PreviousAttempt(purchase: purchase),
              const SizedBox(height: SportikaSpacing.md),
            ],
            _PassSummary(plan: plan),
            const SizedBox(height: SportikaSpacing.md),
            PrimaryButton(
              label: 'Create payment request',
              icon: Icons.qr_code_2,
              busy: _busy,
              onPressed: _busy ? null : () => _buy(plan),
            ),
            const SizedBox(height: SportikaSpacing.sm),
            const InlineBanner(
              icon: Icons.verified_user_outlined,
              tone: SportikaColors.textMuted,
              text:
                  'This creates a request, not a payment. A Sportika operator '
                  'confirms the transfer in the database, and only then does '
                  'the tournament unlock.',
            ),
          ],
        ],
      ),
    );
  }
}

/// What the pass buys, painted entirely from the plan row so the price, the
/// ceiling and the bullets stay configurable.
class _PassSummary extends StatelessWidget {
  const _PassSummary({required this.plan});

  final BillingPlan plan;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text('One event', style: SportikaType.bodyStrong),
              ),
              PlanPrice(plan: plan),
            ],
          ),
          if (plan.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(plan.description, style: SportikaType.caption),
          ],
          if (plan.benefits.isNotEmpty) ...[
            const SizedBox(height: 12),
            PlanBenefits(plan: plan),
          ],
          if (plan.maxEntries != null) ...[
            const SizedBox(height: 6),
            BillingLine(label: 'Entry ceiling', value: '${plan.maxEntries}'),
          ],
          if (plan.groupCounts.isNotEmpty)
            BillingLine(
              label: 'Group draw',
              value: plan.groupCounts.map((c) => '$c').join(', '),
            ),
          if (plan.paymentInstructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('How to pay', style: SportikaType.label),
            const SizedBox(height: 4),
            Text(plan.paymentInstructions, style: SportikaType.caption),
          ],
        ],
      ),
    );
  }
}

/// A finished attempt that did not unlock the event, shown before offering a
/// new one so the member cannot lose track of a failed or expired transfer.
class _PreviousAttempt extends StatelessWidget {
  const _PreviousAttempt({required this.purchase});

  final Purchase purchase;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: SportikaColors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last attempt · ${purchase.reference}',
                  style: SportikaType.bodyStrong,
                ),
              ),
              PurchaseStatusPill(purchase.status),
            ],
          ),
          const SizedBox(height: 8),
          BillingLine(label: 'Amount', value: purchase.amountLabel),
          if (purchase.note.isNotEmpty)
            BillingLine(label: 'Note', value: purchase.note),
        ],
      ),
    );
  }
}

class _UnlockedPanel extends StatelessWidget {
  const _UnlockedPanel({
    required this.tournamentName,
    required this.source,
    required this.entryCap,
  });

  final String tournamentName;
  final BillingStream? source;
  final int entryCap;

  String get _wording => switch (source) {
    BillingStream.organizerPro =>
      'Included with your Organizer Pro subscription',
    BillingStream.tournamentPass => 'Unlocked with your tournament pass',
    _ => 'Premium tools are active',
  };

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_outlined,
                size: 18,
                color: SportikaColors.gold,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$tournamentName is premium',
                  style: SportikaType.bodyStrong,
                ),
              ),
              const PremiumBadge(compact: true),
            ],
          ),
          const SizedBox(height: 10),
          BillingLine(label: 'Access', value: _wording),
          BillingLine(label: 'Entry ceiling', value: '$entryCap'),
          const SizedBox(height: 10),
          const Text(
            'Higher entry limits, the group draw controls and the rule '
            'presets are now available on this tournament.',
            style: SportikaType.caption,
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Back to tournament',
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
