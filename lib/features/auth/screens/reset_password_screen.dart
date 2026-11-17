import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/env.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 09 · Reset password. Live rules instead of a post-submit error, so the user
/// can see exactly what the password still needs.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final TextEditingController _password;
  late final TextEditingController _confirm;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController();
    _confirm = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();

    return AuthPage(
      sport: Sport.padel,
      photoAlignment: const Alignment(0, -.2),
      showBack: true,
      onBack: flow.back,
      stepLabel: 'RESET PASSWORD',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AppEnv.demoMode && !flow.recoveryFromLink)
            const AuthNotice(
              'Demo recovery code: 654321. Changes apply only during this app session.',
            ),
          AuthAction(
            label: 'UPDATE PASSWORD',
            busy: flow.busy,
            onPressed: () =>
                flow.submitResetPassword(_password.text, _confirm.text),
          ),
          const SizedBox(height: 8),
          AuthLink(
            'Back to sign in',
            align: TextAlign.center,
            onTap: flow.openSignIn,
          ),
        ],
      ),
      children: [
        const SizedBox(height: 30),
        const AuthEyebrow('SET A NEW PASSWORD'),
        const SizedBox(height: 14),
        const AuthHeadline('ONE MORE', accent: 'STEP.', size: 46),
        const SizedBox(height: 16),
        AuthLead(
          flow.recoveryFromLink
              ? 'The link you opened already confirmed this address. Choose a '
                    'new password and sign in with it next.'
              : flow.resetEmail.isEmpty
              ? 'Choose a password you will remember. You will sign in with it '
                    'next.'
              : 'Enter the reset code sent to ${flow.resetEmail}, then choose '
                    'your new password.',
        ),
        const SizedBox(height: 24),
        if (flow.notice != null) ...[
          AuthNotice(flow.notice!),
          const SizedBox(height: 16),
        ],
        // A recovery link has already proved the address server-side, so the
        // six-digit field would be an obstacle with nothing to type into it.
        if (flow.recoveryFromLink) ...[
          const AuthNotice(
            'Opened from your email link. No code is needed.',
            icon: Icons.mark_email_read_outlined,
          ),
          const SizedBox(height: 16),
        ] else ...[
          AuthOtpInput(
            value: flow.otp,
            error: flow.inlineField == 'otp',
            onChanged: (value) {
              flow.otp = value;
              if (flow.inlineField == 'otp') flow.clearInline();
            },
            onCompleted: (_) => FocusScope.of(context).nextFocus(),
          ),
          if (flow.inlineField == 'otp') ...[
            const SizedBox(height: 8),
            AuthNotice(
              flow.inlineError!,
              tone: SportikaColors.danger,
              icon: Icons.error_outline,
            ),
          ],
          const SizedBox(height: 8),
          AuthLink(
            flow.otpSecondsLeft > 0
                ? 'Resend in ${flow.otpSecondsLeft}s'
                : 'Resend reset code',
            onTap: flow.otpSecondsLeft > 0 ? null : flow.resendCode,
          ),
          const SizedBox(height: 18),
        ],
        AuthField(
          label: 'New password',
          controller: _password,
          hint: 'Eight characters minimum',
          obscure: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          errorText: flow.inlineField == 'password' ? flow.inlineError : null,
          onChanged: (value) {
            if (flow.inlineField == 'password') flow.clearInline();
            setState(() {});
          },
        ),
        const SizedBox(height: 18),
        AuthField(
          label: 'Confirm password',
          controller: _confirm,
          hint: 'Repeat the password',
          obscure: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          errorText: flow.inlineField == 'confirm' ? flow.inlineError : null,
          onChanged: (value) {
            if (flow.inlineField == 'confirm') flow.clearInline();
            setState(() {});
          },
          onSubmitted: (_) =>
              flow.submitResetPassword(_password.text, _confirm.text),
        ),
        const SizedBox(height: 18),
        const AuthMicro(
          'At least 8 characters are required. The checks below are strength suggestions.',
        ),
        const SizedBox(height: 12),
        for (final check in AuthRules.checks)
          _RuleRow(label: check.label, passed: check.passes(_password.text)),
        const SizedBox(height: 18),
        const AuthMicro(
          'Use a unique password you do not use for other accounts.',
          icon: Icons.devices_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.passed});

  final String label;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 16,
            width: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: passed
                  ? SportikaColors.mint.withValues(alpha: .18)
                  : Colors.transparent,
              border: Border.all(
                color: passed
                    ? SportikaColors.mint
                    : SportikaColors.borderStrong,
              ),
            ),
            child: passed
                ? const Icon(Icons.check, size: 11, color: SportikaColors.mint)
                : null,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: passed
                    ? SportikaColors.textBody
                    : SportikaColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
