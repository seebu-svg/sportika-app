import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Starts an email address change for the signed-in member.
///
/// With "Secure email change" enabled in Supabase, nothing changes when this
/// request succeeds: both the old and the new inbox receive a confirmation
/// mail and the address only moves once both links are opened. The pending
/// panel exists so the member does not read that as a failure.
class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  late final TextEditingController _email;
  late final TextEditingController _password;
  bool _busy = false;
  String? _field;
  String? _error;
  String? _pendingTo;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController();
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _changed(String field) {
    if (_field == field && _error != null) {
      setState(() {
        _field = null;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final requested = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _field = null;
    });
    try {
      await context.read<AuthFlowController>().submitEmailChange(
        email: requested,
        currentPassword: _password.text,
      );
      if (!mounted) return;
      _email.clear();
      _password.clear();
      setState(() => _pendingTo = requested);
      showSnack(context, 'Check both inboxes to confirm the change');
    } on AuthenticationException catch (error) {
      if (mounted) {
        setState(() {
          _field = error.field;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _field = null;
          _error = 'Your email could not be changed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionController>().currentAccount;
    return ScreenScaffold(
      title: 'Change email',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScreenHeader(
            eyebrow: 'Account and security',
            title: 'Change email',
            subtitle:
                'Your email is how you sign in and how reset codes reach you.',
          ),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CURRENT ADDRESS', style: SportikaType.label),
                const SizedBox(height: 6),
                Text(me?.email ?? 'Signed out', style: SportikaType.bodyStrong),
              ],
            ),
          ),
          const SizedBox(height: SportikaSpacing.lg),
          if (_pendingTo != null) ...[
            InlineBanner(
              text:
                  'Confirmation sent. We have emailed $_pendingTo and your '
                  'current address. The change is applied only after both '
                  'inboxes confirm — until then you keep signing in with the '
                  'address above.',
              tone: SportikaColors.gold,
              icon: Icons.mark_email_unread_outlined,
            ),
            const SizedBox(height: SportikaSpacing.md),
          ],
          if (_error != null) ...[
            Semantics(
              liveRegion: true,
              child: AuthNotice(
                _error!,
                tone: SportikaColors.danger,
                icon: Icons.error_outline,
              ),
            ),
            const SizedBox(height: SportikaSpacing.md),
          ],
          AuthField(
            label: 'New email address',
            controller: _email,
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            errorText: _field == 'email' ? _error : null,
            onChanged: (_) => _changed('email'),
          ),
          const SizedBox(height: SportikaSpacing.lg),
          AuthField(
            label: 'Current password',
            controller: _password,
            hint: 'Confirm it is you',
            obscure: true,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            errorText: _field == 'currentPassword' ? _error : null,
            onChanged: (_) => _changed('currentPassword'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: SportikaSpacing.lg),
          const AuthMicro(
            'We ask for your password again so a borrowed phone cannot move '
            'your account to another address.',
          ),
          const SizedBox(height: SportikaSpacing.lg),
          PrimaryButton(
            label: _pendingTo == null
                ? 'Send confirmation'
                : 'Send confirmation again',
            icon: Icons.outgoing_mail,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: SportikaSpacing.md),
          const InfoBanner(
            icon: Icons.info_outline,
            text:
                'Sportika requires a confirmation from both the old and the '
                'new address. If only one arrives, tell support which inbox is '
                'missing it before the change expires.',
          ),
        ],
      ),
    );
  }
}
