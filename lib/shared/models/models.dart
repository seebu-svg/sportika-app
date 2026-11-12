import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';

/// A stable identifier generator that does not depend on Flutter.
String newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '-${(DateTime.now().microsecondsSinceEpoch ~/ 1000 % 997).toRadixString(36)}';

/// One Sportika account. A single account can hold several roles at once
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

  /// Sports the account says it plays, plus the level claimed for each.
  Set<Sport> sports;
  Map<String, PlayingLevel> levels;
  PlayStyle playStyle;

  /// Id of the gradient avatar preset; no binary uploads in the prototype.
  String avatar;

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
    Set<Sport>? sports,
    Map<String, PlayingLevel>? levels,
    this.playStyle = PlayStyle.weekly,
    this.avatar = 'midnight',
    this.setupComplete = true,
  }) : sports = sports ?? {},
       levels = levels ?? {};

  bool has(UserRole role) => roles.contains(role);

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
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
    'sports': sports.map((s) => s.key).toList(),
    'levels': levels.map((key, value) => MapEntry(key, value.key)),
    'playStyle': playStyle.key,
    'avatar': avatar,
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
    sports: (j['sports'] as List<dynamic>? ?? [])
        .map((e) => SportX.fromKey(e as String))
        .toSet(),
    levels: (j['levels'] as Map? ?? {}).map(
      (key, value) =>
          MapEntry(key as String, PlayingLevelX.fromKey(value as String?)),
    ),
    playStyle: PlayStyleX.fromKey(j['playStyle'] as String?),
    avatar: j['avatar'] as String? ?? 'midnight',
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
  final DateTime createdAt;

  Squad({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.sport,
    required this.type,
    required this.memberAccountIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'name': name,
    'sport': sport.key,
    'type': type.key,
    'memberAccountIds': memberAccountIds,
    'createdAt': createdAt.toIso8601String(),
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
    createdAt: DateTime.parse(j['createdAt'] as String),
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

  TournamentStatus status;
  final DateTime createdAt;

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
    'status': status.key,
    'createdAt': createdAt.toIso8601String(),
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
    status: TournamentStatusX.fromKey(j['status'] as String? ?? 'draft'),
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
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

  AppNotification({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.title,
    required this.body,
    this.route,
    required this.read,
    required this.at,
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
  );
}
