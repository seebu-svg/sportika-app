import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/core/state/games_controller.dart';
import 'package:sportika/core/state/personal_games_controller.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/state/teams_controller.dart';
import 'package:sportika/core/state/tournaments_controller.dart';

/// Wires the repository into one controller per feature.
///
/// This is the single place a remote repository would be swapped in: replace
/// [LocalSportikaRepository] with an API-backed implementation and every
/// controller keeps working unchanged.
Widget buildAppProviders({
  required LocalSportikaRepository repository,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocalSportikaRepository>.value(value: repository),
      ChangeNotifierProvider(create: (_) => SessionController(repository)),
      ChangeNotifierProvider(create: (_) => ProfileController(repository)),
      ChangeNotifierProvider(create: (_) => PreferencesController(repository)),
      ChangeNotifierProvider(
        create: (_) => NotificationsController(repository),
      ),
      ChangeNotifierProvider(create: (_) => GamesController(repository)),
      ChangeNotifierProvider(
        create: (_) => TournamentsController(repository),
      ),
      ChangeNotifierProvider(create: (_) => FixturesController(repository)),
      ChangeNotifierProvider(create: (_) => TeamsController(repository)),
      ChangeNotifierProvider(
        create: (_) => PersonalGamesController(repository),
      ),
    ],
    child: child,
  );
}
