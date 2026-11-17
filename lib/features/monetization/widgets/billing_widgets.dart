import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/shared/models/monetization.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Billing timestamps are read as dates, not as "2h ago": a payment history has
/// to stay meaningful after a restart.
String billingDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

String billingDateTime(DateTime date) =>
    '${billingDate(date)} · ${timeLabel(date)}';

Color paymentTone(PaymentStatus status) => switch (status) {
  PaymentStatus.pending => SportikaColors.gold,
  PaymentStatus.paid => SportikaColors.mint,
  PaymentStatus.failed => SportikaColors.danger,
  PaymentStatus.expired => SportikaColors.textMuted,
  PaymentStatus.refunded => SportikaColors.blueBright,
};

Color subscriptionTone(SubscriptionStatus status) => switch (status) {
  SubscriptionStatus.active => SportikaColors.mint,
  SubscriptionStatus.pending ||
  SubscriptionStatus.pastDue => SportikaColors.gold,
  SubscriptionStatus.expired => SportikaColors.textMuted,
  SubscriptionStatus.cancelled ||
  SubscriptionStatus.refunded => SportikaColors.blueBright,
};

/// The one mark that a tournament or plan carries premium tools.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, this.label = 'Premium', this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => StatusPill(
    label,
    color: SportikaColors.gold,
    icon: compact ? null : Icons.workspace_premium_outlined,
  );
}

class PurchaseStatusPill extends StatelessWidget {
  const PurchaseStatusPill(this.status, {super.key});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusPill(status.label, color: paymentTone(status));
}

class SubscriptionStatusPill extends StatelessWidget {
  const SubscriptionStatusPill(this.status, {super.key});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusPill(status.label, color: subscriptionTone(status));
}

/// One label/value row used by every billing card.
class BillingLine extends StatelessWidget {
  const BillingLine({
    super.key,
    required this.label,
    required this.value,
    this.tone,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color? tone;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label.toUpperCase(), style: SportikaType.label),
          ),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: mono
                  ? SportikaType.bodyStrong.copyWith(letterSpacing: 1.1)
                  : SportikaType.body,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// The plan's configured benefits, painted from `billing_plans.benefits`.
class PlanBenefits extends StatelessWidget {
  const PlanBenefits({super.key, required this.plan});

  final BillingPlan plan;

  @override
  Widget build(BuildContext context) {
    if (plan.benefits.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final benefit in plan.benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 15,
                    color: SportikaColors.mint,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(benefit, style: SportikaType.caption)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The price block: the number, its interval and the configured tagline.
class PlanPrice extends StatelessWidget {
  const PlanPrice({super.key, required this.plan});

  final BillingPlan plan;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            plan.priceLabel,
            style: SportikaType.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (plan.priceSuffix.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                plan.priceSuffix,
                style: SportikaType.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A catalogue plan as it appears on the pricing and subscription screens.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    this.onPressed,
    this.actionLabel,
    this.footer,
  });

  final BillingPlan plan;
  final VoidCallback? onPressed;
  final String? actionLabel;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan.label, style: SportikaType.bodyStrong)),
              if (plan.stream == BillingStream.organizerPro)
                const PremiumBadge(compact: true),
            ],
          ),
          if (plan.tagline.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(plan.tagline, style: SportikaType.caption),
          ],
          const SizedBox(height: 12),
          PlanPrice(plan: plan),
          if (plan.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(plan.description, style: SportikaType.caption),
          ],
          if (plan.benefits.isNotEmpty) ...[
            const SizedBox(height: 12),
            PlanBenefits(plan: plan),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            PrimaryButton(label: actionLabel!, onPressed: onPressed),
          ],
          ?footer,
        ],
      ),
    );
  }
}

/// A purchase waiting on the operator. The reference is the only thing the member
/// has to carry to their bank app, so it is selectable and unmissable.
class PendingPurchasePanel extends StatelessWidget {
  const PendingPurchasePanel({
    super.key,
    required this.purchase,
    required this.instructions,
    this.onRefresh,
    this.onSimulate,
    this.busy = false,
  });

