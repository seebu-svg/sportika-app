import 'package:sportika/core/data/profile_photo.dart';

/// Orchestrates one picture from the picker to a persisted reference.
///
/// The order matters and is deliberate:
/// 1. pick and validate the bytes;
/// 2. crop and downscale;
/// 3. write the file;
/// 4. only then move the account reference, and only then delete the old file.
///
/// So a failure at any step leaves the player with the avatar they had before
/// and no orphan on disk. In connected builds, persistence uploads to Supabase
/// Storage and updates the profile before the previous local file is deleted.
class ProfilePhotoService {
  ProfilePhotoService({
    required this.picker,
    required this.store,
    required this.accountId,
    required this.currentPath,
    required this.persist,
  });

  final PhotoPicker picker;
  final ProfilePhotoStore store;

  /// The signed-in account, or null while nobody is signed in.
  final String? Function() accountId;

  /// The reference the account currently carries, used to clean up on replace.
  final String? Function() currentPath;

  /// Moves the reference. Must restore the previous value and throw when the
  /// device refuses the write.
  final Future<void> Function(String? path) persist;

  /// Returns null when the player closed the camera or gallery without choosing.
  Future<PickedPhoto?> pick(PhotoSourceKind source) async {
    final bytes = await picker.grab(source);
    if (bytes == null) return null;
    return decodePickedPhoto(bytes, source);
  }

  /// Cropping, compression and storage for one already-picked picture.
  Future<StoredPhoto> commit({
    required PickedPhoto photo,
    required PhotoCrop crop,
  }) async {
    final id = accountId();
    if (id == null) {
      throw const PhotoException(
        PhotoFailure.notSignedIn,
        'Sign in before changing your profile picture.',
      );
    }
    final previous = currentPath();
    final bytes = await renderCroppedPhoto(photo, crop: crop);
    final String path;
    try {
      path = await store.write(accountId: id, bytes: bytes);
    } on PhotoException {
      rethrow;
    } catch (_) {
      throw const PhotoException(
        PhotoFailure.storage,
        'This device would not accept the picture. Free up space and try again.',
      );
    }
    try {
      await persist(path);
    } on Object {
      // The repository has already put the old reference back, so the new file
      // is the thing that must not linger.
      await store.discard(path);
      rethrow;
    }
    await store.discard(previous);
    return StoredPhoto(
      path: path,
      sourceBytes: photo.bytes.lengthInBytes,
      storedBytes: bytes.lengthInBytes,
      source: photo.source,
    );
  }

  /// Drops the reference first, so a refused write keeps the picture.
  Future<void> remove() async {
    final kept = currentPath();
    try {
      await persist(null);
    } on Object {
      throw const PhotoException(
        PhotoFailure.persistence,
        'Your device refused to remove the picture, so it is still set.',
      );
    }
    await store.discard(kept);
  }

  /// Sweep for the reset and clear-data flows, which drop the whole document.
  Future<void> purgeAllFiles() => store.discardAll();
}

/// What one successful import produced, kept small so the UI can report real
/// numbers instead of a generic "done".
class StoredPhoto {
  const StoredPhoto({
    required this.path,
    required this.sourceBytes,
    required this.storedBytes,
    required this.source,
  });

  final String path;
  final int sourceBytes;
  final int storedBytes;
  final PhotoSourceKind source;

  /// Short, honest description of the compression pass.
  String get summary =>
      '${PhotoBytes.label(sourceBytes)} to ${PhotoBytes.label(storedBytes)}';
}
