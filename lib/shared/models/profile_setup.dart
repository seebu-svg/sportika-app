import 'package:sportika/shared/models/enums.dart';

enum ProfileGender { woman, man, nonBinary, preferNotToSay }

extension ProfileGenderX on ProfileGender {
  String get label => switch (this) {
    ProfileGender.woman => 'Woman',
    ProfileGender.man => 'Man',
    ProfileGender.nonBinary => 'Non-binary',
    ProfileGender.preferNotToSay => 'Prefer not to say',
  };
}

/// The enum names the UI uses are camelCase; the column uses snake_case.
String? profileGenderColumn(ProfileGender? gender) => switch (gender) {
  null => null,
  ProfileGender.woman => 'woman',
  ProfileGender.man => 'man',
  ProfileGender.nonBinary => 'non_binary',
  ProfileGender.preferNotToSay => 'prefer_not_to_say',
};

ProfileGender? profileGenderFromColumn(String? value) => ProfileGender.values
    .where((g) => profileGenderColumn(g) == value)
    .firstOrNull;

String profileDateLabel(DateTime? date) => date == null
    ? ''
    : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

DateTime? parseProfileDate(String value) {
  final parts = value.trim().split('/');
  if (parts.length != 3) return null;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((n) => n == null)) return null;
  if (numbers[2]! < 1 ||
      numbers[2]! > 9999 ||
      numbers[1]! < 1 ||
      numbers[1]! > 12 ||
      numbers[0]! < 1 ||
      numbers[0]! > 31) {
    return null;
  }
  final date = DateTime(numbers[2]!, numbers[1]!, numbers[0]!);
  return date.year == numbers[2] &&
          date.month == numbers[1] &&
          date.day == numbers[0]
      ? date
      : null;
}

String normalizeProfileHandle(String value) =>
    value.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();

/// Shared frontend validation for initial setup and editing an existing profile.
({String field, String message})? validateProfileIdentity({
  required String name,
  required String handle,
  required String city,
  required String bio,
  required DateTime? dateOfBirth,
}) {
  if (name.trim().length < 2 || name.trim().length > 80) {
    return (
      field: 'name',
      message: 'Enter a full name between 2 and 80 characters.',
    );
  }
  final username = normalizeProfileHandle(handle);
  if (!RegExp(r'^[a-z0-9._]{3,30}$').hasMatch(username)) {
    return (
      field: 'handle',
      message: 'Use 3–30 letters, numbers, dots or underscores.',
    );
  }
  final today = DateTime.now();
  if (dateOfBirth == null ||
      dateOfBirth.year < 1900 ||
      dateOfBirth.isAfter(DateTime(today.year, today.month, today.day))) {
    return (
      field: 'birthDate',
      message: 'Choose a valid date of birth on or before today.',
    );
  }
  if (city.trim().isEmpty || city.trim().length > 80) {
    return (field: 'city', message: 'Enter your city, up to 80 characters.');
  }
  if (bio.trim().length > 120) {
    return (field: 'bio', message: 'Keep your bio under 120 characters.');
  }
  return null;
}

List<String> playingPositionsFor(Sport sport) => switch (sport) {
  Sport.cricket => const ['Batter', 'Bowler', 'All-rounder', 'Wicketkeeper'],
  Sport.futsal => const ['Goalkeeper', 'Defender', 'Winger', 'Pivot'],
  Sport.padel => const ['Left side', 'Right side', 'Either side'],
  Sport.badminton => const [],
};
