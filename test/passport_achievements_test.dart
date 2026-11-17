import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/features/profile/widgets/achievements.dart';
import 'package:sportika/shared/models/enums.dart';

void main() {
  group('achievementsFrom', () {
    test('drops personal scoring and keeps seven provable milestones', () {
      final list = achievementsFrom(
        official: const [],
        wins: 0,
        squadsLed: 0,
        tournamentsEntered: 0,
        sports: const {},
      );

      expect(list, hasLength(7));
      expect(list.map((a) => a.title), isNot(contains('Keep your own score')));
      // Nothing can be proved from an empty record, so every medal is locked.
      expect(list.every((a) => !a.unlocked), isTrue);
    });

    test('marks a milestone earned strictly from the real count', () {
      final list = achievementsFrom(
        official: const [],
        wins: 3,
        squadsLed: 1,
        tournamentsEntered: 2,
        sports: {Sport.cricket, Sport.padel, Sport.futsal},
      );
      Achievement byKind(MedalKind kind) =>
          list.firstWhere((a) => a.kind == kind);

      // No official matches played, so appearance medals stay locked even
      // though wins, squads, entries and sports all clear their bars.
      expect(byKind(MedalKind.firstWhistle).unlocked, isFalse);
      expect(byKind(MedalKind.seasonRegular).unlocked, isFalse);
      expect(byKind(MedalKind.firstVictory).unlocked, isTrue);
      expect(byKind(MedalKind.hatTrick).unlocked, isTrue);
      expect(byKind(MedalKind.hatTrick).progress, 1.0);
      expect(byKind(MedalKind.squadBuilder).unlocked, isTrue);
      expect(byKind(MedalKind.entryList).unlocked, isTrue);
      expect(byKind(MedalKind.multiSport).unlocked, isTrue);
    });

    test('progress clamps and the label pluralizes from real counts', () {
      final list = achievementsFrom(
        official: const [],
        wins: 2,
        squadsLed: 0,
        tournamentsEntered: 0,
        sports: {Sport.cricket},
      );
      Achievement byKind(MedalKind kind) =>
          list.firstWhere((a) => a.kind == kind);

      expect(byKind(MedalKind.hatTrick).progress, closeTo(2 / 3, 1e-9));
      expect(byKind(MedalKind.hatTrick).progressLabel, '2 of 3 wins');
      expect(byKind(MedalKind.multiSport).progressLabel, '1 of 3 sports');
      expect(
        byKind(MedalKind.firstWhistle).progressLabel,
        '0 of 1 official match',
      );
    });
  });

  group('nextAchievement', () {
    Achievement make(MedalKind kind, int current, int target, String unit) =>
        Achievement(
          title: kind.name,
          description: '',
          kind: kind,
          current: current,
          target: target,
          unit: unit,
          unlocked: current >= target,
        );

    test('returns null once every milestone is earned', () {
      final list = [
        make(MedalKind.firstWhistle, 1, 1, 'official match'),
        make(MedalKind.hatTrick, 3, 3, 'win'),
      ];
      expect(nextAchievement(list), isNull);
    });

    test('picks the locked milestone closest to completion', () {
      final list = [
        make(MedalKind.firstWhistle, 0, 1, 'official match'),
        make(MedalKind.hatTrick, 2, 3, 'win'),
        make(MedalKind.multiSport, 1, 3, 'sport'),
      ];
      expect(nextAchievement(list)!.kind, MedalKind.hatTrick);
    });

    test('breaks a progress tie toward the smaller target', () {
      final list = [
        make(MedalKind.multiSport, 2, 4, 'sport'),
        make(MedalKind.hatTrick, 1, 2, 'win'),
      ];
      expect(nextAchievement(list)!.kind, MedalKind.hatTrick);
    });
  });
}
