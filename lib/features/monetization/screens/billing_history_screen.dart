import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/features/monetization/widgets/billing_widgets.dart';
import 'package:sportika/shared/models/monetization.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The member's own purchase ledger, newest first, with the money lines that
/// belong to each request underneath it.
///
/// A row is only ever as good as the database said it was: the five payment
/// states all appear here, including the ones that unlock nothing, so a member
/// can see an expired or refunded request instead of wondering about it.
class BillingHistoryScreen extends StatelessWidget {
  const BillingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<MonetizationController>();
    final purchases = _newestFirst(billing.purchases);

    return ScreenScaffold(
      title: 'Billing history',
      onRefresh: billing.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Payments',
            title: 'Billing history',
            subtitle:
                'Every payment request you have made, and what became of it.',
          ),
          if (billing.loading && purchases.isEmpty)
            const LoadingSkeleton(rows: 3, label: 'Loading your purchases')
          else if (purchases.isEmpty) ...[
            EmptyState(
              title: 'No purchases yet',
              body:
                  billing.error ??
                  'Payment requests appear here once you buy a pass or a '
                      'subscription.',
              icon: Icons.receipt_long_outlined,
              action: GhostButton(
                label: 'See plans',
                icon: Icons.workspace_premium_outlined,
                onPressed: () => pushRoute(context, AppRoute.pricing),
              ),
            ),
          ] else ...[
            for (final purchase in purchases)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PurchaseRow(
                  purchase: purchase,
                  planLabel: billing.planByCode(purchase.planCode)?.label,
                  payments: billing.paymentsFor(purchase.id),
                ),
              ),
            const SizedBox(height: SportikaSpacing.sm),
            const InlineBanner(
              icon: Icons.info_outline,
              tone: SportikaColors.textMuted,
              text:
                  'Amounts are the ones recorded when the request was made, so '
                  'a later price change never rewrites your history.',
            ),
          ],
        ],
      ),
    );
  }

  List<Purchase> _newestFirst(List<Purchase> purchases) {
    final sorted = [...purchases]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({
    required this.purchase,
    required this.planLabel,
    required this.payments,
  });

  final Purchase purchase;
  final String? planLabel;
  final List<PaymentRecord> payments;

  @override
  Widget build(BuildContext context) {
    final streamLabel = purchase.metadata['stream_label'];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  planLabel ??
                      purchase.planCode.replaceAll('_', ' ').toUpperCase(),
                  style: SportikaType.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PurchaseStatusPill(purchase.status),
            ],
          ),
          if (streamLabel is String && streamLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(streamLabel, style: SportikaType.label),
          ],
          const SizedBox(height: 10),
          BillingLine(
            label: 'Reference',
            value: purchase.reference,
            mono: true,
          ),
          BillingLine(label: 'Amount', value: purchase.amountLabel),
          BillingLine(
            label: 'Requested',
            value: billingDate(purchase.createdAt),
          ),
          if (purchase.paidAt != null)
            BillingLine(
              label: 'Verified',
              value: billingDate(purchase.paidAt!),
            ),
          if (purchase.expiredAt != null)
            BillingLine(
              label: 'Expired',
              value: billingDate(purchase.expiredAt!),
            ),
          if (purchase.refundedAt != null)
            BillingLine(
              label: 'Refunded',
              value: billingDate(purchase.refundedAt!),
            ),
          if (purchase.targetId != null) ...[
            const SizedBox(height: 8),
            Text(
              purchase.targetKind == PurchaseTargetKind.tournament
                  ? 'One tournament'
                  : 'Your account',
              style: SportikaType.caption,
            ),
          ],
          if (purchase.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(purchase.note, style: SportikaType.caption),
          ],
          for (final payment in payments) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: SportikaColors.borderSubtle),
            const SizedBox(height: 6),
            _PaymentLine(payment: payment),
          ],
        ],
      ),
    );
  }
}

class _PaymentLine extends StatelessWidget {
  const _PaymentLine({required this.payment});

  final PaymentRecord payment;

  @override
  Widget build(BuildContext context) {
    final tone = payment.isRefund
        ? SportikaColors.blueBright
        : SportikaColors.mint;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          payment.isRefund ? Icons.undo_rounded : Icons.payments_outlined,
          size: 15,
          color: tone,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${payment.isRefund ? 'Refund' : 'Charge'} · '
            '${billingDateTime(payment.at)}'
            '${payment.note.isEmpty ? '' : '\n${payment.note}'}',
            style: SportikaType.caption,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          payment.isRefund ? '- ${payment.amountLabel}' : payment.amountLabel,
          style: SportikaType.bodyStrong.copyWith(color: tone),
        ),
      ],
    );
  }
}
