import 'dart:convert';

import 'package:sportika/shared/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/core/state/profile_photo_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/features/profile/widgets/profile_identity_fields.dart';
import 'package:sportika/features/profile/widgets/profile_sport_preferences.dart';
import 'package:sportika/features/profile_photo/profile_photo_flow.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_setup.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name,
      _handle,
      _birthDate,
      _city,
      _bio,
      _email;
  ProfileGender? _gender;
  late Set<Sport> _sports;
  late Map<String, PlayingLevel> _levels;
  late Map<String, String> _positions;
  late PlayStyle _playStyle;
  bool _skipPreferences = false, _saving = false;
  String? _errorField, _error;
  late String _initial;
  late String _lastText;
  String get _textSnapshot => jsonEncode([
    _name.text,
    _handle.text,
    _birthDate.text,
    _city.text,
    _bio.text,
  ]);
  void _onTextChanged() {
    final next = _textSnapshot;
    if (_lastText == next) return;
    _lastText = next;
    _changed();
  }

  bool _allowExit = false, _confirmingExit = false;

  String get _snapshot => jsonEncode([
    _name.text,
    _handle.text,
    _birthDate.text,
    _city.text,
    _bio.text,
    _gender?.name,
    _skipPreferences,
    _playStyle.name,
    for (final sport in Sport.values)
      [
        _sports.contains(sport),
        _levels[sport.key]?.name,
        _positions[sport.key],
      ],
  ]);
  bool get _dirty => _snapshot != _initial;

  @override
  void initState() {
    super.initState();
    final me = context.read<ProfileController>().currentAccount!;
    _name = TextEditingController(text: me.displayName);
    _handle = TextEditingController(text: me.username);
    _birthDate = TextEditingController(text: profileDateLabel(me.dateOfBirth));
    _city = TextEditingController(text: me.city);
    _bio = TextEditingController(text: me.bio);
    _email = TextEditingController(text: me.email);
    _gender = me.gender;
    _sports = Set.of(me.sports);
    _levels = Map.of(me.levels);
    _positions = Map.of(me.playingPositions);
    _skipPreferences = me.playingPreferencesSkipped;
    _playStyle = me.playStyle;
    _initial = _snapshot;
    _lastText = _textSnapshot;
    for (final field in [_name, _handle, _birthDate, _city, _bio]) {
      field.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _handle,
      _birthDate,
      _city,
      _bio,
      _email,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() {
      _error = null;
      _errorField = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<ProfileController>().currentAccount;
    final photos = context.watch<ProfilePhotoController>();
    if (me == null) return const SizedBox.shrink();
    final page = MediaQuery.sizeOf(context).width > 688
        ? (MediaQuery.sizeOf(context).width - 640) / 2
        : 20.0;
    final canSave = !_saving && !photos.busy;
    return PopScope(
      canPop: !_saving && !photos.busy && (!_dirty || _allowExit),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving && !photos.busy) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Edit Profile',
            style: TextStyle(
              fontFamily: SportikaType.displayFamily,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          leading: BackButton(
            onPressed: _saving || photos.busy
                ? null
                : () => Navigator.maybePop(context),
          ),
          actions: [
            TextButton(
              onPressed: canSave ? _save : null,
              child: Text(
                _saving ? 'Saving…' : 'Save',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: SportikaColors.mint,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: SportikaColors.page,
              border: Border(
                top: BorderSide(color: SportikaColors.borderSubtle),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(page, 12, page, 12),
                child: FilledButton(
                  onPressed: canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: SportikaColors.mint,
                    foregroundColor: SportikaColors.deepest,
                    minimumSize: const Size(double.infinity, 54),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _saving
                        ? const SizedBox.square(
                            key: ValueKey('saving'),
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: SportikaColors.deepest,
                            ),
                          )
                        : const Text(
                            'Save changes',
                            key: ValueKey('save'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: SportikaColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: SportikaColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: SportikaColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(
                  color: SportikaColors.mint,
                  width: 1.4,
                ),
              ),
              labelStyle: const TextStyle(
                fontSize: 13,
                color: SportikaColors.textMuted,
              ),
            ),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: SportikaType.bodyFamily),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(page, 20, page, 28),
              children: [
                Center(
                  child: Semantics(
                    button: true,
                    label: 'Manage profile picture',
                    child: GestureDetector(
                      onTap: canSave ? () => _editPhoto(context) : null,
                      child: ProfileAvatar(
                        size: 104,
                        initials: me.initials,
                        avatarId: me.avatar,
                        photoPath: me.photoPath,
                        photoUrl: me.photoUrl,
                        busy: photos.busy || _saving,
                        onEdit: canSave ? () => _editPhoto(context) : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    _name.text.trim().isEmpty
                        ? me.displayName
                        : _name.text.trim(),
                    textAlign: TextAlign.center,
                    style: SportikaType.title,
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    '@${normalizeProfileHandle(_handle.text)}',
                    style: SportikaType.caption,
                  ),
                ),
                const SizedBox(height: 10),
                const ProfilePhotoStatus(),
                const SizedBox(height: 22),
                _section(
                  'Personal information',
                  'The details that help your community know you.',
                ),
                const SizedBox(height: 18),
                if (_error != null &&
                    (_errorField == null || _errorField == 'sports'))
                  Semantics(
                    liveRegion: true,
                    child: AuthNotice(_error!, tone: SportikaColors.danger),
                  ),
                ProfileIdentityFields(
                  polished: true,
                  cityOptions:
                      (context
                          .read<SessionController>()
                          .accounts
                          .map((a) => a.city.trim())
                          .where((c) => c.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort()),
                  personalFooter: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AuthField(
                        label: 'Email',
                        controller: _email,
                        filledStyle: true,
                        enabled: false,
                        labelAction: TextButton(
                          onPressed: _saving
                              ? null
                              : () => pushRoute(context, AppRoute.changeEmail),
                          child: const Text(
                            'Change',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Email changes are confirmed through Account and security.',
                        style: SportikaType.caption,
                      ),
                    ],
                  ),
                  name: _name,
                  username: _handle,
                  birthDate: _birthDate,
                  city: _city,
                  bio: _bio,
                  gender: _gender,
                  enabled: !_saving,
                  errorField: _errorField,
                  errorMessage: _error,
                  onChanged: _changed,
                  onGenderChanged: (value) => setState(() => _gender = value),
                ),
                const SizedBox(height: 18),
                _section(
                  'Your sports',
                  'Choose the sports you play or follow.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sport in Sport.values)
                      AuthChoicePill(
                        label: sport.label,
                        selected: _sports.contains(sport),
                        dense: true,
                        tone: SportikaColors.mint,
                        onTap: () {
                          if (_saving) return;
                          setState(() {
                            if (!_sports.add(sport)) {
                              _sports.remove(sport);
                              _levels.remove(sport.key);
                              _positions.remove(sport.key);
                            }
                            _error = null;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 26),
                _section(
                  'Playing preferences',
                  'Your level, position and style of play.',
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set playing preferences later'),
                  subtitle: const Text(
                    'Optional if you are here to organize. You can still use every Sportika feature.',
                  ),
                  value: _skipPreferences,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _skipPreferences = value),
                ),
                if (!_skipPreferences) ...[
                  for (final sport in Sport.values.where(_sports.contains))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ProfileSportPreferences(
                        refined: true,
                        sport: sport,
                        level: _levels[sport.key] ?? defaultLevelFor(sport),
                        position: _positions[sport.key],
                        onLevelChanged: (value) {
                          if (!_saving) {
                            setState(() => _levels[sport.key] = value);
                          }
                        },
                        onPositionChanged: (value) {
                          if (!_saving) {
                            setState(() {
                              if (value == null) {
                                _positions.remove(sport.key);
                              } else {
                                _positions[sport.key] = value;
                              }
                            });
                          }
                        },
                      ),
                    ),
                  DropdownButtonFormField<PlayStyle>(
                    initialValue: _playStyle,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Play style'),
                    items: [
                      for (final style in PlayStyle.values)
                        DropdownMenuItem(
                          value: style,
                          child: Text(style.label),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _playStyle = value!),
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  'Your profile details save together. Photo updates save when you confirm them.',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: SportikaType.title.copyWith(fontSize: 22)),
      const SizedBox(height: 6),
      Text(subtitle, style: SportikaType.caption),
    ],
  );

  Future<void> _confirmLeave() async {
    if (_confirmingExit) return;
    _confirmingExit = true;
    FocusScope.of(context).unfocus();
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard your changes?', style: SportikaType.title),
        content: const Text(
          'Your profile edits haven’t been saved. Photo updates already confirmed will stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Discard changes',
              style: TextStyle(color: SportikaColors.danger),
            ),
          ),
        ],
      ),
    );
    _confirmingExit = false;
    if (discard != true || !mounted) return;
    setState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_saving || context.read<ProfilePhotoController>().busy) return;
    FocusScope.of(context).unfocus();
    final birth = parseProfileDate(_birthDate.text);
    final error = validateProfileIdentity(
      name: _name.text,
      handle: _handle.text,
      city: _city.text,
      bio: _bio.text,
      dateOfBirth: birth,
    );
    final session = context.read<SessionController>();
    final me = session.currentAccount!;
    final username = normalizeProfileHandle(_handle.text);
    String? field = error?.field, message = error?.message;
    if (message == null &&
        session.accounts.any(
          (a) => a.id != me.id && a.username.toLowerCase() == username,
        )) {
      field = 'handle';
      message = 'That username is already used on this device.';
    }
    if (message == null && _sports.isEmpty) {
      field = 'sports';
      message = 'Choose at least one preferred sport.';
    }
    if (message != null) {
      setState(() {
        _errorField = field;
        _error = message;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await session.completeProfileSetup(
        displayName: _name.text,
        handle: username,
        bio: _bio.text,
        city: _city.text,
        dateOfBirth: birth,
        gender: _gender,
        sports: Set.of(_sports),
        levels: _skipPreferences
            ? {}
            : {
                for (final sport in _sports)
                  sport.key: _levels[sport.key] ?? defaultLevelFor(sport),
              },
        playingPositions: _skipPreferences ? {} : Map.of(_positions),
        playingPreferencesSkipped: _skipPreferences,
        playStyle: _playStyle,
        avatar: me.avatar,
      );
      if (!mounted) return;
      setState(() {
        _allowExit = true;
        _saving = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      showSnack(context, 'Profile updated');
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Your profile could not be saved. Your entered details are still here. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editPhoto(BuildContext context) async {
    final outcome = await runProfilePhotoFlow(context);
    if (outcome == null || !context.mounted) return;
    showSnack(context, outcome.message, error: outcome.isError);
  }
}
