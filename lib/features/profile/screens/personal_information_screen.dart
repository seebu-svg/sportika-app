import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/features/profile/widgets/profile_identity_fields.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Me → Personal information.
///
/// Name, handle, date of birth, gender, city, bio and play style, edited on the
/// same cards the setup journey uses so the two screens cannot disagree about
/// what a valid profile looks like.
class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileModuleController>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final module = context.watch<ProfileModuleController>();
    final personal = module.snapshot?.personal;

    final Widget body;
    if (personal != null) {
      body = _PersonalInformationForm(
        // A saved card arrives as a new snapshot; remaking the form from it
        // keeps the fields and the row in step.
        key: ValueKey(
          '${personal.displayName}|${personal.username}|'
          '${personal.city}|${personal.bio}|${personal.dateOfBirth}',
        ),
        personal: personal,
        busy: module.busy,
      );
    } else if (module.error != null) {
      body = ErrorState(
        title: 'Your profile could not be loaded',
        message: module.error,
        onRetry: module.refresh,
      );
    } else {
      body = const LoadingSkeleton(
        rows: 4,
        label: 'Loading personal information',
      );
    }

    return ScreenScaffold(
      title: 'Personal information',
      onRefresh: module.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Me',
            title: 'Personal information',
            subtitle:
                'The details other members see. Your date of birth is used '
                'only to pick the right optional document.',
          ),
          body,
        ],
      ),
    );
  }
}

class _PersonalInformationForm extends StatefulWidget {
  const _PersonalInformationForm({
    super.key,
    required this.personal,
    required this.busy,
  });

  final ProfilePersonalInformation personal;
  final bool busy;

  @override
  State<_PersonalInformationForm> createState() =>
      _PersonalInformationFormState();
}

class _PersonalInformationFormState extends State<_PersonalInformationForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.personal.displayName,
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.personal.username,
  );
  late final TextEditingController _birth = TextEditingController(
    text: profileDateLabel(widget.personal.dateOfBirth),
  );
  late final TextEditingController _city = TextEditingController(
    text: widget.personal.city,
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.personal.bio,
  );
  late ProfileGender? _gender = widget.personal.gender;
  late PlayStyle _playStyle = widget.personal.playStyle;
  String? _errorField;
  String? _errorMessage;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _birth.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorField == null && _errorMessage == null) return;
    setState(() {
      _errorField = null;
      _errorMessage = null;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final birth = parseProfileDate(_birth.text);
    final problem = validateProfileIdentity(
      name: _name.text,
      handle: _username.text,
      city: _city.text,
      bio: _bio.text,
      dateOfBirth: birth,
    );
    if (problem != null) {
      setState(() {
        _errorField = problem.field;
        _errorMessage = problem.message;
      });
      return;
    }
    setState(() {
      _errorField = null;
      _errorMessage = null;
    });

    final module = context.read<ProfileModuleController>();
    try {
      await module.savePersonalInformation(
        displayName: _name.text,
        city: _city.text,
        bio: _bio.text,
        dateOfBirth: birth!,
        gender: _gender,
        playStyle: _playStyle,
      );
      final wanted = normalizeProfileHandle(_username.text);
      if (wanted != widget.personal.username.toLowerCase()) {
        await module.changeUsername(wanted);
      }
      if (!mounted) return;
      showSnack(context, 'Personal information saved');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      final usernameProblem =
          error.code == '23505' || error.code == 'invalid_username';
      setState(() {
        _errorField = usernameProblem ? 'handle' : null;
        _errorMessage = error.message;
      });
      showSnack(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          child: ProfileIdentityFields(
            name: _name,
            username: _username,
            birthDate: _birth,
            city: _city,
            bio: _bio,
            gender: _gender,
            onGenderChanged: (value) {
              setState(() => _gender = value);
              _clearError();
            },
            onChanged: _clearError,
            errorField: _errorField,
            errorMessage: _errorMessage,
            enabled: enabled,
          ),
        ),
        const SectionHeader('Play style'),
        const Text(
          'How often you expect to be on court or in the middle.',
          style: SportikaType.caption,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        DropdownButtonFormField<PlayStyle>(
          initialValue: _playStyle,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Play style'),
          items: [
            for (final option in PlayStyle.values)
              DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) setState(() => _playStyle = value);
                }
              : null,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Text(_playStyle.blurb, style: SportikaType.caption),
        const SizedBox(height: SportikaSpacing.lg),
        if (_errorField == null && _errorMessage != null)
          InlineBanner(text: _errorMessage!, tone: SportikaColors.danger),
        if (_errorField == null && _errorMessage != null)
          const SizedBox(height: SportikaSpacing.md),
        PrimaryButton(
          label: 'Save changes',
          icon: Icons.check,
          busy: widget.busy,
          onPressed: widget.busy ? null : _save,
        ),
        const SizedBox(height: SportikaSpacing.sm),
        const HelperText(
          'Your handle is your public @name. Changing it keeps your record, '
          'your matches and your teams.',
        ),
      ],
    );
  }
}
