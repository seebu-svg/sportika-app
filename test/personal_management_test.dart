import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';

void main() {
  test(
    'paused cards reject scoring and private metadata survives serialization',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = LocalSportikaRepository(await LocalStorage.open());
      await state.load();
      // Same demo sign-in entry point used by the application.
      await state.signIn(state.accounts.first.id);
      final m = state.startPersonalMatch(
        sport: Sport.badminton,
        format: SportEngines.formatsFor(Sport.badminton).first,
        sideA: 'A',
        sideB: 'B',
      );
      state.updatePersonalDetails(m.id, {
        'venue': 'Court 1',
        'confirmUndo': false,
      });
      state.setPersonalStatus(m.id, PersonalMatchStatus.paused);
      final action = state.progressOfPersonal(m).actions.first;
      final event = action.build(
        ActionContext(side: 0, by: state.currentAccount!.id),
      );
      state.recordPersonalEvent(m.id, event);
      expect(m.events, isEmpty);
      final restored = PersonalMatch.fromJson(m.toJson());
      expect(restored.status, PersonalMatchStatus.paused);
      expect(restored.details['venue'], 'Court 1');
      state.setPersonalStatus(m.id, PersonalMatchStatus.inProgress);
      state.recordPersonalEvent(m.id, event);
      expect(m.events.length, 1);
      state.setPersonalStatus(m.id, PersonalMatchStatus.paused);
      state.undoPersonalEvent(m.id);
      expect(m.status, PersonalMatchStatus.paused);
      expect(m.events, isEmpty);
      state.dispose();
    },
  );
}
