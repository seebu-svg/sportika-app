import 'package:flutter/material.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/shared/models/profile_setup.dart';

/// The same editable identity fields in setup and Me → Edit Profile.
class ProfileIdentityFields extends StatelessWidget {
  const ProfileIdentityFields({
    super.key,
    required this.name,
    required this.username,
    required this.birthDate,
    required this.city,
    required this.bio,
    required this.gender,
    required this.onGenderChanged,
    required this.onChanged,
    this.errorField,
    this.errorMessage,
    this.enabled = true,
    this.polished = false,
    this.personalFooter,
    this.cityOptions = const [],
  });
  final TextEditingController name, username, birthDate, city, bio;
  final ProfileGender? gender;
  final ValueChanged<ProfileGender?> onGenderChanged;
  final VoidCallback onChanged;
  final String? errorField, errorMessage;
  final bool enabled;
  final bool polished;
  final Widget? personalFooter;
  final List<String> cityOptions;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AuthField(
        filledStyle: polished,
        label: 'Full name',
        controller: name,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        enabled: enabled,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
        errorText: errorField == 'name' ? errorMessage : null,
        onChanged: (_) => onChanged(),
      ),
      const SizedBox(height: 18),
      AuthField(
        filledStyle: polished,
        label: 'Username',
        controller: username,
        maxLength: 30,
        hint: 'yourhandle',
        enabled: enabled,
        textInputAction: TextInputAction.next,
        errorText: errorField == 'handle' ? errorMessage : null,
        onChanged: (_) => onChanged(),
      ),
      const SizedBox(height: 18),
      AuthField(
        filledStyle: polished,
        label: 'Date of birth',
        trailing: polished
            ? IconButton(
                tooltip: 'Choose date of birth',
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                onPressed: enabled ? () => _pickDate(context) : null,
              )
            : null,
        controller: birthDate,
        hint: 'Choose day, month and year',
        readOnly: true,
        onTap: enabled ? () => _pickDate(context) : null,
        textInputAction: TextInputAction.next,
        enabled: enabled,
        maxLength: 10,
        errorText: errorField == 'birthDate' ? errorMessage : null,
        labelAction: polished
            ? null
            : IconButton(
                tooltip: 'Choose date of birth',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: enabled ? () => _pickDate(context) : null,
              ),
        onChanged: (_) => onChanged(),
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<ProfileGender>(
        initialValue: gender,
        style: polished
            ? const TextStyle(fontSize: 15.5, color: SportikaColors.text)
            : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Gender (optional)'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Not specified')),
          for (final option in ProfileGender.values)
            DropdownMenuItem(value: option, child: Text(option.label)),
        ],
        onChanged: enabled ? onGenderChanged : null,
      ),
      const SizedBox(height: 18),
      AuthField(
        filledStyle: polished,
        label: 'City',
        trailing: polished && cityOptions.isNotEmpty
            ? TextButton(
                onPressed: enabled ? () => _pickCity(context) : null,
                child: const Text('Browse', style: TextStyle(fontSize: 12)),
              )
            : null,
        controller: city,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        enabled: enabled,
        textInputAction: TextInputAction.next,
        errorText: errorField == 'city' ? errorMessage : null,
        onChanged: (_) => onChanged(),
      ),
      const SizedBox(height: 18),
      if (personalFooter != null) ...[
        personalFooter!,
        const SizedBox(height: 18),
      ],
      if (polished) ...[
        const Padding(
          padding: EdgeInsets.only(top: 10, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('About me', style: SportikaType.title),
          ),
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'A little about the athlete behind the profile.',
            style: SportikaType.caption,
          ),
        ),
        const SizedBox(height: 18),
      ],
      AuthField(
        filledStyle: polished,
        label: 'Short bio',
        controller: bio,
        maxLines: 3,
        maxLength: 120,
        hint: 'Optional: tell the community a little about you.',
        enabled: enabled,
        textCapitalization: TextCapitalization.sentences,
        errorText: errorField == 'bio' ? errorMessage : null,
        onChanged: (_) => onChanged(),
      ),
    ],
  );

  Future<void> _pickCity(BuildContext context) async {
    FocusScope.of(context).unfocus();
    var query = '';
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: SportikaColors.page,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Choose your city', style: SportikaType.title),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose a city in your community, or enter your own in the form.',
                      style: SportikaType.caption,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) => update(() => query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search cities',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final option in cityOptions.where(
                            (value) => value.toLowerCase().contains(
                              query.toLowerCase(),
                            ),
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(option),
                              trailing: city.text.trim() == option
                                  ? const Icon(
                                      Icons.check,
                                      color: SportikaColors.mint,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, option),
                            ),
                          if (!cityOptions.any(
                            (value) => value.toLowerCase().contains(
                              query.toLowerCase(),
                            ),
                          ))
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No matching cities. You can enter yours directly in the form.',
                                style: SportikaType.caption,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    city.text = selected;
    onChanged();
  }

  Future<void> _pickDate(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final today = DateUtils.dateOnly(DateTime.now());
    final current = parseProfileDate(birthDate.text);
    final selected = await showDatePicker(
      context: context,
      initialDate:
          current != null && current.year >= 1900 && !current.isAfter(today)
          ? current
          : DateTime(today.year - 18, today.month, today.day),
      builder: polished
          ? (context, child) => Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: SportikaColors.mint,
                  onPrimary: SportikaColors.deepest,
                  surface: SportikaColors.surfaceElevated,
                ),
              ),
              child: child!,
            )
          : null,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: polished ? 'Date of birth' : 'DATE OF BIRTH',
      initialDatePickerMode: DatePickerMode.year,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (selected == null || !context.mounted) return;
    birthDate.text = profileDateLabel(selected);
    onChanged();
  }
}
