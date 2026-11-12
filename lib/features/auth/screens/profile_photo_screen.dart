import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/shared/widgets/avatar_presets.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 13 · Profile photo setup. No binary uploads in the prototype, so the screen
/// offers a deliberate set of brand avatars and says so plainly.
class ProfilePhotoScreen extends StatelessWidget {
  const ProfilePhotoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final option = avatarOptionFor(flow.avatar);

    return AuthPage(
      sport: Sport.badminton,
      photoAlignment: const Alignment(0, -.35),
      stepLabel: 'PROFILE SETUP',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'FINISH SETUP',
            busy: flow.busy,
            onPressed: flow.finishSetup,
            icon: Icons.check,
          ),
          const SizedBox(height: 8),
          const AuthMicro(
            'Next: your Sportika welcome card and the five-tab app.',
          ),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(
          current: 3,
          labels: ['Basics', 'Sports', 'Levels', 'Photo'],
        ),
        const SizedBox(height: 26),
        const AuthEyebrow('PROFILE PHOTO'),
        const SizedBox(height: 14),
        const AuthHeadline('ONE LAST', accent: 'TOUCH.', size: 42),
        const SizedBox(height: 14),
        const AuthLead(
          'Pick the colour your teammates will learn to recognise. Initials '
          'keep it personal without a photo.',
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              AuthAvatar(
                initials: initialsOf(flow.fullName),
                avatarId: flow.avatar,
                size: 112,
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
                  fontWeight: FontWeight.w600,
                  color: option.colors.first,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            const Text(
              'CHOOSE A COLOUR',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
                color: SportikaColors.textDim,
              ),
            ),
            const Spacer(),
            Text(
              option.label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
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
        AuthAction(
          label: 'UPLOAD A PHOTO',
          ghost: true,
          icon: Icons.photo_camera_outlined,
          onPressed: () => showSnack(
            context,
            'Photo uploads arrive with the production build. '
            'Gradient avatars stay on this device.',
          ),
        ),
        const SizedBox(height: 12),
        const AuthMicro(
          'You can change your avatar from the Me tab at any time.',
          icon: Icons.palette_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
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
                  ? Colors.white.withValues(alpha: .85)
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
