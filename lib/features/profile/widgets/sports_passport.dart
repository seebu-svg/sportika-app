import 'package:flutter/material.dart';

import 'package:sportika/features/profile/widgets/sporting_record.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/profile_avatar.dart';
import 'package:sportika/shared/widgets/surfaces.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Athlete Passport hero: the strongest surface on the Me screen.
///
/// A signature navy surface with the Sportika mark, a single small
/// ATHLETE PASSPORT label, the member's photo and name as the focal point,
/// their published record, and one labelled edit action. The oversized
/// wrapping wordmark is deliberately gone so the identity reads first.
///
/// Presentation only. Account data, official statistics, and navigation
/// remain owned by their existing models and callbacks.
class SportsPassportCard extends StatelessWidget {
  const SportsPassportCard({
    super.key,
    required this.account,
    required this.onEditProfile,
    this.record,
  });

  final Account account;
  final VoidCallback onEditProfile;
  final SportingRecord? record;

  @override
  Widget build(BuildContext context) {
    final record = this.record;

    return SportikaSurface(
      style: SportikaSurfaceStyle.signature,
      tone: SportikaColors.mint,
      radius: SportikaRadius.passport,
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PassportMasthead(),

          const SizedBox(height: SportikaSpacing.lg),
          _PassportIdentity(account: account),

          if (record != null) ...[
            const SizedBox(height: SportikaSpacing.lg),
            const _PassportDivider(),
            const SizedBox(height: SportikaSpacing.md),

            Row(
              children: [
                Expanded(
                  child: Text(
                    'OFFICIAL RECORD',
                    style: SportikaType.label.copyWith(
                      color: SportikaColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const Icon(
                  Icons.insights_outlined,
                  size: SportikaIconSize.sm,
                  color: SportikaColors.mint,
                ),
              ],
            ),

            const SizedBox(height: SportikaSpacing.md),

            // Keep the existing official record implementation.
            // No statistics are fabricated or recalculated here.
            SportingRecordStrip(record: record),

            if (record.draws > 0) ...[
              const SizedBox(height: SportikaSpacing.sm),
              Text(
                record.draws == 1
                    ? '1 match drawn · a draw counts as neither a win nor a '
                          'loss'
                    : '${record.draws} matches drawn · a draw counts as '
                          'neither a win nor a loss',
                style: SportikaType.caption.copyWith(
                  color: SportikaColors.textMuted,
                ),
              ),
            ],

            if (record.isEmpty) ...[
              const SizedBox(height: SportikaSpacing.sm),
              Text(
                'Your first official result sets your win rate.',
                style: SportikaType.caption.copyWith(
                  color: SportikaColors.textMuted,
                ),
              ),
            ],
          ],

          const SizedBox(height: SportikaSpacing.lg),
          const _PassportDivider(),
          const SizedBox(height: SportikaSpacing.md),

          GhostButton(
            label: 'Edit profile',
            icon: Icons.edit_outlined,
            expand: true,
            onPressed: onEditProfile,
          ),
        ],
      ),
    );
  }
}

/// Compact brand identity: the mark and one small passport label.
class _PassportMasthead extends StatelessWidget {
  const _PassportMasthead();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ExcludeSemantics(child: BrandMark(size: SportikaSpacing.xl)),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: Text(
            'ATHLETE PASSPORT',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SportikaType.label.copyWith(
              color: SportikaColors.textBody,
              letterSpacing: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

/// Athlete portrait, display name, username, and location.
///
/// The existing ProfileAvatar is retained so all image sources and
/// fallback behavior continue to work.
class _PassportIdentity extends StatelessWidget {
  const _PassportIdentity({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final displayName = account.displayName.trim();
    final username = account.username.trim();
    final city = account.city.trim();

    final handle = username.isEmpty ? '' : '@$username';

    final primaryName = displayName.isNotEmpty
        ? displayName
        : handle.isNotEmpty
        ? handle
        : 'Sportika member';

    const portraitSize = SportikaSpacing.xxxl * 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale =
            MediaQuery.textScalerOf(context).scale(SportikaSpacing.lg) /
            SportikaSpacing.lg;

        final stacked =
            constraints.maxWidth <
            (portraitSize +
                SportikaSpacing.md +
                SportikaSpacing.xxxl * 3 * textScale);

        final portrait = Container(
          width: portraitSize,
          height: portraitSize,
          padding: const EdgeInsets.all(SportikaBorder.rule),
          decoration: BoxDecoration(
            color: SportikaColors.surfaceSunken,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(
              color: SportikaColors.mint.withValues(alpha: .34),
              width: SportikaBorder.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: ProfileAvatar(
            initials: account.initials,
            avatarId: account.avatar,
            figure: defaultAvatarFigureFor(account.gender),
            photoPath: account.photoPath,
            photoUrl: account.photoUrl,
            size: portraitSize - SportikaBorder.rule * 2,
          ),
        );

        final identity = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              primaryName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SportikaType.hero,
            ),

            if (displayName.isNotEmpty && handle.isNotEmpty) ...[
              const SizedBox(height: SportikaSpacing.xxs),
              Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SportikaType.caption.copyWith(
                  color: SportikaColors.textBody,
                ),
              ),
            ],

            const SizedBox(height: SportikaSpacing.sm),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: SportikaIconSize.sm,
                  color: SportikaColors.textMuted,
                ),
                const SizedBox(width: SportikaSpacing.xs),
                Flexible(
                  child: Text(
                    city.isEmpty ? 'City not set' : city,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SportikaType.caption,
                  ),
                ),
              ],
            ),
          ],
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              portrait,
              const SizedBox(height: SportikaSpacing.md),
              identity,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            portrait,
            const SizedBox(width: SportikaSpacing.md),
            Expanded(child: identity),
          ],
        );
      },
    );
  }
}

/// Fine, understated separation between passport sections.
class _PassportDivider extends StatelessWidget {
  const _PassportDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: SportikaBorder.rule,
      thickness: SportikaBorder.hairline,
      color: SportikaColors.borderSubtle,
    );
  }
}
