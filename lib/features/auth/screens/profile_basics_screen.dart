import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 10 · Basic profile information. The first setup step; identity only, no
/// preferences yet, with a live preview of the initials avatar.
class ProfileBasicsScreen extends StatefulWidget {
  const ProfileBasicsScreen({super.key});

  @override
  State<ProfileBasicsScreen> createState() => _ProfileBasicsScreenState();
}

class _ProfileBasicsScreenState extends State<ProfileBasicsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _handle;
  late final TextEditingController _city;
  late final TextEditingController _bio;

  @override
  void initState() {
    super.initState();
    final flow = context.read<AuthFlowController>();
    _name = TextEditingController(text: flow.fullName);
    _handle = TextEditingController(text: flow.handle);
    _city = TextEditingController(text: flow.city);
    _bio = TextEditingController(text: flow.bio);
  }

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final initials = initialsOf(
      _name.text.trim().isEmpty ? flow.fullName : _name.text,
    );

    return AuthPage(
      sport: Sport.cricket,
      photoAlignment: const Alignment(0, -.4),
      stepLabel: 'PROFILE SETUP',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'CONTINUE',
            onPressed: () => flow.saveBasics(
              name: _name.text,
              handleValue: _handle.text,
              cityValue: _city.text,
              bioValue: _bio.text,
            ),
          ),
          const SizedBox(height: 8),
          const AuthMicro('You can change all of this from the Me tab.'),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(
          current: 0,
          labels: ['Basics', 'Sports', 'Levels', 'Photo'],
        ),
        const SizedBox(height: 26),
        const AuthEyebrow('YOUR IDENTITY'),
        const SizedBox(height: 14),
        const AuthHeadline("LET'S MAKE", accent: 'THIS YOURS.', size: 42),
        const SizedBox(height: 16),
        const AuthLead(
          'This is what teammates and organizers see when you enter a squad or '
          'a tournament.',
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            AuthAvatar(initials: initials, avatarId: flow.avatar, size: 62),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PHOTO COMES NEXT',
                    style: authDisplay(
                      10,
                      color: SportikaColors.mint,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Four quick steps and your profile is ready.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: SportikaColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AuthField(
          label: 'Display name',
          controller: _name,
          hint: 'Your name on the scorecard',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          errorText: flow.inlineField == 'name' ? flow.inlineError : null,
          onChanged: (value) {
            if (flow.inlineField == 'name') flow.clearInline();
            setState(() {});
          },
        ),
        const SizedBox(height: 18),
        AuthField(
          label: 'Username',
          controller: _handle,
          hint: 'yourhandle',
          textInputAction: TextInputAction.next,
          errorText: flow.inlineField == 'handle' ? flow.inlineError : null,
          onChanged: (value) {
            if (flow.inlineField == 'handle') flow.clearInline();
          },
        ),
        const SizedBox(height: 18),
        AuthField(
          label: 'City',
          controller: _city,
          hint: 'Karachi',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          errorText: flow.inlineField == 'city' ? flow.inlineError : null,
          onChanged: (value) {
            if (flow.inlineField == 'city') flow.clearInline();
          },
        ),
        const SizedBox(height: 18),
        AuthField(
          label: 'Short bio',
          controller: _bio,
          hint: 'Left-arm spinner. Plays padel on Thursdays.',
          maxLines: 3,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          errorText: flow.inlineField == 'bio' ? flow.inlineError : null,
        ),
        const SizedBox(height: 10),
        const AuthMicro(
          'Your handle appears in entries and squads. You can change it later.',
          icon: Icons.alternate_email,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
