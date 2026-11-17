import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_setup.dart';

import 'helpers/auth_service_fixture.dart';

class _FailingStorage extends LocalStorage {
  // ignore: use_super_parameters
  _FailingStorage(SharedPreferences prefs) : super(prefs);
  bool failProfile = false;
  bool failSession = false;
  @override
  Future<void> writeState(Map<String, dynamic> value) async {
    if (failProfile) throw StateError('device is full');
    await super.writeState(value);
  }

  @override
  Future<void> writeSessionAccountId(String? id) async {
    if (failSession) throw StateError('device is full');
    await super.writeSessionAccountId(id);
  }
}

void main() {
  late _FailingStorage storage;
  late LocalSportikaRepository store;
  late SessionController session;
  late AuthServiceFixture service;
  late AuthFlowController flow;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sportika.onboarding_seen.v1': true,
    });
    storage = _FailingStorage(await SharedPreferences.getInstance());
    store = LocalSportikaRepository(storage);
    await store.load();
    session = SessionController(store);
    service = AuthServiceFixture(store);
    // This file walks the signup code screen, which the shipped build has off.
    flow = AuthFlowController(
      session,
      service: service,
      emailVerificationEnabled: true,
    );
    flow.continueFromSplash();
    await pumpEventQueue();
  });
  tearDown(() {
    flow.dispose();
    service.dispose();
    session.dispose();
    store.dispose();
  });

  test('failed session persistence never opens the app', () async {
    storage.failSession = true;
    flow.email = store.accounts.first.email;
    flow.password = AuthServiceFixture.validPassword;
    await flow.submitSignIn();
    expect(flow.canAccessApp, isFalse);
    expect(flow.stage, AuthStage.signIn);
    expect(flow.busy, isFalse);
    expect(store.currentAccount, isNull);
  });

  test('failed profile save stays on setup and rolls fields back', () async {
    flow.openCreateAccount();
    flow.fullName = 'New Player';
    flow.email = 'new@example.com';
    flow.password = 'NewPassword9!';
    flow.acceptedTerms = true;
    await flow.submitAccountDetails();

    await flow.verifyCode('123456');
    flow.saveBasics(
      name: 'Updated Name',
      handleValue: 'new_player',
      dateOfBirthValue: DateTime(1998, 5, 12),
      cityValue: 'Lahore',
      bioValue: 'Ready',
    );
    flow.continueFromPhoto();
    flow.toggleSport(Sport.cricket);
    flow.submitSports();
    flow.submitLevels();
    flow.gender = ProfileGender.woman;
    flow.setPosition(Sport.cricket, 'Bowler');
    storage.failProfile = true;
    await flow.finishSetup();
    expect(flow.stage, AuthStage.setupComplete);
    expect(flow.busy, isFalse);
    expect(flow.inlineError, isNotNull);
    expect(store.currentAccount!.setupComplete, isFalse);
    expect(store.currentAccount!.displayName, 'New Player');
    expect(store.currentAccount!.handle, isEmpty);
    expect(store.currentAccount!.dateOfBirth, isNull);
    expect(store.currentAccount!.gender, isNull);
    expect(store.currentAccount!.playingPositions, isEmpty);
    expect(flow.dateOfBirth, DateTime(1998, 5, 12));
    storage.failProfile = false;
    await flow.finishSetup();
    expect(flow.stage, AuthStage.home);
    expect(store.currentAccount!.setupComplete, isTrue);
  });

  test('local sign-out write failure still hides protected UI', () async {
    flow.email = store.accounts.first.email;
    flow.password = AuthServiceFixture.validPassword;
    await flow.submitSignIn();
    expect(flow.canAccessApp, isTrue);
    storage.failSession = true;
    await flow.signOut();
    expect(flow.canAccessApp, isFalse);
    expect(flow.stage, AuthStage.signIn);
    expect(flow.notice, contains('storage could not be cleared'));
  });

  test(
    'profile snapshots do not share mutable sports and levels with draft',
    () async {
      await store.signIn(store.accounts.first.id);
      final sports = {Sport.cricket};
      final levels = {'cricket': PlayingLevel.beginner};
      await store.completeProfileSetup(
        displayName: 'Player',
        handle: 'player',
        bio: '',
        city: 'Karachi',
        sports: sports,
        levels: levels,
        playStyle: PlayStyle.weekly,
        avatar: 'midnight',
      );
      sports.clear();
      levels.clear();
      expect(store.currentAccount!.sports, {Sport.cricket});
      expect(store.currentAccount!.levels, {'cricket': PlayingLevel.beginner});
    },
  );
}
