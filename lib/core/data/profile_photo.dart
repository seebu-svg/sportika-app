import 'dart:typed_data';
import 'dart:ui' as ui;

/// Everything the profile-picture feature needs that is independent of the
/// picker plugin, the file system and the widget tree.
///
/// Sportika has no backend today (see README "Scope"), so an "upload" is an
/// import into this device's storage: the bytes are validated, cropped,
/// downscaled and written to a file, and only the resulting path is persisted in
/// the account document. The seams below exist so a future
/// `ApiProfilePhotoStore` can replace the local one without touching a screen.

/// Where the picture came from.
enum PhotoSourceKind { camera, gallery }

/// Why a picture could not become an avatar. Each case has distinct copy in
/// the UI, so the player learns what to change instead of seeing a toast.
enum PhotoFailure {
  cancelled,
  unsupportedType,
  tooSmall,
  tooLarge,
  unreadable,

  /// The camera or gallery could not be opened at all: no capture app, a
  /// denied permission, or the platform picker refused to start.
  sourceUnavailable,
  storage,
  persistence,
  notSignedIn,
}

class PhotoException implements Exception {
  const PhotoException(this.kind, this.message);

  final PhotoFailure kind;
  final String message;

  /// True when nothing was lost and the player simply backed out.
  bool get isCancel => kind == PhotoFailure.cancelled;

  @override
  String toString() => 'PhotoException(${kind.name}): $message';
}

class PhotoRules {
  /// Smallest accepted edge in pixels. Below this the avatar is a blur at
  /// 3x sizes, so the picture is rejected with actionable copy.
  static const int minEdge = 240;

  /// Largest accepted source in bytes (12 MB). Camera JPEGs on mid-range
  /// Android sit well under this.
  static const int maxSourceBytes = 12 * 1024 * 1024;

  /// Edge length of the stored square. 512 keeps the tile crisp on a 3x
  /// device at the largest avatar in the app (112 dp) while staying small.
  static const int storedEdge = 512;

  static const int maxZoom = 4;

  /// Magic numbers of the container formats the picker is allowed to hand
  /// over. JPEG, PNG and WebP cover every Android camera and gallery output.
  static bool isSupportedBytes(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    final isPng =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final isWebp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isJpeg || isPng || isWebp;
  }
}

/// A picture the player just selected, before any cropping.
class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
    required this.source,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final PhotoSourceKind source;

  int get shortestEdge => width < height ? width : height;

  /// Human readable source size, used to show what compression saved.
  String get sourceSizeLabel => PhotoBytes.label(bytes.length);
}

/// Pan/zoom selection inside a square viewport, expressed in viewport units so
/// the widget and the renderer agree on the same numbers.
class PhotoCrop {
  const PhotoCrop({this.scale = 1, this.dx = 0, this.dy = 0});

  /// Extra zoom on top of the cover baseline. 1.0 means "fill the viewport".
  final double scale;

  /// Top-left of the drawn image inside the viewport, always <= 0.
  final double dx;
  final double dy;

  /// Side of the square viewport these numbers were authored against.
  static const double viewportEdge = 260;

  /// The scale at which the image just covers a square viewport.
  static double coverScale(double imageWidth, double imageHeight) =>
      viewportEdge / (imageWidth < imageHeight ? imageWidth : imageHeight);

  /// The drawn size of the image at [scale].
  static ui.Size drawnSize(
    double imageWidth,
    double imageHeight, {
    required double scale,
  }) {
    final cover = coverScale(imageWidth, imageHeight);
    final factor = cover * scale;
    return ui.Size(imageWidth * factor, imageHeight * factor);
  }

  /// Keeps the viewport fully covered, so the crop can never expose a gap.
  factory PhotoCrop.clamped({
    required double imageWidth,
    required double imageHeight,
    required double scale,
    required double dx,
    required double dy,
  }) {
    final capped = scale.clamp(1.0, PhotoRules.maxZoom.toDouble()).toDouble();
    final drawn = drawnSize(imageWidth, imageHeight, scale: capped);
    return PhotoCrop(
      scale: capped,
      dx: dx.clamp(viewportEdge - drawn.width, 0.0).toDouble(),
      dy: dy.clamp(viewportEdge - drawn.height, 0.0).toDouble(),
    );
  }

  @override
  String toString() =>
      'PhotoCrop(scale: ${scale.toStringAsFixed(2)}, dx: ${dx.toStringAsFixed(1)}, dy: ${dy.toStringAsFixed(1)})';
}

