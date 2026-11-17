import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/core/state/fixtures_controller.dart';
import 'package:sportika/features/auth/services/mock_authentication_service.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/features/personal_games/scoring/scoring_service.dart';
import 'package:sportika/features/profile/screens/profile_tab.dart';
import 'package:provider/provider.dart';

import 'helpers/harness.dart';

void main() {
  test(
    'every member creates tournaments; management follows ownership',
    () async {
      final state = await freshState();
      addTearDown(state.dispose);
      await state.signIn(
        'acc-zain',
      ); // Legacy player only, without scorer role.
      expect(state.canOrganize, isTrue);
      final rules = SportEngines.rulesFor(
        Sport.padel,
        SportEngines.formatsFor(Sport.padel).first,
      );
      await state.createTournament(
        name: 'Clifton Community Padel',
        city: 'Karachi',
        sport: Sport.padel,
        format: TournamentFormat.knockout,
        entryType: EntryType.pair,
        startsAt: DateTime(2026, 12, 1),
        endsAt: DateTime(2026, 12, 2),
        registrationLimit: 8,
        entryFee: 'Free',
        rulesSummary: 'Best of three sets',
        rules: rules,
        publishNow: false,
      );
      final tournament = state.tournaments.first;
      expect(tournament.organizerId, 'acc-zain');
      state.setTournamentStatus(tournament.id, TournamentStatus.open);
      expect(tournament.status, TournamentStatus.open);
      await state.signIn('acc-seebu');
      state.setTournamentStatus(tournament.id, TournamentStatus.draft);
      expect(tournament.status, TournamentStatus.open);
      expect(await state.generateDraw(tournament.id), 0);
    },
  );

  test('assignment alone grants scoring and owner alone assigns', () async {
    final state = await freshState();
    addTearDown(state.dispose);
    final fixture = state.fixtures.firstWhere(
      (f) => f.status == FixtureStatus.upcoming,
    );
    final owner = state.tournamentById(fixture.tournamentId)!.organizerId;
    await state.signIn(owner);
    state.assignScorer(fixture.id, 'acc-zain');
    await state.signIn('acc-zain');
    state.assignScorer(fixture.id, 'acc-sana');
    expect(fixture.scorerAccountIds, isNot(contains('acc-sana')));
    state.startOfficialScoring(fixture.id);
    expect(fixture.status, FixtureStatus.live);
    state.submitOfficialResult(fixture.id);
    expect(fixture.status, FixtureStatus.submitted);
    state.publishOfficialResult(fixture.id);
    expect(fixture.status, FixtureStatus.submitted);
    await state.signIn(owner);
    state.publishOfficialResult(fixture.id);
    expect(fixture.status, FixtureStatus.published);
  });

  test(
    'demo registration, restoration, recovery and logout stay local',
    () async {
      final state = await freshState();
      addTearDown(state.dispose);
      final mock = MockAuthenticationService(state);
      addTearDown(mock.dispose);
      final challenge = await mock.register(
        name: 'Ayesha Khan',
        email: 'ayesha@example.com',
        password: 'DemoPassword9!',
        intent: AccountIntent.player,
        acceptedTerms: true,
      );
      final session = await mock.verifyEmail(
        challengeId: challenge.id,
        code: '123456',
      );
      expect(state.accountById(session.accountId)!.displayName, 'Ayesha Khan');
      expect((await mock.restoreSession())!.accountId, session.accountId);
      final reset = await mock.requestPasswordReset(
        email: 'ayesha@example.com',
      );
      await mock.resetPassword(
        challengeId: reset.id,
        code: '654321',
        password: 'ChangedDemo9!',
      );
      expect(mock.session, isNull);
      expect(
        (await mock.signIn(
          email: 'ayesha@example.com',
          password: 'ChangedDemo9!',
        )).accountId,
        session.accountId,
      );
      await mock.signOut();
      await state.signOut();
      expect(await mock.restoreSession(), isNull);
    },
  );

  testWidgets('local demo login exposes universal tools without role badges', (
    tester,
  ) async {
    final state = await freshState();
    final mock = MockAuthenticationService(state);
    addTearDown(mock.dispose);
    await pumpApp(
      tester,
      state: state,
      authenticationService: mock,
      size: const Size(320, 844),
      textScale: 1.3,
    );
    final context = tester.element(find.byType(MaterialApp));
    final flow = context.read<AuthFlowController>();
    flow.openSignIn();
    flow.email = 'zain@sportika.pk';
    flow.password = 'Sportika9!';
    await flow.submitSignIn();
    await tester.pumpAndSettle();
    expect(context.read<FixturesController>().myScoringFixtures, isEmpty);
    await tester.tap(find.byType(NavigationDestination).at(4));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileTab), findsOneWidget);
    await tester.scrollUntilVisible(find.text('My tournaments'), 250);
    expect(find.text('My tournaments'), findsOneWidget);
    expect(find.text('Player'), findsNothing);
    expect(find.text('Organizer'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
