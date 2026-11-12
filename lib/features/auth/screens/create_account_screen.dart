import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 05 · Create account. Three fields, one password meter, and terms that stay
/// visible instead of hiding behind a checkbox at the bottom of the app.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    final flow = context.read<AuthFlowController>();
    _name = TextEditingController(text: flow.fullName);
    _email = TextEditingController(text: flow.email);
    _password = TextEditingController(text: flow.password);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit(AuthFlowController flow) {
    FocusScope.of(context).unfocus();
    flow.fullName = _name.text;
    flow.email = _email.text;
    flow.password = _password.text;
    flow.submitAccountDetails();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();

    return AuthPage(
      sport: Sport.padel,
      photoAlignment: const Alignment(0, -.3),
      showBack: true,
      onBack: flow.back,
      stepLabel: 'CREATE ACCOUNT',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(label: 'CONTINUE', onPressed: () => _submit(flow)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Already have an account?',
                style: TextStyle(fontSize: 11.5, color: SportikaColors.textDim),
              ),
              AuthLink(' Sign in', onTap: flow.openSignIn),
            ],
          ),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(current: 0, labels: ['Account', 'Type', 'Verify']),
        const SizedBox(height: 26),
        const AuthEyebrow('CREATE ACCOUNT'),
        const SizedBox(height: 14),
        const AuthHeadline('JOIN THE', accent: 'NEXT MATCH.', size: 42),
        const SizedBox(height: 16),
        const AuthLead(
          'One account for the sports you play, the events you enter and the '
          'scorecards you keep.',
        ),
        const SizedBox(height: 24),
        AuthField(
          label: 'Full name',
          controller: _name,
          hint: 'Your name on the scorecard',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          errorText: flow.inlineField == 'name' ? flow.inlineError : null,
          onChanged: (value) {
            flow.fullName = value;
            if (flow.inlineField == 'name') flow.clearInline();
          },
        ),
        const SizedBox(height: 18),
        AuthField(
          label: 'Email address',
          controller: _email,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
          errorText: flow.inlineField == 'email' ? flow.inlineError : null,
          onChanged: (value) {
            flow.email = value;
            if (flow.inlineField == 'email') flow.clearInline();
          },
        ),
        const SizedBox(height: 18),
        AuthField(
          label: 'Password',
          controller: _password,
          hint: 'Eight characters minimum',
          obscure: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          errorText: flow.inlineField == 'password' ? flow.inlineError : null,
          onChanged: (value) {
            flow.password = value;
            if (flow.inlineField == 'password') flow.clearInline();
            setState(() {});
          },
          onSubmitted: (_) => _submit(flow),
        ),
        if (_password.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          _StrengthBar(value: _password.text),
        ],
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AuthCheckbox(
                value: flow.acceptedTerms,
                error: flow.inlineField == 'terms',
                onChanged: flow.setAcceptedTerms,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'I agree to the ',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: SportikaColors.textMuted,
                    ),
                  ),
                  AuthLink(
                    'Terms & Privacy',
                    tone: SportikaColors.textBody,
                    onTap: () => flow.openTerms(AuthStage.createAccount),
                  ),
                  const Text(
                    '. Official results are published by organizers only.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: SportikaColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (flow.inlineField == 'terms') ...[
          const SizedBox(height: 8),
          Text(
            flow.inlineError ?? '',
            style: const TextStyle(fontSize: 11, color: SportikaColors.danger),
          ),
        ],
        const SizedBox(height: 14),
        const AuthMicro(
          'We use your email for match updates, entry decisions and nothing else.',
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final score = AuthRules.strength(value);
    final label = AuthRules.strengthLabel(value);
    final tone = score >= .99
        ? SportikaColors.mint
        : score >= .5
        ? SportikaColors.gold
        : SportikaColors.danger;

    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              decoration: BoxDecoration(
                color: i < (score * 4).ceil() ? tone : SportikaColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: tone,
          ),
        ),
      ],
    );
  }
}
