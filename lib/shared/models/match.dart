import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';

/// A standalone official match.
///
/// This is deliberately not a [Fixture]: a fixture belongs to a tournament and
/// borrows its sport from it, while a match is its own aggregate that carries
/// the sport, the two sides, the invited players, the official scorer and the
/// recorded event log. Tournaments, personal scorecards and pickup games are
/// untouched by this type.
///
/// The lifecycle reuses [FixtureStatus] so the existing status pill, colours
/// and icons keep working without a second vocabulary.
class SportMatch {
  final String id;
  Sport sport;
  String formatLabel;
  Map<String, dynamic> rules;
  String title;
  String venue;
  DateTime scheduledAt;
  MatchVisibility visibility;
  String organizerId;

  /// The assigned official scorer. Null while the organizer scores it
  /// themselves; transferring the role never touches [events].
  String? scorerId;
  FixtureStatus status;

  /// `[sideA, sideB]`, the same shape the scoring engines fold.
  List<String> sideNames;
  MatchDiscipline discipline;
  int capacity;

  DateTime? startedAt;
  DateTime? submittedAt;
  DateTime? completedAt;
  DateTime? publishedAt;

  /// Pause is a timestamp, never a status value: [FixtureStatus] has no
  /// `paused` key, and inventing one would make the existing status pill,
  /// colours and `isLive` checks fall back to `upcoming` everywhere. A paused
  /// match is still live; scoring is what stops. Mirrors the three columns
  /// migration 0012 adds to public.matches.
  DateTime? pausedAt;
  String? pausedBy;
  String? pauseReason;

  /// Challenges raised against this match's official result. The client only
  /// ever reads them: `raise_match_dispute` and `resolve_match_dispute` write
  /// the rows, and RLS gives a member only the disputes of matches they can see.
  List<MatchDispute> disputes;

  /// Highest sequence number handed out by the server. It only moves forward,
  /// so undoing an event can never resurrect it through a late retry.
  int eventCount;

  List<MatchParticipant> participants;
  List<MatchEvent> events;
  OfficialResult? result;
  List<ResultCorrection> corrections;
  final DateTime createdAt;

  /// Tournament and fixture links for matches generated from a draw.
  /// Null for a standalone friendly match. The server persists both ids in
  /// public.matches (migration 0008) so other devices see the link too.
  final String? tournamentId;
  final String? fixtureId;

  /// True when the match row was created for preview/testing. Demo matches are
  /// deletable and never belong to a member's own history.
  final bool isDemo;

  /// True when this match was generated from a tournament fixture.
  bool get isTournamentMatch => tournamentId != null;

  SportMatch({
    required this.id,
    required this.sport,
    required this.formatLabel,
    required this.rules,
    required this.title,
    required this.venue,
    required this.scheduledAt,
    required this.visibility,
    required this.organizerId,
    required this.status,
    required this.sideNames,
    required this.discipline,
    required this.capacity,
    required this.createdAt,
    this.scorerId,
    this.startedAt,
    this.submittedAt,
    this.completedAt,
    this.publishedAt,
    this.pausedAt,
    this.pausedBy,
    this.pauseReason,
    this.eventCount = 0,
    this.tournamentId,
    this.fixtureId,
    List<MatchParticipant>? participants,
    List<MatchEvent>? events,
    this.result,
    List<ResultCorrection>? corrections,
    List<MatchDispute>? disputes,
    this.isDemo = false,
  }) : participants = participants ?? [],
       events = events ?? [],
       corrections = corrections ?? [],
       disputes = disputes ?? [];

  // ── derived lifecycle ────────────────────────────────────────────────────

  bool get isLive => status == FixtureStatus.live;
  bool get isFinished =>
      status == FixtureStatus.published ||
      status == FixtureStatus.walkover ||
      status == FixtureStatus.cancelled;
  bool get canRecordEvents =>
      status == FixtureStatus.live || status == FixtureStatus.upcoming;
  bool get awaitingReview => status == FixtureStatus.submitted;

  /// Scoring is stopped without the match leaving [FixtureStatus.live].
  bool get isPaused => pausedAt != null;

