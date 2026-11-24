import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/profile_avatar.dart';

void main() {
  testWidgets(
    'profile portrait fits narrow layouts and exposes camera editing',
    (tester) async {
      var edits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                child: ProfileAvatar(initials: 'SK', onEdit: () => edits++),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ProfileAvatar)), const Size(120, 120));
      expect(find.byType(ClipOval), findsWidgets);
      expect(find.text('SK'), findsOneWidget);
      final edit = find.byTooltip('Edit profile picture');
      expect(
        tester
            .getRect(find.byType(ProfileAvatar))
            .contains(tester.getCenter(edit)),
        isTrue,
      );
      await tester.tap(edit);
      expect(edits, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('busy avatar blocks duplicate edits and shows progress', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(
            initials: '',
            size: 80,
            busy: true,
            onEdit: () => edits++,
          ),
        ),
      ),
    );
    expect(find.byType(BrandedDefaultAvatar), findsOneWidget);
    expect(find.text('?'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byTooltip('Updating profile picture'));
    expect(edits, 0);
    expect(tester.takeException(), isNull);
  });
}
