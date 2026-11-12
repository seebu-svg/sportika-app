import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 07 · Email / OTP verification. Six boxes, a live resend timer and an honest
/// note about how the prototype treats codes.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  String _code = '';

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final waiting = flow.otpSecondsLeft > 0;

    return AuthPage(
      sport: Sport.cricket,
      photoAlignment: const Alignment(0, -.3),
      showBack: true,
      onBack: flow.back,
      stepLabel: 'VERIFY EMAIL',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'VERIFY & CONTINUE',
            busy: flow.busy,
            onPressed: () => flow.verifyCode(_code),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Wrong address?',
                style: TextStyle(fontSize: 11.5, color: SportikaColors.textDim),
              ),
              AuthLink(' Change email', onTap: flow.changeEmail),
            ],
          ),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(current: 2, labels: ['Account', 'Type', 'Verify']),
        const SizedBox(height: 26),
        const AuthEyebrow('VERIFY EMAIL'),
        const SizedBox(height: 14),
        const AuthHeadline('CHECK YOUR', accent: 'INBOX.', size: 44),
        const SizedBox(height: 16),
        AuthLead(
          'We sent a six-digit code to ${flow.maskedEmail}. It expires in ten '
          'minutes.',
        ),
        if (flow.notice != null) ...[
          const SizedBox(height: 14),
          AuthNotice(flow.notice!),
        ],
        const SizedBox(height: 24),
        AuthOtpInput(
          value: _code,
          error: flow.inlineField == 'otp',
          onChanged: (value) {
            setState(() => _code = value);
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
        Row(
          children: [
            Text(
              waiting
                  ? 'RESEND IN 0:${flow.otpSecondsLeft.toString().padLeft(2, '0')}'
                  : 'DIDN\'T GET IT?',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
                color: SportikaColors.textDim,
              ),
            ),
            const Spacer(),
            if (!waiting)
              AuthLink(
                'Resend code',
                onTap: flow.resendCode,
                icon: Icons.refresh,
              ),
          ],
        ),
        const SizedBox(height: 18),
        const AuthMeetingNote(),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Prototype-only hint kept in one place so it can be removed with the mock
/// verification service.
class AuthMeetingNote extends StatelessWidget {
  const AuthMeetingNote({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthNotice(
      'Prototype: any six digits verify the account. Enter 000000 to preview '
      'the expired-code error and retry state.',
      tone: SportikaColors.gold,
      icon: Icons.science_outlined,
    );
  }
}
