import 'dart:typed_data';

enum IdentityDocumentKind { cnic, bForm }

extension IdentityDocumentKindX on IdentityDocumentKind {
  String get label => this == IdentityDocumentKind.cnic ? 'CNIC' : 'B-Form';
  String get key => this == IdentityDocumentKind.cnic ? 'cnic' : 'b_form';
}

/// Calendar age; a member becomes an adult on their eighteenth birthday.
IdentityDocumentKind identityKindFor(DateTime birthDate, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final age =
      now.year -
      birthDate.year -
      ((now.month < birthDate.month ||
              (now.month == birthDate.month && now.day < birthDate.day))
          ? 1
          : 0);
  return age >= 18 ? IdentityDocumentKind.cnic : IdentityDocumentKind.bForm;
}

String normalizeIdentityNumber(String value) =>
    value.trim().replaceAll('-', '');

String? validateIdentityNumber(String value) {
  if (value.trim().isEmpty) return null;
  if (!RegExp(r'^(?:[0-9]{13}|[0-9]{5}-[0-9]{7}-[0-9])$')
      .hasMatch(value.trim())) {
    return 'Use 13 digits, or 12345-1234567-1. You can also leave this blank.';
  }
  return null;
}

/// Sensitive, ephemeral setup data. Never added to Account or device JSON.
class IdentityDocumentDraft {
  String number = '';
  Uint8List? front;
  Uint8List? back;

  bool get isEmpty => number.trim().isEmpty && front == null && back == null;
  void clear() {
    number = '';
    front = null;
    back = null;
  }
}

class IdentitySubmission {
  const IdentitySubmission({
    required this.kind,
    this.number,
    this.front,
    this.back,
  });
  final IdentityDocumentKind kind;
  final String? number;
  final Uint8List? front, back;
  bool get isEmpty =>
      (number?.isEmpty ?? true) && front == null && back == null;
}
