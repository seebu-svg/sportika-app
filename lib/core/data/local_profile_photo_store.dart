import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:sportika/core/data/profile_photo.dart';

/// Keeps avatar pictures as files, never as bytes inside the account document.
///
/// The persisted state is a single JSON document on SharedPreferences, which is
/// the wrong place for a several-hundred-kilobyte image: every mutation rewrites
/// the whole document. So the document stores only the path this class hands
/// back, and the bytes live in the app's support directory.
///
/// No backend exists yet, so there is no URL to fetch and nothing is uploaded
/// off-device. `ApiProfilePhotoStore` can replace this class behind the same
/// interface when a real endpoint lands.
class LocalProfilePhotoStore implements ProfilePhotoStore {
  LocalProfilePhotoStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const String dirName = managedPhotoDirName;
  static const String prefix = managedPhotoFileNamePrefix;

  final Future<Directory> Function() _directoryProvider;

  Future<Directory> directory() async {
    final base = await _directoryProvider();
    final dir = Directory('${base.path}/$dirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String> write({
    required String accountId,
    required Uint8List bytes,
  }) async {
    final dir = await directory();
    final name =
        '$prefix${_sanitize(accountId)}'
        '-${DateTime.now().microsecondsSinceEpoch}.png';
    final file = File('${dir.path}/$name');
    try {
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw PhotoException(
        PhotoFailure.storage,
        'This device refused to store the picture (${error.osError?.message ?? 'write failed'}).',
      );
    }
    return file.path;
  }

  @override
  bool manages(String? path) => looksLikeManagedPhotoPath(path);

  @override
  Future<void> discard(String? path) async {
    if (!manages(path)) return;
    try {
      final file = File(path!);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // A leftover file is not worth failing the player's action over; the
      // next reset sweeps it up.
    }
  }

  @override
  Future<void> discardAll() async {
    final dir = Directory('${(await _directoryProvider()).path}/$dirName');
    if (!dir.existsSync()) return;
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // See discard(): cleanup is best effort.
    }
  }

  /// Account ids are internal ids, but the seed is user-editable JSON, so only
  /// characters that can never form a traversal or a hidden path are kept.
  String _sanitize(String accountId) {
    final cleaned = accountId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return cleaned.isEmpty ? 'account' : cleaned;
  }
}
