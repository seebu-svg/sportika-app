import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_setup.dart';

/// A stable identifier generator that does not depend on Flutter.
String newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '-${(DateTime.now().microsecondsSinceEpoch ~/ 1000 % 997).toRadixString(36)}';

/// One universal Sportika account. Legacy roles remain for local compatibility
/// (spec §1), for example player + scorer.
class Account {
  final String id;
  String displayName;
  String email;
  String city;
  final List<UserRole> roles;

  /// Public @handle chosen during profile setup.
  String handle;
  String bio;
  DateTime? dateOfBirth;
  ProfileGender? gender;
  Map<String, String> playingPositions;
  bool playingPreferencesSkipped;

  /// Sports the account says it plays, plus the level claimed for each.
  Set<Sport> sports;
  Map<String, PlayingLevel> levels;
  PlayStyle playStyle;

  /// Id of the gradient avatar preset, used whenever no photo is set.
  String avatar;

  /// Absolute path of the picture the player imported, written by the profile
  /// photo store. Only the reference is persisted; the bytes stay in the app's
  /// support directory. Null means the preset avatar is shown.
  String? photoPath;

  /// Public URL of the same picture once it has been uploaded. A server-backed
  /// account always has one after a photo change; the on-device store never sets
  /// it. [photoPath] stays the fast path and this is the fallback, so a fresh
  /// install still shows the member's face.
  String? photoUrl;

  /// False while a freshly created account is still inside profile setup.
  bool setupComplete;

  Account({
    required this.id,
    required this.displayName,
    required this.email,
    required this.city,
    required this.roles,
    this.handle = '',
    this.bio = '',
    this.dateOfBirth,
    this.gender,
    Map<String, String>? playingPositions,
    this.playingPreferencesSkipped = false,
    Set<Sport>? sports,
    Map<String, PlayingLevel>? levels,
    this.playStyle = PlayStyle.weekly,
    this.avatar = 'midnight',
    this.photoPath,
    this.photoUrl,
    this.setupComplete = true,
  }) : sports = sports ?? {},
       levels = levels ?? {},
       playingPositions = playingPositions ?? {};

  bool has(UserRole role) => roles.contains(role);

  /// Whether there is a picture to paint instead of initials.
  bool get hasPhoto =>
      (photoPath != null && photoPath!.isNotEmpty) ||
      (photoUrl != null && photoUrl!.isNotEmpty);

  /// Avatar letters for the name. A profile can arrive from the server with no
  /// display name yet, and the avatar still has to paint something, so an empty
  /// name falls back to the same neutral `?` that [initialsOf] uses rather than
  /// slicing an empty string.
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// Falls back to the email local part so seeded accounts still have a name
  /// for the @handle line.
  String get username => handle.isNotEmpty ? handle : email.split('@').first;

  PlayingLevel levelFor(Sport sport) =>
      levels[sport.key] ?? defaultLevelFor(sport);

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'email': email,
    'city': city,
    'roles': roles.map((r) => r.key).toList(),
    'handle': handle,
    'bio': bio,
    'dateOfBirth': dateOfBirth?.toIso8601String(),
    'gender': gender?.name,
    'playingPositions': Map<String, String>.of(playingPositions),
    'playingPreferencesSkipped': playingPreferencesSkipped,
    'sports': sports.map((s) => s.key).toList(),
    'levels': levels.map((key, value) => MapEntry(key, value.key)),
    'playStyle': playStyle.key,
    'avatar': avatar,
    'photoPath': photoPath,
    'photoUrl': photoUrl,
    'setupComplete': setupComplete,
  };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['id'] as String,
    displayName: j['displayName'] as String,
    email: j['email'] as String? ?? '',
    city: j['city'] as String? ?? '',
    roles: (j['roles'] as List<dynamic>? ?? [])
        .map((e) => UserRoleX.fromKey(e as String))
        .toSet()
        .toList(),
    handle: j['handle'] as String? ?? '',
    bio: j['bio'] as String? ?? '',
    dateOfBirth: DateTime.tryParse(j['dateOfBirth'] as String? ?? ''),
    gender: ProfileGender.values
        .where((g) => g.name == j['gender'])
        .firstOrNull,
    playingPositions: Map<String, String>.from(
      j['playingPositions'] as Map? ?? {},
    ),
    playingPreferencesSkipped: j['playingPreferencesSkipped'] as bool? ?? false,
    sports: (j['sports'] as List<dynamic>? ?? [])
        .map((e) => SportX.fromKey(e as String))
        .toSet(),
    levels: (j['levels'] as Map? ?? {}).map(
      (key, value) =>
          MapEntry(key as String, PlayingLevelX.fromKey(value as String?)),
    ),
    playStyle: PlayStyleX.fromKey(j['playStyle'] as String?),
    avatar: j['avatar'] as String? ?? 'midnight',
    photoPath: j['photoPath'] as String?,
    photoUrl: j['photoUrl'] as String?,
    setupComplete: j['setupComplete'] as bool? ?? true,
  );
}

