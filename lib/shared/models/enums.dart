/// Core enumerations for the Sportika domain.
///
/// This library is intentionally free of Flutter imports so the scoring
/// engines and models stay unit-testable with `dart test`.
library;

/// Sports shipped in the MVP.
enum Sport { cricket, padel, futsal, badminton }

extension SportX on Sport {
  String get key => name;

  String get label => switch (this) {
    Sport.cricket => 'Cricket',
    Sport.padel => 'Padel',
    Sport.futsal => 'Futsal',
    Sport.badminton => 'Badminton',
  };

  static Sport fromKey(String key) => Sport.values.firstWhere(
    (s) => s.name == key,
    orElse: () => Sport.cricket,
  );
}

/// Roles a single Sportika account can hold at the same time.
enum UserRole { player, organizer, scorer }

extension UserRoleX on UserRole {
  String get key => name;
  String get label => switch (this) {
    UserRole.player => 'Player',
    UserRole.organizer => 'Organizer',
    UserRole.scorer => 'Scorer',
  };
  static UserRole fromKey(String key) => UserRole.values.firstWhere(
    (r) => r.name == key,
    orElse: () => UserRole.player,
  );
}

/// How a tournament advances teams once fixtures are played.
enum TournamentFormat { knockout, group }

extension TournamentFormatX on TournamentFormat {
  String get key => name;
  String get label => switch (this) {
    TournamentFormat.knockout => 'Knockout',
    TournamentFormat.group => 'Group play',
  };
  static TournamentFormat fromKey(String key) =>
      TournamentFormat.values.firstWhere(
        (r) => r.name == key,
        orElse: () => TournamentFormat.knockout,
      );
}

/// What a player registers as. Driven by the sport + tournament format.
enum EntryType { individual, pair, team }

extension EntryTypeX on EntryType {
  String get key => name;
  String get label => switch (this) {
    EntryType.individual => 'Individual',
    EntryType.pair => 'Pair',
    EntryType.team => 'Team',
  };
  static EntryType fromKey(String key) => EntryType.values.firstWhere(
    (r) => r.name == key,
    orElse: () => EntryType.team,
  );
}

enum TournamentStatus { draft, open, inProgress, completed }

extension TournamentStatusX on TournamentStatus {
  String get key => name;
  String get label => switch (this) {
    TournamentStatus.draft => 'Draft',
    TournamentStatus.open => 'Registration open',
    TournamentStatus.inProgress => 'In progress',
    TournamentStatus.completed => 'Completed',
  };
  static TournamentStatus fromKey(String key) => TournamentStatus.values
      .firstWhere((r) => r.name == key, orElse: () => TournamentStatus.draft);
}

/// Lifecycle of an official fixture. Only `published` feeds brackets/standings.
enum FixtureStatus { upcoming, live, submitted, published, walkover, cancelled }

extension FixtureStatusX on FixtureStatus {
  String get key => name;
  String get label => switch (this) {
    FixtureStatus.upcoming => 'Upcoming',
    FixtureStatus.live => 'Live',
    FixtureStatus.submitted => 'Awaiting review',
    FixtureStatus.published => 'Published',
    FixtureStatus.walkover => 'Walkover',
    FixtureStatus.cancelled => 'Cancelled',
  };
  static FixtureStatus fromKey(String key) => FixtureStatus.values.firstWhere(
    (r) => r.name == key,
    orElse: () => FixtureStatus.upcoming,
  );
}

enum EntryStatus { pending, confirmed, rejected, withdrawn }

extension EntryStatusX on EntryStatus {
  String get key => name;
  String get label => switch (this) {
    EntryStatus.pending => 'Pending review',
    EntryStatus.confirmed => 'Confirmed',
    EntryStatus.rejected => 'Rejected',
    EntryStatus.withdrawn => 'Withdrawn',
  };
  static EntryStatus fromKey(String key) => EntryStatus.values.firstWhere(
    (r) => r.name == key,
    orElse: () => EntryStatus.pending,
  );
}

