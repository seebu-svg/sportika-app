import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/features/auth/services/mock_authentication_service.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/features/profile/screens/identity_documents_screen.dart';
import 'package:sportika/features/profile/screens/personal_information_screen.dart';
import 'package:sportika/features/profile/screens/profile_tab.dart';
import 'package:sportika/features/profile/screens/scorer_assignments_screen.dart';
import 'package:sportika/features/profile/screens/sports_preferences_screen.dart';
import 'package:sportika/features/profile/screens/team_memberships_screen.dart';
import 'package:sportika/features/profile/screens/tournament_history_screen.dart';
import 'package:sportika/features/profile/widgets/sporting_record.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';

import 'helpers/harness.dart';
import 'helpers/profile_module_fixture.dart';

/// Signs a demo member in and parks the app on Me, with the Me module pointed at
/// [fake] instead of the device adapter or a live project. [prepare] runs on the
/// seeded document before the first frame, which is how a test can take the
/// member's tournament history away.
Future<LocalSportikaRepository> _openMe(
  WidgetTester tester,
  ProfileModuleFixture fake, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
  void Function(LocalSportikaRepository state)? prepare,
}) async {
  final state = await freshState();
  prepare?.call(state);
  final mock = MockAuthenticationService(state);
  addTearDown(mock.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
  await pumpApp(
    tester,
    state: state,
    authenticationService: mock,
    profileModule: fake,
    size: size,
    textScale: textScale,
  );
  final context = tester.element(find.byType(MaterialApp));
  final flow = context.read<AuthFlowController>();
  flow.openSignIn();
  flow.email = 'zain@sportika.pk';
  flow.password = 'Sportika9!';
  await flow.submitSignIn();
  await tester.pumpAndSettle();
  await tester.tap(find.byType(NavigationDestination).at(4));
  await tester.pumpAndSettle();
  return state;
}

/// The profile tab's own scrollable. The shell has no other vertical scrollable
/// on this tab, but naming it explicitly keeps the drag deterministic.
Finder _meScrollable(WidgetTester tester) => find
    .descendant(of: find.byType(ProfileTab), matching: find.byType(Scrollable))
    .first;

Future<void> _openRoute(WidgetTester tester, String route) async {
  pushRoute(tester.element(find.byType(ProfileTab)), route);
  await tester.pumpAndSettle();
}

/// The [TextField] behind a labelled [AuthField]. AuthField renders its label
/// upper-cased above the field.
Finder _field(String label) => find.descendant(
  of: find
      .ancestor(
        of: find.text(label.toUpperCase()),
        matching: find.byType(AuthField),
      )
      .first,
  matching: find.byType(TextField),
);

void main() {
  group('ProfileModuleController', () {
    test('loads once and exposes a retryable failure', () async {
      final fake = ProfileModuleFixture();
      final controller = ProfileModuleController(fake);
      addTearDown(controller.dispose);

      await controller.ensureLoaded();
      expect(controller.status, ProfileModuleStatus.ready);
      expect(controller.snapshot?.personal.username, 'zain');
      expect(fake.loads, 1);

      // A second build of the overview must not pay for another read.
      await controller.ensureLoaded();
      expect(fake.loads, 1);

      fake.loadError = const ProfileModuleException('Profile service offline.');
      await controller.refresh();
      expect(controller.status, ProfileModuleStatus.error);
      expect(controller.error, 'Profile service offline.');
      // The previous card stays readable while the refresh is retried.
      expect(controller.snapshot, isNotNull);

      fake.loadError = null;
      await controller.refresh();
      expect(controller.status, ProfileModuleStatus.ready);
      expect(controller.error, isNull);
    });

    test('a write re-reads the card and always clears the busy flag', () async {
      final fake = ProfileModuleFixture();
      final controller = ProfileModuleController(fake);
      addTearDown(controller.dispose);

      await controller.savePersonalInformation(
        displayName: 'Ali Raza',
        city: 'Lahore',
        bio: 'New to padel.',
        dateOfBirth: DateTime(1998, 2, 3),
        gender: ProfileGender.woman,
        playStyle: PlayStyle.competitive,
      );
      expect(fake.savedDisplayName, 'Ali Raza');
      expect(fake.savedGender, ProfileGender.woman);
      expect(fake.savedPlayStyle, PlayStyle.competitive);
      expect(controller.snapshot?.personal.displayName, 'Ali Raza');
      expect(controller.busy, isFalse);

      fake.writeError = const ProfileModuleException('That handle is taken.');
      await expectLater(
        controller.changeUsername('taken'),
        throwsA(isA<ProfileModuleException>()),
      );
      expect(controller.busy, isFalse);
      // The stored card is untouched by a refused write.
      expect(controller.snapshot?.personal.displayName, 'Ali Raza');
    });

    test('unknown failures become a sentence that is safe to show', () {
      expect(
        ProfileModuleController.messageFor(StateError('device is full')),
        'device is full',
      );
      expect(
        ProfileModuleController.messageFor(Exception('socket closed')),
        'Something went wrong. Check your connection and try again.',
      );
    });
  });

  testWidgets('passport overview leads with the card, then record and account', (
    tester,
  ) async {
    final fake = ProfileModuleFixture(
      sports: [sportRow(Sport.cricket, level: PlayingLevel.advanced)],
    );
    final state = await _openMe(
      tester,
      fake,
      size: const Size(320, 844),
      textScale: 1.3,
    );

    expect(find.byType(ProfileTab), findsOneWidget);
    expect(fake.loads, 1);
    expect(find.text('MY PASSPORT'), findsOneWidget);
    expect(find.text('SPORTIKA · ATHLETE PASSPORT'), findsOneWidget);
    expect(find.text(state.currentAccount!.displayName), findsOneWidget);
    expect(find.text('@${state.currentAccount!.username}'), findsOneWidget);
    expect(find.text('SPORTIKA MEMBER'), findsOneWidget);
    // One universal account: no role badge is ever drawn.
    expect(find.text('Player'), findsNothing);
    expect(find.text('Organizer'), findsNothing);
    expect(tester.takeException(), isNull);

    // The Me list builds lazily, so every section is scrolled to in the order a
    // reader meets it on the way down.
    final scrollable = _meScrollable(tester);
    Future<void> reach(String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        300,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
    }

    await reach('MY SPORTS');
    expect(find.text('Cricket'), findsOneWidget);
    expect(find.text('Edit sports'), findsOneWidget);

    await reach('SPORTING RECORD');
    expect(find.text('MATCHES'), findsOneWidget);
    expect(find.text('WINS'), findsOneWidget);
    expect(find.text('LOSSES'), findsOneWidget);
    expect(find.text('WIN RATE'), findsOneWidget);
    // The strip renders the member's real published results, not a placeholder.
    final me = state.currentAccount!;
    final expected = sportingRecordOf(
      fixtures: state.fixtures,
      myEntryIds: state.entries
          .where(
            (entry) =>
                entry.memberAccountIds.contains(me.id) &&
                entry.status != EntryStatus.withdrawn,
          )
          .map((entry) => entry.id)
          .toSet(),
    );
    expect(expected.played, greaterThan(0));
    final strip = tester.widget<SportingRecordStrip>(
      find.byType(SportingRecordStrip),
    );
    expect(strip.record.played, expected.played);
    expect(strip.record.wins, expected.wins);
    expect(strip.record.losses, expected.losses);
    expect(strip.record.draws, expected.draws);

    await reach('MY JOURNEY');
    expect(find.text('View history'), findsOneWidget);
    // The seeded member is entered in live tournaments, so the journey is real
    // data rather than the first-match invitation. The cup is named once by its
    // tournament row and again by the published match played in it.
    expect(find.text('Karachi Padel Cup'), findsWidgets);
    expect(find.byType(FirstMatchCard), findsNothing);

    await reach('MY TEAMS');
    expect(find.text('Sportika Strikers'), findsOneWidget);

    await reach('ACHIEVEMENTS');
    // Only provable milestones are listed, and the count is honest.
    expect(find.textContaining('of 7 unlocked'), findsOneWidget);

    await reach('ACCOUNT & SETTINGS');
    expect(find.text('Personal information'), findsOneWidget);
    expect(find.text('Sports preferences'), findsOneWidget);
    expect(find.text('1 preferred sport'), findsOneWidget);
    expect(find.text('Identity documents'), findsOneWidget);
    expect(find.text('Settings & privacy'), findsOneWidget);

    await reach('RECORDS');
    expect(find.text('Tournament history'), findsOneWidget);
    expect(find.text('Scorer assignments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a medal opens its detail with the real progress', (
    tester,
  ) async {
    await _openMe(
      tester,
      ProfileModuleFixture(
        sports: [sportRow(Sport.cricket, level: PlayingLevel.advanced)],
      ),
    );

    final scrollable = _meScrollable(tester);
    await tester.scrollUntilVisible(
      find.text('ACHIEVEMENTS'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    // The seeded member has played official matches, so 'First whistle' is a
    // genuinely earned medal rather than a fabricated badge.
    final medal = find.byKey(const Key('achievement-first_whistle'));
    await tester.ensureVisible(medal);
    await tester.pumpAndSettle();
    await tester.tap(medal);
    await tester.pumpAndSettle();

    expect(find.text('ACTUAL PROGRESS'), findsOneWidget);
    expect(find.text('EARNED'), findsOneWidget);
    expect(find.textContaining('official match'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a member with no official play gets the first-match state', (
    tester,
  ) async {
    // With no entries the member can have no published fixture, which is the
    // state a brand-new passport is in.
    await _openMe(
      tester,
      ProfileModuleFixture(),
      size: const Size(320, 844),
      textScale: 1.3,
      prepare: (document) => document.entries.clear(),
    );

    final scrollable = _meScrollable(tester);
    await tester.scrollUntilVisible(
      find.text('SPORTING RECORD'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    final strip = tester.widget<SportingRecordStrip>(
      find.byType(SportingRecordStrip),
    );
    expect(strip.record.isEmpty, isTrue);
    // A dash, never a misleading 0%.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(
      find.text('Your first official result sets your win rate.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('MY JOURNEY'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Your journey starts here'), findsOneWidget);
    expect(find.byType(FirstMatchCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed read offers a retry that reloads the card', (
    tester,
  ) async {
    final fake = ProfileModuleFixture()
      ..loadError = const ProfileModuleException('Profile service offline.');
    await _openMe(tester, fake);

    expect(find.text('Your profile card could not be loaded'), findsOneWidget);
    expect(find.text('Profile service offline.'), findsOneWidget);

    fake.loadError = null;
    await tapVisible(tester, find.text('Try again'));
    expect(fake.loads, 2);
    expect(find.text('Your profile card could not be loaded'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal information edits the record behind validation', (
    tester,
  ) async {
    final fake = ProfileModuleFixture();
    // A tall surface keeps the whole form on screen; the 320dp matrix the
    // overview test covers is the one that proves the responsive layout.
    await _openMe(tester, fake, size: const Size(430, 1500));

    final scrollable = _meScrollable(tester);
    await tester.scrollUntilVisible(
      find.text('Personal information'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Personal information'));
    expect(find.byType(PersonalInformationScreen), findsOneWidget);

    // The date of birth is chosen from the calendar, never typed.
    await tapVisible(tester, find.byTooltip('Choose date of birth'));
    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(calendar.initialCalendarMode, DatePickerMode.year);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(_field('Full name'));
    await tester.enterText(_field('Full name'), 'A');
    await tapVisible(tester, find.text('Save changes'));
    expect(
      find.text('Enter a full name between 2 and 80 characters.'),
      findsOneWidget,
    );
    expect(fake.savedDisplayName, isNull);

    await tester.enterText(_field('Full name'), 'Ali Raza');
    await tester.enterText(_field('Username'), 'ali.raza');
    await tester.enterText(_field('City'), 'Lahore');
    await tapVisible(tester, find.text('Save changes'));

    expect(fake.savedDisplayName, 'Ali Raza');
    expect(fake.savedCity, 'Lahore');
    expect(fake.savedDateOfBirth, isNotNull);
    // The handle is a separate write because it has its own unique index.
    expect(fake.savedUsername, 'ali.raza');
    expect(find.text('Personal information saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sports preferences save the chosen set or the skip answer', (
    tester,
  ) async {
    final fake = ProfileModuleFixture(
      sports: [sportRow(Sport.cricket, level: PlayingLevel.advanced)],
    );
    await _openMe(tester, fake);
    await _openRoute(tester, AppRoute.sportsPreferences);
    expect(find.byType(SportsPreferencesScreen), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(AuthChoicePill, 'Padel'));
    await tapVisible(tester, find.text('Save sports'));
    expect(fake.savedSports, isNotNull);
    expect(fake.savedSports!.map((s) => s.sport).toSet(), {
      Sport.cricket,
      Sport.padel,
    });
    expect(fake.savedSports!.every((s) => s.level != null), isTrue);

    // "I'd rather not rank my sports" keeps both sports with no level.
    await tapVisible(tester, find.text("I'd rather not rank my sports"));
    await tapVisible(tester, find.text('Save sports'));
    expect(fake.savedSports!.every((s) => s.level == null), isTrue);
    expect(fake.savedSports!.every((s) => s.position == null), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scorer assignments answer the scorer and gate the organizer', (
    tester,
  ) async {
    final fake = ProfileModuleFixture();
    final state = await _openMe(tester, fake);
    final me = state.currentAccount!.id;
    fake.assignments = [
      assignmentRow(id: 'a1', scorerId: me, authorizedBy: 'acc-other'),
      assignmentRow(
        id: 'a2',
        scorerId: 'acc-other',
        authorizedBy: me,
        status: ScorerAssignmentStatus.accepted,
      ),
    ];

    await _openRoute(tester, AppRoute.scorerAssignments);
    expect(find.byType(ScorerAssignmentsScreen), findsOneWidget);
    expect(find.text('AWAITING REPLY'), findsOneWidget);
    expect(find.text('Revoke assignment'), findsOneWidget);

    await tapVisible(tester, find.text('Accept'));
    expect(fake.responses, ['a1:accept']);

    // No tournament in this device build is organized by the member, so the
    // assign panel explains what has to exist first instead of failing later.
    expect(
      find.text(
        'Organize a tournament with a generated draw to assign official scorers.',
      ),
      findsOneWidget,
    );
    expect(find.text('Assign scorer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('identity documents stay optional and withdrawable', (
    tester,
  ) async {
    final fake = ProfileModuleFixture(
      identity: ProfileIdentityRecord(
        kind: IdentityDocumentKind.cnic,
        submittedAt: DateTime(2026, 11, 1),
        number: '1234512345671',
        hasFront: true,
      ),
    );
    await _openMe(tester, fake);
    await _openRoute(tester, AppRoute.identityDocuments);

    expect(find.byType(IdentityDocumentsScreen), findsOneWidget);
    expect(find.text('CNIC on file'), findsOneWidget);
    expect(find.text('•••••••••5671'), findsOneWidget);

    await tapVisible(tester, find.text('Withdraw documents'));
    await tapVisible(tester, find.text('Withdraw'));
    expect(fake.deletedIdentities, 1);
    expect(find.text('CNIC NUMBER (OPTIONAL)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device-only build says identity documents cannot be stored', (
    tester,
  ) async {
    final fake = ProfileModuleFixture(supportsIdentityDocuments: false);
    await _openMe(tester, fake);
    await _openRoute(tester, AppRoute.identityDocuments);

    expect(
      find.textContaining('identity documents are deliberately never written'),
      findsOneWidget,
    );
    expect(find.text('CNIC NUMBER (OPTIONAL)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history screens render the member record after a refresh', (
    tester,
  ) async {
    await _openMe(tester, ProfileModuleFixture());

    await _openRoute(tester, AppRoute.tournamentHistory);
    expect(find.byType(TournamentHistoryScreen), findsOneWidget);
    expect(
      find.text('Every event you played in or organized, newest first.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _openRoute(tester, AppRoute.teamMemberships);
    expect(find.byType(TeamMembershipsScreen), findsOneWidget);
    expect(
      find.text('The squads you play for and the invitations waiting on you.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
