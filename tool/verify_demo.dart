import 'dart:io';

import 'package:sportika/shared/data/seed.dart';
import 'package:sportika/shared/models/community_game.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';

void main() {
  final world = buildSeed();
  assert(world.accounts.where((a) => a.has(UserRole.player)).length >= 20);
  assert(world.squads.length == 10);
  assert(world.tournaments.length == 8);
  assert(world.personal.length == 10);
  assert(world.notifications.length == 15);
  assert(
    world.fixtures.where((f) => f.status == FixtureStatus.live).length == 8,
  );
  assert(
    world.fixtures.where((f) => f.status == FixtureStatus.published).length ==
        12,
  );
  assert(
    world.fixtures.map((f) => f.id).toSet().length == world.fixtures.length,
  );
  final games = seedCommunityGames();
  assert(games.length == 24);
  for (final game in games) {
    assert(game.members.length <= game.capacity);
    assert(CommunityGame.fromJson(game.toJson()).title == game.title);
  }
  for (final match in world.personal) {
    SportEngines.progressOf(
      sport: match.sport,
      sides: match.sideNames,
      rules: match.rules,
      rawEvents: match.events,
    );
  }
  stdout.writeln(
    'PASS: seed counts, community game serialization/capacities, and all personal scoring replays',
  );
  stdout.writeln(
    'Official fixtures: ${world.fixtures.length}; live: ${world.fixtures.where((f) => f.status == FixtureStatus.live).length}; results: ${world.fixtures.where((f) => f.status == FixtureStatus.published).length}',
  );
}
