import 'package:flutter/material.dart';

import 'package:sportika/shared/models/profile_setup.dart';
import 'package:sportika/shared/theme/theme.dart';

/// The portrait a member sees in place of a profile picture.
///
/// The profile setup already records a gender, so the default portrait can be
/// the matching silhouette instead of the same anonymous circle for everyone.
/// Anything the member has not stated, or prefers not to state, keeps facing
/// [neutral].
enum DefaultAvatarFigure { man, woman, neutral }

/// Chooses the default portrait for a stored profile gender.
DefaultAvatarFigure defaultAvatarFigureFor(ProfileGender? gender) {
  return switch (gender) {
    ProfileGender.man => DefaultAvatarFigure.man,
    ProfileGender.woman => DefaultAvatarFigure.woman,
    _ => DefaultAvatarFigure.neutral,
  };
}

/// Stand-ins that mean "there is no name to draw" rather than real letters.
const Set<String> _letterlessInitials = {'', '?', '—', '–', '-'};

/// Whether [initials] carry an identity, or are one of the neutral stand-ins
/// (`''`, `'?'`, `'—'`) that mean the slot has nothing to draw.
bool hasAvatarInitials(String? initials) =>
    !_letterlessInitials.contains(initials?.trim() ?? '');

/// Branded default portrait, drawn wherever a member has no profile picture.
///
/// A flat brand surface with a mint hairline ring and a mint athlete
/// silhouette: no gradient, so a default avatar reads the same on Home, in the
/// player directory, on tickets and inside the scoring workspaces. The widget
/// is static by design — dozens can sit on one screen, and an animated
/// placeholder would make `pumpAndSettle` tests hang.
class BrandedDefaultAvatar extends StatelessWidget {
  const BrandedDefaultAvatar({
    super.key,
    this.size = 40,
    this.figure = DefaultAvatarFigure.neutral,
    this.ring = true,
  });

  /// Diameter of the disc.
  final double size;

  /// Which silhouette to draw.
  final DefaultAvatarFigure figure;

  /// Whether to draw the mint hairline ring. Frames that already draw their own
  /// ring pass false so the edge is not doubled up.
  final bool ring;

  IconData get _glyph => switch (figure) {
    DefaultAvatarFigure.man => Icons.man_rounded,
    DefaultAvatarFigure.woman => Icons.woman_rounded,
    DefaultAvatarFigure.neutral => Icons.person_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Default profile picture',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SportikaColors.surfaceAlt,
            shape: BoxShape.circle,
            border: ring
                ? Border.all(
                    color: SportikaColors.mint.withValues(alpha: .45),
                    width: SportikaBorder.hairline,
                  )
                : null,
          ),
          child: Icon(_glyph, size: size * .56, color: SportikaColors.mint),
        ),
      ),
    );
  }
}
