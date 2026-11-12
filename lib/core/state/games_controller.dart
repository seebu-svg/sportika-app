import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/community_game.dart';

/// Community pickup games: the list, publishing and join/leave.
class GamesController extends FeatureController {
  GamesController(super.repo);

  List<CommunityGame> get games => repo.games;

  void publishGame(CommunityGame game) => repo.publishGame(game);

  void toggleGameJoin(CommunityGame game) => repo.toggleGameJoin(game);
}
