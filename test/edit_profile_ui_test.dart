import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/app/routes.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/features/profile/screens/edit_profile_screen.dart';
import 'package:sportika/shared/widgets/profile_avatar.dart';

import 'helpers/harness.dart';

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AuthField && w.label == label),
  matching: find.byType(TextField),
);

Future<void> openEditor(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  final repo = await freshState();
  await repo.signIn('acc-seebu');
  await pumpApp(tester, state: repo, size: size, textScale: scale);
  pushRoute(tester.element(find.byType(NavigationBar)), AppRoute.editProfile);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unsaved edits require confirmation and can be retained or discarded',
    (tester) async {
      await openEditor(tester);
      await tester.ensureVisible(field('Full name'));
      await tester.enterText(field('Full name'), 'Ayesha Athlete');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Full name')).controller!.text,
        'Ayesha Athlete',
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('avatar opens photo management and invalid edits stay inline', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.byType(ProfileAvatar));
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    Navigator.pop(tester.element(find.text('Profile picture')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(field('Full name'));
    await tester.enterText(field('Full name'), 'A');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a full name between 2 and 80 characters.'),
      findsOneWidget,
    );
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('city browser supports search and leaves free entry available', (
    tester,
  ) async {
    await openEditor(tester, size: const Size(800, 360), scale: 1.3);
    await tester.scrollUntilVisible(
      field('City'),
      160,
      scrollable: find
          .descendant(
            of: find.byType(EditProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Browse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your city'), findsOneWidget);
    final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search cities',
    );
    await tester.ensureVisible(search);
    await tester.enterText(search, 'No matching city');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No matching cities. You can enter yours directly in the form.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(800, 360),
  ]) {
    testWidgets(
      'editor fits $size with enlarged text and sticky keyboard action',
      (tester) async {
        await openEditor(tester, size: size, scale: 1.3);
        final scrollable = find
            .descendant(
              of: find.byType(EditProfileScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        for (
          double offset = 0;
          offset < position.maxScrollExtent + 300;
          offset += 300
        ) {
          position.jumpTo(offset.clamp(0, position.maxScrollExtent));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('Save changes').hitTestable(), findsOneWidget);
        tester.view.viewInsets = FakeViewPadding(
          bottom: size.height > 600 ? 280 : 160,
        );
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(find.text('Save changes').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
