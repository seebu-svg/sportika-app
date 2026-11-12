# Sportika mobile prototype

A local Flutter/Dart sports prototype for Cricket, Padel, Futsal, and Badminton. All identities, competitions, scores, and notifications are fictional demonstration data. No backend or authentication service is required.

## Run

With Flutter installed:

```sh
flutter pub get
flutter run
```

The repository includes an Android runner. An iOS runner has not been generated or validated.

## Try the prototype

- Pick **Seebu Ali** for player and scorer functionality.
- Pick **Yasir Malik** for approved organizer tools and tournament management.
- Pick **Zain Rehman** for a player without official scoring permissions.
- Use **Profile → Switch account** to change roles. **Reset demo data** restores the expanded seed world if you already have older saved data.

The navigation is Home, Games, Events, Scores, Profile. Tab state survives switching.

**Games:** search titles/sports/locations, select a sport and category, filter date, availability, status, and fictional distance with the filter icon, join/leave a match, publish a validated match, and access team management. Match creation and membership persist across restarts.

**Events:** discover tournaments, review your entries or organized competitions, register, view fixtures/brackets/standings, and use organizer tools to manage entries, generate draws, assign scorers, and publish results.

**Scores:** follow live official fixtures and published results, or create/reopen/delete private scorecards. Each sport has its own scoring engine. Assigned scorers can record and undo official events and submit results for organizer review. Published results feed tournament progression. Official scoring mutations require both the scorer role and a fixture assignment.

**Profile:** edit your identity, inspect official participation/wins/losses and sport appearances, view teams and match history, open role-specific tools, and switch accounts.

## Local architecture

- `lib/domain/`: models, independent community games, event-based scoring engines, official results, tournament progression.
- `lib/data/seed.dart`: fictional Pakistani demo world, including 24 community games (seeded in `community_game.dart`), 20+ players, 10 teams, 8 tournaments, 12 published results, 8 live fixtures, 10 personal cards, and 15 notifications.
- `lib/state/app_state.dart`: shared state and mutation boundaries.
- `lib/data/local_storage.dart`: on-device JSON persistence through SharedPreferences.
- `lib/core/theme.dart`: dark navy Sportika palette with blue actions, mint highlights, and gold achievements.
- `lib/ui/`: reusable components, five-tab shell, detail views, and role workspaces.

Personal scorecards are owner-filtered, stored independently, and never feed official statistics or standings. Storage is intended for demonstration data, not sensitive production records.

## Verification and remaining work

The Flutter debug asset bundle compiles. A direct headless Flutter smoke check rendered all five core screens at 320 and 390 logical pixels without layout exceptions, using the offline photo fallback. It does not verify remote photo rendering or all interactions. A standalone Dart verification checked seed counts, community-game round trips and capacities, and replay of all personal scoring logs. The Flutter test suite could not start in the managed environment because it forbids the localhost socket used by Flutter's test runner. Static analysis was blocked by the SDK's telemetry write outside the workspace.

Run locally:

```sh
dart --enable-asserts tool/verify_demo.dart
flutter analyze
flutter test
flutter build apk --debug
```

This is an MVP implementation, not a finished production app. Home, game cards, event banners, and Profile now use real sport-specific photography from Unsplash and Pexels. Images load over HTTPS with loading and unavailable states. Photo sources are documented in `assets/PHOTO_CREDITS.md`. The generated montage is no longer referenced or bundled. Photo delivery requires internet; all match data remains local. Bundled Inter/Barlow fonts remain unfinished because external font downloads were unavailable; the UI currently uses the platform font fallback. Account reminder, invitation, and profile visibility switches are persisted demo preferences. Broader visual polish remains outstanding. Detail pages use normal full-screen navigation. Headless screenshots were reviewed for layout. Real-device photography checks, iOS validation, and a full interaction review remain outstanding.


The core-screen visual refinement adds a consistent mint Sportika lockup, editorial photograph banners, sporting typography, immediate player statistics, distinct event and live-score sections, structured match-card metadata, and consistent outline icons. Emoji and em dashes have been removed from the application source.

## Personal Games & Scoring prototype

Open **Scores → Personal → My personal games**. This module is separate from community pickup games and official tournament scoring. All personal cards are account-scoped and local to this device.

The 32 requested screens and states are implemented using dedicated pages, guided steps, filters, and confirmation dialogs:

| Requested screens | Prototype location |
| --- | --- |
| 1–7: dashboard, creation, sport, setup, sides, rules, review | My personal games → Create personal game; six guided steps |
| 8–12: scoring dashboard and four sport scorers | Personal dashboard → game → Open scoring; sport-specific engine and controls |
| 13–16: timeline, edit/undo, pause/resume, end | Scoring overflow menu → Timeline / edit scores, Pause / Resume, End game; undo confirmation below scoring controls |
| 17–22: active, paused, completed, details, edit, delete | Dashboard status filters → game details → Edit game details / Delete game |
| 23–25: result, scorecard, statistics | Completed game → result summary → Detailed scorecard / Match statistics |
| 26–28: history, filters, overview | Dashboard search, sport and date filters; insights button for recording activity |
| 29–32: settings, discard, empty, help | Scoring overflow → Scoring settings / Scoring help; leave creation to discard; empty lists show contextual states |

Game details retain venue, player roster and notes. House rules are notes; the selected format controls scoring. Paused games reject score actions. Undo and timeline replacement recalculate the event log, preserving paused status where appropriate. Manual endings keep the recorded score and do not infer a winner for unfinished games. Performance overview reports recording activity rather than attributing spectator results to the account holder. Player-level statistics require attributed event data and are not fabricated.

Personal cards never submit to organizers, change tournament results, or feed official standings. Settings and metadata are serialized alongside each personal card.

## Four-sport scoring screens (29 routes)

Create a personal game to enter its sport setup, or open an existing card and tap **[Sport] match centre** above the live score. The same match centre is available from personal game details.

- **Cricket (8):** match setup; toss and playing XI; live scoring; batting scorecard; bowling scorecard; over history; innings summary; match result.
- **Padel (7):** match setup; singles/doubles player selection; live scoring; game/set tracker; tie-break scoring; statistics; match result.
- **Futsal (7):** match setup; starting lineup; live scoreboard; timer/periods; goals/fouls/cards; events timeline; match result.
- **Badminton (7):** match setup; singles/doubles player selection; live scoring; rally/point tracker; game progress; statistics; match result.

Setup accepts 11 cricket players, five futsal starters, or one/two racket players per side. A clearly labelled button fills fictional demo players. Players can be omitted for quick spectator scoring; unattributed entries are explicitly shown as unassigned. Setup becomes read-only after scoring starts. Cricket toss determines the first batting side when configured; select striker, bowler and dismissal type before recording each delivery. Strike changes and bowler changes are manual. Bowling figures exclude byes/leg byes and run-out wickets; unspecified dismissals are not credited to a bowler.

Padel tie-break controls unlock at 6–6, and service order follows games and tie-break points. Badminton service follows the last rally winner. Progress and statistics derive from recorded events. Futsal clock display ticks from persisted start/stop timestamps; pausing the game stops its clock, resuming restarts it if previously running. Period boundaries and disciplinary enforcement are manual. Fouls accumulate separately per half; cards do not alter goals.

Validation: `dart run tool/verify_sport_prototype.dart` checks cricket extras/legal deliveries, padel tie-break progression/service, badminton rally service/30-point cap, and futsal clock persistence and discipline separation. Flutter UI tests require permission to bind a localhost socket.
