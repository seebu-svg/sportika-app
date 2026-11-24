import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/env.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// One screen for the three codes the server can send: the signup
/// confirmation, a passwordless sign-in code and a recovery code. Only the
/// purpose, the copy and the way back change — the input and the request are
/// identical, so there is no second screen to keep in sync.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final waiting = flow.otpSecondsLeft > 0;
    final signIn = flow.codePurpose == AuthCodePurpose.signIn;

    return AuthPage(
      sport: Sport.cricket,
      photoAlignment: const Alignment(0, -.3),
      showBack: true,
      onBack: flow.back,
      stepLabel: signIn ? 'SIGN IN' : 'VERIFY EMAIL',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AppEnv.demoMode)
            const AuthNotice(
              'Demo verification code: 123456. No email is sent.',
            ),
          AuthAction(
            label: signIn ? 'SIGN IN' : 'VERIFY & CONTINUE',
            busy: flow.busy,
            onPressed: () => flow.verifyCode(flow.otp),
          ),
          // A sign-in code belongs to the address that was typed on the sign-in
          // screen, so there is no account step to send the member back to.
          if (!signIn) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Wrong address?',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: SportikaColors.textDim,
                  ),
                ),
                // The gap is a widget rather than a leading space in the label,
                // so the link text stays exactly what the member reads.
                const SizedBox(width: 6),
                AuthLink('Change email', onTap: flow.changeVerificationEmail),
              ],
            ),
          ],
        ],
      ),
      children: [
        if (!signIn) ...[
          const SizedBox(height: 8),
          const AuthStepRail(
            current: 1,
            labels: ['Account', 'Verify', 'Profile'],
          ),
        ],
        const SizedBox(height: 26),
        AuthEyebrow(signIn ? 'PASSWORDLESS SIGN-IN' : 'VERIFY EMAIL'),
        const SizedBox(height: 14),
        signIn
            ? const AuthHeadline('YOUR CODE', accent: 'TO GET IN.', size: 44)
            : const AuthHeadline('CHECK YOUR', accent: 'INBOX.', size: 44),
        const SizedBox(height: 16),
        AuthLead(
          'Enter the six-digit code sent to ${flow.maskedEmail}. If it has '
          'expired, request a new code below.',
        ),
        if (flow.notice != null) ...[
          const SizedBox(height: 14),
          AuthNotice(flow.notice!),
        ],
        const SizedBox(height: 24),
        AuthOtpInput(
          value: flow.otp,
          error: flow.inlineField == 'otp',
          onChanged: (value) {
            if (flow.inlineField == 'otp') flow.clearInline();
            flow.otp = value;
          },
          onCompleted: (value) => flow.verifyCode(value),
        ),
        if (flow.inlineField == 'otp') ...[
          const SizedBox(height: 8),
          Text(
            flow.inlineError ?? '',
            style: const TextStyle(fontSize: 11, color: SportikaColors.danger),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              waiting ? 'RESEND IN ${flow.otpSecondsLeft}s' : 'DIDN\'T GET IT?',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: SportikaFontWeight.extraBold,
                letterSpacing: 1.3,
                color: SportikaColors.textDim,
              ),
            ),
            if (!waiting)
              AuthLink(
                'Resend code',
                onTap: flow.resendCode,
                icon: Icons.refresh,
              ),
          ],
        ),
        const SizedBox(height: 18),
        AuthMicro(
          signIn
              ? 'The code expires shortly after it is sent. Check your spam '
                    'folder before requesting another one.'
              : 'Check your spam folder before requesting another code.',
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
