import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 04 · Sign in. Email-first, social providers as secondary options, and a
/// clearly labelled demo door into the seeded prototype world.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final TextEditingController _email;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    final flow = context.read<AuthFlowController>();
    _email = TextEditingController(text: flow.email);
    _password = TextEditingController(text: flow.password);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit(AuthFlowController flow) {
    FocusScope.of(context).unfocus();
    flow.email = _email.text;
    flow.password = _password.text;
    flow.submitSignIn();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final state = context.watch<AppState>();
    final demos = [
      state.accountById('acc-seebu'),
      state.accountById('acc-yasir'),
      state.accountById('acc-imran'),
    ].whereType<Account>().toList();

    return AuthPage(
      sport: Sport.futsal,
      photoAlignment: const Alignment(0, -.25),
      showBack: true,
      onBack: flow.back,
      stepLabel: 'SIGN IN',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'SIGN IN',
            busy: flow.busy,
            onPressed: () => _submit(flow),
            icon: Icons.arrow_forward,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    'New to Sportika?',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: SportikaColors.textDim,
                    ),
                  ),
                ),
              ),
              AuthLink('Create an account', onTap: flow.openCreateAccount),
            ],
          ),
        ],
      ),
      children: [
        const SizedBox(height: 18),
        const AuthEyebrow('WELCOME BACK'),
        const SizedBox(height: 14),
        const AuthHeadline('PICK UP', accent: 'WHERE YOU\nLEFT OFF.', size: 42),
        if (flow.notice != null) ...[
          const SizedBox(height: 18),
          AuthNotice(flow.notice!),
        ],
        const SizedBox(height: 20),
        AuthField(
          label: 'Email address',
          controller: _email,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
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
          hint: 'Your password',
          obscure: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          errorText: flow.inlineField == 'password' ? flow.inlineError : null,
          onChanged: (value) {
            flow.password = value;
            if (flow.inlineField == 'password') flow.clearInline();
          },
          onSubmitted: (_) => _submit(flow),
          labelAction: AuthLink(
            'FORGOT?',
            tone: SportikaColors.textMuted,
            onTap: () => flow.openForgotPassword(),
          ),
        ),
        const SizedBox(height: 22),
        const AuthDivider(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ProviderButton(
                label: 'GOOGLE',
                icon: Icons.g_mobiledata_rounded,
                onTap: () => showSnack(
                  context,
                  'Google sign-in arrives with the production build.',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProviderButton(
                label: 'APPLE',
                icon: Icons.apple,
                onTap: () => showSnack(
                  context,
                  'Apple sign-in arrives with the production build.',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const AuthRule(label: 'DEMO ACCESS'),
        const SizedBox(height: 4),
        const AuthMicro(
          'No password needed. Sign in as one of the seeded accounts to preview '
          'the signed-in app.',
          icon: Icons.science_outlined,
        ),
        const SizedBox(height: 10),
        for (final account in demos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DemoRow(
              account: account,
              enabled: !flow.busy,
              onTap: () => flow.demoSignIn(account.id),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SportikaColors.surface.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SportikaColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: SportikaColors.textBody),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: SportikaColors.textBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoRow extends StatelessWidget {
  const _DemoRow({
    required this.account,
    required this.onTap,
    required this.enabled,
  });

  final Account account;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final organizer = account.has(UserRole.organizer);
    final tone = organizer ? SportikaColors.mint : SportikaColors.blueBright;
    return Material(
      color: SportikaColors.surfaceSunken.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SportikaColors.borderSubtle),
          ),
          child: Row(
            children: [
              AccountAvatar(account: account, size: 32),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      account.displayName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: SportikaColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.roles.map((r) => r.label).join(' · '),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .4,
                        color: tone,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_outward,
                size: 15,
                color: SportikaColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
