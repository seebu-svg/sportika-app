import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/state/profile_photo_controller.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_setup.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Final review before the local profile is committed and Home is unlocked.
class SetupCompleteScreen extends StatelessWidget {
  const SetupCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final photos = context.watch<ProfilePhotoController>();
    return AuthPage(
      sport: flow.selectedSports.firstOrNull ?? Sport.cricket,
      showBack: true,
      onBack: flow.back,
      stepLabel: 'REVIEW PROFILE',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'FINISH SETUP',
            icon: Icons.check,
            busy: flow.busy || photos.busy,
            onPressed: flow.finishSetup,
          ),
          const SizedBox(height: 8),
          const AuthMicro(
            'Finish your profile and enter Sportika. You can add your CNIC or B-Form for verification later from the Me tab.',
          ),
        ],
      ),
      children: [
        const AuthStepRail(
          current: 4,
          labels: ['Basics', 'Photo', 'Sports', 'Play', 'Review'],
        ),
        const SizedBox(height: 26),
        const AuthEyebrow('READY WHEN YOU ARE'),
        const SizedBox(height: 14),
        const AuthHeadline('YOUR PROFILE.', accent: 'YOUR GAME.', size: 42),
        const SizedBox(height: 14),
        const AuthLead(
          'Review your details, make any changes and finish setup. One account opens the whole Sportika ecosystem.',
        ),
        const SizedBox(height: 22),
        Center(
          child: AuthAvatar(
            initials: initialsOf(flow.fullName),
            avatarId: flow.avatar,
            figure: defaultAvatarFigureFor(flow.gender),
            photoPath: photos.photoPath,
            photoUrl: photos.photoUrl,
            size: 88,
          ),
        ),
        Center(
          child: AuthLink(
            'Edit photo',
            onTap: () => flow.editSetupStep(AuthStage.profilePhoto),
          ),
        ),
        SurfaceCard(
          child: Column(
            children: [
              AuthSummaryRow('Full name', flow.fullName),
              AuthSummaryRow('Username', '@${flow.handle}'),
              AuthSummaryRow(
                'Date of birth',
                profileDateLabel(flow.dateOfBirth),
              ),
              AuthSummaryRow('Gender', flow.gender?.label ?? 'Not specified'),
              AuthSummaryRow(
                'Identity documents',
                flow.identityDocuments.isEmpty
                    ? 'Skipped · can add later'
                    : 'Added · submitted',
              ),
              if (!flow.identityDocuments.isEmpty)
                AuthLink(
                  'Skip identity documents',
                  onTap: flow.skipIdentityDocuments,
                ),
              AuthSummaryRow('City', flow.city),
              if (flow.bio.isNotEmpty) AuthSummaryRow('Bio', flow.bio),
              AuthLink(
                'Edit basic information',
                onTap: () => flow.editSetupStep(AuthStage.profileBasics),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final sport in flow.selectedSports)
                AuthSummaryRow(
                  sport.label,
                  flow.playingPreferencesSkipped
                      ? 'Following · playing preferences not set'
                      : '${(flow.levels[sport.key] ?? defaultLevelFor(sport)).label}${flow.playingPositions[sport.key] == null ? '' : '\n${flow.playingPositions[sport.key]}'}',
                ),
              if (flow.selectedSports.isEmpty)
                const AuthNotice('Choose at least one preferred sport.'),
              if (!flow.playingPreferencesSkipped)
                AuthSummaryRow('Play style', flow.playStyle.label),
              AuthLink(
                'Edit sports',
                onTap: () => flow.editSetupStep(AuthStage.selectSports),
              ),
              AuthLink(
                'Edit playing preferences',
                onTap: () => flow.editSetupStep(AuthStage.sportsLevels),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const AuthNotice(
          'Your photo and playing preferences are optional. Required details must be complete before Home opens. Everything stays on this device.',
          icon: Icons.info_outline,
        ),
      ],
    );
  }
}
