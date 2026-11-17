import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/shared/models/models.dart';

/// The uploaded copy of a profile picture is a second reference, not a
/// replacement: a device can hold the file, the URL, or neither.
void main() {
  Account account({String? photoPath, String? photoUrl}) => Account(
    id: 'acc-1',
    displayName: 'Ayesha Khan',
    email: 'ayesha@sportika.pk',
    city: 'Lahore',
    roles: const [],
    photoPath: photoPath,
    photoUrl: photoUrl,
  );

  test('the uploaded URL survives the account document', () {
    const url = 'https://cdn.sportika.pk/avatars/acc-1/avatar-1.png';
    final restored = Account.fromJson(account(photoUrl: url).toJson());

    expect(restored.photoUrl, url);
    expect(restored.photoPath, isNull);
  });

  test('both references survive together', () {
    const url = 'https://cdn.sportika.pk/avatars/acc-1/avatar-1.png';
    const path = '/data/support/profile_photos/avatar-acc-1-1.png';
    final restored = Account.fromJson(
      account(photoPath: path, photoUrl: url).toJson(),
    );

    expect(restored.photoPath, path);
    expect(restored.photoUrl, url);
  });

  test('an uploaded picture alone counts as a photo', () {
    expect(account(photoUrl: 'https://cdn.sportika.pk/a.png').hasPhoto, isTrue);
  });

  test('an account written before URLs existed still reads as photo-free', () {
    final legacy = account().toJson()..remove('photoUrl');
    final restored = Account.fromJson(legacy);

    expect(restored.photoUrl, isNull);
    expect(restored.hasPhoto, isFalse);
  });

  group('initials', () {
    Account named(String displayName) => Account(
      id: 'acc-1',
      displayName: displayName,
      email: 'ayesha@sportika.pk',
      city: 'Lahore',
      roles: const [],
    );

    test('takes the first letter of each end of the name', () {
      expect(named('Ayesha Khan').initials, 'AK');
      expect(named('  ayesha   khan  ').initials, 'AK');
      expect(named('Zara').initials, 'Z');
    });

    // A server row can carry no display name, and the avatar must still build
    // instead of throwing on substring(0, 1) of an empty string.
    test('a missing or blank name renders the neutral placeholder', () {
      expect(named('').initials, '?');
      expect(named('   ').initials, '?');
    });
  });
}
