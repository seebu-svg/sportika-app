import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/core/data/repositories.dart';

/// Session, identity and account-directory reads and writes.
class SessionController extends FeatureController<SessionRepository> {
  SessionController(super.repo);

  bool get ready => repo.ready;
  bool get onboardingSeen => repo.onboardingSeen;
  bool get isSignedIn => repo.isSignedIn;
  Account? get currentAccount => repo.currentAccount;
  List<Account> get accounts => repo.accounts;

  bool hasRole(UserRole role) => repo.hasRole(role);
  bool get canOrganize => repo.canOrganize;
  Account? accountById(String? id) => repo.accountById(id);
  Account? accountByEmail(String email) => repo.accountByEmail(email);

  Future<void> signIn(String accountId) => repo.signIn(accountId);
  Future<void> signOut() => repo.signOut();
  Future<void> markOnboardingSeen() => repo.markOnboardingSeen();
  Future<void> resetDemoData() => repo.resetDemoData();

  Future<Account> createAccount({
    required String displayName,
    required String email,
    required String city,
    required AccountIntent intent,
  }) => repo.createAccount(
    displayName: displayName,
    email: email,
    city: city,
    intent: intent,
  );

  Future<void> completeProfileSetup({
    required String displayName,
    required String handle,
    required String bio,
    required String city,
    required Set<Sport> sports,
    required Map<String, PlayingLevel> levels,
    required PlayStyle playStyle,
    required String avatar,
  }) => repo.completeProfileSetup(
    displayName: displayName,
    handle: handle,
    bio: bio,
    city: city,
    sports: sports,
    levels: levels,
    playStyle: playStyle,
    avatar: avatar,
  );
}

/// Profile statistics and identity edits for the signed-in account.
class ProfileController extends FeatureController<ProfileRepository> {
  ProfileController(super.repo);

  Account? get currentAccount => repo.currentAccount;

  Future<void> updateProfile({
    String? displayName,
    String? city,
    String? email,
  }) => repo.updateProfile(displayName: displayName, city: city, email: email);

  /// Sports an account has real exposure to: official fixtures plus teams.
  List<Sport> sportsPlayedBy(String accountId) =>
      repo.sportsPlayedBy(accountId);

  /// Official fixtures the given account has appeared in.
  List<Fixture> appearancesOf(String accountId) =>
      repo.appearancesOf(accountId);

  List<Fixture> officialMatchesPlayed() => repo.officialMatchesPlayed();
}

/// Per-account demo switches (reminders, invitations, visibility).
class PreferencesController extends FeatureController<PreferencesRepository> {
  PreferencesController(super.repo);

  Map<String, bool> get preferences => repo.preferences;

  bool preference(String key, {bool fallback = true}) =>
      repo.preference(key, fallback: fallback);

  void setPreference(String key, bool value) => repo.setPreference(key, value);
}

/// Notifications for the signed-in account.
class NotificationsController
    extends FeatureController<NotificationRepository> {
  NotificationsController(super.repo);

  List<AppNotification> get myNotifications => repo.myNotifications;
  int get unreadCount => repo.unreadCount;

  void markNotificationRead(String id) => repo.markNotificationRead(id);
  void markAllNotificationsRead() => repo.markAllNotificationsRead();
}