/// Turns the picked picture plus the crop into the square that gets stored.
///
/// `dart:ui` can only encode PNG (no quality knob), so compression here is a
/// downscale to [PhotoRules.storedEdge]. That is a real reduction for camera
/// JPEGs, and the UI reports the before/after byte counts instead of claiming
/// a lossy pass that did not happen.
Future<Uint8List> renderCroppedPhoto(
  PickedPhoto photo, {
  required PhotoCrop crop,
  int edge = PhotoRules.storedEdge,
}) async {
  final codec = await ui.instantiateImageCodec(photo.bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final drawn = PhotoCrop.drawnSize(
      image.width.toDouble(),
      image.height.toDouble(),
      scale: crop.scale,
    );
    // The crop is authored in viewport units, so the canvas only has to map
    // that viewport onto the requested output edge.
    canvas.scale(edge / PhotoCrop.viewportEdge);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(crop.dx, crop.dy, drawn.width, drawn.height),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(edge, edge);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    out.dispose();
    if (data == null) {
      throw const PhotoException(
        PhotoFailure.unreadable,
        'The cropped picture could not be encoded.',
      );
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Reads the decoded dimensions the validators and the cropper need.
Future<PickedPhoto> decodePickedPhoto(
  Uint8List bytes,
  PhotoSourceKind source,
) async {
  if (bytes.lengthInBytes > PhotoRules.maxSourceBytes) {
    throw PhotoException(
      PhotoFailure.tooLarge,
      'That image is ${PhotoBytes.label(bytes.lengthInBytes)}. Pick one under '
      '${PhotoBytes.label(PhotoRules.maxSourceBytes)} or retake it.',
    );
  }
  if (!PhotoRules.isSupportedBytes(bytes)) {
    throw const PhotoException(
      PhotoFailure.unsupportedType,
      'JPG, PNG and WebP images only. Screenshots from some editors are not '
      'accepted.',
    );
  }
  ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
  } catch (_) {
    throw const PhotoException(
      PhotoFailure.unreadable,
      'That file could not be read as an image. Try another one.',
    );
  }
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final width = image.width;
  final height = image.height;
  image.dispose();
  codec.dispose();
  final shortest = width < height ? width : height;
  if (shortest < PhotoRules.minEdge) {
    throw PhotoException(
      PhotoFailure.tooSmall,
      'That image is only $shortest px on its short edge. Use one at least '
      '${PhotoRules.minEdge} px so it stays sharp across the app.',
    );
  }
  return PickedPhoto(
    bytes: bytes,
    width: width,
    height: height,
    source: source,
  );
}

/// Byte formatting shared with the validators' messages.
abstract final class PhotoBytes {
  static String label(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Plugin seam: hands back the raw bytes of whatever the player chose.
abstract interface class PhotoPicker {
  Future<Uint8List?> grab(PhotoSourceKind source);
}

/// Storage seam: owns the files behind the avatars and nothing else.
abstract interface class ProfilePhotoStore {
  /// Writes [bytes] for [accountId] and returns the absolute file path.
  Future<String> write({required String accountId, required Uint8List bytes});

  /// Deletes a file the store previously handed out. A path that the store did
  /// not issue is ignored, which keeps a tampered account document from
  /// deleting anything outside the photo directory.
  Future<void> discard(String? path);

  /// Deletes every managed picture, for reset and clear-data flows.
  Future<void> discardAll();

  /// True when [path] points into this store's own directory.
  bool manages(String? path);
}

/// Directory and file prefix the local store writes into. Kept here so the
/// guard below and the store cannot drift apart.
const String managedPhotoDirName = 'profile_photos';
const String managedPhotoFileNamePrefix = 'avatar-';

/// Whether a persisted reference could plausibly have come from the store.
///
/// The account document is plain JSON on the device, so a hand-edited or
/// corrupted value must never be handed to `Image.file`: a picture has to sit
/// in the photo directory, carry no traversal segment and end in `.png`.
bool looksLikeManagedPhotoPath(String? path) {
  if (path == null || path.isEmpty || !path.endsWith('.png')) {
    return false;
  }
  final segments = path.split('/');
  if (segments.contains('..') || path.contains(String.fromCharCode(0))) {
    return false;
  }
  final name = segments.last;
  return segments.contains(managedPhotoDirName) &&
      name.startsWith(managedPhotoFileNamePrefix);
}