  final Purchase purchase;
  final String instructions;
  final VoidCallback? onRefresh;

  /// Demo builds only; null hides the button.
  final VoidCallback? onSimulate;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final expiresAt = purchase.expiresAt;
    return SurfaceCard(
      borderColor: SportikaColors.gold.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Awaiting payment verification',
                  style: SportikaType.bodyStrong,
                ),
              ),
              PurchaseStatusPill(purchase.status),
            ],
          ),
          const SizedBox(height: 10),
          BillingLine(label: 'Amount', value: purchase.amountLabel),
          BillingLine(
            label: 'Reference',
            value: purchase.reference,
            mono: true,
          ),
          BillingLine(label: 'Created', value: billingDate(purchase.createdAt)),
          if (expiresAt != null)
            BillingLine(label: 'Expires', value: billingDate(expiresAt)),
          const SizedBox(height: 12),
          const Text(
            'Use the reference as the payment description',
            style: SportikaType.label,
          ),
          const SizedBox(height: 4),
          SelectableText(purchase.reference, style: SportikaType.bodyStrong),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(instructions, style: SportikaType.caption),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'I have paid - check status',
            icon: Icons.refresh,
            busy: busy,
            onPressed: busy ? null : onRefresh,
          ),
          if (onSimulate != null) ...[
            const SizedBox(height: 8),
            GhostButton(
              label: 'Demo: simulate operator verification',
              icon: Icons.science_outlined,
              tone: SportikaColors.gold,
              expand: true,
              onPressed: busy ? null : onSimulate,
            ),
          ],
        ],
      ),
    );
  }
}

/// What one tournament has today, and the single tap that changes it.
///
/// This is the only premium affordance on a tournament page, and it is an offer
/// rather than a gate: an event that was created, filled and drawn for free
/// keeps doing all three whether or not anything is ever bought.
class TournamentPremiumCard extends StatelessWidget {
  const TournamentPremiumCard({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<MonetizationController>();
    if (billing.canUsePremiumTournament(tournamentId)) {
      final source = switch (billing.premiumSourceFor(tournamentId)) {
        BillingStream.organizerPro =>
          'Included with your Organizer Pro subscription',
        BillingStream.tournamentPass => 'Unlocked with your tournament pass',
        _ => 'Premium tools are active',
      };
      return SurfaceCard(
        borderColor: SportikaColors.gold.withValues(alpha: 0.42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Premium tools are on',
                    style: SportikaType.bodyStrong,
                  ),
                ),
                PremiumBadge(compact: true),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$source. This event accepts up to '
              '${billing.entryCapFor(tournamentId)} entries and can use the '
              'group draw controls.',
              style: SportikaType.caption,
            ),
          ],
        ),
      );
    }

    final purchase = billing.purchaseForTournament(tournamentId);
    final pending =
        purchase != null && purchase.status == PaymentStatus.pending;
    return SurfaceCard(
      borderColor: SportikaColors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_outlined,
                size: 17,
                color: SportikaColors.gold,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Premium tools for this event',
                  style: SportikaType.bodyStrong,
                ),
              ),
              if (pending) PurchaseStatusPill(purchase.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pending
                ? 'Waiting on the operator to confirm reference '
                      '${purchase.reference}. Everything on this tournament '
                      'keeps working in the meantime.'
                : 'Raise the entry ceiling to '
                      '${billing.premiumEntryCap}, choose the group count and '
                      'use the rule presets for this one event.',
            style: SportikaType.caption,
          ),
          const SizedBox(height: 12),
          GhostButton(
            label: pending ? 'Check payment' : 'Unlock this event',
            icon: pending ? Icons.refresh : Icons.lock_open_outlined,
            tone: SportikaColors.gold,
            expand: true,
            onPressed: () => pushRoute(
              context,
              AppRoute.tournamentUpgrade,
              args: TournamentUpgradeArgs(tournamentId),
            ),
          ),
        ],
      ),
    );
  }
}
