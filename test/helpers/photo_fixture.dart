import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/core/data/profile_photo_service.dart';
import 'package:sportika/shared/data/local_storage.dart';

/// Encodes a real PNG through the engine, so the validators and the cropper are
/// exercised against bytes an image decoder actually produced rather than a
/// fixture that merely happens to have a header.
Future<Uint8List> pngBytes(
  int width,
  int height, {
  ui.Color color = const ui.Color(0xFF2E7DFF),
}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('the test encoder produced nothing');
  return data.buffer.asUint8List();
}

/// Decodes stored bytes again so a test can assert on the real output size.
Future<(int, int)> decodedSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = (frame.image.width, frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return size;
}

/// A picker that hands back whatever the test asked for, or throws.
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker(this.reply);

  /// Bytes to return, or an exception to throw. Null models the player closing
  /// the camera without choosing anything.
  Object? reply;

  PhotoSourceKind? lastSource;

  @override
  Future<Uint8List?> grab(PhotoSourceKind source) async {
    lastSource = source;
    final value = reply;
    if (value is PhotoException) throw value;
    if (value is Exception) throw value;
    return value as Uint8List?;
  }
}

/// Records what the service asked the store to do, in order, so the
/// "delete the old file only after the new reference stuck" guarantee is
/// testable rather than merely asserted in a comment.
class MemoryPhotoStore implements ProfilePhotoStore {
  final List<String> written = [];
  final List<String?> deleted = [];
  int counter = 0;

  /// Makes every write fail, modelling a device out of space.
  bool refuseWrites = false;

  @override
  Future<String> write({
    required String accountId,
    required Uint8List bytes,
  }) async {
    if (refuseWrites) throw const FileSystemException('no space left');
    final path =
        '/data/user/0/pk.sportika.mobile/support/profile_photos/'
        'avatar-$accountId-${counter++}.png';
    written.add(path);
    return path;
  }

  @override
  Future<void> discard(String? path) async {
    if (path != null && written.contains(path)) deleted.add(path);
  }

  @override
  Future<void> discardAll() async {
    deleted.addAll(written);
  }

  @override
  bool manages(String? path) => looksLikeManagedPhotoPath(path);
}

/// A service wired to in-memory parts, plus the account references it moved.
class PhotoRig {
  PhotoRig(this.service, this.refs);

  final ProfilePhotoService service;

  /// Every value the account reference held, oldest first. The default persist
  /// appends, so a test can see whether a failed save changed anything.
  final List<String?> refs;

  String? get current => refs.last;
}

PhotoRig photoService({
  PhotoPicker? picker,
  ProfilePhotoStore? store,
  String? accountId = 'acc-seebu',
  String? initialPath,
  Future<void> Function(String?)? persist,
}) {
  final refs = <String?>[initialPath];
  final service = ProfilePhotoService(
    picker: picker ?? FakePhotoPicker(null),
    store: store ?? MemoryPhotoStore(),
    accountId: () => accountId,
    currentPath: () => refs.last,
    persist:
        persist ??
        (path) async {
          refs.add(path);
        },
  );
  return PhotoRig(service, refs);
}

/// A picture with enough detail that downscaling really costs the encoder
/// something, so a compression assertion is not a rounding accident.
Future<Uint8List> noisyPngBytes(int edge, {int tiles = 90}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final step = edge / tiles;
  for (var y = 0; y < tiles; y++) {
    for (var x = 0; x < tiles; x++) {
      final seed = (x * 73856093) ^ (y * 19349663);
      canvas.drawRect(
        ui.Rect.fromLTWH(x * step, y * step, step, step),
        ui.Paint()..color = ui.Color(0xFF000000 | (seed & 0xFFFFFF)),
      );
    }
  }
  final image = await recorder.endRecording().toImage(edge, edge);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('the test encoder produced nothing');
  return data.buffer.asUint8List();
}

/// A service that never touches the image codec or the file system.
///
/// `testWidgets` runs inside a fake-async zone, where a real engine decode can
/// never complete, so the widget tests drive the whole picture UI through this
/// stand-in: sheet, cropper, save and remove all behave, and the account
/// reference really moves. The codec-backed pipeline is covered with real bytes
/// in test/profile_photo_test.dart.
class ScriptedPhotoService extends ProfilePhotoService {
  ScriptedPhotoService({
    required super.picker,
    required super.store,
    required super.accountId,
    required super.currentPath,
    required super.persist,
    required this.photo,
    required this.storedPath,
  });

  /// The picture `pick` hands back, as if the camera had produced it.
  final PickedPhoto photo;

  /// Path the fake store "writes", usually a real png in a temp directory.
  final String storedPath;

  PhotoCrop? lastCrop;
  int commits = 0;
  int removals = 0;

  @override
  Future<PickedPhoto?> pick(PhotoSourceKind source) async => photo;

  @override
  Future<StoredPhoto> commit({
    required PickedPhoto photo,
    required PhotoCrop crop,
  }) async {
    lastCrop = crop;
    commits++;
    await persist(storedPath);
    return StoredPhoto(
      path: storedPath,
      sourceBytes: 1_240_064,
      storedBytes: 215_040,
      source: photo.source,
    );
  }

  @override
  Future<void> remove() async {
    removals++;
    await persist(null);
  }
}

/// Storage whose writer can be told to fail, for the picture paths of the
/// optimistic-mutation contract.
class FlakyPhotoStorage extends LocalStorage {
  // The super constructor's parameter is library-private, so it cannot be
  // forwarded with a super parameter from this file.
  // ignore: use_super_parameters
  FlakyPhotoStorage(SharedPreferences prefs) : super(prefs);

  bool failWrites = false;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {
    if (failWrites) throw StateError('disk is full');
    await super.writeState(state);
  }
}

/// A seeded store plus the storage handle behind it.
Future<(LocalSportikaRepository, FlakyPhotoStorage)> flakyPhotoStore() async {
  SharedPreferences.setMockInitialValues({'sportika.onboarding_seen.v1': true});
  final storage = FlakyPhotoStorage(await SharedPreferences.getInstance());
  final store = LocalSportikaRepository(storage);
  await store.load();
  return (store, storage);
}

/// A throwaway directory for the real file store.
Directory tempPhotoDir() =>
    Directory.systemTemp.createTempSync('sportika_photos_test');
