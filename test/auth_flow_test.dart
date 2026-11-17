import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';

import 'helpers/auth_service_fixture.dart';
import 'helpers/harness.dart';

void main() {
  late LocalSportikaRepository store;
  late SessionController session;
  late AuthServiceFixture service;
  late AuthFlowController flow;

  /// Existing coverage is written for the build that confirms addresses, so it
  /// asks for the code screen explicitly; the shipped default has it off.
  Future<void> start({
    String? accountId,
    bool emailVerificationEnabled = true,
  }) async {
    store = await freshState();
    if (accountId != null) await store.signIn(accountId);
    session = SessionController(store);
    service = AuthServiceFixture(store, restoredAccountId: accountId);
    flow = AuthFlowController(
      session,
      service: service,
      emailVerificationEnabled: emailVerificationEnabled,
    );
    flow.continueFromSplash();
    await pumpEventQueue();
  }

  Future<void> signIn() async {
    flow.openSignIn();
    flow.email = store.accountById('acc-seebu')!.email;
    flow.password = AuthServiceFixture.validPassword;
    await flow.submitSignIn();
  }

  Future<void> register({AccountIntent intent = AccountIntent.player}) async {
    flow.openCreateAccount();
    flow.fullName = 'New Player';
    flow.email = 'new@example.com';
    flow.password = 'NewPassword9!';
    flow.acceptedTerms = true;
    await flow.submitAccountDetails();
  }

  tearDown(() {
    flow.dispose();
    service.dispose();
    session.dispose();
    store.dispose();
  });

  test(
    'unconfigured authentication never trusts saved local identity',
    () async {
      await start(accountId: 'acc-seebu');
      flow.dispose();
      flow = AuthFlowController(session);
      flow.continueFromSplash();
      await pumpEventQueue();
      expect(flow.stage, AuthStage.signIn);
      expect(flow.canAccessApp, isFalse);
      expect(store.isSignedIn, isFalse);
      flow.email = 'someone@example.com';
      flow.password = 'anything';
      await flow.submitSignIn();
      expect(flow.inlineError, contains('not connected'));
      expect(flow.busy, isFalse);
      expect(flow.canAccessApp, isFalse);
    },
  );

  test(
    'restores only a service-verified account and persists identity',
    () async {
      await start(accountId: 'acc-seebu');
      expect(flow.stage, AuthStage.home);
      expect(flow.canAccessApp, isTrue);
      final restored = LocalSportikaRepository(await LocalStorage.open());
      await restored.load();
      expect(restored.currentAccount?.id, 'acc-seebu');
      restored.dispose();
    },
  );

  test(
    'malformed email and missing password do not call the service',
    () async {
      await start();
      flow.email = 'bad@.com';
      flow.password = '';
      await flow.submitSignIn();
      expect(flow.inlineField, 'email');
      flow.email = 'valid@example.com';
      await flow.submitSignIn();
      expect(flow.inlineField, 'password');
      expect(service.signInCalls, 0);
    },
  );

  test('wrong credentials never open a local seeded account', () async {
    await start();
    flow.email = store.accounts.first.email;
    flow.password = 'wrong password';
    await flow.submitSignIn();
    expect(flow.inlineError, contains('incorrect'));
    expect(flow.stage, AuthStage.signIn);
    expect(flow.authenticated, isFalse);
    expect(store.currentAccount, isNull);
  });

  test('sign-in clears password and hydrates a verified profile', () async {
    await start();
    await signIn();
    expect(flow.canAccessApp, isTrue);
    expect(flow.password, isEmpty);
    expect(flow.fullName, store.currentAccount!.displayName);
  });

  test(
    'duplicate submissions and back navigation are blocked while busy',
    () async {
      await start();
      service.signInBarrier = Completer<void>();
      flow.email = store.accounts.first.email;
      flow.password = AuthServiceFixture.validPassword;
      final pending = flow.submitSignIn();
      await flow.submitSignIn();
      flow.back();
      flow.openCreateAccount();
      expect(flow.stage, AuthStage.signIn);
      expect(service.signInCalls, 1);
      expect(flow.busy, isTrue);
      service.signInBarrier!.complete();
      await pending;
      expect(flow.canAccessApp, isTrue);
    },
  );

  test(
    'sign-out during sign-in prevents late completion from reopening app',
    () async {
      await start();
      service.signInBarrier = Completer<void>();
      flow.email = store.accounts.first.email;
      flow.password = AuthServiceFixture.validPassword;
      final pending = flow.submitSignIn();
      await flow.signOut();
      service.signInBarrier!.complete();
      await pending;
      expect(flow.stage, AuthStage.signIn);
      expect(flow.canAccessApp, isFalse);
      expect(store.currentAccount, isNull);
    },
  );

  test(
    'session revocation clears all identity and registration drafts',
    () async {
      await start(accountId: 'acc-seebu');
      flow.password = 'secret';
      flow.otp = '123456';
      service.revoke();
      await pumpEventQueue();
      expect(flow.stage, AuthStage.signIn);
      expect(flow.fullName, isEmpty);
      expect(flow.password, isEmpty);
      expect(flow.otp, isEmpty);
      expect(flow.sports, isEmpty);
      expect(flow.acceptedTerms, isFalse);
      expect(store.currentAccount, isNull);
    },
  );

  test('expiry and session refresh failures fail closed', () async {
    await start(accountId: 'acc-seebu');
    service.establish('acc-seebu', lifetime: const Duration(seconds: -1));
    await pumpEventQueue();
    expect(flow.canAccessApp, isFalse);
    expect(flow.stage, AuthStage.signIn);
  });

  test('resume verifies session and rejects a failed refresh', () async {
    await start(accountId: 'acc-seebu');
    service.nextError = const AuthenticationException('Refresh failed.');
    await flow.revalidateSession();
    expect(flow.stage, AuthStage.signIn);
    expect(flow.authenticated, isFalse);
  });

  test(
    'remote logout failure still hides account and clears persisted identity',
    () async {
      await start(accountId: 'acc-seebu');
      service.failSignOut = true;
      await flow.signOut();
      expect(flow.canAccessApp, isFalse);
      expect(flow.stage, AuthStage.signIn);
      expect(flow.notice, contains('could not be confirmed'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LocalStorage.sessionKey), isNull);
    },
  );

  test('signup validates terms and password before registration', () async {
    await start();
    flow.openCreateAccount();
    flow.fullName = 'New Player';
    flow.email = 'new@example.com';
    flow.password = 'short';
    await flow.submitAccountDetails();
    expect(flow.inlineField, 'password');
    flow.password = 'NewPassword9!';
    await flow.submitAccountDetails();
    expect(flow.inlineField, 'terms');
    expect(service.registerCalls, 0);
  });

  for (final intent in AccountIntent.values) {
    test(
      'registers and verifies a ${intent.name} only through the service',
      () async {
        await start();
        final before = store.accounts.length;
        await register(intent: intent);
        expect(flow.stage, AuthStage.verifyEmail);
        expect(store.accounts.length, before);
        expect(service.registeredIntent, AccountIntent.player);
        expect(flow.password, isEmpty);
        await flow.verifyCode('000000');
        expect(flow.stage, AuthStage.verifyEmail);
        expect(flow.inlineField, 'otp');
        expect(store.accounts.length, before);
        await flow.verifyCode('123456');
        expect(flow.stage, AuthStage.profileBasics);
        expect(flow.authenticated, isTrue);
        expect(flow.canAccessApp, isFalse);
        expect(store.currentAccount!.roles, AccountIntent.player.roles);
      },
    );
  }

  test(
    'registration errors stay visible without issuing a fake code',
    () async {
      await start();
      service.nextError = const AuthenticationException(
        'Email cannot be used.',
        field: 'email',
      );
      await register();
      expect(flow.stage, AuthStage.createAccount);
      expect(flow.inlineError, 'Email cannot be used.');
      expect(flow.otpSecondsLeft, 0);
      expect(flow.busy, isFalse);
    },
  );

  test('resend cooldown blocks duplicate code requests', () async {
    await start();
    await register();
    expect(flow.otpSecondsLeft, greaterThan(0));
    await flow.resendCode();
    expect(service.resendCalls, 0);
    flow.changeVerificationEmail();
    expect(flow.stage, AuthStage.createAccount);
    expect(flow.otp, isEmpty);
  });

  test(
    'profile setup validates, supports back, persists and enters app',
    () async {
      await start();
      await register();
      await flow.verifyCode('123456');
      flow.saveBasics(
        name: 'New Player',
        handleValue: '@bad@handle',
        cityValue: 'Karachi',
        bioValue: '',
      );
      expect(flow.inlineField, 'handle');
      flow.saveBasics(
        name: 'New Player',
        handleValue: '@new_player',
        dateOfBirthValue: DateTime(1998, 5, 12),
        cityValue: 'Karachi',
        bioValue: 'Ready to play',
      );
      expect(flow.stage, AuthStage.profilePhoto);
      flow.continueFromPhoto();
      expect(flow.stage, AuthStage.selectSports);
      flow.submitSports();
      expect(flow.inlineField, 'sports');
      flow.toggleSport(Sport.padel);
      flow.submitSports();
      flow.back();
      expect(flow.stage, AuthStage.selectSports);
      flow.submitSports();
      flow.submitLevels();
      expect(flow.stage, AuthStage.setupComplete);
      expect(store.currentAccount!.setupComplete, isFalse);
      await flow.finishSetup();
      expect(flow.stage, AuthStage.home);
      flow.enterApp();
      expect(flow.canAccessApp, isTrue);
      final restored = LocalSportikaRepository(await LocalStorage.open());
      await restored.load();
      expect(restored.currentAccount!.handle, 'new_player');
      expect(restored.currentAccount!.sports, {Sport.padel});
      expect(restored.currentAccount!.setupComplete, isTrue);
      restored.dispose();
    },
  );

  test('incomplete profiles resume setup after verified restoration', () async {
    await start();
    await register();
    await flow.verifyCode('123456');
    flow.dispose();
    flow = AuthFlowController(
      session,
      service: service,
      emailVerificationEnabled: true,
    );
    flow.continueFromSplash();
    await pumpEventQueue();
    expect(flow.stage, AuthStage.profileBasics);
    expect(flow.canAccessApp, isFalse);
    expect(flow.fullName, 'New Player');
  });

  test('recovery validates code and confirmation; updates only after service success', () async {
    await start();
    final email = store.accounts.first.email;
    flow.openForgotPassword();
    flow.email = email;
    await flow.submitForgotPassword();
    expect(flow.stage, AuthStage.resetPassword);
    expect(flow.notice, contains('If an account exists'));
    await flow.submitResetPassword('ChangedPassword9!', 'ChangedPassword9!');
    expect(flow.inlineField, 'otp');
    flow.otp = '654321';
    await flow.submitResetPassword('ChangedPassword9!', 'different');
    expect(flow.inlineField, 'confirm');
    flow.otp = '000000';
    await flow.submitResetPassword('ChangedPassword9!', 'ChangedPassword9!');
    expect(flow.inlineField, 'otp');
    expect(flow.stage, AuthStage.resetPassword);
    flow.otp = '654321';
    await flow.submitResetPassword('ChangedPassword9!', 'ChangedPassword9!');
    expect(flow.stage, AuthStage.signIn);
    expect(flow.notice, contains('Password updated'));
    flow.password = 'ChangedPassword9!';
    await flow.submitSignIn();
    expect(flow.canAccessApp, isTrue);
  });

  test(
    'unknown recovery address receives the same request confirmation',
    () async {
      await start();
      flow.openForgotPassword();
      flow.email = 'unknown@example.com';
      await flow.submitForgotPassword();
      expect(flow.stage, AuthStage.resetPassword);
      expect(
        flow.notice,
        'If an account exists for this address, a reset code has been sent.',
      );
      flow.otp = '654321';
      await flow.submitResetPassword('ChangedPassword9!', 'ChangedPassword9!');
      expect(flow.stage, AuthStage.resetPassword);
      expect(flow.inlineField, 'otp');
    },
  );

  test('restoration can be cancelled without late navigation', () async {
    await start();
    flow.dispose();
    service.establish('acc-seebu');
    service.restoreBarrier = Completer<void>();
    flow = AuthFlowController(
      session,
      service: service,
      emailVerificationEnabled: true,
    );
    flow.continueFromSplash();
    expect(flow.stage, AuthStage.sessionCheck);
    await flow.cancelSession();
    service.restoreBarrier!.complete();
    await pumpEventQueue();
    expect(flow.stage, AuthStage.signIn);
    expect(flow.canAccessApp, isFalse);
  });

  test(
    'resending replaces the verification challenge and clears the old code',
    () async {
      await start();
      service.cooldown = Duration.zero;
      await register();
      flow.otp = '000000';
      await flow.resendCode();
      expect(service.resendCalls, 1);
      expect(flow.otp, isEmpty);
      expect(flow.notice, contains('new verification code'));
      await flow.verifyCode('123456');
      expect(flow.stage, AuthStage.profileBasics);
    },
  );

  test(
    'unverified sign-in uses a server-issued verification challenge',
    () async {
      await start();
      final challenge = await service.register(
        name: 'New Player',
        email: 'new@example.com',
        password: 'NewPassword9!',
        intent: AccountIntent.player,
        acceptedTerms: true,
      );
      service.nextError = EmailVerificationRequired(challenge);
      flow.email = 'new@example.com';
      flow.password = 'NewPassword9!';
      await flow.submitSignIn();
      expect(flow.stage, AuthStage.verifyEmail);
      expect(flow.authenticated, isFalse);
      await flow.verifyCode('123456');
      expect(flow.stage, AuthStage.profileBasics);
      expect(flow.authenticated, isTrue);
    },
  );

  test(
    'email and OTP rules reject whitespace, invalid domains and signed codes',
    () async {
      await start();
      for (final email in [
        'bad@.com',
        'a@b..com',
        'a@b.com\nother',
        'a..b@site.com',
        'a@-site.com',
      ]) {
        expect(AuthRules.email(email), isFalse, reason: email);
      }
      expect(AuthRules.email('player+padel@example.com'), isTrue);
      for (final code in ['+12345', '-12345', '12345 ', '12345', 'abcdef']) {
        expect(AuthRules.otp(code), isFalse, reason: code);
      }
      expect(
        AuthRules.otp('000000'),
        isTrue,
      ); // shape only; service validates it
    },
  );

  test(
    'signup without verification takes the session in the same call',
    () async {
      await start(emailVerificationEnabled: false);
      final before = store.accounts.length;
      await register();

      expect(service.registerCalls, 0);
      expect(store.accounts, hasLength(before + 1));
      expect(flow.stage, AuthStage.profileBasics);
      expect(flow.authenticated, isTrue);
      expect(flow.canAccessApp, isFalse);
      expect(flow.password, isEmpty);
      expect(flow.otpSecondsLeft, 0);
      expect(flow.emailVerificationEnabled, isFalse);
      expect(flow.signupStepLabels, ['Account', 'Profile']);
    },
  );

  test(
    'a passwordless request has nowhere to go while verification is off',
    () async {
      await start(emailVerificationEnabled: false);
      flow.openSignIn();
      flow.email = store.accounts.first.email;
      await flow.beginPasswordlessSignIn();

      expect(service.signInCodeCalls, 0);
      expect(flow.stage, AuthStage.signIn);
      expect(flow.busy, isFalse);
    },
  );

  test(
    'a server-side confirmation request never opens the hidden code screen',
    () async {
      await start(emailVerificationEnabled: false);
      service.nextError = const EmailVerificationRequired(
        AuthChallenge(id: 'pending@example.com', email: 'pending@example.com'),
      );
      flow.email = 'pending@example.com';
      flow.password = 'NewPassword9!';
      await flow.submitSignIn();

      expect(flow.stage, AuthStage.signIn);
      expect(flow.authenticated, isFalse);
      expect(flow.inlineField, 'email');
      expect(flow.inlineError, contains('email confirmation'));
      expect(flow.otpSecondsLeft, 0);
    },
  );
}
