import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/env.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/features/monetization/widgets/billing_widgets.dart';
import 'package:sportika/shared/models/monetization.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Organizer Pro: the subscription state, its benefits, and the two actions a
/// member is ever allowed to take - start a renewal request, or stop renewing.
///
/// Nothing on this page can make the subscription active. The status block reads
/// the `subscriptions` row the server returned, and the "awaiting verification"
/// block only appears while a purchase row really is `pending`.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _busy = false;

  MonetizationController get _billing => context.read<MonetizationController>();

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final billing = _billing;
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
    await billing.refresh();
  }

  Future<void> _start(BillingPlan plan) => _run(
    () async {
      await _billing.startPurchase(planCode: plan.code);
    },
    done:
        'Subscription request created. Send the transfer, then check the '
        'status.',
  );

  Future<void> _cancel(BillingPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop renewing?'),
        content: const Text(
          'Your premium tools stay active until the end of the period you '
          'already paid for. After that the subscription lapses on its own '
          'and nothing further is requested.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel at period end'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => _billing.cancelSubscription(plan.code),
      done: 'Your plan will not renew after the current period.',
    );
  }

  Future<void> _simulate(String purchaseId) => _run(
    () => _billing.simulateVerification(purchaseId),
    done: 'Operator verified the payment.',
  );

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<MonetizationController>();
    final plan = billing.planFor(BillingStream.organizerPro);

    if (plan == null) {
      return ScreenScaffold(
        title: 'Organizer Pro',
        onRefresh: billing.refresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(eyebrow: 'Subscription', title: 'Organizer Pro'),
            ErrorState(
              title: 'The plan is not available right now',
              message:
                  billing.error ??
                  'The plan catalogue could not be read. Nothing was charged.',
              onRetry: billing.refresh,
            ),
          ],
        ),
      );
    }

    final subscription = billing.subscriptionFor(plan.code);
    final pending = billing.openProPurchase;
    final live = subscription != null && subscription.isLive;

    return ScreenScaffold(
      title: 'Organizer Pro',
      onRefresh: billing.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            eyebrow: 'Subscription',
            title: plan.label,
            subtitle: plan.tagline.isEmpty
                ? 'Premium tournament tools on every event you organise.'
                : plan.tagline,
          ),
          if (live) ...[
            _StatusCard(
              subscription: subscription,
              entryCap: billing.premiumEntryCap,
            ),
            const SizedBox(height: SportikaSpacing.md),
          ] else if (pending != null) ...[
            PendingPurchasePanel(
              purchase: pending,
              instructions: plan.paymentInstructions,
              busy: _busy,
              onRefresh: () => billing.refresh(),
              onSimulate: AppEnv.demoMode ? () => _simulate(pending.id) : null,
            ),
            const SizedBox(height: SportikaSpacing.md),
          ] else ...[
            PlanCard(
              plan: plan,
              actionLabel: _busy ? 'Working...' : 'Request subscription',
              onPressed: _busy ? null : () => _start(plan),
            ),
            const SizedBox(height: SportikaSpacing.md),
          ],
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What Pro changes', style: SportikaType.bodyStrong),
                const SizedBox(height: 8),
                const _ProScopeNote(),
                if (plan.benefits.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  PlanBenefits(plan: plan),
                ],
                if (live && !subscription.cancelAtPeriodEnd) ...[
                  const SizedBox(height: 14),
                  GhostButton(
                    label: 'Cancel at period end',
                    icon: Icons.close_rounded,
                    tone: SportikaColors.danger,
                    expand: true,
                    onPressed: _busy ? null : () => _cancel(plan),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          const InlineBanner(
            icon: Icons.lock_open_outlined,
            tone: SportikaColors.textMuted,
            text:
                'Pro adds limits and tools to tournaments you organise. It '
                'never gates match creation, official scoring, result '
                'publication or disputes.',
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.subscription, required this.entryCap});

  final Subscription subscription;
  final int entryCap;

  @override
  Widget build(BuildContext context) {
    final periodEnd = subscription.currentPeriodEnd;
    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Your plan', style: SportikaType.bodyStrong),
              ),
              SubscriptionStatusPill(subscription.status),
            ],
          ),
          const SizedBox(height: 10),
          if (periodEnd != null)
            BillingLine(
              label: subscription.cancelAtPeriodEnd
                  ? 'Active until'
                  : 'Renews on',
              value: billingDate(periodEnd),
            ),
          if (subscription.currentPeriodStart != null)
            BillingLine(
              label: 'This period',
              value:
                  '${billingDate(subscription.currentPeriodStart!)} - '
                  '${periodEnd == null ? 'open' : billingDate(periodEnd)}',
            ),
          BillingLine(label: 'Entry ceiling', value: '$entryCap'),
          if (subscription.cancelAtPeriodEnd) ...[
            const SizedBox(height: 10),
            const InlineBanner(
              icon: Icons.event_busy_outlined,
              tone: SportikaColors.gold,
              text:
                  'Cancelled. Premium tools stay on until the period you '
                  'paid for ends, then the plan lapses without a new request.',
            ),
          ],
        ],
      ),
    );
  }
}

/// Explains the entitlement in the member's own terms, and names the one thing
/// the cached snapshot cannot tell them: whether the server still agrees.
class _ProScopeNote extends StatelessWidget {
  const _ProScopeNote();

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<MonetizationController>();
    final premium = billing.isPro;
    return Text(
      premium
          ? 'Organizer Pro is active on your account, so every tournament you '
                'organise gets the premium entry ceiling, the group draw '
                'controls and the rule presets. A per-event pass is only '
                'needed while Pro is not active.'
          : 'While Pro is not active you can still unlock a single event with '
                'a tournament pass, and every tournament keeps the free '
                'limits.',
      style: SportikaType.caption,
    );
  }
}
