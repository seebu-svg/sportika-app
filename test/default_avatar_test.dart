import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/models/profile_setup.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// A member without a profile picture must never leave a blank disc: the
/// branded default portrait fills the slot, and the silhouette follows the
/// gender the member stated during setup.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: buildSportikaTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  Account account({required String displayName, ProfileGender? gender}) =>
      Account(
        id: 'acc-1',
        displayName: displayName,
        email: 'ayesha@sportika.pk',
        city: 'Lahore',
        roles: const [],
        gender: gender,
      );

  group('figure selection', () {
    test('stated genders map to their silhouette, the rest stay neutral', () {
      expect(
        defaultAvatarFigureFor(ProfileGender.man),
        DefaultAvatarFigure.man,
      );
      expect(
        defaultAvatarFigureFor(ProfileGender.woman),
        DefaultAvatarFigure.woman,
      );
      expect(
        defaultAvatarFigureFor(ProfileGender.nonBinary),
        DefaultAvatarFigure.neutral,
      );
      expect(
        defaultAvatarFigureFor(ProfileGender.preferNotToSay),
        DefaultAvatarFigure.neutral,
      );
      expect(defaultAvatarFigureFor(null), DefaultAvatarFigure.neutral);
    });

    test('empty placeholders are not treated as initials', () {
      expect(hasAvatarInitials('AK'), isTrue);
      expect(hasAvatarInitials(' a '), isTrue);
      expect(hasAvatarInitials(null), isFalse);
      expect(hasAvatarInitials(''), isFalse);
      expect(hasAvatarInitials('   '), isFalse);
      expect(hasAvatarInitials('?'), isFalse);
      expect(hasAvatarInitials('—'), isFalse);
      expect(hasAvatarInitials('-'), isFalse);
    });
  });

  testWidgets('the default portrait is a flat branded disc', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const BrandedDefaultAvatar(size: 64, figure: DefaultAvatarFigure.woman),
      ),
    );

    expect(
      tester.getSize(find.byType(BrandedDefaultAvatar)),
      const Size(64, 64),
    );
    expect(find.byIcon(Icons.woman_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Default profile picture'), findsOneWidget);

    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(BrandedDefaultAvatar),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.color, SportikaColors.surfaceAlt);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('the disc keeps its proportions on the smallest tiles', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandedDefaultAvatar(size: 22),
            BrandedDefaultAvatar(size: 36, figure: DefaultAvatarFigure.man),
          ],
        ),
      ),
    );

    expect(tester.getSize(find.byType(BrandedDefaultAvatar).first).height, 22);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.byIcon(Icons.man_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('PlayerAvatar', () {
    testWidgets('a name without a picture keeps its initials', (tester) async {
      await tester.pumpWidget(host(const PlayerAvatar(initials: 'AK')));

      expect(find.text('AK'), findsOneWidget);
      expect(find.byType(BrandedDefaultAvatar), findsNothing);
    });

    testWidgets('a photo-less empty slot shows the default portrait', (
      tester,
    ) async {
      await tester.pumpWidget(host(const PlayerAvatar(initials: '?')));

      expect(find.byType(BrandedDefaultAvatar), findsOneWidget);
      expect(find.text('?'), findsNothing);
    });

    testWidgets('a neutral dash is a default portrait, not letters', (
      tester,
    ) async {
      await tester.pumpWidget(host(const PlayerAvatar(initials: '—')));

      expect(find.byType(BrandedDefaultAvatar), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });
  });

  group('AccountAvatar', () {
    testWidgets('a nameless member gets the portrait for their gender', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AccountAvatar(
            account: account(displayName: '', gender: ProfileGender.woman),
            size: 44,
          ),
        ),
      );

      expect(find.byIcon(Icons.woman_rounded), findsOneWidget);
    });

    testWidgets('a nameless member with no stated gender stays neutral', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(AccountAvatar(account: account(displayName: ''), size: 44)),
      );

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('a named member without a picture keeps the chosen initials', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AccountAvatar(
            account: account(
              displayName: 'Ayesha Khan',
              gender: ProfileGender.woman,
            ),
            size: 44,
          ),
        ),
      );

      expect(find.text('AK'), findsOneWidget);
      expect(find.byType(BrandedDefaultAvatar), findsNothing);
    });
  });
}
