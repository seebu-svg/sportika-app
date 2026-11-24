import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Changes the password of the signed-in member.
///
/// The server requires the current password on the same request, so this screen
/// asks for it instead of trusting an older session. Everything here is local
/// state: the flow only validates and forwards, so a failure keeps whatever the
/// member typed.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  late final TextEditingController _current;
  late final TextEditingController _next;
  late final TextEditingController _confirm;
  bool _busy = false;
  bool _saved = false;
  String? _field;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = TextEditingController();
    _next = TextEditingController();
    _confirm = TextEditingController();
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
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
    setState(() {
      _busy = true;
      _error = null;
      _field = null;
    });
    try {
      await context.read<AuthFlowController>().submitPasswordChange(
        currentPassword: _current.text,
        next: _next.text,
        confirm: _confirm.text,
      );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      setState(() => _saved = true);
      showSnack(context, 'Password updated');
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
          _error = 'Your password could not be changed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOutEverywhere() async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Sign out of all devices?',
          style: SportikaType.title,
        ),
        content: const Text(
          'Every device, including this one, has to sign in again with the new '
          'password.',
          style: SportikaType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SportikaColors.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await context.read<AuthFlowController>().signOutEverywhere();
    if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Change password',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScreenHeader(
            eyebrow: 'Account and security',
            title: 'Change password',
            subtitle:
                'Confirm your current password, then choose a new one. At '
                'least 8 characters.',
          ),
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
          if (_saved) ...[
            const InlineBanner(
              text:
                  'Password updated. Use it the next time you sign in. If you '
                  'think anyone else still has the old one, sign out everywhere.',
              tone: SportikaColors.mint,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: SportikaSpacing.md),
          ],
          AuthField(
            label: 'Current password',
            controller: _current,
            hint: 'Your password now',
            obscure: true,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.password],
            errorText: _field == 'currentPassword' ? _error : null,
            onChanged: (_) => _changed('currentPassword'),
          ),
          const SizedBox(height: SportikaSpacing.lg),
          AuthField(
            label: 'New password',
            controller: _next,
            hint: 'Eight characters minimum',
            obscure: true,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            errorText: _field == 'password' ? _error : null,
            onChanged: (_) => _changed('password'),
          ),
          const SizedBox(height: SportikaSpacing.lg),
          AuthField(
            label: 'Confirm new password',
            controller: _confirm,
            hint: 'Repeat the new password',
            obscure: true,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            errorText: _field == 'confirm' ? _error : null,
            onChanged: (_) => _changed('confirm'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: SportikaSpacing.lg),
          const AuthMicro(
            'A unique password you do not use anywhere else keeps this account '
            'yours.',
          ),
          const SizedBox(height: SportikaSpacing.lg),
          PrimaryButton(
            label: 'Update password',
            icon: Icons.lock_reset,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
          if (_saved) ...[
            const SizedBox(height: SportikaSpacing.md),
            GhostButton(
              label: 'Sign out everywhere',
              icon: Icons.devices_outlined,
              tone: SportikaColors.danger,
              expand: true,
              onPressed: _busy ? null : _signOutEverywhere,
            ),
          ],
        ],
      ),
    );
  }
}
