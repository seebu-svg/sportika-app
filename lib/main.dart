import 'package:sportika/core/data/identity_document_store.dart';
import 'package:sportika/core/data/supabase_identity_document_store.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app.dart';
import 'package:sportika/app/env.dart';
import 'package:sportika/app/error_handling.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/data/secure_auth_storage.dart';
import 'package:sportika/core/data/supabase_account_repository.dart';
import 'package:sportika/core/data/supabase_fixture_repository.dart';
import 'package:sportika/core/data/supabase_game_repository.dart';
import 'package:sportika/core/data/supabase_match_repository.dart';
import 'package:sportika/core/data/supabase_team_repository.dart';
import 'package:sportika/core/data/supabase_tournament_repository.dart';
import 'package:sportika/core/data/supabase_monetization_repository.dart';
import 'package:sportika/core/data/supabase_notification_repository.dart';
import 'package:sportika/core/data/supabase_profile_module_repository.dart';
import 'package:sportika/features/auth/services/authentication_service.dart';
import 'package:sportika/features/auth/services/mock_authentication_service.dart';
import 'package:sportika/features/auth/services/supabase_authentication_service.dart';
import 'package:sportika/shared/data/local_storage.dart';
// Prefixed because Supabase exports its own `LocalStorage`, and this file needs
// Sportika's on-device document store under that name.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash guards go in before anything else can throw: a failed first read
  // still has to reach a friendly screen instead of a blank window.
  installGlobalErrorHandling(onReport: _reportError);

  runZonedGuarded(() async {
    // Sportika keeps its games, teams and scorecards in one on-device document,
    // so the first frame already has the saved tournament state. Identity is the
    // one thing that comes from the server.
    final storage = await LocalStorage.open();
    // A live build must never paint the fictional Karachi world over a real
    // session; the device document still holds personal scorecards, but it
    // starts empty and only the demo build seeds itself.
    final state = LocalSportikaRepository(
      storage,
      seedOnFirstRun: AppEnv.demoMode,
    );
    await state.load();

    final backend = await _openAuthentication(state, storage);

    runApp(
      ChangeNotifierProvider<LocalSportikaRepository>.value(
        value: state,
        child: SportikaApp(
          authenticationService: backend.authentication,
          accountRepository: backend.accountRepository,
          profileModuleRepository: backend.profileModule,
          matchRepository: backend.matchRepository,
          tournamentRepository: backend.tournaments,
          fixtureRepository: backend.fixtures,
          gameRepository: backend.games,
          teamRepository: backend.teams,
          notificationRepository: backend.notifications,
          monetizationRepository: backend.monetization,
          identityStore: backend.identityStore,
        ),
      ),
    );
  }, _reportError);
}

/// What this build authenticates against, and where identity is read from.
///
/// The two travel together on purpose: a remote session with a device profile
/// would authenticate one member and then draw another.
typedef _Backend = ({
  AuthenticationService authentication,
  AccountRepository? accountRepository,
  ProfileModuleRepository? profileModule,
  MatchRepository? matchRepository,
  TournamentRepository? tournaments,
  FixtureRepository? fixtures,
  GameRepository? games,
  TeamRepository? teams,
  NotificationRepository? notifications,
  MonetizationRepository? monetization,
  IdentityDocumentStore? identityStore,
});

/// Chooses the authentication implementation for this build exactly once.
///
/// The three outcomes are deliberate: an internal demo build talks to the seeded
/// device world, a configured build talks to Supabase, and anything else refuses
/// to authenticate at all. There is no silent fallback between them.
Future<_Backend> _openAuthentication(
  LocalSportikaRepository state,
  LocalStorage storage,
) async {
  switch (AppEnv.authBackend) {
    case AuthBackend.demo:
      return (
        authentication: MockAuthenticationService(state),
        accountRepository: null,
        profileModule: null,
        matchRepository: null,
        tournaments: null,
        fixtures: null,
        games: null,
        teams: null,
        notifications: null,
        monetization: null,
        identityStore: null,
      );

    case AuthBackend.supabase:
      try {
        await supabase.Supabase.initialize(
          url: AppEnv.supabaseUrl,
          publishableKey: AppEnv.supabaseKey,
          authOptions: supabase.FlutterAuthClientOptions(
            // The session is a credential, so it lives behind the Android
            // keystore rather than in shared preferences.
            localStorage: SecureSessionStorage(),
            pkceAsyncStorage: SecureGotrueStorage(),
            // Email links (signup confirmation, magic link, recovery, email
            // change) land on the app's own scheme; the predicate keeps
            // unrelated deep links from being exchanged for a session.
            detectSessionInUri: true,
            detectSessionInUriPredicate: AppEnv.isAuthCallback,
          ),
        );
        final client = supabase.Supabase.instance.client;
        final accounts = SupabaseAccountRepository(
          client: client,
          device: state,
        );
        final matches = SupabaseMatchRepository(
          client: client,
          outbox: storage,
        );
        final tournaments = SupabaseTournamentRepository(
          client: client,
          accounts: accounts,
        );
        // A tournament fixture *is* a match row, so the bracket and the review
        // queue project the match module instead of keeping a second copy of
        // the event log.
        final fixtures = SupabaseFixtureRepository(
          matches: matches,
          tournaments: tournaments,
          accounts: accounts,
        );
        // Standings read the same fixtures, so the two views can never disagree
        // about which result was published.
        tournaments.fixturesOf = fixtures.fixturesFor;
        return (
          authentication: SupabaseAuthenticationService(client),
          identityStore: SupabaseIdentityDocumentStore(client),
          accountRepository: accounts,
          // The Me module reloads [accounts] after every write, so the header
          // and the profile screen cannot drift apart.
          profileModule: SupabaseProfileModuleRepository(
            client: client,
            accounts: accounts,
          ),
          // Official matches are the one aggregate the server owns end to end:
          // the outbox keeps a scoring tap alive across a dropped connection.
          matchRepository: matches,
          tournaments: tournaments,
          fixtures: fixtures,
          games: SupabaseGameRepository(client: client),
          teams: SupabaseTeamRepository(
            client: client,
            directory: accounts.directory,
            accounts: accounts,
          ),
          // The inbox is server-owned too: the member only ever sees their own
          // rows, and the live channel carries new ones without polling.
          notifications: SupabaseNotificationRepository(client: client),
          // Billing is the one aggregate a member must never be able to fake:
          // every write is an RPC and the operator functions have no member
          // grant.
          monetization: SupabaseMonetizationRepository(client: client),
        );
      } catch (error, stack) {
        // A bad URL or key must not blank the app. The sign-in screen explains
        // that the service is unavailable instead.
        _reportError(error, stack);
        return (
          authentication: UnavailableAuthenticationService(),
          accountRepository: null,
          profileModule: null,
          matchRepository: null,
          tournaments: null,
          fixtures: null,
          games: null,
          teams: null,
          notifications: null,
          monetization: null,
          identityStore: null,
        );
      }

    case AuthBackend.unavailable:
      return (
        authentication: UnavailableAuthenticationService(),
        accountRepository: null,
        profileModule: null,
        matchRepository: null,
        tournaments: null,
        fixtures: null,
        games: null,
        teams: null,
        notifications: null,
        monetization: null,
        identityStore: null,
      );
  }
}

/// Single sink for uncaught errors. Debug prints the report; release keeps the
/// console clean for the store build but still records it for the crash tool
/// that will replace this stub.
void _reportError(Object error, StackTrace stack) {
  debugPrint('Sportika error: $error');
  if (kDebugMode) debugPrintStack(stackTrace: stack);
}