  bool isOrganizer(String? accountId) =>
      accountId != null && accountId == organizerId;

  bool isScorer(String? accountId) =>
      accountId != null && scorerId != null && accountId == scorerId;

  /// Who may start the match and write to the event log: the organizer and the
  /// assigned scorer, exactly like the RPCs.
  bool canScore(String? accountId) =>
      isOrganizer(accountId) || isScorer(accountId);

  /// Who may object to the official result. Mirrors `raise_match_dispute`,
  /// which also lets the owner of the tournament this fixture belongs to - a
  /// fact the device cannot read per match, so a tournament organizer resolves
  /// through the same RPC and the server decides.
  bool canDispute(String? accountId) =>
      canScore(accountId) ||
      (accountId != null &&
          participants.any(
            (p) =>
                p.profileId == accountId &&
                p.status != MatchParticipantStatus.declined &&
                p.status != MatchParticipantStatus.removed,
          ));

  /// Only the organizer answers a dispute, the same rule `publish_match_result`
  /// uses.
  bool canResolveDispute(String? accountId) => isOrganizer(accountId);

  /// A dispute needs something to contest: the result row does not exist until
  /// the match has been submitted or walked over.
  bool get hasResult => result != null;

  MatchParticipant? participantOf(String? accountId) {
    if (accountId == null) return null;
    for (final p in participants) {
      if (p.profileId == accountId) return p;
    }
    return null;
  }

  bool isParticipant(String? accountId) {
    final p = participantOf(accountId);
    return p != null && p.status == MatchParticipantStatus.accepted;
  }

  /// Participants that actually count towards capacity.
  int get acceptedCount => participants
      .where((p) => p.status == MatchParticipantStatus.accepted)
      .length;

  List<MatchParticipant> participantsOnSide(int side) => participants
      .where(
        (p) => p.side == side && p.status == MatchParticipantStatus.accepted,
      )
      .toList();

  /// The newest active entry, which is the only one undo may withdraw.
  MatchEvent? get lastActiveEvent {
    MatchEvent? last;
    for (final e in events) {
      if (!e.voided) last = e;
    }
    return last;
  }

  /// The log as the scoring engine should fold it: voided entries dropped, in
  /// the order the server handed out sequence numbers.
  List<Map<String, dynamic>> get scoringLog {
    final active = events.where((e) => !e.voided).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return [for (final e in active) e.scoringJson];
  }

  List<String> get sideLabels => List<String>.from(sideNames);

