import 'package:sportika/shared/models/enums.dart';

/// What an account says it came to Sportika for, before roles are finalised.
///
/// A single account can hold several roles (spec §1); the intent only decides
/// which role a brand-new account starts with and which copy the setup flow
/// uses.
enum AccountIntent { player, organizer }

extension AccountIntentX on AccountIntent {
  String get key => name;

  String get label => switch (this) {
    AccountIntent.player => 'Player',
    AccountIntent.organizer => 'Organizer',
  };

  String get headline => switch (this) {
    AccountIntent.player => 'I play the game',
    AccountIntent.organizer => 'I run the game',
  };

  String get tagline => switch (this) {
    AccountIntent.player =>
      'Keep private scorecards, join tournaments and track your level across '
          'four sports.',
    AccountIntent.organizer =>
      'Publish tournaments, assign scorers and release official results when '
          'you are ready.',
  };

  String get proof => switch (this) {
    AccountIntent.player => 'Personal scoring · Entries · Squads',
    AccountIntent.organizer => 'Draws · Fixtures · Official results',
  };

  String get sport => switch (this) {
    AccountIntent.player => 'cricket',
    AccountIntent.organizer => 'futsal',
  };

  List<UserRole> get roles => switch (this) {
    AccountIntent.player => [UserRole.player],
    AccountIntent.organizer => [UserRole.organizer],
  };

  static AccountIntent fromKey(String? key) => AccountIntent.values.firstWhere(
    (i) => i.name == key,
    orElse: () => AccountIntent.player,
  );
}

/// Playing standard a player claims for one sport.
enum PlayingLevel { beginner, intermediate, advanced, pro }

extension PlayingLevelX on PlayingLevel {
  String get key => name;

  String get label => switch (this) {
    PlayingLevel.beginner => 'Beginner',
    PlayingLevel.intermediate => 'Intermediate',
    PlayingLevel.advanced => 'Advanced',
    PlayingLevel.pro => 'Pro',
  };

  String get blurb => switch (this) {
    PlayingLevel.beginner => 'Learning the rules',
    PlayingLevel.intermediate => 'Weekend regular',
    PlayingLevel.advanced => 'League standard',
    PlayingLevel.pro => 'Competing seriously',
  };

  static PlayingLevel fromKey(String? key) => PlayingLevel.values.firstWhere(
    (l) => l.name == key,
    orElse: () => PlayingLevel.intermediate,
  );
}

/// How often an account expects to be on court or in the middle.
enum PlayStyle { social, weekly, competitive }

extension PlayStyleX on PlayStyle {
  String get key => name;

  String get label => switch (this) {
    PlayStyle.social => 'Social',
    PlayStyle.weekly => 'Weekly',
    PlayStyle.competitive => 'Competitive',
  };

  String get blurb => switch (this) {
    PlayStyle.social => 'When friends call',
    PlayStyle.weekly => 'A fixed night out',
    PlayStyle.competitive => 'Chasing the final',
  };

  static PlayStyle fromKey(String? key) => PlayStyle.values.firstWhere(
    (s) => s.name == key,
    orElse: () => PlayStyle.weekly,
  );
}

/// Default level applied to a sport the moment it is selected, so setup never
/// hands the profile screen a sport without a preference.
PlayingLevel defaultLevelFor(Sport sport) => switch (sport) {
  Sport.cricket || Sport.badminton => PlayingLevel.intermediate,
  Sport.padel || Sport.futsal => PlayingLevel.beginner,
};

/// Very small validators shared by the auth screens and the flow controller.
/// Kept here so the rules are testable without Flutter.
class AuthRules {
  AuthRules._();

  static bool email(String value) {
    final v = value.trim();
    if (v.length > 254 || RegExp(r'\s').hasMatch(v)) return false;
    final parts = v.split('@');
    if (parts.length != 2 || parts.first.isEmpty || parts.first.length > 64) {
      return false;
    }
    final local = parts.first;
    if (local.startsWith('.') || local.endsWith('.') || local.contains('..')) {
      return false;
    }
    if (!RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(local)) {
      return false;
    }
    final labels = parts.last.split('.');
    return labels.length >= 2 &&
        labels.last.length >= 2 &&
        labels.every(
          (label) =>
              label.isNotEmpty &&
              label.length <= 63 &&
              RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$')
                  .hasMatch(label),
        );
  }

  static bool password(String value) => value.trim().length >= 8;

  static bool otp(String value) => RegExp(r'^[0-9]{6}$').hasMatch(value);

  /// Password checklist surfaced on Reset Password.
  static List<({String label, bool Function(String) passes})> get checks => [
    (label: 'At least 8 characters', passes: (v) => v.trim().length >= 8),
    (label: 'One letter', passes: (v) => v.contains(RegExp('[A-Za-z]'))),
    (label: 'One number', passes: (v) => v.contains(RegExp('[0-9]'))),
    (label: 'One symbol', passes: (v) => v.contains(RegExp(r'[^A-Za-z0-9\s]'))),
  ];

  static String strengthLabel(String value) {
    final passed = checks.where((c) => c.passes(value)).length;
    return switch (passed) {
      <= 1 => 'Weak',
      2 => 'Fair',
      3 => 'Good',
      _ => 'Strong',
    };
  }

  static double strength(String value) =>
      checks.where((c) => c.passes(value)).length / checks.length;
}
