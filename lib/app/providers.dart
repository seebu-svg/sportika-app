import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
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
/// The interfaces are [Listenable] because controllers subscribe to them for
/// change notifications; that is why they are published with
/// [ListenableProvider] rather than [Provider].
Widget buildAppProviders({
  required LocalSportikaRepository repository,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocalSportikaRepository>.value(value: repository),
      ListenableProvider<SessionRepository>.value(value: repository),
      ListenableProvider<ProfileRepository>.value(value: repository),
      ListenableProvider<PreferencesRepository>.value(value: repository),
      ListenableProvider<NotificationRepository>.value(value: repository),
      ListenableProvider<GameRepository>.value(value: repository),
      ListenableProvider<TournamentRepository>.value(value: repository),
      ListenableProvider<FixtureRepository>.value(value: repository),
      ListenableProvider<TeamRepository>.value(value: repository),
      ListenableProvider<PersonalGamesRepository>.value(value: repository),
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
    ],
    child: child,
  );
}