  // ── JSON ────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'sport': sport.key,
    'formatLabel': formatLabel,
    'rules': rules,
    'title': title,
    'venue': venue,
    'scheduledAt': scheduledAt.toIso8601String(),
    'visibility': visibility.key,
    'organizerId': organizerId,
    'scorerId': scorerId,
    'status': status.key,
    'sideNames': sideNames,
    'discipline': discipline.key,
    'capacity': capacity,
    'startedAt': startedAt?.toIso8601String(),
    'submittedAt': submittedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'publishedAt': publishedAt?.toIso8601String(),
    'pausedAt': pausedAt?.toIso8601String(),
    'pausedBy': pausedBy,
    'pauseReason': pauseReason,
    'eventCount': eventCount,
    'participants': participants.map((p) => p.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'result': result?.toJson(),
    'corrections': corrections.map((c) => c.toJson()).toList(),
    'disputes': disputes.map((d) => d.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'tournamentId': tournamentId,
    'fixtureId': fixtureId,
    'isDemo': isDemo,
  };

  factory SportMatch.fromJson(Map<String, dynamic> j) => SportMatch(
    id: j['id'] as String,
    sport: SportX.fromKey(j['sport'] as String? ?? 'cricket'),
    formatLabel: j['formatLabel'] as String? ?? '',
    rules: Map<String, dynamic>.from(j['rules'] as Map? ?? const {}),
    title: j['title'] as String? ?? '',
    venue: j['venue'] as String? ?? '',
    scheduledAt:
        DateTime.tryParse(j['scheduledAt'] as String? ?? '') ?? DateTime.now(),
    visibility: MatchVisibilityX.fromKey(
      j['visibility'] as String? ?? 'public',
    ),
    organizerId: j['organizerId'] as String? ?? '',
    scorerId: j['scorerId'] as String?,
    status: FixtureStatusX.fromKey(j['status'] as String? ?? 'upcoming'),
    sideNames: (j['sideNames'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
    discipline: MatchDisciplineX.fromKey(j['discipline'] as String? ?? 'team'),
    capacity: (j['capacity'] as num?)?.toInt() ?? 10,
    startedAt: DateTime.tryParse(j['startedAt'] as String? ?? ''),
    submittedAt: DateTime.tryParse(j['submittedAt'] as String? ?? ''),
    completedAt: DateTime.tryParse(j['completedAt'] as String? ?? ''),
    publishedAt: DateTime.tryParse(j['publishedAt'] as String? ?? ''),
    pausedAt: DateTime.tryParse(j['pausedAt'] as String? ?? ''),
    pausedBy: j['pausedBy'] as String?,
    pauseReason: j['pauseReason'] as String?,
    eventCount: (j['eventCount'] as num?)?.toInt() ?? 0,
    participants: (j['participants'] as List<dynamic>? ?? const [])
        .map(
          (e) => MatchParticipant.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    events: (j['events'] as List<dynamic>? ?? const [])
        .map((e) => MatchEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    result: j['result'] == null
        ? null
        : OfficialResult.fromJson(
            Map<String, dynamic>.from(j['result'] as Map),
          ),
    corrections: (j['corrections'] as List<dynamic>? ?? const [])
        .map(
          (e) => ResultCorrection.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    disputes: (j['disputes'] as List<dynamic>? ?? const [])
        .map((e) => MatchDispute.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    tournamentId: j['tournamentId'] as String?,
    fixtureId: j['fixtureId'] as String?,
    isDemo: j['isDemo'] as bool? ?? false,
  );
}

/// Who can see a match.
enum MatchVisibility { public, invite }

extension MatchVisibilityX on MatchVisibility {
  String get key => name;
  String get label => switch (this) {
    MatchVisibility.public => 'Public',
    MatchVisibility.invite => 'Invite only',
  };
  String get helper => switch (this) {
    MatchVisibility.public => 'Anyone can find this match',
    MatchVisibility.invite => 'Only invited players can see it',
  };
  static MatchVisibility fromKey(String key) => MatchVisibility.values
      .firstWhere((v) => v.name == key, orElse: () => MatchVisibility.public);
}

/// Team composition. Cricket and futsal are always [team]; the racket sports
/// must declare [singles] or [doubles] because their engines read it.
enum MatchDiscipline { singles, doubles, team }

extension MatchDisciplineX on MatchDiscipline {
  String get key => name;
  String get label => switch (this) {
    MatchDiscipline.singles => 'Singles',
    MatchDiscipline.doubles => 'Doubles',
    MatchDiscipline.team => 'Team',
  };
  static MatchDiscipline fromKey(String key) => MatchDiscipline.values
      .firstWhere((d) => d.name == key, orElse: () => MatchDiscipline.team);

  /// The discipline a sport allows. Racket sports offer singles and doubles,
  /// the team sports only team.
  static List<MatchDiscipline> forSport(Sport sport) => switch (sport) {
    Sport.padel ||
    Sport.badminton => [MatchDiscipline.singles, MatchDiscipline.doubles],
    Sport.cricket || Sport.futsal => [MatchDiscipline.team],
  };
}

enum MatchParticipantStatus { invited, accepted, declined, removed }

extension MatchParticipantStatusX on MatchParticipantStatus {
  String get key => name;
  String get label => switch (this) {
    MatchParticipantStatus.invited => 'Invited',
    MatchParticipantStatus.accepted => 'Joined',
    MatchParticipantStatus.declined => 'Declined',
    MatchParticipantStatus.removed => 'Removed',
  };
  static MatchParticipantStatus fromKey(String key) =>
      MatchParticipantStatus.values.firstWhere(
        (s) => s.name == key,
        orElse: () => MatchParticipantStatus.invited,
      );
}

class MatchParticipant {
  final String profileId;

  /// Denormalised for the roster list so a name never needs a second lookup.
  String displayName;

  /// 0 = side A, 1 = side B.
  int side;
  MatchParticipantStatus status;
  final String? invitedById;
  DateTime? joinedAt;

  MatchParticipant({
    required this.profileId,
    required this.displayName,
    required this.side,
    required this.status,
    this.invitedById,
    this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'displayName': displayName,
    'side': side,
    'status': status.key,
    'invitedById': invitedById,
    'joinedAt': joinedAt?.toIso8601String(),
  };

  factory MatchParticipant.fromJson(Map<String, dynamic> j) => MatchParticipant(
    profileId: j['profileId'] as String? ?? '',
    displayName: j['displayName'] as String? ?? '',
    side: (j['side'] as num?)?.toInt() ?? 0,
    status: MatchParticipantStatusX.fromKey(
      j['status'] as String? ?? 'invited',
    ),
    invitedById: j['invitedById'] as String?,
    joinedAt: DateTime.tryParse(j['joinedAt'] as String? ?? ''),
  );
}

/// One recorded scoring action of a match.
///
/// Mirrors `public.match_events`: [seq] is the server-assigned order, [clientId]
/// is the idempotency key a retried tap reuses, and [voided] marks an undo
/// without ever rewinding the log.
class MatchEvent {
  final String id;
  int seq;
  final String clientId;
  final String kind;
  final int? side;
  final Map<String, dynamic> data;
  final DateTime at;
  final String byAccountId;
  bool voided;

  MatchEvent({
    required this.id,
    required this.seq,
    required this.clientId,
    required this.kind,
    required this.side,
    required this.data,
    required this.at,
    required this.byAccountId,
    this.voided = false,
  });

  /// The shape the sport engines fold, identical to [ScoringEvent.toJson].
  Map<String, dynamic> get scoringJson => {
    'id': id,
    'kind': kind,
    'side': side,
    'data': data,
    'at': at.toIso8601String(),
    'by': byAccountId,
  };

  ScoringEvent toScoringEvent() => ScoringEvent.fromJson(scoringJson);

  Map<String, dynamic> toJson() => {
    'id': id,
    'seq': seq,
    'clientId': clientId,
    'kind': kind,
    'side': side,
    'data': data,
    'at': at.toIso8601String(),
    'by': byAccountId,
    'voided': voided,
  };

  factory MatchEvent.fromJson(Map<String, dynamic> j) => MatchEvent(
    id: j['id'] as String? ?? '',
    seq: (j['seq'] as num?)?.toInt() ?? 0,
    clientId: j['clientId'] as String? ?? '',
    kind: j['kind'] as String? ?? '',
    side: (j['side'] as num?)?.toInt(),
    data: Map<String, dynamic>.from(j['data'] as Map? ?? const {}),
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
    byAccountId: j['by'] as String? ?? '',
    voided: j['voided'] as bool? ?? false,
  );
}

/// How far a dispute over an official result has travelled.
///
/// `open` and `under_review` are both live: the server keeps at most one of
/// them per member per match, and either can be answered. A closed one records
/// how it was closed and can be raised again on new evidence.
enum MatchDisputeStatus { open, underReview, resolved, rejected }

extension MatchDisputeStatusX on MatchDisputeStatus {
  /// The value PostgreSQL stores, with the underscore the check constraint uses.
  String get key => switch (this) {
    MatchDisputeStatus.open => 'open',
    MatchDisputeStatus.underReview => 'under_review',
    MatchDisputeStatus.resolved => 'resolved',
    MatchDisputeStatus.rejected => 'rejected',
  };
  String get label => switch (this) {
    MatchDisputeStatus.open => 'Disputed',
    MatchDisputeStatus.underReview => 'Under review',
    MatchDisputeStatus.resolved => 'Upheld',
    MatchDisputeStatus.rejected => 'Rejected',
  };
  bool get isOpen =>
      this == MatchDisputeStatus.open || this == MatchDisputeStatus.underReview;
  static MatchDisputeStatus fromKey(String key) => MatchDisputeStatus.values
      .firstWhere((s) => s.key == key, orElse: () => MatchDisputeStatus.open);
}

/// One challenge against a match's published result.
///
/// Mirrors `public.match_disputes`. A dispute never pauses, reopens or hides
/// the result: the official row stays published exactly as it is until the
/// organizer corrects it through the normal correction path.
class MatchDispute {
  final String id;
  final String matchId;
  final String raisedById;
  final String reason;
  MatchDisputeStatus status;
  String? resolution;

  /// The organizer who answered it, and when.
  String? resolvedById;
  DateTime? resolvedAt;
  final DateTime raisedAt;

  MatchDispute({
    required this.id,
    required this.matchId,
    required this.raisedById,
    required this.reason,
    required this.status,
    required this.raisedAt,
    this.resolution,
    this.resolvedById,
    this.resolvedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'matchId': matchId,
    'raisedById': raisedById,
    'reason': reason,
    'status': status.key,
    'resolution': resolution,
    'resolvedById': resolvedById,
    'resolvedAt': resolvedAt?.toIso8601String(),
    'raisedAt': raisedAt.toIso8601String(),
  };

  factory MatchDispute.fromJson(Map<String, dynamic> j) => MatchDispute(
    id: j['id'] as String? ?? '',
    matchId: j['matchId'] as String? ?? '',
    raisedById: j['raisedById'] as String? ?? '',
    reason: j['reason'] as String? ?? '',
    status: MatchDisputeStatusX.fromKey(j['status'] as String? ?? 'open'),
    resolution: j['resolution'] as String?,
    resolvedById: j['resolvedById'] as String?,
    resolvedAt: DateTime.tryParse(j['resolvedAt'] as String? ?? ''),
    raisedAt:
        DateTime.tryParse(j['raisedAt'] as String? ?? '') ?? DateTime.now(),
  );

  /// The server row shape, for a repository that reads the table directly.
  factory MatchDispute.fromRow(Map<String, dynamic> row) => MatchDispute(
    id: row['id'] as String? ?? '',
    matchId: row['match_id'] as String? ?? '',
    raisedById: row['raised_by'] as String? ?? '',
    reason: row['reason'] as String? ?? '',
    status: MatchDisputeStatusX.fromKey(row['status'] as String? ?? 'open'),
    resolution: row['resolution'] as String?,
    resolvedById: row['resolved_by'] as String?,
    resolvedAt: DateTime.tryParse(row['resolved_at'] as String? ?? ''),
    raisedAt:
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// Where an official match stands with the server, for the sync banner.
enum MatchSyncState { idle, syncing, offline, failed }

extension MatchSyncStateX on MatchSyncState {
  String get label => switch (this) {
    MatchSyncState.idle => 'Saved',
    MatchSyncState.syncing => 'Syncing',
    MatchSyncState.offline => 'Offline',
    MatchSyncState.failed => 'Not saved',
  };
  bool get isWarning =>
      this == MatchSyncState.offline || this == MatchSyncState.failed;
}

/// The arguments a match is created with. Kept as a value object so the create
/// screen, the local store and the Supabase RPC all take the same shape.
class MatchDraft {
  final Sport sport;
  final String formatLabel;
  final Map<String, dynamic> rules;
  final String title;
  final String venue;
  final DateTime scheduledAt;
  final MatchVisibility visibility;
  final String sideA;
  final String sideB;
  final int capacity;
  final MatchDiscipline discipline;
  final String? scorerId;
  final String? tournamentId;
  final String? fixtureId;

  MatchDraft({
    required this.sport,
    required this.formatLabel,
    required this.rules,
    required this.title,
    required this.venue,
    required this.scheduledAt,
    required this.visibility,
    required this.sideA,
    required this.sideB,
    required this.capacity,
    required this.discipline,
    this.scorerId,
    this.tournamentId,
    this.fixtureId,
  });
}
