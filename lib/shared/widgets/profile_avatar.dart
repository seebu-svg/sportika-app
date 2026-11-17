import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/avatar_presets.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Shared profile portrait. The edit target stays within the allocated bounds
/// while its visible disc overlaps the portrait's bottom-right edge.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.initials,
    this.avatarId = 'midnight',
    this.photoPath,
    this.photoUrl,
    this.size = 120,
    this.onEdit,
    this.busy = false,
    this.showRing = true,
  });

  final String initials;
  final String avatarId;
  final String? photoPath, photoUrl;
  final double size;
  final VoidCallback? onEdit;
  final bool busy;
  final bool showRing;

  @override
  Widget build(BuildContext context) {
    final preset = avatarOptionFor(avatarId);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: showRing
                      ? SportikaColors.mint.withValues(alpha: .5)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(showRing ? 4 : 0),
                child: ClipOval(
                  child: PlayerAvatar(
                    initials: initials.isEmpty ? '?' : initials,
                    size: showRing ? size - 8 : size,
                    photoPath: photoPath,
                    photoUrl: photoUrl,
                    gradient: preset.colors,
                    ink: preset.ink,
                    ring: SportikaColors.mint,
                  ),
                ),
              ),
            ),
          ),
          if (onEdit != null || busy)
            Positioned(
              right: 0,
              bottom: 0,
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: Material(
                    color: SportikaColors.mint,
                    shape: const CircleBorder(
                      side: BorderSide(color: SportikaColors.deepest, width: 3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      tooltip: busy
                          ? 'Updating profile picture'
                          : 'Edit profile picture',
                      onPressed: busy ? null : onEdit,
                      constraints: const BoxConstraints.tightFor(
                        width: 38,
                        height: 38,
                      ),
                      padding: EdgeInsets.zero,
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SportikaColors.deepest,
                              ),
                            )
                          : const Icon(
                              Icons.photo_camera_outlined,
                              size: 19,
                              color: SportikaColors.deepest,
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
