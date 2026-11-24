import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/features/profile/widgets/profile_identity_fields.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Sportika Athlete Identity & Personal Information.
///
/// Existing profile fields remain connected to ProfileModuleController.
/// New sensitive-data modules are represented as integration-ready sections.
/// They do not collect or persist sensitive information until a dedicated
/// secure repository and verification workflow are implemented.
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

    Widget body;

    if (personal != null) {
      body = _PersonalInformationForm(personal: personal, busy: module.busy);
    } else if (module.error != null) {
      body = ErrorState(
        title: 'Your profile could not be loaded',
        message: module.error,
        onRetry: module.refresh,
      );
    } else {
      body = const LoadingSkeleton(
        rows: 4,
        label: 'Loading athlete information',
      );
    }

    return ScreenScaffold(
      title: 'Personal information',
      onRefresh: module.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AthleteIdentityHero(),
          const SizedBox(height: SportikaSpacing.lg),
          body,
        ],
      ),
    );
  }
}

// ============================================================
// ATHLETE IDENTITY HERO
// ============================================================

class _AthleteIdentityHero extends StatelessWidget {
  const _AthleteIdentityHero();

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        gradient: SportikaGradients.sportCoin(theme.live),
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined, color: theme.live),
              const SizedBox(width: SportikaSpacing.sm),
              Text(
                'SPORTIKA / ATHLETE IDENTITY',
                style: SportikaType.micro.copyWith(color: theme.live),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.lg),
          const Text('MAKE IT\nYOURS.', style: SportikaType.title),
          const SizedBox(height: SportikaSpacing.sm),
          Text(
            'Build your identity on and off the field.',
            style: SportikaType.body.copyWith(color: theme.textBody),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PERSONAL INFORMATION FORM
// ============================================================

class _PersonalInformationForm extends StatefulWidget {
  const _PersonalInformationForm({required this.personal, required this.busy});

  final ProfilePersonalInformation personal;
  final bool busy;

  @override
  State<_PersonalInformationForm> createState() =>
      _PersonalInformationFormState();
}

class _PersonalInformationFormState extends State<_PersonalInformationForm> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _birth;
  late final TextEditingController _city;
  late final TextEditingController _bio;

  late ProfileGender? _gender;
  late PlayStyle _playStyle;

  String? _errorField;
  String? _errorMessage;

  bool _saving = false;
  bool _personalSaved = false;
  bool _hasExternalUpdate = false;

  late String _savedSignature;

  @override
  void initState() {
    super.initState();

    _name = TextEditingController();
    _username = TextEditingController();
    _birth = TextEditingController();
    _city = TextEditingController();
    _bio = TextEditingController();

    _loadPersonal(widget.personal);

    for (final controller in [_name, _username, _birth, _city, _bio]) {
      controller.addListener(_onFieldChanged);
    }
  }

  void _loadPersonal(ProfilePersonalInformation personal) {
    _name.text = personal.displayName;
    _username.text = personal.username;
    _birth.text = profileDateLabel(personal.dateOfBirth);
    _city.text = personal.city;
    _bio.text = personal.bio;
    _gender = personal.gender;
    _playStyle = personal.playStyle;

    _savedSignature = _signatureForPersonal(personal);
    _personalSaved = false;
    _hasExternalUpdate = false;
  }

  String _signatureForPersonal(ProfilePersonalInformation personal) {
    return [
      personal.displayName.trim(),
      normalizeProfileHandle(personal.username),
      profileDateLabel(personal.dateOfBirth),
      personal.city.trim(),
      personal.bio.trim(),
      personal.gender?.name ?? '',
      personal.playStyle.name,
    ].join('\u001f');
  }

  String get _draftSignature {
    return [
      _name.text.trim(),
      normalizeProfileHandle(_username.text),
      _birth.text.trim(),
      _city.text.trim(),
      _bio.text.trim(),
      _gender?.name ?? '',
      _playStyle.name,
    ].join('\u001f');
  }

  bool get _dirty => _draftSignature != _savedSignature;

  bool get _enabled => !widget.busy && !_saving;

  @override
  void didUpdateWidget(covariant _PersonalInformationForm oldWidget) {
    super.didUpdateWidget(oldWidget);

    final incoming = _signatureForPersonal(widget.personal);

    if (incoming == _savedSignature) return;

    // A controller update must not erase the user's unsaved draft.
    if (!_dirty && !_saving) {
      _loadPersonal(widget.personal);
    } else {
      _hasExternalUpdate = true;
    }
  }

  void _onFieldChanged() {
    if (!mounted) return;

    setState(() {
      _errorField = null;
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _birth.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_enabled || !_dirty) return;

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
      _saving = true;
      _errorField = null;
      _errorMessage = null;
      _personalSaved = false;
    });

    final module = context.read<ProfileModuleController>();
    final wantedHandle = normalizeProfileHandle(_username.text);

    final savedHandle = normalizeProfileHandle(widget.personal.username);

    try {
      await module.savePersonalInformation(
        displayName: _name.text.trim(),
        city: _city.text.trim(),
        bio: _bio.text.trim(),
        dateOfBirth: birth!,
        gender: _gender,
        playStyle: _playStyle,
      );

      if (!mounted) return;

      _personalSaved = true;

      if (wantedHandle != savedHandle) {
        await module.changeUsername(wantedHandle);
      }

      if (!mounted) return;

      setState(() {
        _savedSignature = _draftSignature;
        _personalSaved = false;
        _hasExternalUpdate = false;
      });

      showSnack(context, 'Personal information saved');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;

      final usernameProblem =
          error.code == '23505' || error.code == 'invalid_username';

      setState(() {
        _errorField = usernameProblem ? 'handle' : null;
        _errorMessage = _personalSaved
            ? 'Your profile details were saved, but the handle '
                  'could not be updated. ${error.message}'
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _personalSaved
            ? 'Profile details were saved, but the remaining '
                  'update could not be completed.'
            : 'Unable to save your profile. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ----------------------------------------------------
        // LIVE IDENTITY PREVIEW
        // ----------------------------------------------------

        _AthleteIdentityPreview(
          name: _name.text,
          username: _username.text,
          city: _city.text,
        ),

        const SizedBox(height: SportikaSpacing.lg),

        // ----------------------------------------------------
        // PUBLIC IDENTITY
        // ----------------------------------------------------
        const _ProfileSectionHeading(
          number: '01',
          title: 'Public Identity',
          subtitle: 'How other athletes recognize you.',
          icon: Icons.badge_outlined,
        ),

        const SizedBox(height: SportikaSpacing.md),

        SurfaceCard(
          child: ProfileIdentityFields(
            name: _name,
            username: _username,
            birthDate: _birth,
            city: _city,
            bio: _bio,
            gender: _gender,
            onGenderChanged: (value) {
              setState(() {
                _gender = value;
                _errorField = null;
                _errorMessage = null;
              });
            },
            onChanged: _onFieldChanged,
            errorField: _errorField,
            errorMessage: _errorMessage,
            enabled: _enabled,
          ),
        ),

        const SizedBox(height: SportikaSpacing.sm),

        const HelperText(
          'Your display name, handle, city and bio help '
          'other athletes recognize you. Date of birth and '
          'gender are also edited here using the existing '
          'profile setup fields.',
        ),

        const SizedBox(height: SportikaSpacing.lg),

        // ----------------------------------------------------
        // PLAY STYLE
        // ----------------------------------------------------
        const _ProfileSectionHeading(
          number: '02',
          title: 'Your Play Style',
          subtitle: 'Choose how you approach sport.',
          icon: Icons.sports_outlined,
        ),

        const SizedBox(height: SportikaSpacing.md),

        for (final option in PlayStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
            child: _PlayStyleCard(
              option: option,
              selected: _playStyle == option,
              enabled: _enabled,
              onTap: () {
                setState(() => _playStyle = option);
              },
            ),
          ),

        const SizedBox(height: SportikaSpacing.lg),

        // ----------------------------------------------------
        // CONTACT & SECURITY
        // ----------------------------------------------------
        const _ProfileSectionHeading(
          number: '03',
          title: 'Contact & Security',
          subtitle: 'Secure access and account recovery.',
          icon: Icons.shield_outlined,
        ),

        const SizedBox(height: SportikaSpacing.md),

        const _ProfileModuleCard(
          title: 'Email Address',
          subtitle: 'Verified email and account recovery',
          icon: Icons.alternate_email_rounded,
          fields: ['Email address', 'Verification status'],
          requiresIntegration: true,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        const _ProfileModuleCard(
          title: 'Phone Number',
          subtitle: 'Phone verification and secure contact',
          icon: Icons.phone_android_outlined,
          fields: ['Country code', 'Phone number', 'OTP verification'],
          requiresIntegration: true,
        ),

        const SizedBox(height: SportikaSpacing.lg),

        // ----------------------------------------------------
        // IDENTITY VERIFICATION
        // ----------------------------------------------------
        const _ProfileSectionHeading(
          number: '04',
          title: 'Identity Verification',
          subtitle: 'Official athlete identity checks.',
          icon: Icons.verified_user_outlined,
        ),

        const SizedBox(height: SportikaSpacing.md),

        const _ProfileModuleCard(
          title: 'Verify Your Identity',
          subtitle:
              'CNIC, B-Form or passport verification, '
              'depending on eligibility.',
          icon: Icons.badge_outlined,
          fields: [
            'Full legal name',
            'Document type',
            'Document verification',
            'Verification status',
          ],
          requiresIntegration: true,
          sensitive: true,
        ),

        const SizedBox(height: SportikaSpacing.lg),

        // ----------------------------------------------------
        // ATHLETE INFORMATION
        // ----------------------------------------------------
        const _ProfileSectionHeading(
          number: '05',
          title: 'Athlete Information',
          subtitle: 'Your physical and sporting attributes.',
          icon: Icons.fitness_center_outlined,
        ),

        const SizedBox(height: SportikaSpacing.md),

        // Athlete attributes are stored in `profiles_private` and written
        // through the update_profile_athlete_details RPC, so this section is a
        // real, saveable form rather than an integration placeholder.
        const _AthleteDetailsSection(),

        const SizedBox(height: SportikaSpacing.sm),

        const _ProfileModuleCard(
          title: 'Team Preferences',
          subtitle:
              'Preferred jersey number and sport-specific '
              'positions belong to the relevant squad or sport.',
          icon: Icons.groups_2_outlined,
          fields: ['Preferred jersey number', 'Sport-specific position'],
          requiresIntegration: true,
        ),

        const SizedBox(height: SportikaSpacing.lg),

        // ----------------------------------------------------
        // EMERGENCY & SAFETY
        // ----------------------------------------------------
        const _ProfileSectionHeading(
          number: '06',
          title: 'Emergency & Safety',
          subtitle: 'Optional information for player safety.',
          icon: Icons.health_and_safety_outlined,
        ),

        const SizedBox(height: SportikaSpacing.md),

        const _ProfileModuleCard(
          title: 'Emergency Contact',
          subtitle: 'A trusted contact for genuine emergencies.',
          icon: Icons.contact_emergency_outlined,
          fields: ['Contact name', 'Relationship', 'Emergency phone number'],
          requiresIntegration: true,
          sensitive: true,
        ),

        const SizedBox(height: SportikaSpacing.sm),

        const _ProfileModuleCard(
          title: 'Medical Information',
          subtitle:
              'Optional emergency-relevant information, '
              'subject to explicit consent.',
          icon: Icons.medical_information_outlined,
          fields: ['Emergency medical notes', 'Consent and access controls'],
          requiresIntegration: true,
          sensitive: true,
        ),

        const SizedBox(height: SportikaSpacing.lg),

        // ----------------------------------------------------
        // PRIVACY
        // ----------------------------------------------------
        const _ProfileSectionHeading(
          number: '07',
          title: 'Privacy & Visibility',
          subtitle: 'Control your athlete profile exposure.',
          icon: Icons.lock_outline_rounded,
        ),

        const SizedBox(height: SportikaSpacing.md),

        const _ProfileModuleCard(
          title: 'Profile Visibility',
          subtitle:
              'Configure who can discover and view your '
              'profile information.',
          icon: Icons.visibility_outlined,
          fields: [
            'Profile discoverability',
            'City visibility',
            'Age visibility',
            'Contact information visibility',
          ],
          requiresIntegration: true,
          sensitive: true,
        ),

        const SizedBox(height: SportikaSpacing.lg),

        // ----------------------------------------------------
        // SAVE EXISTING PROFILE FIELDS
        // ----------------------------------------------------
        if (_hasExternalUpdate) ...[
          const InlineBanner(
            text:
                'Your profile was updated elsewhere. '
                'Your current edits have been preserved. '
                'Review them before saving.',
            tone: SportikaColors.gold,
          ),
          const SizedBox(height: SportikaSpacing.md),
        ],

        if (_errorField == null && _errorMessage != null) ...[
          InlineBanner(text: _errorMessage!, tone: SportikaColors.danger),
          const SizedBox(height: SportikaSpacing.md),
        ],

        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _dirty
                        ? Icons.edit_note_rounded
                        : Icons.check_circle_outline_rounded,
                    color: _dirty ? theme.live : theme.textMuted,
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: Text(
                      _dirty
                          ? 'Unsaved profile changes'
                          : 'Profile details up to date',
                      style: SportikaType.bodyStrong,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.md),
              PrimaryButton(
                label: 'Save Profile Changes',
                icon: Icons.check_rounded,
                busy: widget.busy || _saving,
                onPressed: _enabled && _dirty ? _save : null,
              ),
            ],
          ),
        ),

        const SizedBox(height: SportikaSpacing.sm),

        const HelperText(
          'This save action updates your existing profile '
          'information and play style. Verification, contact, '
          'emergency, medical and privacy modules require '
          'their dedicated secure integrations.',
        ),
      ],
    );
  }
}

