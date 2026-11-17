import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/core/data/profile_photo_service.dart';
import 'package:sportika/core/data/repositories.dart';
import 'package:sportika/core/state/feature_controller.dart';
import 'package:sportika/shared/models/models.dart';

/// Where the profile-picture flow stands.
///
/// Storage does not expose byte progress; show an indeterminate meter until
/// both the image and account reference are saved.
enum PhotoFlowStage { idle, picking, cropping, saving, removing, failed }

/// Owns the profile picture for the signed-in account.
///
/// Screens call [start], [save] and [remove]; nothing in the widget tree touches
/// the picker plugin, the photo files or the account reference directly.
class ProfilePhotoController extends FeatureController<ProfileRepository> {
  ProfilePhotoController(super.repo, {required this.service});

  /// The pick, crop, compress and store pipeline this controller drives.
  final ProfilePhotoService service;

  PhotoFlowStage _stage = PhotoFlowStage.idle;
  PickedPhoto? _pending;
  StoredPhoto? _lastStored;
  PhotoFailure? _failureKind;
  String? _failureMessage;

  Account? get account => repo.currentAccount;

  /// The stored reference, or null while the preset avatar is showing.
  String? get photoPath => repo.currentAccount?.photoPath;

  /// The uploaded copy of the picture, when the account has one. A server-backed
  /// account keeps this after the local file is gone.
  String? get photoUrl => repo.currentAccount?.photoUrl;

  bool get hasPhoto => repo.currentAccount?.hasPhoto ?? false;

  PhotoFlowStage get stage => _stage;

  /// A picture that has been picked but not committed yet; the cropper draws it.
  PickedPhoto? get pending => _pending;

  /// Result of the last successful import, so the UI can quote the real
  /// compression numbers back to the player.
  StoredPhoto? get lastStored => _lastStored;

  PhotoFailure? get failureKind => _failureKind;
  String? get failureMessage => _failureMessage;
  bool get hasFailure => _failureMessage != null;

  bool get busy =>
      _stage == PhotoFlowStage.picking ||
      _stage == PhotoFlowStage.saving ||
      _stage == PhotoFlowStage.removing;

  /// One line describing what is happening right now, used by the progress meter
  /// and by the error state alike.
  String get statusLabel => switch (_stage) {
    PhotoFlowStage.idle => 'Your profile picture is up to date.',
    PhotoFlowStage.picking => 'Reading the picture you chose…',
    PhotoFlowStage.cropping => 'Frame the shot, then save it.',
    PhotoFlowStage.saving => 'Preparing and uploading your profile picture…',
    PhotoFlowStage.removing => 'Removing the picture…',
    PhotoFlowStage.failed =>
      _failureMessage ?? 'That picture could not be used.',
  };

  /// Opens the camera or the gallery.
  ///
  /// Returns the picture that is now waiting to be cropped, or null when the
  /// player backed out of the system sheet or the picture was rejected.
  Future<PickedPhoto?> start(PhotoSourceKind source) async {
    if (busy) return null;
    _pending = null;
    _stage = PhotoFlowStage.picking;
    _clearFailure();
    notifyListeners();
    try {
      final photo = await service.pick(source);
      if (photo == null) {
        // Nothing was chosen and nothing was lost: back to idle, quietly.
        _stage = PhotoFlowStage.idle;
        notifyListeners();
        return null;
      }
      _pending = photo;
      _stage = PhotoFlowStage.cropping;
      notifyListeners();
      return photo;
    } on PhotoException catch (error) {
      _reject(error);
      return null;
    } catch (_) {
      _reject(
        const PhotoException(
          PhotoFailure.unreadable,
          'Something went wrong while reading that picture. Nothing was '
          'changed, so your current avatar is still in place.',
        ),
      );
      return null;
    }
  }

  /// Commits the pending picture with [crop]. True when the account now points
  /// at the new file.
  Future<bool> save(PhotoCrop crop) async {
    final photo = _pending;
    if (photo == null) {
      _reject(
        const PhotoException(
          PhotoFailure.unreadable,
          'That picture is no longer available. Choose one again.',
        ),
      );
      return false;
    }
    _stage = PhotoFlowStage.saving;
    notifyListeners();
    try {
      final stored = await service.commit(photo: photo, crop: crop);
      _lastStored = stored;
      _pending = null;
      _stage = PhotoFlowStage.idle;
      _clearFailure();
      notifyListeners();
      return true;
    } on PhotoException catch (error) {
      _reject(error, backToCropping: true);
      return false;
    } catch (_) {
      _reject(
        const PhotoException(
          PhotoFailure.storage,
          'This device refused the picture. Your previous avatar is still in '
          'place.',
        ),
        backToCropping: true,
      );
      return false;
    }
  }

  /// Clears the picture and goes back to the preset avatar. The file is only
  /// deleted once the reference is gone, so a refused write cannot leave the
  /// account pointing at a file that no longer exists.
  Future<bool> remove() async {
    if (busy) return false;
    _pending = null;
    _stage = PhotoFlowStage.removing;
    _clearFailure();
    notifyListeners();
    try {
      await service.remove();
      _stage = PhotoFlowStage.idle;
      _lastStored = null;
      notifyListeners();
      return true;
    } on PhotoException catch (error) {
      _reject(error);
      return false;
    } catch (_) {
      _reject(
        const PhotoException(
          PhotoFailure.persistence,
          'This device would not remove the picture, so it is still set.',
        ),
      );
      return false;
    }
  }

  /// Closes the cropper without saving. The old avatar stays untouched.
  void discardPending() {
    _pending = null;
    if (_stage == PhotoFlowStage.cropping || _stage == PhotoFlowStage.failed) {
      _stage = PhotoFlowStage.idle;
    }
    _clearFailure();
    notifyListeners();
  }

  void dismissFailure() {
    if (_stage == PhotoFlowStage.failed) _stage = PhotoFlowStage.idle;
    _clearFailure();
    notifyListeners();
  }

  /// Sweep for the reset and clear-data flows. File cleanup is best effort: a
  /// failure there must not make the account document look like it survived.
  Future<void> purgeStoredFiles() => service.purgeAllFiles();

  void _reject(PhotoException error, {bool backToCropping = false}) {
    _failureKind = error.kind;
    _failureMessage = error.message;
    _stage = backToCropping && _pending != null
        ? PhotoFlowStage.cropping
        : PhotoFlowStage.failed;
    notifyListeners();
  }

  void _clearFailure() {
    _failureKind = null;
    _failureMessage = null;
  }
}