/// A pair or team a player forms and then uses to enter tournaments.
class Squad {
  final String id;
  final String ownerId;
  String name;
  final Sport sport;
  final EntryType type;
  List<String> memberAccountIds;

  /// Players invited but not yet in [memberAccountIds]. Persisted so an invite
  /// survives a restart while it waits for the other player.
  final List<String> invitedAccountIds;
  final DateTime createdAt;

  /// True when the team was created for preview/testing. Demo content is
  /// deletable without touching a member's own rows.
  final bool isDemo;

  Squad({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.sport,
    required this.type,
    required this.memberAccountIds,
    List<String>? invitedAccountIds,
    required this.createdAt,
    this.isDemo = false,
  }) : invitedAccountIds = invitedAccountIds ?? [];

  String get captainId => ownerId;

  int get size => memberAccountIds.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'name': name,
    'sport': sport.key,
    'type': type.key,
    'memberAccountIds': memberAccountIds,
    'invitedAccountIds': invitedAccountIds,
    'createdAt': createdAt.toIso8601String(),
    'isDemo': isDemo,
  };

  factory Squad.fromJson(Map<String, dynamic> j) => Squad(
    id: j['id'] as String,
    ownerId: j['ownerId'] as String,
    name: j['name'] as String,
    sport: SportX.fromKey(j['sport'] as String),
    type: EntryTypeX.fromKey(j['type'] as String),
    memberAccountIds: (j['memberAccountIds'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList(),
    invitedAccountIds: (j['invitedAccountIds'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    isDemo: j['isDemo'] as bool? ?? false,
  );
}

/// A tournament created and published by an organizer (spec §4.1).
class Tournament {
  final String id;
  final String organizerId;
  String name;
  String city;
  Sport sport;
  String formatLabel;
  TournamentFormat format;
  EntryType entryType;
  DateTime startsAt;
  DateTime endsAt;
  int registrationLimit;
  String entryFee;

  /// Human readable match rules shown to scorers and players (spec §4.1).
  String matchRules;

  /// Key rules the scoring engines read, e.g. overs / sets / half length.
  Map<String, dynamic> rules;

  /// Where the organizer uploaded a card image, if they did. A tournament card
  /// falls back to the bundled sport photograph when this is null.
  final String? bannerUrl;

  TournamentStatus status;
  final DateTime createdAt;

  /// True when the record was created for preview/testing.
  final bool isDemo;

  Tournament({
    required this.id,
    required this.organizerId,
    required this.name,
    required this.city,
    required this.sport,
    required this.formatLabel,
    required this.format,
    required this.entryType,
    required this.startsAt,
    required this.endsAt,
    required this.registrationLimit,
    required this.entryFee,
    required this.matchRules,
    required this.rules,
    required this.status,
    required this.createdAt,
    this.bannerUrl,
    this.isDemo = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'organizerId': organizerId,
    'name': name,
    'city': city,
    'sport': sport.key,
    'formatLabel': formatLabel,
    'format': format.key,
    'entryType': entryType.key,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': endsAt.toIso8601String(),
    'registrationLimit': registrationLimit,
    'entryFee': entryFee,
    'matchRules': matchRules,
    'rules': rules,
    'bannerUrl': bannerUrl,
    'status': status.key,
    'createdAt': createdAt.toIso8601String(),
    'isDemo': isDemo,
  };

  factory Tournament.fromJson(Map<String, dynamic> j) => Tournament(
    id: j['id'] as String,
    organizerId: j['organizerId'] as String,
    name: j['name'] as String,
    city: j['city'] as String? ?? '',
    sport: SportX.fromKey(j['sport'] as String),
    formatLabel: j['formatLabel'] as String? ?? '',
    format: TournamentFormatX.fromKey(j['format'] as String? ?? 'knockout'),
    entryType: EntryTypeX.fromKey(j['entryType'] as String? ?? 'team'),
    startsAt: DateTime.parse(j['startsAt'] as String),
    endsAt: DateTime.parse(j['endsAt'] as String),
    registrationLimit: j['registrationLimit'] as int? ?? 8,
    entryFee: j['entryFee'] as String? ?? 'PKR 0',
    matchRules: j['matchRules'] as String? ?? '',
    rules: Map<String, dynamic>.from(j['rules'] as Map? ?? const {}),
    bannerUrl: j['bannerUrl'] as String?,
    status: TournamentStatusX.fromKey(j['status'] as String? ?? 'draft'),
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    isDemo: j['isDemo'] as bool? ?? false,
  );
}

/// An entry into a tournament: an individual, pair or team (spec §4.2).
class Entry {
  final String id;
  final String tournamentId;

  /// Null for individual entries.
  String? squadId;
  String captainAccountId;
  String label;
  List<String> memberAccountIds;
  EntryStatus status;
  final DateTime submittedAt;
  String? decisionNote;

  /// True when the entry was created for preview/testing.
  final bool isDemo;

  Entry({
    required this.id,
    required this.tournamentId,
    this.squadId,
    required this.captainAccountId,
    required this.label,
    required this.memberAccountIds,
    required this.status,
    required this.submittedAt,
    this.decisionNote,
    this.isDemo = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'tournamentId': tournamentId,
    'squadId': squadId,
    'captainAccountId': captainAccountId,
    'label': label,
    'memberAccountIds': memberAccountIds,
    'status': status.key,
    'submittedAt': submittedAt.toIso8601String(),
    'decisionNote': decisionNote,
    'isDemo': isDemo,
  };

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'] as String,
    tournamentId: j['tournamentId'] as String,
    squadId: j['squadId'] as String?,
    captainAccountId: j['captainAccountId'] as String,
    label: j['label'] as String,
    memberAccountIds: (j['memberAccountIds'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList(),
    status: EntryStatusX.fromKey(j['status'] as String? ?? 'pending'),
    submittedAt:
        DateTime.tryParse(j['submittedAt'] as String? ?? '') ?? DateTime.now(),
    decisionNote: j['decisionNote'] as String?,
    isDemo: j['isDemo'] as bool? ?? false,
  );
}

/// One side of a fixture. Backed by an entry, or a placeholder for a bracket
/// slot that is still TBD.
class FixtureSide {
  final String entryId;
  String label;

  /// Group letter for group play fixtures.
  String? group;

  FixtureSide({required this.entryId, required this.label, this.group});

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'label': label,
    'group': group,
  };

  factory FixtureSide.fromJson(Map<String, dynamic> j) => FixtureSide(
    entryId: j['entryId'] as String,
    label: j['label'] as String,
    group: j['group'] as String?,
  );
}

/// An official match. Carries its own event log, separate from personal cards.
class Fixture {
  final String id;
  final String tournamentId;

  /// e.g. "Quarter-final", "Semi-final", "Final", or "Group A · Round 2".
  String stage;
  int round;
  String? group;
  FixtureSide home;
  FixtureSide away;
  DateTime scheduledAt;
  String venue;
  FixtureStatus status;

  /// Scorers assigned per fixture; an organizer may assign themselves (spec §1).
  /// Reassigning mid-match transfers access and keeps the recorded events.
  List<String> scorerAccountIds;
  String? submittedByScorerId;
  DateTime? startedAt;
  DateTime? completedAt;

  /// Official scoring event log. Resumes from the latest saved state (spec §6).
  List<Map<String, dynamic>> events;
  Map<String, dynamic> rules;

  /// Published outcome, kept even after a correction so history survives.
  OfficialResult? result;

  /// Correction audit trail (spec §4.5).
  List<ResultCorrection> corrections;

  /// Player-initiated escalation reviewed by the tournament organizer (spec §5).
  String? disputeNote;
  String? disputeRaisedBy;
  bool disputeResolved;

  Fixture({
    required this.id,
    required this.tournamentId,
    required this.stage,
    required this.round,
    this.group,
    required this.home,
    required this.away,
    required this.scheduledAt,
    required this.venue,
    required this.status,
    required this.scorerAccountIds,
    this.submittedByScorerId,
    this.startedAt,
    this.completedAt,
    required this.events,
    required this.rules,
    this.result,
    required this.corrections,
    this.disputeNote,
    this.disputeRaisedBy,
    this.disputeResolved = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'tournamentId': tournamentId,
    'stage': stage,
    'round': round,
    'group': group,
    'home': home.toJson(),
    'away': away.toJson(),
    'scheduledAt': scheduledAt.toIso8601String(),
    'venue': venue,
    'status': status.key,
    'scorerAccountIds': scorerAccountIds,
    'submittedByScorerId': submittedByScorerId,
    'startedAt': startedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'events': events,
    'rules': rules,
    'result': result?.toJson(),
    'corrections': corrections.map((c) => c.toJson()).toList(),
    'disputeNote': disputeNote,
    'disputeRaisedBy': disputeRaisedBy,
    'disputeResolved': disputeResolved,
  };

  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
    id: j['id'] as String,
    tournamentId: j['tournamentId'] as String,
    stage: j['stage'] as String? ?? '',
    round: j['round'] as int? ?? 1,
    group: j['group'] as String?,
    home: FixtureSide.fromJson(Map<String, dynamic>.from(j['home'] as Map)),
    away: FixtureSide.fromJson(Map<String, dynamic>.from(j['away'] as Map)),
    scheduledAt:
        DateTime.tryParse(j['scheduledAt'] as String? ?? '') ?? DateTime.now(),
    venue: j['venue'] as String? ?? '',
    status: FixtureStatusX.fromKey(j['status'] as String? ?? 'upcoming'),
    scorerAccountIds: (j['scorerAccountIds'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList(),
    submittedByScorerId: j['submittedByScorerId'] as String?,
    startedAt: j['startedAt'] == null
        ? null
        : DateTime.parse(j['startedAt'] as String),
    completedAt: j['completedAt'] == null
        ? null
        : DateTime.parse(j['completedAt'] as String),
    events: (j['events'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    rules: Map<String, dynamic>.from(j['rules'] as Map? ?? const {}),
    result: j['result'] == null
        ? null
        : OfficialResult.fromJson(
            Map<String, dynamic>.from(j['result'] as Map),
          ),
    corrections: (j['corrections'] as List<dynamic>? ?? [])
        .map(
          (e) => ResultCorrection.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    disputeNote: j['disputeNote'] as String?,
    disputeRaisedBy: j['disputeRaisedBy'] as String?,
    disputeResolved: j['disputeResolved'] as bool? ?? false,
  );
}

/// The published outcome of a fixture. Scores are stored per side so all four
/// sports can share one shape.
class OfficialResult {
  final List<String> sideScores;
  final List<int> sideValues;
  final int winnerIndex;

  /// -1 for a draw (possible in group / futsal regulation play).
  final String headline;
  final String detail;
  final DateTime publishedAt;
  final String publishedById;

  /// True when set by an organizer walkover rather than played scoring.
  final bool walkover;

  OfficialResult({
    required this.sideScores,
    required this.sideValues,
    required this.winnerIndex,
    required this.headline,
    required this.detail,
    required this.publishedAt,
    required this.publishedById,
    this.walkover = false,
  });

  Map<String, dynamic> toJson() => {
    'sideScores': sideScores,
    'sideValues': sideValues,
    'winnerIndex': winnerIndex,
    'headline': headline,
    'detail': detail,
    'publishedAt': publishedAt.toIso8601String(),
    'publishedById': publishedById,
    'walkover': walkover,
  };

  factory OfficialResult.fromJson(Map<String, dynamic> j) => OfficialResult(
    sideScores: (j['sideScores'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList(),
    sideValues: (j['sideValues'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt())
        .toList(),
    winnerIndex: j['winnerIndex'] as int? ?? -1,
    headline: j['headline'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    publishedAt:
        DateTime.tryParse(j['publishedAt'] as String? ?? '') ?? DateTime.now(),
    publishedById: j['publishedById'] as String? ?? '',
    walkover: j['walkover'] as bool? ?? false,
  );
}

/// A published correction. Keeps the previous result, the reason and who
/// changed it (spec §4.5).
class ResultCorrection {
  final String id;
  final OfficialResult previous;
  final OfficialResult current;
  final String reason;
  final String byAccountId;
  final DateTime at;

  ResultCorrection({
    required this.id,
    required this.previous,
    required this.current,
    required this.reason,
    required this.byAccountId,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'previous': previous.toJson(),
    'current': current.toJson(),
    'reason': reason,
    'byAccountId': byAccountId,
    'at': at.toIso8601String(),
  };

  factory ResultCorrection.fromJson(Map<String, dynamic> j) => ResultCorrection(
    id: j['id'] as String,
    previous: OfficialResult.fromJson(
      Map<String, dynamic>.from(j['previous'] as Map),
    ),
    current: OfficialResult.fromJson(
      Map<String, dynamic>.from(j['current'] as Map),
    ),
    reason: j['reason'] as String? ?? '',
    byAccountId: j['byAccountId'] as String? ?? '',
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// A private scorecard kept by a player (spec §2). Never linked or shared.
class PersonalMatch {
  final String id;
  final String ownerId;
  final Sport sport;
  final String formatLabel;
  List<String> sideNames;
  List<Map<String, dynamic>> events;
  Map<String, dynamic> rules;
  PersonalMatchStatus status;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> details;

  /// Set when the engine decides the match reached its end under the rules.
  String? autoCompletedReason;

  PersonalMatch({
    required this.id,
    required this.ownerId,
    required this.sport,
    required this.formatLabel,
    required this.sideNames,
    required this.events,
    required this.rules,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.autoCompletedReason,
    Map<String, dynamic>? details,
  }) : details = details ?? {};

  Map<String, dynamic> toJson() => {
    'details': details,
    'id': id,
    'ownerId': ownerId,
    'sport': sport.key,
    'formatLabel': formatLabel,
    'sideNames': sideNames,
    'events': events,
    'rules': rules,
    'status': status.key,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'autoCompletedReason': autoCompletedReason,
  };

  factory PersonalMatch.fromJson(Map<String, dynamic> j) => PersonalMatch(
    details: Map<String, dynamic>.from(j['details'] as Map? ?? {}),
    id: j['id'] as String,
    ownerId: j['ownerId'] as String,
    sport: SportX.fromKey(j['sport'] as String),
    formatLabel: j['formatLabel'] as String? ?? '',
    sideNames: (j['sideNames'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toList(),
    events: (j['events'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    rules: Map<String, dynamic>.from(j['rules'] as Map? ?? const {}),
    status: PersonalMatchStatusX.fromKey(
      j['status'] as String? ?? 'inProgress',
    ),
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    autoCompletedReason: j['autoCompletedReason'] as String?,
  );
}

class AppNotification {
  final String id;
  final String accountId;
  final NotificationKind kind;
  final String title;
  final String body;
  final String? route;
  final bool read;
  final DateTime at;

  /// The server event type, for example `match_invite`. Empty for the device
  /// store, which has no server vocabulary.
  final String type;

  /// What the notification points at: `match`, `result`, `dispute`,
  /// `tournament`, `fixture`, `account` or `team`.
  final String? entityType;

  /// The id of that entity, as the server wrote it.
  final String? entityId;

  /// The structured navigation payload. The server sends ids and a tab hint,
  /// never a path: the app decides what a notification opens.
  final Map<String, dynamic> payload;

  /// Who caused the event, when the server could tell.
  final String? actorId;

  /// When the notification stops being relevant.
  final DateTime? expiresAt;

  AppNotification({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.title,
    required this.body,
    this.route,
    required this.read,
    required this.at,
    this.type = '',
    this.entityType,
    this.entityId,
    this.payload = const {},
    this.actorId,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'kind': kind.key,
    'title': title,
    'body': body,
    'route': route,
    'read': read,
    'at': at.toIso8601String(),
    'type': type,
    'entityType': entityType,
    'entityId': entityId,
    'payload': payload,
    'actorId': actorId,
    'expiresAt': expiresAt?.toIso8601String(),
  };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    accountId: j['accountId'] as String,
    kind: NotificationKindX.fromKey(j['kind'] as String? ?? 'entryDecision'),
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
    route: j['route'] as String?,
    read: j['read'] as bool? ?? false,
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
    type: j['type'] as String? ?? '',
    entityType: j['entityType'] as String?,
    entityId: j['entityId'] as String?,
    payload: Map<String, dynamic>.from(j['payload'] as Map? ?? const {}),
    actorId: j['actorId'] as String?,
    expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? ''),
  );
}

/// Which families of notification a member wants to receive.
///
/// These live in PostgreSQL and are enforced while the notification is
/// generated, so a switch is a promise the server keeps rather than a filter
/// the client applies after the fact.
class NotificationPreferences {
  const NotificationPreferences({
    this.matchActivity = true,
    this.tournamentUpdates = true,
    this.teamActivity = true,
    this.scorerAssignments = true,
    this.platformAnnouncements = true,
  });

  /// Invitations, schedule changes, cancellations, results and disputes.
  final bool matchActivity;

  /// Registrations, draws, fixtures and tournament announcements.
  final bool tournamentUpdates;

  /// Squad invitations and roster changes.
  final bool teamActivity;

  /// Assignments to score, and reminders about them.
  final bool scorerAssignments;

  /// News from Sportika itself.
  final bool platformAnnouncements;

  /// Reads the preferences from a server row or from the device document.
  ///
  /// The server speaks snake_case and the device document speaks camelCase, so
  /// both are accepted and the switch is only off when a source says so.
  factory NotificationPreferences.fromJson(Map<String, dynamic> j) {
    bool flag(String serverKey, String deviceKey) =>
        j[serverKey] as bool? ?? j[deviceKey] as bool? ?? true;

    return NotificationPreferences(
      matchActivity: flag('match_activity', 'matchActivity'),
      tournamentUpdates: flag('tournament_updates', 'tournamentUpdates'),
      teamActivity: flag('team_activity', 'teamActivity'),
      scorerAssignments: flag('scorer_assignments', 'scorerAssignments'),
      platformAnnouncements: flag(
        'platform_announcements',
        'platformAnnouncements',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'match_activity': matchActivity,
    'tournament_updates': tournamentUpdates,
    'team_activity': teamActivity,
    'scorer_assignments': scorerAssignments,
    'platform_announcements': platformAnnouncements,
  };

  NotificationPreferences copyWith({
    bool? matchActivity,
    bool? tournamentUpdates,
    bool? teamActivity,
    bool? scorerAssignments,
    bool? platformAnnouncements,
  }) => NotificationPreferences(
    matchActivity: matchActivity ?? this.matchActivity,
    tournamentUpdates: tournamentUpdates ?? this.tournamentUpdates,
    teamActivity: teamActivity ?? this.teamActivity,
    scorerAssignments: scorerAssignments ?? this.scorerAssignments,
    platformAnnouncements: platformAnnouncements ?? this.platformAnnouncements,
  );
}
