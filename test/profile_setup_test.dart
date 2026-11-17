import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sportika/core/data/identity_document_store.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/features/profile/screens/edit_profile_screen.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_setup.dart';

import 'helpers/auth_service_fixture.dart';
import 'helpers/harness.dart';

typedef SetupRig = ({LocalSportikaRepository store, AuthFlowController flow});

Future<SetupRig> startSetup({IdentityDocumentStore? identityStore}) async {
  final store = await freshState();
  final account = await store.createAccount(
    displayName: 'Ayesha Khan',
    email: 'ayesha@example.com',
    city: 'Karachi',
    intent: AccountIntent.player,
  );
  final session = SessionController(store);
  final service = AuthServiceFixture(store, restoredAccountId: account.id);
  final flow = AuthFlowController(
    session,
    service: service,
    identityStore: identityStore,
  );
  addTearDown(() {
    flow.dispose();
    service.dispose();
    session.dispose();
    store.dispose();
  });
  flow.continueFromSplash();
  await pumpEventQueue();
  return (store: store, flow: flow);
}

void validBasics(AuthFlowController flow) => flow.saveBasics(
  name: 'Ayesha Khan',
  handleValue: 'ayesha_plays',
  cityValue: 'Lahore',
  bioValue: 'Ready to play',
  dateOfBirthValue: DateTime(1998, 5, 12),
);

class _IdentityStore implements IdentityDocumentStore {
  int calls = 0;
  IdentitySubmission? saved;
  bool fail = false;
  Completer<void>? barrier;
  @override
  Future<void> save({
    required String accountId,
    required IdentitySubmission submission,
  }) async {
    calls++;
    saved = submission;
    if (barrier != null) await barrier!.future;
    if (fail) throw StateError('upload failed');
  }
}

Future<void> review(AuthFlowController flow) async {
  validBasics(flow);
  flow.continueFromPhoto();
  flow.toggleSport(Sport.cricket);
  flow.submitSports();
  flow.skipPlayingPreferences();
}

