import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/data/composite_notification_repository.dart';
import 'package:sportika/core/data/image_picker_photo_picker.dart';
import 'package:sportika/core/data/local_profile_module_repository.dart';
import 'package:sportika/core/data/local_profile_photo_store.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/profile_photo_service.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/match_controller.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/core/state/profile_photo_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';

/// Wires one persisted store into one controller per feature.
///
/// This is the single seam for a remote backend. The store is published under
/// each of the nine narrow [SportikaRepository] interfaces, so replacing
/// [LocalSportikaRepository] with an API-backed implementation only changes
/// this function — no controller and no screen knows the difference.
///
/// [accountRepository] is the one exception: identity and profile come from the
/// server while games, teams and scorecards stay on the device, so the two
/// account surfaces are published from it instead. Everything else keeps the
/// device store, and demo builds pass nothing at all.
///
/// The interfaces are [Listenable] because controllers subscribe to them for
/// change notifications; that is why they are published with
/// [ListenableProvider] rather than [Provider].
///
/// [photoService] is a test seam: widget and unit tests hand in a service over a
/// temporary directory and a fake picker so the whole picture flow runs without
/// a camera.
Widget buildAppProviders({
  required LocalSportikaRepository repository,
  AccountRepository? accountRepository,
  ProfileModuleRepository? profileModuleRepository,
  MatchRepository? matchRepository,
  TournamentRepository? tournamentRepository,
  FixtureRepository? fixtureRepository,
  GameRepository? gameRepository,
  TeamRepository? teamRepository,
  NotificationRepository? notificationRepository,
  ProfilePhotoService? photoService,
  required Widget child,
}) {
  final SessionRepository session = accountRepository ?? repository;
  final ProfileRepository profile = accountRepository ?? repository;
  final PreferencesRepository preferences = accountRepository ?? repository;
  // Official matches live on the server once identity does, while tournaments,
  // personal scorecards and pickup games stay in the device document.
  final MatchRepository matches = matchRepository ?? repository;
  // The discovery modules: a live build reads all four from PostgreSQL, which
  // is what makes the same controllers (and therefore Home) show server rows
  // without a single screen change.
  final TournamentRepository tournaments = tournamentRepository ?? repository;
  final FixtureRepository fixtures = fixtureRepository ?? repository;
  final GameRepository games = gameRepository ?? repository;
  final TeamRepository teams = teamRepository ?? repository;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocalSportikaRepository>.value(value: repository),
      ListenableProvider<SessionRepository>.value(value: session),
      ListenableProvider<ProfileRepository>.value(value: profile),
      ListenableProvider<PreferencesRepository>.value(value: preferences),
      // A live build reads the inbox from PostgreSQL, but teams, tournaments,
      // fixtures and pickup games still live in the device document, so the
      // centre is handed a composite that merges both sources. A demo build
      // keeps the plain device inbox. The composite is disposed here; its two
      // sources are owned by whoever injected them and are left alone.
      ListenableProvider<NotificationRepository>(
        create: (_) => notificationRepository == null
            ? repository
            : CompositeNotificationRepository(
                server: notificationRepository,
                device: repository,
              ),
        dispose: (_, inbox) {
          if (inbox is CompositeNotificationRepository) inbox.dispose();
        },
      ),
      ListenableProvider<GameRepository>.value(value: games),
      ListenableProvider<TournamentRepository>.value(value: tournaments),
      ListenableProvider<FixtureRepository>.value(value: fixtures),
      ListenableProvider<TeamRepository>.value(value: teams),
      ListenableProvider<PersonalGamesRepository>.value(value: repository),
      ListenableProvider<MatchRepository>.value(value: matches),
      ListenableProvider<ProfileModuleRepository>(
        create: (_) =>
            profileModuleRepository ?? LocalProfileModuleRepository(repository),
        dispose: (_, module) {
          // Only the fallback adapter is owned here; an injected repository is
          // owned by whoever built it.
          if (profileModuleRepository == null && module is ChangeNotifier) {
            (module as ChangeNotifier).dispose();
          }
        },
      ),
      ChangeNotifierProvider(
        create: (context) =>
            SessionController(context.read<SessionRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) =>
            ProfileController(context.read<ProfileRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) =>
            PreferencesController(context.read<PreferencesRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) =>
            NotificationsController(context.read<NotificationRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) => GamesController(context.read<GameRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) =>
            TournamentsController(context.read<TournamentRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) =>
            FixturesController(context.read<FixtureRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) => TeamsController(context.read<TeamRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) =>
            PersonalGamesController(context.read<PersonalGamesRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) => MatchController(context.read<MatchRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) =>
            ProfileModuleController(context.read<ProfileModuleRepository>()),
      ),
      ChangeNotifierProvider(
        create: (context) => ProfilePhotoController(
          context.read<ProfileRepository>(),
          service:
              photoService ??
              buildLocalProfilePhotoService(context.read<ProfileRepository>()),
        ),
      ),
    ],
    child: child,
  );
}

/// The production wiring of the picture pipeline: system picker, on-device file
/// store, and the account reference moved through [ProfileRepository].
///
/// This is the one place that knows a photo lives on the device. When Sportika
/// gains an upload endpoint, swapping [LocalProfilePhotoStore] for an API-backed
/// store happens here and no controller or screen changes.
ProfilePhotoService buildLocalProfilePhotoService(ProfileRepository repo) {
  return ProfilePhotoService(
    picker: ImagePickerPhotoPicker(),
    store: LocalProfilePhotoStore(),
    accountId: () => repo.currentAccount?.id,
    currentPath: () => repo.currentAccount?.photoPath,
    persist: repo.setProfilePhoto,
  );
}
