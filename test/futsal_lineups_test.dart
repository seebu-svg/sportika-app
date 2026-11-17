import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/matches/widgets/futsal_lineups.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';

import 'match_scoring_test.dart' as harness;

void main() {
  Future<SportMatch> setup(
    WidgetTester tester, {
    bool empty = false,
    bool readOnly = false,
    double scale = 1,
    bool confirmed = false,
    List<String>? initialIds,
    bool longNames = false,
    List<List<String>>? records,
  }) async {
    final store = await harness.loadedStore();
    final match = SportMatch(
      id: 'lineups',
      sport: Sport.futsal,
      formatLabel: '2 × 20 min',
      rules: confirmed || initialIds != null
          ? {
              'lineups': [
                initialIds ?? ['p0', 'p1', 'p2', 'p3', 'p4'],
                <String>[],
              ],
            }
          : {},
      title: 'Match',
      venue: 'Court',
      scheduledAt: DateTime(2026),
      visibility: MatchVisibility.public,
      organizerId: 'organizer',
      status: FixtureStatus.upcoming,
      sideNames: ['Home team', 'Away team'],
      discipline: MatchDiscipline.team,
      capacity: 14,
      createdAt: DateTime(2026),
    );
    if (!empty) {
      for (var i = 0; i < 7; i++) {
        match.participants.add(
          MatchParticipant(
            profileId: 'p$i',
            displayName: longNames
                ? 'Player $i with a very long display name'
                : 'Player $i',
            side: 0,
            status: i == 6
                ? MatchParticipantStatus.invited
                : MatchParticipantStatus.accepted,
          ),
        );
      }
    }
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SessionController(store),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: FutsalLineups(
                match: match,
                onRecord: readOnly
                    ? null
                    : (kind, side, data) {
                        expect(kind, 'lineup');
                        expect(side, 0);
                        records?.add(
                          List<String>.from(data['players'] as List),
                        );
                      },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return match;
  }

  testWidgets('selection limit, cancel, reopen and confirm accepted players', (
    tester,
  ) async {
    final records = <List<String>>[];
    await setup(tester, records: records);
    Future<void> open() async {
      await tester.tap(find.text('Edit Lineup').first);
      await tester.pumpAndSettle();
    }

    Future<void> choose(int i) async {
      final name = find.text('Player $i');
      await tester.scrollUntilVisible(
        name,
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(tester.element(name), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(name);
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.text('0/5 selected'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('Player 6'), findsNothing);
    for (var i = 0; i < 5; i++) {
      await choose(i);
    }
    await choose(5);
    tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('5/5 selected'), findsOneWidget);
    await choose(0);
    tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('4/5 selected'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(records, isEmpty);
    await open();
    expect(find.text('0/5 selected'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await choose(i);
    }
    await tester.tap(find.text('Confirm starting five'));
    await tester.pumpAndSettle();
    expect(records.single, ['p0', 'p1', 'p2', 'p3', 'p4']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed grid, substitutes and canceled edits preserve starters at large scale',
    (tester) async {
      await setup(tester, confirmed: true, scale: 2);
      expect(find.text('Starting five confirmed'), findsOneWidget);
      final substitutes = find.text('Substitutes (1)');
      await tester.ensureVisible(substitutes);
      await tester.tap(substitutes);
      await tester.pumpAndSettle();
      expect(find.text('Player 5'), findsOneWidget);
      await tester.ensureVisible(find.text('Edit Lineup').first);
      await tester.tap(find.text('Edit Lineup').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('5/5 selected'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('5/5 selected'), findsOneWidget);
      final name = find.descendant(
        of: find.byType(ListView),
        matching: find.text('Player 0'),
      );
      await tester.scrollUntilVisible(
        name,
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(tester.element(name), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(name);
      await tester.pumpAndSettle();
      expect(find.text('4/5 selected'), findsOneWidget);
      tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Starting five confirmed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty read-only layout supports large text at 320dp', (
    tester,
  ) async {
    await setup(tester, empty: true, readOnly: true, scale: 2);
    expect(find.text('Edit Lineup'), findsNothing);
    expect(find.textContaining('No accepted players yet.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large text sheet scrolls and empty confirmation stays disabled',
    (tester) async {
      await setup(tester, empty: true, scale: 2);
      await tester.tap(find.text('Edit Lineup').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'incomplete roster remains editable and names truncate accessibly',
    (tester) async {
      await setup(
        tester,
        initialIds: ['p0', 'p1', 'missing'],
        longNames: true,
        scale: 2,
      );
      expect(find.text('2/5 · Awaiting confirmation'), findsOneWidget);
      final name = tester.widget<Text>(
        find.text('Player 0 with a very long display name'),
      );
      expect(name.maxLines, 2);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(name.semanticsLabel, name.data);
      expect(find.text('Edit Lineup'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unchanged confirmation and rapid taps do not submit duplicate events',
    (tester) async {
      final records = <List<String>>[];
      await setup(tester, confirmed: true, records: records);
      await tester.tap(find.text('Edit Lineup').first);
      await tester.pumpAndSettle();
      final confirm = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      confirm();
      confirm();
      await tester.pumpAndSettle();
      expect(records, isEmpty);
      expect(find.byType(FutsalLineupSelectionSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reverse selection order saves canonical roster order once', (
    tester,
  ) async {
    final records = <List<String>>[];
    await setup(tester, records: records);
    await tester.tap(find.text('Edit Lineup').first);
    await tester.pumpAndSettle();
    for (final i in [4, 3, 2, 1, 0]) {
      final player = find.descendant(
        of: find.byType(ListView),
        matching: find.text('Player $i'),
      );
      await tester.scrollUntilVisible(
        player,
        i == 4 ? 150 : -150,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(player);
      await tester.pumpAndSettle();
    }
    final confirm = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    confirm();
    confirm();
    await tester.pumpAndSettle();
    expect(records, [
      ['p0', 'p1', 'p2', 'p3', 'p4'],
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale accepted player is removed before confirmation', (
    tester,
  ) async {
    final records = <List<String>>[];
    final match = await setup(tester, confirmed: true, records: records);
    await tester.tap(find.text('Edit Lineup').first);
    await tester.pumpAndSettle();
    match.participants.first.status = MatchParticipantStatus.removed;
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!();
    await tester.pumpAndSettle();
    expect(records, isEmpty);
    expect(find.text('4/5 selected'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byType(FutsalLineupSelectionSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed read-only roster exposes no edit action', (
    tester,
  ) async {
    await setup(tester, confirmed: true, readOnly: true);
    expect(find.text('Starting five confirmed'), findsOneWidget);
    expect(find.text('Edit Lineup'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('concurrent lineup change is not overwritten', (tester) async {
    final records = <List<String>>[];
    final match = await setup(tester, confirmed: true, records: records);
    await tester.tap(find.text('Edit Lineup').first);
    await tester.pumpAndSettle();
    match.rules['lineups'] = [
      ['p1', 'p2', 'p3', 'p4', 'p5'],
      <String>[],
    ];
    await tester.tap(find.text('Confirm starting five'));
    await tester.pumpAndSettle();
    expect(records, isEmpty);
    expect(
      find.text('The roster changed. Review the lineup and try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection exposes checkbox semantics and a persistent counter', (
    tester,
  ) async {
    await setup(tester);
    await tester.tap(find.text('Edit Lineup').first);
    await tester.pumpAndSettle();
    final player = find.descendant(
      of: find.byType(ListView),
      matching: find.text('Player 0'),
    );
    await tester.scrollUntilVisible(
      player,
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(player), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(player);
    await tester.pumpAndSettle();
    final selection = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.label == 'Player 0' &&
          w.properties.checked != null,
    );
    expect(tester.widget<Semantics>(selection).properties.checked, isTrue);
    expect(find.text('1/5 selected').hitTestable(), findsOneWidget);
    expect(find.text('Confirm starting five').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
