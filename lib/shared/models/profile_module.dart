import 'package:flutter/foundation.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_setup.dart';

/// One member's own profile card, read straight from `profiles` +
/// `profiles_private`.
///
/// [Account] stays the app-wide view model; this is the narrower shape the
/// profile module edits section by section, so a save can never rewrite a field
/// the member did not touch.
@immutable
class ProfilePersonalInformation {
  const ProfilePersonalInformation({
    required this.displayName,
    required this.username,
    required this.city,
    required this.bio,
    required this.dateOfBirth,
    required this.gender,
    required this.playStyle,
    required this.avatarPreset,
    required this.avatarUrl,
    required this.setupComplete,
  });

  final String displayName;
  final String username;
  final String city;
  final String bio;
  final DateTime? dateOfBirth;
  final ProfileGender? gender;
  final PlayStyle playStyle;
  final String avatarPreset;
  final String? avatarUrl;
  final bool setupComplete;
}

/// One preferred sport and the optional level and position claimed for it.
@immutable
class ProfileSportPreference {
  const ProfileSportPreference(this.sport, {this.level, this.position});

  final Sport sport;
  final PlayingLevel? level;
  final String? position;

  /// Wire shape accepted by `replace_profile_sports`. An empty level stays null
  /// so "I declined to rank my sports" survives the round trip.
  Map<String, dynamic> toRow() => <String, dynamic>{
    'sport_key': sport.key,
    'level': level?.key,
    'position': position,
  };
}

/// A laterality choice for a physical attribute. The three values mirror the
/// `dominant_hand` / `dominant_foot` check constraint in `profiles_private`.
enum ProfileSide { left, right, ambidextrous }

extension ProfileSideX on ProfileSide {
  String get label => switch (this) {
    ProfileSide.left => 'Left',
    ProfileSide.right => 'Right',
    ProfileSide.ambidextrous => 'Either',
  };

  /// Wire value stored in PostgreSQL.
  String get key => name;

  static ProfileSide? fromKey(String? key) {
    if (key == null || key.isEmpty) return null;
    return ProfileSide.values.where((s) => s.name == key).firstOrNull;
  }
}

/// The optional physical attributes and preferred jersey number a member keeps
/// on their own athlete profile. Every field is nullable: an untouched profile
/// stays untouched, and a save never invents a value the member did not give.
@immutable
class ProfileAthleteDetails {
  const ProfileAthleteDetails({
    this.heightCm,
    this.weightKg,
    this.dominantHand,
    this.dominantFoot,
    this.preferredJersey,
  });

  final int? heightCm;
  final double? weightKg;
  final ProfileSide? dominantHand;
  final ProfileSide? dominantFoot;
  final int? preferredJersey;

  /// A profile that has not filled any athlete field yet. The screen uses this
  /// to decide whether to show the empty prompt instead of fabricated numbers.
  bool get isEmpty =>
      heightCm == null &&
      weightKg == null &&
      dominantHand == null &&
      dominantFoot == null &&
      preferredJersey == null;

  static const ProfileAthleteDetails empty = ProfileAthleteDetails();
}

/// The optional CNIC / B-Form submission. It is never a verification claim.
@immutable
class ProfileIdentityRecord {
  const ProfileIdentityRecord({
    required this.kind,
    required this.submittedAt,
    this.number,
    this.hasFront = false,
    this.hasBack = false,
  });

  final IdentityDocumentKind kind;
  final DateTime submittedAt;
  final String? number;
  final bool hasFront;
  final bool hasBack;

  /// The full number never leaves the owner's device; the UI shows the tail.
  String get maskedNumber {
    final value = number ?? '';
    if (value.length < 4) return value;
    return '•••••••••${value.substring(value.length - 4)}';
  }
}

/// Everything one refresh of the profile module reads.
@immutable
class ProfileModuleSnapshot {
  const ProfileModuleSnapshot({
    required this.personal,
    required this.sports,
    this.identity,
    this.athlete,
  });

  final ProfilePersonalInformation personal;
  final List<ProfileSportPreference> sports;
  final ProfileIdentityRecord? identity;

  /// The athlete attributes section. Null means this build could not read them
  /// (for example a backend that predates the columns); the screen then keeps
  /// the section as an honest placeholder rather than showing an editable form.
  final ProfileAthleteDetails? athlete;

  /// No level anywhere is what the skipped preferences step looks like after a
  /// round trip.
  bool get preferencesSkipped =>
      sports.isNotEmpty && sports.every((s) => s.level == null);
}

enum ScorerAssignmentStatus { assigned, accepted, declined, revoked }

extension ScorerAssignmentStatusX on ScorerAssignmentStatus {
  String get label => switch (this) {
    ScorerAssignmentStatus.assigned => 'Awaiting reply',
    ScorerAssignmentStatus.accepted => 'Accepted',
    ScorerAssignmentStatus.declined => 'Declined',
    ScorerAssignmentStatus.revoked => 'Revoked',
  };

  bool get isActive =>
      this == ScorerAssignmentStatus.assigned ||
      this == ScorerAssignmentStatus.accepted;

  static ScorerAssignmentStatus fromKey(String? key) =>
      ScorerAssignmentStatus.values.firstWhere(
        (s) => s.name == key,
        orElse: () => ScorerAssignmentStatus.assigned,
      );
}

/// An official match handed to a scorer by the match or tournament organizer.
@immutable
class ScorerAssignment {
  const ScorerAssignment({
    required this.id,
    required this.tournamentId,
    required this.fixtureId,
    required this.scorerId,
    required this.authorizedBy,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String tournamentId;
  final String fixtureId;
  final String scorerId;

  /// The organizer whose session created the assignment. The database refuses
  /// any write that is not authorised by this profile.
  final String authorizedBy;
  final ScorerAssignmentStatus status;
  final DateTime createdAt;

  factory ScorerAssignment.fromRow(Map<String, dynamic> row) =>
      ScorerAssignment(
        id: row['id'] as String,
        tournamentId: row['tournament_id'] as String,
        fixtureId: row['fixture_id'] as String,
        scorerId: row['scorer_profile_id'] as String,
        authorizedBy: row['authorized_by'] as String,
        status: ScorerAssignmentStatusX.fromKey(row['status'] as String?),
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// A public member card, used when an organizer picks a scorer.
@immutable
class ProfileSummary {
  const ProfileSummary({
    required this.id,
    required this.displayName,
    required this.username,
    this.city = '',
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String username;
  final String city;
  final String? avatarUrl;

  String get label =>
      displayName.trim().isEmpty ? '@$username' : displayName.trim();

  factory ProfileSummary.fromRow(Map<String, dynamic> row) => ProfileSummary(
    id: row['id'] as String,
    displayName: row['display_name'] as String? ?? '',
    username: row['username'] as String? ?? '',
    city: row['city'] as String? ?? '',
    avatarUrl: row['avatar_url'] as String?,
  );
}

/// A user-facing failure from the profile module. The message is safe to show:
/// it never carries a submitted identity value or a transport dump.
class ProfileModuleException implements Exception {
  const ProfileModuleException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