// ============================================================
// LIVE ATHLETE IDENTITY PREVIEW
// ============================================================

class _AthleteIdentityPreview extends StatelessWidget {
  const _AthleteIdentityPreview({
    required this.name,
    required this.username,
    required this.city,
  });

  final String name;
  final String username;
  final String city;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final displayName = name.trim().isEmpty
        ? 'Your Athlete Identity'
        : name.trim();

    final handle = username.trim().isEmpty
        ? '@yourhandle'
        : '@${normalizeProfileHandle(username)}';

    return SurfaceCard(
      child: Row(
        children: [
          const BrandedDefaultAvatar(size: SportikaSpacing.xxl * 2),
          const SizedBox(width: SportikaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: SportikaType.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  handle,
                  style: SportikaType.caption.copyWith(color: theme.live),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (city.trim().isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: SportikaIconSize.sm,
                        color: theme.textMuted,
                      ),
                      const SizedBox(width: SportikaSpacing.xxs),
                      Expanded(
                        child: Text(
                          city.trim(),
                          style: SportikaType.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SECTION HEADING
// ============================================================

class _ProfileSectionHeading extends StatelessWidget {
  const _ProfileSectionHeading({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String number;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(SportikaSpacing.sm),
          decoration: BoxDecoration(
            color: theme.surfaceSunken,
            borderRadius: BorderRadius.circular(SportikaRadius.control),
          ),
          child: Icon(icon, color: theme.live, size: SportikaIconSize.md),
        ),
        const SizedBox(width: SportikaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$number / $title', style: SportikaType.titleMedium),
              const SizedBox(height: SportikaSpacing.xxs),
              Text(
                subtitle,
                style: SportikaType.caption.copyWith(color: theme.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PLAY STYLE SELECTION
// ============================================================

class _PlayStyleCard extends StatelessWidget {
  const _PlayStyleCard({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PlayStyle option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? theme.surfaceAlt : theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(SportikaRadius.control),
          child: Container(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SportikaRadius.control),
              border: Border.all(
                color: selected ? theme.live : theme.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? theme.live : theme.textMuted,
                ),
                const SizedBox(width: SportikaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label, style: SportikaType.bodyStrong),
                      const SizedBox(height: SportikaSpacing.xxs),
                      Text(option.blurb, style: SportikaType.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SECURE MODULE INTEGRATION CARD
// ============================================================

class _ProfileModuleCard extends StatelessWidget {
  const _ProfileModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fields,
    this.requiresIntegration = false,
    this.sensitive = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> fields;
  final bool requiresIntegration;
  final bool sensitive;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.live, size: SportikaIconSize.lg),
              const SizedBox(width: SportikaSpacing.md),
              Expanded(child: Text(title, style: SportikaType.bodyStrong)),
              if (sensitive)
                Icon(
                  Icons.lock_outline_rounded,
                  size: SportikaIconSize.sm,
                  color: theme.textMuted,
                ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          Text(subtitle, style: SportikaType.caption),
          const SizedBox(height: SportikaSpacing.md),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    Icons.circle_outlined,
                    size: SportikaIconSize.sm,
                    color: theme.textMuted,
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(child: Text(field, style: SportikaType.caption)),
                ],
              ),
            ),
          if (requiresIntegration) ...[
            const SizedBox(height: SportikaSpacing.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(SportikaSpacing.sm),
              decoration: BoxDecoration(
                color: theme.surfaceSunken,
                borderRadius: BorderRadius.circular(SportikaRadius.control),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.construction_outlined,
                    size: SportikaIconSize.sm,
                    color: theme.textMuted,
                  ),
                  const SizedBox(width: SportikaSpacing.sm),
                  Expanded(
                    child: Text(
                      'Secure integration required',
                      style: SportikaType.caption.copyWith(
                        color: theme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// ATHLETE INFORMATION (DATABASE BACKED)
// ============================================================

/// Section 05 of the personal information screen.
///
/// These physical attributes are stored in `profiles_private` and written
/// through the `update_profile_athlete_details` RPC, so the section is a real
/// editable form rather than an integration placeholder. It watches
/// [ProfileModuleController] directly and keeps its own busy flag, mirroring the
/// outer form's "re-read after a successful write" contract: the controller
/// already performs the silent reload, so this widget only has to repaint from
/// the refreshed snapshot.
class _AthleteDetailsSection extends StatefulWidget {
  const _AthleteDetailsSection();

  @override
  State<_AthleteDetailsSection> createState() => _AthleteDetailsSectionState();
}

class _AthleteDetailsSectionState extends State<_AthleteDetailsSection> {
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _jersey = TextEditingController();

  ProfileSide? _hand;
  ProfileSide? _foot;

  String _savedSignature = '';
  bool _hydrated = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _jersey.dispose();
    super.dispose();
  }

  static String _signatureFor(ProfileAthleteDetails a) => [
    a.heightCm?.toString() ?? '',
    a.weightKg?.toString() ?? '',
    a.dominantHand?.key ?? '',
    a.dominantFoot?.key ?? '',
    a.preferredJersey?.toString() ?? '',
  ].join('\u001f');

  String get _draftSignature => [
    _height.text.trim(),
    _weight.text.trim(),
    _hand?.key ?? '',
    _foot?.key ?? '',
    _jersey.text.trim(),
  ].join('\u001f');

  bool get _dirty => _hydrated && _draftSignature != _savedSignature;

  void _apply(ProfileAthleteDetails a) {
    _height.text = a.heightCm?.toString() ?? '';
    _weight.text = a.weightKg?.toString() ?? '';
    _jersey.text = a.preferredJersey?.toString() ?? '';
    _hand = a.dominantHand;
    _foot = a.dominantFoot;
  }

  /// Re-seeds the controllers from the stored snapshot whenever the stored
  /// values change and the member has no unsaved edits, so an update that came
  /// from the reload (or another screen) never overwrites a draft in progress.
  void _syncFrom(ProfileAthleteDetails a) {
    final incoming = _signatureFor(a);
    if (!_hydrated) {
      _apply(a);
      _savedSignature = incoming;
      _hydrated = true;
      return;
    }
    if (incoming != _savedSignature && !_dirty) {
      _apply(a);
      _savedSignature = incoming;
    }
  }

  void _onChanged() {
    if (_error == null) return;
    setState(() => _error = null);
  }

  Future<void> _save() async {
    if (_saving) return;

    FocusScope.of(context).unfocus();

    final height = _parse(_height.text, field: 'height');
    final weight = _weight.text.trim().isEmpty
        ? null
        : double.tryParse(_weight.text.trim());
    final jersey = _parse(_jersey.text, field: 'jersey');

    if (_error != null) return;
    if (height != null && (height < 50 || height > 280)) {
      setState(() => _error = 'Height should be between 50 and 280 cm.');
      return;
    }
    if (weight != null && (weight < 20 || weight > 400)) {
      setState(() => _error = 'Weight should be between 20 and 400 kg.');
      return;
    }
    if (jersey != null && (jersey < 1 || jersey > 999)) {
      setState(() => _error = 'Jersey number should be between 1 and 999.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final module = context.read<ProfileModuleController>();
    try {
      await module.saveAthleteDetails(
        heightCm: height,
        weightKg: weight,
        dominantHand: _hand,
        dominantFoot: _foot,
        preferredJersey: jersey,
      );

      if (!mounted) return;

      // The controller has already reloaded the snapshot; adopt the stored
      // values so the section returns to a clean state.
      final stored = module.snapshot?.athlete ?? ProfileAthleteDetails.empty;
      setState(() {
        _apply(stored);
        _savedSignature = _signatureFor(stored);
        _hydrated = true;
      });

      showSnack(context, 'Athlete details saved');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Unable to save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int? _parse(String raw, {required String field}) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null) {
      setState(() => _error = 'Enter a whole number for $field.');
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final module = context.watch<ProfileModuleController>();
    final athlete = module.snapshot?.athlete ?? ProfileAthleteDetails.empty;
    _syncFrom(athlete);

    final busy = module.busy || _saving;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: context.sportika.live),
              const SizedBox(width: SportikaSpacing.sm),
              const Text('Athlete Attributes', style: SportikaType.bodyStrong),
            ],
          ),
          const SizedBox(height: SportikaSpacing.xs),
          const HelperText(
            'Optional details for your athlete profile. Only you '
            'can see them.',
          ),

          const SizedBox(height: SportikaSpacing.md),

          Row(
            children: [
              Expanded(
                child: _AthleteField(
                  controller: _height,
                  label: 'Height (cm)',
                  hint: '180',
                  enabled: !busy,
                  onChanged: _onChanged,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: _AthleteField(
                  controller: _weight,
                  label: 'Weight (kg)',
                  hint: '72.5',
                  enabled: !busy,
                  onChanged: _onChanged,
                ),
              ),
              const SizedBox(width: SportikaSpacing.sm),
              Expanded(
                child: _AthleteField(
                  controller: _jersey,
                  label: 'Jersey',
                  hint: '10',
                  enabled: !busy,
                  onChanged: _onChanged,
                ),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          _SideChoiceRow(
            label: 'Dominant hand',
            selected: _hand,
            enabled: !busy,
            onChanged: (value) => setState(() {
              _hand = value;
              _error = null;
            }),
          ),

          const SizedBox(height: SportikaSpacing.sm),

          _SideChoiceRow(
            label: 'Dominant foot',
            selected: _foot,
            enabled: !busy,
            onChanged: (value) => setState(() {
              _foot = value;
              _error = null;
            }),
          ),

          if (_error != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: _error!, tone: SportikaColors.danger),
          ],

          const SizedBox(height: SportikaSpacing.md),

          PrimaryButton(
            label: 'Save Athlete Details',
            icon: Icons.check_rounded,
            busy: busy,
            onPressed: _enabled(busy) ? _save : null,
          ),
        ],
      ),
    );
  }

  bool _enabled(bool busy) => !busy && _dirty;
}

class _AthleteField extends StatelessWidget {
  const _AthleteField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        LengthLimitingTextInputFormatter(6),
      ],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}

class _SideChoiceRow extends StatelessWidget {
  const _SideChoiceRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final ProfileSide? selected;
  final bool enabled;
  final ValueChanged<ProfileSide?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SportikaType.micro),
        const SizedBox(height: SportikaSpacing.xs),
        Wrap(
          spacing: SportikaSpacing.sm,
          runSpacing: SportikaSpacing.xs,
          children: [
            _SideChip(
              label: 'Not set',
              selected: selected == null,
              tone: theme,
              onTap: enabled ? () => onChanged(null) : null,
            ),
            for (final side in ProfileSide.values)
              _SideChip(
                label: side.label,
                selected: selected == side,
                tone: theme,
                onTap: enabled ? () => onChanged(side) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _SideChip extends StatelessWidget {
  const _SideChip({
    required this.label,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final SportikaTheme tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tone.surfaceElevated : tone.surfaceSunken,
      borderRadius: BorderRadius.circular(SportikaRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SportikaSpacing.md,
            vertical: SportikaSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SportikaRadius.control),
            border: Border.all(color: selected ? tone.live : tone.borderSubtle),
          ),
          child: Text(
            label,
            style: SportikaType.caption.copyWith(
              color: selected ? tone.textBody : tone.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
