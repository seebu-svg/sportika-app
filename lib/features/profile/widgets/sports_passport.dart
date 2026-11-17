import 'package:flutter/material.dart';

import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/profile_avatar.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// The signature Sports Passport card: one premium navy surface carrying the
/// member's photographic identity, handle, city and Sportika membership.
///
/// Nothing here is invented — no rank, no tier, no serial number. The only
/// claims on the card are the member's own profile record.
class SportsPassportCard extends StatelessWidget {
  const SportsPassportCard({
    super.key,
    required this.account,
    required this.onEditProfile,
  });

  final Account account;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final name = account.displayName.trim().isEmpty
        ? '@${account.username}'
        : account.displayName.trim();
    // A profile that has not set a name yet already shows the handle as the
    // headline, so the small line underneath is skipped rather than repeated.
    final handle = account.displayName.trim().isEmpty
        ? null
        : '@${account.username}';
    final city = account.city.trim();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SportikaColors.borderStrong.withValues(alpha: .65),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16304E), Color(0xFF0C1F36), Color(0xFF09182D)],
          stops: [0, .58, 1],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 26,
            offset: Offset(0, 14),
          ),
          BoxShadow(color: Color(0x1436506D), blurRadius: 2, spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _PassportGuardPainter()),
              ),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SizedBox(
                  height: 1.4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x00FFFFFF),
                          Color(0x33FFFFFF),
                          Color(0x00FFFFFF),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SPORTIKA · ATHLETE PASSPORT',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SportikaType.micro.copyWith(
                            color: SportikaColors.mint,
                            letterSpacing: 1.3,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onEditProfile,
                        style: TextButton.styleFrom(
                          foregroundColor: SportikaColors.textBody,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text(
                          'Edit profile',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const IgnorePointer(
                    child: SizedBox(
                      height: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0x00F6B84B),
                              Color(0x40F6B84B),
                              Color(0x00F6B84B),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ProfileAvatar(
                        initials: account.initials,
                        avatarId: account.avatar,
                        photoPath: account.photoPath,
                        photoUrl: account.photoUrl,
                        size: 84,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: SportikaType.displayFamily,
                                fontSize: 26,
                                height: 1.02,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.2,
                                color: SportikaColors.text,
                              ),
                            ),
                            if (handle != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                handle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SportikaType.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: SportikaColors.textBody,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.place_outlined,
                                  size: 12,
                                  color: SportikaColors.textDim,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    city.isEmpty ? 'City not set' : city,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SportikaType.caption,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                    decoration: BoxDecoration(
                      color: SportikaColors.deepest.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SportikaColors.borderSubtle),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('MEMBERSHIP', style: SportikaType.micro),
                        SizedBox(height: 6),
                        StatusPill(
                          'Sportika member',
                          color: SportikaColors.blueBright,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Very quiet concentric rings in the passport's upper right: enough to read as
/// a printed security detail, never bright enough to compete with the name.
class _PassportGuardPainter extends CustomPainter {
  const _PassportGuardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = SportikaColors.mint.withValues(alpha: .1);
    final centre = Offset(size.width * .93, size.height * .06);
    for (final radius in const [34.0, 58.0, 82.0]) {
      canvas.drawCircle(centre, radius, ring);
    }

    final sweep = Paint()
      ..strokeWidth = 1
      ..color = SportikaColors.blueBright.withValues(alpha: .08);
    canvas.drawLine(
      Offset(size.width * .62, size.height),
      Offset(size.width, size.height * .38),
      sweep,
    );

    // A faint embossed wordmark, low enough to read as printed security
    // engraving rather than competing with the member's name.
    final wordmark = TextPainter(
      text: const TextSpan(
        text: 'SPORTIKA',
        style: TextStyle(
          fontFamily: 'Barlow Condensed',
          fontSize: 62,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
          color: Color(0x0FFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(size.width * .5, size.height * .66);
    canvas.rotate(-.16);
    wordmark.paint(canvas, Offset(-wordmark.width / 2, 0));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PassportGuardPainter oldDelegate) => false;
}
