import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/env.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/monetization_controller.dart';
import 'package:sportika/features/monetization/widgets/billing_widgets.dart';
import 'package:sportika/shared/models/monetization.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The monetization catalogue, one section per activated stream.
///
/// Streams configured with `enabled = false, ui_visible = false` are absent
/// rather than greyed out, which is how the three future revenue streams stay
/// prepared without being advertised.
class PricingScreen extends StatelessWidget {
  const PricingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<MonetizationController>();
    final streams = billing.visibleStreams;
    final hasCatalogue = billing.activePlans.isNotEmpty;

    return ScreenScaffold(
      title: 'Plans and billing',
      onRefresh: billing.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Monetization',
            title: 'Plans and billing',
            subtitle:
                'Official scoring, results and disputes are always free. '
                'These plans add organizer tools and higher limits.',
          ),
          if (AppEnv.demoMode) ...[
            const InlineBanner(
              icon: Icons.science_outlined,
              tone: SportikaColors.gold,
              text:
                  'Demo build. Prices come from the demo catalogue and an '
                  'operator is simulated, so nothing is charged.',
            ),
            const SizedBox(height: SportikaSpacing.md),
          ],
          if (billing.loading && !hasCatalogue)
            const LoadingSkeleton(rows: 2, label: 'Loading plans')
          else if (!hasCatalogue) ...[
            ErrorState(
              title: 'Plans are not available right now',
              message:
                  billing.error ??
                  'The catalogue could not be read. Nothing was charged.',
              onRetry: billing.refresh,
            ),
            const SizedBox(height: SportikaSpacing.md),
            const InlineBanner(
              icon: Icons.info_outline,
              tone: SportikaColors.textMuted,
              text:
                  'Basic match creation and official scoring keep working '
                  'while plans are unavailable.',
            ),
          ] else ...[
            for (final stream in streams)
              _StreamSection(
                stream: stream,
                plans: billing.plansFor(stream.stream),
              ),
            const SizedBox(height: SportikaSpacing.sm),
            GhostButton(
              label: 'Billing history',
              icon: Icons.receipt_long_outlined,
              expand: true,
              onPressed: () => pushRoute(context, AppRoute.billingHistory),
            ),
            const SizedBox(height: SportikaSpacing.lg),
            const InlineBanner(
              icon: Icons.verified_user_outlined,
              tone: SportikaColors.textMuted,
              text:
                  'Payments are confirmed by a Sportika operator, never by '
                  'this app. A purchase only unlocks once the server records '
                  'it as paid.',
            ),
          ],
        ],
      ),
    );
  }
}

class _StreamSection extends StatelessWidget {
  const _StreamSection({required this.stream, required this.plans});

  final MonetizationStream stream;
  final List<BillingPlan> plans;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(stream.label),
        if (stream.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(stream.summary, style: SportikaType.caption),
          ),
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlanCard(
              plan: plan,
              actionLabel: switch (plan.stream) {
                BillingStream.organizerPro => 'View plan',
                BillingStream.tournamentPass => 'Choose a tournament',
                _ => 'Not available yet',
              },
              onPressed: switch (plan.stream) {
                BillingStream.organizerPro => () => pushRoute(
                  context,
                  AppRoute.subscription,
                ),
                BillingStream.tournamentPass => () => pushRoute(
                  context,
                  AppRoute.organizerDashboard,
                ),
                _ => null,
              },
            ),
          ),
      ],
    );
  }
}
