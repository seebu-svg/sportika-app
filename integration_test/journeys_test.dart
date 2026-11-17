import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/features/profile/screens/personal_information_screen.dart';
import 'package:sportika/features/profile/screens/sports_preferences_screen.dart';
import 'package:sportika/shared/models/enums.dart';

import '../test/helpers/harness.dart';
import '../test/helpers/auth_service_fixture.dart';

/// The three journeys the plan promises, driven through the real app object
/// graph (repository → controllers → widgets) rather than mocks.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('journey 1: first run lands on the five-tab shell', (
    tester,
  ) async {
    // No stored session and no onboarding flag: the splash, the intro and the
    // sign-in gate all have to resolve before Home exists.
    await pumpApp(tester, state: await freshState(onboardingSeen: false));

    await tapVisible(tester, find.text('SKIP'));
    await tapVisible(tester, find.text('SIGN IN'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final email = authFlow(tester);
    // The seeded directory supplies the address; credentials are checked by
    // the injected test-only service, never by the production local store.
    final repo = tester
        .element(find.byType(MaterialApp))
        .read<LocalSportikaRepository>();
    email.email = repo.accountById('acc-seebu')!.email;
    email.password = AuthServiceFixture.validPassword;
    await email.submitSignIn();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // The shell is the proof that the whole pre-auth chain completed.
    for (final tab in ['Home', 'Discover', 'Live', 'Team', 'Me']) {
      expect(find.text(tab), findsWidgets, reason: 'shell is missing $tab');
    }
    expect(find.text('Your sports'), findsOneWidget);
  });

  testWidgets('journey 2: a player joins a community game', (tester) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    await pumpApp(tester, state: state);

    openTab(tester, 'Discover');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Games').first);
    await tester.pumpAndSettle();

    final games = state.games.where((g) => !g.members.contains('acc-seebu'));
    expect(games, isNotEmpty, reason: 'seed has no open game to join');
    final game = games.first;

    await scrollTo(tester, find.text(game.title).first);
    await tapVisible(tester, find.text(game.title).first);
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Join match').first);
    await tapVisible(tester, find.text('Join match').first);

    // The membership is persisted, not just painted.
    expect(
      state.games.firstWhere((g) => g.id == game.id).members,
      contains('acc-seebu'),
    );
    expect(find.text('Joined'), findsWidgets);
  });

  testWidgets('journey 3: a scorer submits and the organizer publishes', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    // Boot the shell so the real widgets are mounted over this same store.
    await pumpApp(tester, state: state);

    final fixture = state.myScoringFixtures.firstWhere(
      (f) =>
          f.status == FixtureStatus.upcoming || f.status == FixtureStatus.live,
    );
    final tournament = state.tournamentById(fixture.tournamentId)!;
    final before = standingsFingerprint(state, tournament.id);

    // The scorer records one action built by the engine that owns this sport,
    // so the event log is exactly what the scorecard would append.
    state.startOfficialScoring(fixture.id);
    expect(state.fixtureById(fixture.id)!.status, FixtureStatus.live);

    final progress = state.progressOfFixture(state.fixtureById(fixture.id)!);
    final action = progress.actions.firstWhere(
      (a) => a.style == ActionStyle.primary,
    );
    state.recordOfficialEvent(
      fixture.id,
      action.build(const ActionContext(side: 0, by: 'acc-seebu')),
    );
    expect(state.fixtureById(fixture.id)!.events, isNotEmpty);

    state.submitOfficialResult(fixture.id);
    expect(
      state.fixtureById(fixture.id)!.status,
      FixtureStatus.submitted,
      reason: 'a submitted card must wait for the organizer',
    );
    expect(
      standingsFingerprint(state, tournament.id),
      before,
      reason: 'a submitted card must not move the table yet',
    );

    // The organizer signs in on the same device and publishes the result.
    await state.signIn(tournament.organizerId);
    await tester.pumpAndSettle();
    expect(state.canOrganize, isTrue);

    state.publishOfficialResult(fixture.id);
    expect(state.fixtureById(fixture.id)!.status, FixtureStatus.published);
    expect(
      standingsFingerprint(state, tournament.id),
      isNot(before),
      reason: 'publishing has to move the table',
    );
  });

  testWidgets('journey 4: the Me module edits the one account record', (
    tester,
  ) async {
    final state = await freshState();
    await state.signIn('acc-seebu');
    await pumpApp(tester, state: state);
    final me = state.currentAccount!;

    openTab(tester, 'Me');
    await tester.pumpAndSettle();

    // Personal information: the card and the stored account move together.
    await scrollTo(tester, find.text('Personal information'));
    await tapVisible(tester, find.text('Personal information'));
    expect(find.byType(PersonalInformationScreen), findsOneWidget);

    await scrollTo(tester, find.text('Save changes'));
    await tester.enterText(profileField('City'), 'Hyderabad');
    await tapVisible(tester, find.text('Save changes'));
    expect(find.text('Personal information saved'), findsWidgets);
    expect(state.currentAccount!.city, 'Hyderabad');
    expect(state.currentAccount!.id, me.id);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // Sports preferences: the selection is persisted, not just painted.
    await scrollTo(tester, find.text('Sports preferences'));
    await tapVisible(tester, find.text('Sports preferences'));
    expect(find.byType(SportsPreferencesScreen), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(AuthChoicePill, 'Badminton'));
    await tapVisible(tester, find.text('Save sports'));
    expect(state.currentAccount!.sports, contains(Sport.badminton));

    await tester.pageBack();
    await tester.pumpAndSettle();

    // Identity documents stay optional, and a device build says where they
    // would live instead of pretending to upload them.
    await scrollTo(tester, find.text('Identity documents'));
    await tapVisible(tester, find.text('Identity documents'));
    expect(
      find.textContaining('identity documents are deliberately never written'),
      findsOneWidget,
    );
  });
}

/// The [TextField] behind a labelled [AuthField]. The label is upper-cased.
Finder profileField(String label) => find.descendant(
  of: find
      .ancestor(
        of: find.text(label.toUpperCase()),
        matching: find.byType(AuthField),
      )
      .first,
  matching: find.byType(TextField),
);

/// Taps a bottom-navigation destination by label.
void openTab(WidgetTester tester, String label) {
  final destination = find.byTooltip(label);
  if (destination.evaluate().isNotEmpty) {
    tester.tap(destination.first);
    return;
  }
  tester.tap(find.text(label).last);
}

/// Scrolls the nearest vertical scrollable until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

/// A comparable snapshot of a tournament table.
String standingsFingerprint(
  LocalSportikaRepository state,
  String tournamentId,
) {
  final tournament = state.tournamentById(tournamentId)!;
  return state
      .standingsFor(tournament)
      .map(
        (row) =>
            '${row.entryId}:${row.played}:${row.won}:'
            '${row.drawn}:${row.lost}:${row.points}',
      )
      .join('|');
}