void main() {
  test('optional numbers accept blank, compact and formatted values only', () {
    for (final value in ['', '  ', '1234512345671', '12345-1234567-1']) {
      expect(validateIdentityNumber(value), isNull);
    }
    for (final value in [
      '123',
      '12345123456712',
      '12345A2345671',
      '12345--12345671',
    ]) {
      expect(validateIdentityNumber(value), isNotNull);
    }
    expect(normalizeIdentityNumber(' 12345-1234567-1 '), '1234512345671');
  });

  test('age group changes on the eighteenth birthday', () {
    final today = DateTime(2026, 11, 13);
    expect(
      identityKindFor(DateTime(2008, 11, 13), today: today),
      IdentityDocumentKind.cnic,
    );
    expect(
      identityKindFor(DateTime(2008, 11, 14), today: today),
      IdentityDocumentKind.bForm,
    );
    expect(
      identityKindFor(DateTime(2000, 2, 29), today: DateTime(2018, 2, 28)),
      IdentityDocumentKind.bForm,
    );
    expect(
      identityKindFor(DateTime(2000, 2, 29), today: DateTime(2018, 3, 1)),
      IdentityDocumentKind.cnic,
    );
  });

  test('skipped identity never calls storage or changes completion', () async {
    final storage = _IdentityStore()..fail = true;
    final rig = await startSetup(identityStore: storage);
    await review(rig.flow);
    await rig.flow.finishSetup();
    expect(rig.flow.canAccessApp, isTrue);
    expect(storage.calls, 0);
  });

  test(
    'optional upload failure and delay never gate Home or leak into local JSON',
    () async {
      final storage = _IdentityStore()
        ..fail = true
        ..barrier = Completer<void>();
      final rig = await startSetup(identityStore: storage);
      rig.flow.identityDocuments.number = '12345-1234567-1';
      rig.flow.identityDocuments.front = Uint8List.fromList([1, 2, 3]);
      await review(rig.flow);
      final saving = rig.flow.finishSetup();
      await pumpEventQueue();
      expect(storage.calls, 1);
      expect(rig.flow.canAccessApp, isTrue);
      expect(rig.flow.busy, isFalse);
      expect(rig.flow.identityDocuments.isEmpty, isTrue);
      expect(
        jsonEncode(rig.store.currentAccount!.toJson()),
        isNot(contains('1234512345671')),
      );
      storage.barrier!.complete();
      await saving;
      expect(rig.flow.canAccessApp, isTrue);
      expect(rig.flow.takeIdentityNotice(), contains('could not confirm'));
    },
  );

  test('age changes discard incompatible documents; invalid numbers can be skipped', () async {
    final rig = await startSetup();
    rig.flow.updateBirthDate('12/05/1998');
    rig.flow.identityDocuments.number = 'invalid';
    rig.flow.identityDocuments.front = Uint8List.fromList([1]);
    validBasics(rig.flow);
    expect(rig.flow.inlineField, 'documentNumber');
    rig.flow.skipIdentityDocuments();
    validBasics(rig.flow);
    expect(rig.flow.stage, AuthStage.profilePhoto);
    rig.flow.identityDocuments.number = '1234512345671';
    rig.flow.updateBirthDate(
      profileDateLabel(DateTime.now().subtract(const Duration(days: 365))),
    );
    expect(rig.flow.identityKind, IdentityDocumentKind.bForm);
    expect(rig.flow.identityDocuments.isEmpty, isTrue);
  });

  test(
    'valid optional B-Form submission is private and does not require photos',
    () async {
      final storage = _IdentityStore();
      final rig = await startSetup(identityStore: storage);
      rig.flow.updateBirthDate(
        profileDateLabel(DateTime(DateTime.now().year - 12, 1, 1)),
      );
      rig.flow.identityDocuments.number = '12345-1234567-1';
      rig.flow.saveBasics(
        name: 'Ayesha Khan',
        handleValue: 'ayesha_plays',
        cityValue: 'Lahore',
        bioValue: '',
      );
      rig.flow.continueFromPhoto();
      rig.flow.toggleSport(Sport.padel);
      rig.flow.submitSports();
      rig.flow.skipPlayingPreferences();
      await rig.flow.finishSetup();
      expect(rig.flow.canAccessApp, isTrue);
      expect(storage.saved!.kind, IdentityDocumentKind.bForm);
      expect(storage.saved!.number, '1234512345671');
      expect(storage.saved!.front, isNull);
      expect(storage.saved!.back, isNull);
      expect(rig.flow.takeIdentityNotice(), contains('saved privately'));
      await rig.flow.signOut();
      expect(rig.flow.identityDocuments.isEmpty, isTrue);
    },
  );

  testWidgets('birth date is picker-only and age controls optional documents', (
    tester,
  ) async {
    final state = await freshState();
    await state.createAccount(
      displayName: 'Ayesha Khan',
      email: 'ayesha@example.com',
      city: 'Karachi',
      intent: AccountIntent.player,
    );
    await pumpApp(
      tester,
      state: state,
      size: const Size(320, 844),
      textScale: 1.3,
    );
    final birth = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is AuthField && w.label == 'Date of birth',
      ),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(birth);
    expect(tester.widget<TextField>(birth).readOnly, isTrue);
    await chooseBirthDate(tester, DateTime(1998, 5, 12));
    final flow = authFlow(tester);
    expect(flow.dateOfBirth, DateTime(1998, 5, 12));
    await tapVisible(tester, find.text('Skip identity documents'));
    expect(find.text('CNIC number (optional)'), findsWidgets);
    expect(find.text('CNIC front (optional)'), findsOneWidget);
    expect(find.text('CNIC back (optional)'), findsOneWidget);
    await chooseBirthDate(tester, DateTime(DateTime.now().year - 12, 1, 1));
    await tapVisible(tester, find.text('Skip identity documents'));
    expect(find.text('B-Form number (optional)'), findsWidgets);
    expect(find.text('CNIC front (optional)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'required identity validates and Home stays locked until final review save',
    () async {
      final rig = await startSetup();
      final flow = rig.flow;
      flow.enterApp();
      expect(flow.canAccessApp, isFalse);
      flow.saveBasics(
        name: 'Ayesha Khan',
        handleValue: 'ayesha_plays',
        cityValue: 'Lahore',
        bioValue: '',
      );
      expect(flow.inlineField, 'birthDate');
      flow.saveBasics(
        name: 'Ayesha Khan',
        handleValue: 'ayesha_plays',
        cityValue: 'Lahore',
        bioValue: '',
        dateOfBirthValue: DateTime(2099),
      );
      expect(flow.inlineField, 'birthDate');
      flow.saveBasics(
        name: 'Ayesha Khan',
        handleValue: 'seebu',
        cityValue: 'Lahore',
        bioValue: '',
        dateOfBirthValue: DateTime(1998),
      );
      expect(flow.inlineField, 'handle');
      flow.gender = ProfileGender.woman;
      validBasics(flow);
      expect(flow.stage, AuthStage.profilePhoto);
      flow.continueFromPhoto();
      expect(flow.stage, AuthStage.selectSports);
      flow.toggleSport(Sport.cricket);
      flow.toggleSport(Sport.futsal);
      flow.submitSports();
      flow.setLevel(Sport.cricket, PlayingLevel.advanced);
      flow.setPosition(Sport.cricket, 'Wicketkeeper');
      flow.setPosition(Sport.futsal, 'Pivot');
      flow.submitLevels();
      expect(flow.stage, AuthStage.setupComplete);
      expect(rig.store.currentAccount!.setupComplete, isFalse);
      expect(flow.canAccessApp, isFalse);
      await flow.finishSetup();
      expect(flow.stage, AuthStage.home);
      expect(flow.canAccessApp, isTrue);
      final reopened = LocalSportikaRepository(await LocalStorage.open());
      await reopened.load();
      addTearDown(reopened.dispose);
      final saved = reopened.currentAccount!;
      expect(saved.dateOfBirth, DateTime(1998, 5, 12));
      expect(saved.gender, ProfileGender.woman);
      expect(saved.playingPositions, {
        'cricket': 'Wicketkeeper',
        'futsal': 'Pivot',
      });
      expect(saved.levels['cricket'], PlayingLevel.advanced);
      expect(saved.city, 'Lahore');
      flow.playingPositions['cricket'] = 'Bowler';
      expect(saved.playingPositions['cricket'], 'Wicketkeeper');
    },
  );

  test(
    'camera resume revalidation preserves the incomplete draft and step',
    () async {
      final rig = await startSetup();
      validBasics(rig.flow);
      rig.flow.gender = ProfileGender.nonBinary;
      await rig.flow.revalidateSession();
      expect(rig.flow.stage, AuthStage.profilePhoto);
      expect(rig.flow.handle, 'ayesha_plays');
      expect(rig.flow.dateOfBirth, DateTime(1998, 5, 12));
      expect(rig.flow.gender, ProfileGender.nonBinary);
      expect(rig.store.currentAccount!.setupComplete, isFalse);
    },
  );

  test('any universal account can skip playing preferences without fabricated levels', () async {
    final rig = await startSetup();
    validBasics(rig.flow);
    rig.flow.continueFromPhoto();
    rig.flow.toggleSport(Sport.padel);
    rig.flow.submitSports();
    rig.flow.skipPlayingPreferences();
    expect(rig.flow.stage, AuthStage.setupComplete);
    rig.flow.editSetupStep(AuthStage.profileBasics);
    expect(rig.flow.birthDateText, '12/05/1998');
    validBasics(rig.flow);
    expect(rig.flow.stage, AuthStage.setupComplete);
    rig.flow.editSetupStep(AuthStage.selectSports);
    rig.flow.back();
    expect(rig.flow.stage, AuthStage.setupComplete);
    rig.flow.editSetupStep(AuthStage.sportsLevels);
    rig.flow.skipPlayingPreferences();
    expect(rig.flow.stage, AuthStage.setupComplete);
    await rig.flow.finishSetup();
    final account = rig.store.currentAccount!;
    expect(account.playingPreferencesSkipped, isTrue);
    expect(account.levels, isEmpty);
    expect(account.playingPositions, isEmpty);
    expect(account.sports, {Sport.padel});
    expect(rig.store.canOrganize, isTrue);
    await rig.flow.signOut();
    expect(rig.flow.birthDateText, isEmpty);
    expect(rig.flow.gender, isNull);
  });

  test('date parsing rejects impossible calendar dates', () {
    expect(parseProfileDate('31/02/2000'), isNull);
    expect(parseProfileDate('29/02/2000'), DateTime(2000, 2, 29));
    expect(parseProfileDate('29/02/2001'), isNull);
    expect(parseProfileDate('hello'), isNull);
  });

  testWidgets(
    'position selection, review edits and system back preserve the setup draft',
    (tester) async {
      final store = await freshState();
      await store.createAccount(
        displayName: 'Ayesha Khan',
        email: 'ayesha@example.com',
        city: 'Karachi',
        intent: AccountIntent.player,
      );
      await pumpApp(tester, state: store);
      final flow = authFlow(tester);
      validBasics(flow);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Skip photo for now'));
      await tapVisible(tester, find.text('FUTSAL').first);
      await tapVisible(tester, find.text('CONTINUE'));
      final position = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(position);
      await tester.tap(position);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pivot').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('CONTINUE'));
      expect(flow.stage, AuthStage.setupComplete);
      expect(flow.playingPositions['futsal'], 'Pivot');
      expect(store.currentAccount!.setupComplete, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(flow.stage, AuthStage.sportsLevels);
      await tapVisible(tester, find.text('CONTINUE'));
      await tapVisible(tester, find.text('Edit basic information'));
      expect(flow.stage, AuthStage.profileBasics);
      final birthday = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is AuthField && w.label == 'Date of birth',
        ),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(birthday).controller!.text, '12/05/1998');
      pushRoute(
        tester.element(find.byType(AuthField).first),
        AppRoute.createTournament,
      );
      await tester.pumpAndSettle();
      expect(flow.canAccessApp, isFalse);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Me edit profile saves all shared details and preferences', (
    tester,
  ) async {
    final store = await freshState();
    await store.signIn('acc-seebu');
    await pumpApp(tester, state: store);
    pushRoute(tester.element(find.byType(NavigationBar)), AppRoute.editProfile);
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsOneWidget);
    Future<void> fill(String label, String text) async {
      final target = find.descendant(
        of: find.byWidgetPredicate((w) => w is AuthField && w.label == label),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(target);
      await tester.enterText(target, text);
      await tester.pump();
    }

    await fill('Full name', 'Seebu Updated');
    await fill('Username', 'seebu_updated');
    await chooseBirthDate(tester, DateTime(1998, 5, 12));
    await fill('City', 'Lahore');
    await tester.ensureVisible(find.text('Padel'));
    await tester.tap(find.text('Padel'));
    await tester.pumpAndSettle();
    final skip = find.byType(SwitchListTile);
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save changes'));
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(store.currentAccount!.displayName, 'Seebu Updated');
    expect(store.currentAccount!.dateOfBirth, DateTime(1998, 5, 12));
    expect(store.currentAccount!.playingPreferencesSkipped, isTrue);
    expect(store.currentAccount!.sports, contains(Sport.padel));
    expect(tester.takeException(), isNull);
  });
}
