import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/core/data/repositories.dart';

/// Community pickup games: the list, publishing and join/leave.
class GamesController extends FeatureController<GameRepository> {
  GamesController(super.repo);

  /// True while the server read is in flight.
  bool get loading => repo.loading;

  /// Why the last read failed, or null while it is healthy.
  String? get lastError => repo.lastError;

  /// Re-reads the coming week of games.
  Future<void> refresh() => repo.refresh();

  List<CommunityGame> get games => repo.games;

  void publishGame(CommunityGame game) => repo.publishGame(game);

  void toggleGameJoin(CommunityGame game) => repo.toggleGameJoin(game);
}
