import 'package:sportika/shared/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/core/state/profile_photo_controller.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/shared/widgets/avatar_presets.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/features/profile_photo/profile_photo_flow.dart';

/// 13 · Profile photo setup. The player can import a real picture (camera or
/// gallery, cropped in the app) or stop at a brand gradient avatar.
class ProfilePhotoScreen extends StatelessWidget {
  const ProfilePhotoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final photos = context.watch<ProfilePhotoController>();
    final option = avatarOptionFor(flow.avatar);

    return AuthPage(
      showBack: true,
      onBack: flow.back,
      sport: Sport.badminton,
      photoAlignment: const Alignment(0, -.35),
      stepLabel: 'PROFILE SETUP',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'CONTINUE',
            busy: flow.busy || photos.busy,
            onPressed: flow.continueFromPhoto,
            icon: Icons.arrow_forward_rounded,
          ),
          if (!photos.hasPhoto)
            AuthLink(
              'Skip photo for now',
              onTap: photos.busy ? null : flow.continueFromPhoto,
            ),
          const SizedBox(height: 8),
          const AuthMicro(
            'Next: choose the sports you want to follow and play.',
          ),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(
          current: 1,
          labels: ['Basics', 'Photo', 'Sports', 'Play', 'Review'],
        ),
        const SizedBox(height: 26),
        const AuthEyebrow('PROFILE PHOTO'),
        const SizedBox(height: 14),
        const AuthHeadline('PUT A FACE', accent: 'TO THE NAME.', size: 42),
        const SizedBox(height: 14),
        const AuthLead(
          'Add a real picture, or pick the colour your teammates will learn to '
          'recognise. Initials keep it personal without a photo.',
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              ProfileAvatar(
                initials: initialsOf(flow.fullName),
                avatarId: flow.avatar,
                figure: defaultAvatarFigureFor(flow.gender),
                photoPath: photos.photoPath,
                photoUrl: photos.photoUrl,
                size: 120,
                busy: photos.busy,
                onEdit: () => _edit(context),
              ),
              const SizedBox(height: 14),
              Text(
                flow.fullName.isEmpty
                    ? 'YOUR PROFILE'
                    : flow.fullName.toUpperCase(),
                style: authDisplay(20, height: 1, letterSpacing: .4),
              ),
              const SizedBox(height: 4),
              Text(
                flow.handle.isEmpty ? '@yourhandle' : '@${flow.handle}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: SportikaFontWeight.semibold,
                  color: option.colors.first,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            const Text(
              'CHOOSE A COLOUR',
              style: TextStyle(
                fontSize: 9,
                fontWeight: SportikaFontWeight.extraBold,
                letterSpacing: 1.6,
                color: SportikaColors.textDim,
              ),
            ),
            Text(
              option.label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: SportikaFontWeight.extraBold,
                letterSpacing: 1.4,
                color: option.colors.first,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in avatarOptions)
              _AvatarSwatch(
                option: preset,
                selected: preset.id == flow.avatar,
                onTap: () => flow.selectAvatar(preset.id),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const ProfilePhotoStatus(),
        const SizedBox(height: 16),
        AuthAction(
          label: photos.hasPhoto ? 'CHANGE MY PHOTO' : 'UPLOAD A PHOTO',
          ghost: !photos.hasPhoto,
          busy: photos.busy,
          icon: photos.hasPhoto
              ? Icons.swap_horiz
              : Icons.photo_camera_outlined,
          onPressed: () => _edit(context),
        ),
        const SizedBox(height: 12),
        const AuthMicro(
          'The colour behind your initials stays as the fallback, and comes '
          'back if you ever remove the picture.',
          icon: Icons.palette_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// One trip through the shared picture flow, then the honest result: what it
  /// cost in bytes, or exactly why nothing changed.
  Future<void> _edit(BuildContext context) async {
    final outcome = await runProfilePhotoFlow(context);
    if (outcome == null || !context.mounted) return;
    showSnack(context, outcome.message, error: outcome.isError);
  }
}

class _AvatarSwatch extends StatelessWidget {
  const _AvatarSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AvatarOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: option.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          width: 38,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? SportikaColors.onAccent.withValues(alpha: .85)
                  : SportikaColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: option.colors,
              ),
            ),
            child: selected
                ? const Icon(
                    Icons.check,
                    size: 15,
                    color: SportikaColors.deepest,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