/// A personal scorecard is private to its owner and never touches official data.
enum PersonalMatchStatus { inProgress, paused, completed }

extension PersonalMatchStatusX on PersonalMatchStatus {
  String get key => name;
  String get label => switch (this) {
    PersonalMatchStatus.inProgress => 'In progress',
    PersonalMatchStatus.paused => 'Paused',
    PersonalMatchStatus.completed => 'Completed',
  };
  static PersonalMatchStatus fromKey(String key) =>
      PersonalMatchStatus.values.firstWhere(
        (r) => r.name == key,
        orElse: () => PersonalMatchStatus.inProgress,
      );
}

/// What a notification is about.
///
/// The first seven kinds are the device store's own vocabulary and go back to
/// the seeded demo world. The rest arrived with the server-backed inbox and
/// fold the many server event types into the handful of shapes the
/// notification centre draws.
enum NotificationKind {
  entryDecision,
  fixtureChange,
  scorerAssignment,
  resultSubmitted,
  resultPublished,
  resultCorrected,
  dispute,
  matchInvite,
  matchUpdate,
  matchReminder,
  tournamentUpdate,
  teamUpdate,
  accountUpdate,
  platformUpdate,
}

extension NotificationKindX on NotificationKind {
  String get key => name;
  static NotificationKind fromKey(String key) =>
      NotificationKind.values.firstWhere(
        (r) => r.name == key,
        orElse: () => NotificationKind.entryDecision,
      );

  /// Maps a server event type onto the shape the notification centre draws.
  ///
  /// The server names every event precisely; the centre only needs to know
  /// which icon and colour to use, so the types collapse into these kinds. An
  /// unknown type falls back to a match update rather than to a failure: a
  /// server event the app has not heard of yet must still reach the inbox.
  static NotificationKind fromServerType(String type) => switch (type) {
    'match_invite' ||
    'match_invite_accepted' ||
    'match_invite_declined' => NotificationKind.matchInvite,
    'match_removed' ||
    'match_schedule_changed' ||
    'match_cancelled' => NotificationKind.matchUpdate,
    'match_starting_soon' => NotificationKind.matchReminder,
    'match_result_submitted' => NotificationKind.resultSubmitted,
    'result_published' => NotificationKind.resultPublished,
    'result_corrected' => NotificationKind.resultCorrected,
    'scorer_assigned' ||
    'scorer_assignment_revoked' ||
    'scorer_match_started' ||
    'scorer_match_completed' ||
    'scorer_fixture_assigned' ||
    'scorer_fixture_revoked' ||
    'scorer_fixture_answered' ||
    'scorer_duty_reminder' => NotificationKind.scorerAssignment,
    'dispute_submitted' ||
    'dispute_resolved' ||
    'dispute_rejected' ||
    'dispute_status_changed' => NotificationKind.dispute,
    'tournament_registration_received' ||
    'tournament_registration_confirmed' ||
    'tournament_registration_rejected' ||
    'tournament_entry_withdrawn' ||
    'tournament_advancement' ||
    'tournament_result' ||
    'tournament_cancelled' ||
    'tournament_schedule_changed' ||
    'tournament_registration_closing' ||
    'tournament_staff_added' ||
    'fixture_published' ||
    'draw_published' => NotificationKind.tournamentUpdate,
    'team_invite' ||
    'team_join_request' ||
    'team_member_joined' ||
    'team_member_left' ||
    'team_member_removed' ||
    'team_invite_cancelled' ||
    'team_invite_declined' ||
    'team_captain_changed' ||
    'team_deleted' => NotificationKind.teamUpdate,
    'account_username_changed' ||
    'security_email_changed' ||
    'security_password_changed' => NotificationKind.accountUpdate,
    _ => NotificationKind.matchUpdate,
  };
}
