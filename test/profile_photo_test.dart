import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:sportika/core/data/local_profile_photo_store.dart';
import 'package:sportika/core/data/local_sportika_repository.dart';
import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/core/state/profile_photo_controller.dart';

import 'helpers/photo_fixture.dart';

/// Byte-level rules, the crop maths, the file store, the pipeline order, the
/// persisted reference and the controller's stage machine — the whole picture
/// path except the camera plugin and the widget tree.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('validation', () {
    test('a real image is accepted with its dimensions', () async {
      final photo = await decodePickedPhoto(
        await pngBytes(900, 1200),
        PhotoSourceKind.camera,
      );
      expect(photo.width, 900);
      expect(photo.height, 1200);
      expect(photo.shortestEdge, 900);
      expect(photo.source, PhotoSourceKind.camera);
      expect(photo.sourceSizeLabel, matches(RegExp(r'(KB|MB|B)$')));
    });

    test(
      'bytes that are not a picture are rejected by the container',
      () async {
        expect(
          PhotoRules.isSupportedBytes(
            Uint8List.fromList('not really an image'.codeUnits),
          ),
          isFalse,
        );
        await expectLater(
          decodePickedPhoto(
            Uint8List.fromList(List.filled(64, 0x41)),
            PhotoSourceKind.gallery,
          ),
          throwsA(
            isA<PhotoException>().having(
              (e) => e.kind,
              'kind',
              PhotoFailure.unsupportedType,
            ),
          ),
        );
      },
    );

    test('a JPEG header is treated as supportable before decoding', () {
      final header = Uint8List(16)
        ..[0] = 0xFF
        ..[1] = 0xD8
        ..[2] = 0xFF;
      expect(PhotoRules.isSupportedBytes(header), isTrue);
    });

    test(
      'a picture below the minimum edge is refused with the number',
      () async {
        await expectLater(
          decodePickedPhoto(await pngBytes(120, 120), PhotoSourceKind.camera),
          throwsA(
            isA<PhotoException>()
                .having((e) => e.kind, 'kind', PhotoFailure.tooSmall)
                .having((e) => e.message, 'message', contains('120')),
          ),
        );
      },
    );

    test('an oversized file is refused before it is decoded', () async {
      // Only the header has to be real: the size gate runs first on purpose so
      // a 40 MB import never reaches the codec.
      final huge = Uint8List(PhotoRules.maxSourceBytes + 8)
        ..[0] = 0x89
        ..[1] = 0x50
        ..[2] = 0x4E
        ..[3] = 0x47;
      await expectLater(
        decodePickedPhoto(huge, PhotoSourceKind.gallery),
        throwsA(
          isA<PhotoException>().having(
            (e) => e.kind,
            'kind',
            PhotoFailure.tooLarge,
          ),
        ),
      );
    });
  });

  group('crop and compression', () {
    test(
      'the output is the stored square regardless of source shape',
      () async {
        final photo = await decodePickedPhoto(
          await pngBytes(1200, 800),
          PhotoSourceKind.gallery,
        );
        final bytes = await renderCroppedPhoto(
          photo,
          crop: PhotoCrop.clamped(
            imageWidth: 1200,
            imageHeight: 800,
            scale: 1,
            dx: 0,
            dy: 0,
          ),
        );
        expect(await decodedSize(bytes), (512, 512));
      },
    );

    test('the stored square is capped, not the whole import', () async {
      // dart:ui encodes PNG only, so there is no JPEG quality knob to promise
      // and the byte count can legitimately go either way for a small, heavily
      // compressed import. What the pipeline does guarantee, and what the UI
      // therefore quotes instead of a percentage, is a fixed 512 px square.
      final source = await noisyPngBytes(1600, tiles: 90);
      final photo = await decodePickedPhoto(source, PhotoSourceKind.camera);
      expect(photo.width, 1600);
      final stored = await renderCroppedPhoto(photo, crop: const PhotoCrop());
      expect(await decodedSize(stored), (512, 512));
      expect(
        stored[0],
        0x89,
      ); // PNG signature: the format the app states it writes
      expect(stored[1], 0x50);
      // A large camera import must never be persisted whole behind the avatar.
      expect(stored.lengthInBytes, lessThan(1024 * 1024));
    });

    test('panning changes which part of the picture is kept', () async {
      // A left half that differs from the right half, so a horizontal pan has to
      // produce different bytes.
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..drawRect(
          const ui.Rect.fromLTWH(0, 0, 300, 600),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        )
        ..drawRect(
          const ui.Rect.fromLTWH(300, 0, 300, 600),
          ui.Paint()..color = const ui.Color(0xFF000000),
        );
      final image = await recorder.endRecording().toImage(600, 600);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      final photo = await decodePickedPhoto(
        data!.buffer.asUint8List(),
        PhotoSourceKind.gallery,
      );
      final drawnWidth = PhotoCrop.drawnSize(600, 600, scale: 2).width;
      final left = await renderCroppedPhoto(
        photo,
        crop: PhotoCrop.clamped(
          imageWidth: 600,
          imageHeight: 600,
          scale: 2,
          dx: 0,
          dy: 0,
        ),
      );
      final right = await renderCroppedPhoto(
        photo,
        crop: PhotoCrop.clamped(
          imageWidth: 600,
          imageHeight: 600,
          scale: 2,
          dx: -drawnWidth,
          dy: 0,
        ),
      );
      expect(left, isNot(right));
    });

    test('the clamp keeps the frame covered and the zoom sane', () {
      final crop = PhotoCrop.clamped(
        imageWidth: 1000,
        imageHeight: 700,
        scale: 99,
        dx: 500,
        dy: 500,
      );
      expect(crop.scale, PhotoRules.maxZoom.toDouble());
      // Offsets can never be positive: that would slide the image off the frame.
      expect(crop.dx, lessThanOrEqualTo(0));
      expect(crop.dy, lessThanOrEqualTo(0));
      final drawn = PhotoCrop.drawnSize(1000, 700, scale: crop.scale);
      expect(drawn.width, greaterThanOrEqualTo(PhotoCrop.viewportEdge));
      expect(drawn.height, greaterThanOrEqualTo(PhotoCrop.viewportEdge));
      expect(PhotoCrop.viewportEdge + crop.dx, lessThanOrEqualTo(drawn.width));
    });
  });

  group('the file store', () {
    late Directory root;
    late LocalProfilePhotoStore store;

    setUp(() {
      root = tempPhotoDir();
      store = LocalProfilePhotoStore(directoryProvider: () async => root);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('writes a managed png inside its own directory', () async {
      final path = await store.write(
        accountId: 'acc-seebu',
        bytes: await pngBytes(600, 600),
      );
      expect(path, endsWith('.png'));
      expect(File(path).existsSync(), isTrue);
      expect(store.manages(path), isTrue);
      expect(path, contains('${LocalProfilePhotoStore.dirName}/'));
      expect(
        path.split('/').last,
        startsWith('${LocalProfilePhotoStore.prefix}acc-seebu-'),
      );
    });

    test('a hostile account id cannot escape the photo directory', () async {
      final path = await store.write(
        accountId: '../../etc/cron',
        bytes: await pngBytes(400, 400),
      );
      expect(path.split('/').last, startsWith('avatar-'));
      expect(path.split('/').where((s) => s == '..'), isEmpty);
      expect(path, startsWith(root.path));
    });

    test('discard removes only files this store issued', () async {
      final mine = await store.write(
        accountId: 'acc-seebu',
        bytes: await pngBytes(500, 500),
      );
      final outside = File('${root.path}/holiday.jpg')..createSync();

      await store.discard(mine);
      await store.discard(outside.path);
      await store.discard(null);

      expect(File(mine).existsSync(), isFalse);
      expect(outside.existsSync(), isTrue);
      outside.deleteSync();
    });

    test('discardAll sweeps the directory for the reset flow', () async {
      for (var i = 0; i < 3; i++) {
        await store.write(accountId: 'acc-$i', bytes: await pngBytes(400, 400));
      }
      await store.discardAll();
      expect(
        Directory('${root.path}/${LocalProfilePhotoStore.dirName}')
            .existsSync(),
        isFalse,
      );
    });

    test('a path that was never issued is never rendered', () {
      expect(looksLikeManagedPhotoPath(null), isFalse);
      expect(looksLikeManagedPhotoPath(''), isFalse);
      expect(looksLikeManagedPhotoPath('/etc/passwd'), isFalse);
      expect(looksLikeManagedPhotoPath('/tmp/evil.jpg'), isFalse);
      expect(
        looksLikeManagedPhotoPath('/app/support/profile_photos/../x.png'),
        isFalse,
      );
      expect(
        looksLikeManagedPhotoPath('/app/support/profile_photos/avatar-1.png'),
        isTrue,
      );
    });
  });

  group('pipeline order keeps an orphan file impossible', () {
    test('a cancel is not an error and writes nothing', () async {
      final store = MemoryPhotoStore();
      final rig = photoService(picker: FakePhotoPicker(null), store: store);
      expect(await rig.service.pick(PhotoSourceKind.camera), isNull);
      expect(store.written, isEmpty);
      expect(rig.refs, hasLength(1));
    });

    test('the old picture survives until the new reference is in', () async {
      final picker = FakePhotoPicker(await pngBytes(800, 800));
      final store = MemoryPhotoStore();
      final rig = photoService(
        picker: picker,
        store: store,
        initialPath: '/app/support/profile_photos/avatar-old.png',
      );
      store.written.add('/app/support/profile_photos/avatar-old.png');

      final photo = await rig.service.pick(PhotoSourceKind.gallery);
      final stored = await rig.service.commit(
        photo: photo!,
        crop: const PhotoCrop(scale: 1.5),
      );

      expect(picker.lastSource, PhotoSourceKind.gallery);
      expect(rig.current, stored.path);
      expect(stored.storedBytes, greaterThan(0));
      expect(stored.summary, contains('to'));
      // Old file goes last, so a failure above could never lose both.
      expect(store.deleted, ['/app/support/profile_photos/avatar-old.png']);
    });

    test(
      'a refused save rolls the reference back and cleans the new file',
      () async {
        final store = MemoryPhotoStore();
        final rig = photoService(
          picker: FakePhotoPicker(await pngBytes(700, 700)),
          store: store,
          persist: (path) async => throw const PhotoException(
            PhotoFailure.persistence,
            'This device would not save the new picture.',
          ),
        );

        final photo = await rig.service.pick(PhotoSourceKind.camera);
        await expectLater(
          rig.service.commit(photo: photo!, crop: const PhotoCrop()),
          throwsA(
            isA<PhotoException>().having(
              (e) => e.kind,
              'kind',
              PhotoFailure.persistence,
            ),
          ),
        );
        // Nothing appended to the reference list, and the fresh file was swept.
        expect(rig.refs, hasLength(1));
        expect(store.deleted, store.written);
      },
    );

    test(
      'a device that will not take the file says so as storage trouble',
      () async {
        final store = MemoryPhotoStore()..refuseWrites = true;
        final rig = photoService(
          picker: FakePhotoPicker(await pngBytes(700, 700)),
          store: store,
        );
        final photo = await rig.service.pick(PhotoSourceKind.gallery);
        await expectLater(
          rig.service.commit(photo: photo!, crop: const PhotoCrop()),
          throwsA(
            isA<PhotoException>().having(
              (e) => e.kind,
              'kind',
              PhotoFailure.storage,
            ),
          ),
        );
        expect(rig.refs, hasLength(1));
      },
    );

    test('nobody signed in stops the commit before any work', () async {
      final store = MemoryPhotoStore();
      final rig = photoService(
        picker: FakePhotoPicker(await pngBytes(700, 700)),
        store: store,
        accountId: null,
      );
      final photo = await rig.service.pick(PhotoSourceKind.camera);
      await expectLater(
        rig.service.commit(photo: photo!, crop: const PhotoCrop()),
        throwsA(
          isA<PhotoException>().having(
            (e) => e.kind,
            'kind',
            PhotoFailure.notSignedIn,
          ),
        ),
      );
      expect(store.written, isEmpty);
    });

    test('removal drops the reference first, then the file', () async {
      final store = MemoryPhotoStore();
      final kept = '/app/support/profile_photos/avatar-old.png';
      store.written.add(kept);
      final rig = photoService(store: store, initialPath: kept);

      await rig.service.remove();

      expect(rig.current, isNull);
      expect(store.deleted, [kept]);
    });

    test('a removal the device refuses keeps the picture', () async {
      final store = MemoryPhotoStore();
      final kept = '/app/support/profile_photos/avatar-old.png';
      store.written.add(kept);
      final rig = photoService(
        store: store,
        initialPath: kept,
        persist: (path) async => throw StateError('read only'),
      );

      await expectLater(rig.service.remove(), throwsA(isA<PhotoException>()));
      expect(rig.refs, hasLength(1));
      expect(store.deleted, isEmpty);
    });
  });

  group('the account document carries the picture', () {
    test('a saved reference survives a reload of the document', () async {
      final (store, storage) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      final path = '/app/support/profile_photos/avatar-seebu.png';
      await store.setProfilePhoto(path);

      // A fresh repository over the same storage is what a relaunch is.
      final reopened = LocalSportikaRepository(storage);
      await reopened.load();

      expect(reopened.currentAccount!.photoPath, path);
      expect(reopened.currentAccount!.hasPhoto, isTrue);
    });

    test('clearing the reference puts the default avatar back', () async {
      final (store, _) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      await store.setProfilePhoto('/app/support/profile_photos/avatar-a.png');
      await store.setProfilePhoto(null);

      expect(store.currentAccount!.photoPath, isNull);
      expect(store.currentAccount!.hasPhoto, isFalse);
    });

    test('a refused write restores the previous avatar and says why', () async {
      final (store, storage) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      const kept = '/app/support/profile_photos/avatar-kept.png';
      await store.setProfilePhoto(kept);

      storage.failWrites = true;
      await expectLater(
        store.setProfilePhoto('/app/support/profile_photos/avatar-new.png'),
        throwsA(
          isA<PhotoException>().having(
            (e) => e.kind,
            'kind',
            PhotoFailure.persistence,
          ),
        ),
      );

      expect(store.currentAccount!.photoPath, kept);
      expect(store.takeStorageNotice(), contains('could not be saved'));
    });

    test('changing a picture while signed out is refused', () async {
      final (store, _) = await flakyPhotoStore();
      await expectLater(
        store.setProfilePhoto('/app/support/profile_photos/avatar-x.png'),
        throwsA(
          isA<PhotoException>().having(
            (e) => e.kind,
            'kind',
            PhotoFailure.notSignedIn,
          ),
        ),
      );
    });

    test(
      'an empty reference is stored as nothing, not as a broken path',
      () async {
        final (store, _) = await flakyPhotoStore();
        await store.signIn('acc-seebu');
        await store.setProfilePhoto('');
        expect(store.currentAccount!.photoPath, isNull);
      },
    );
  });

  group('the controller stage machine', () {
    test('pick then save moves through the real stages', () async {
      final (store, _) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      final memory = MemoryPhotoStore();
      final controller = ProfilePhotoController(
        store,
        service: photoService(
          picker: FakePhotoPicker(await pngBytes(900, 900)),
          store: memory,
          persist: store.setProfilePhoto,
        ).service,
      );

      expect(controller.stage, PhotoFlowStage.idle);
      expect(controller.hasPhoto, isFalse);

      final picked = await controller.start(PhotoSourceKind.camera);
      expect(controller.stage, PhotoFlowStage.cropping);
      expect(picked, isNotNull);
      expect(controller.pending, same(picked));

      final saved = await controller.save(const PhotoCrop(scale: 2));
      expect(saved, isTrue);
      expect(controller.stage, PhotoFlowStage.idle);
      expect(controller.hasPhoto, isTrue);
      expect(controller.pending, isNull);
      expect(controller.lastStored!.summary, contains('to'));
      expect(controller.statusLabel, isNotEmpty);
      controller.dispose();
    });

    test(
      'closing the camera leaves the avatar untouched and unstaged',
      () async {
        final (store, _) = await flakyPhotoStore();
        await store.signIn('acc-seebu');
        final controller = ProfilePhotoController(
          store,
          service: photoService(picker: FakePhotoPicker(null)).service,
        );

        expect(await controller.start(PhotoSourceKind.gallery), isNull);
        expect(controller.stage, PhotoFlowStage.idle);
        expect(controller.hasFailure, isFalse);
        controller.dispose();
      },
    );

    test('a rejected picture reports its own reason', () async {
      final (store, _) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      final controller = ProfilePhotoController(
        store,
        service: photoService(picker: FakePhotoPicker(await pngBytes(100, 100)))
            .service,
      );

      expect(await controller.start(PhotoSourceKind.camera), isNull);
      expect(controller.stage, PhotoFlowStage.failed);
      expect(controller.failureKind, PhotoFailure.tooSmall);
      expect(controller.statusLabel, controller.failureMessage);
      expect(controller.hasPhoto, isFalse);

      controller.dismissFailure();
      expect(controller.stage, PhotoFlowStage.idle);
      expect(controller.hasFailure, isFalse);
      controller.dispose();
    });

    test('a picker the platform refuses is surfaced, not swallowed', () async {
      final (store, _) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      final controller = ProfilePhotoController(
        store,
        service: photoService(
          picker: FakePhotoPicker(
            const PhotoException(
              PhotoFailure.sourceUnavailable,
              'This device could not open the camera.',
            ),
          ),
        ).service,
      );

      await controller.start(PhotoSourceKind.camera);
      expect(controller.failureKind, PhotoFailure.sourceUnavailable);
      expect(controller.statusLabel, contains('camera'));
      controller.dispose();
    });

    test('abandoning the cropper keeps the previous picture', () async {
      final (store, _) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      const kept = '/app/support/profile_photos/avatar-kept.png';
      await store.setProfilePhoto(kept);
      final controller = ProfilePhotoController(
        store,
        service: photoService(
          picker: FakePhotoPicker(await pngBytes(900, 900)),
          initialPath: kept,
          persist: store.setProfilePhoto,
        ).service,
      );

      await controller.start(PhotoSourceKind.gallery);
      controller.discardPending();

      expect(controller.pending, isNull);
      expect(controller.stage, PhotoFlowStage.idle);
      expect(store.currentAccount!.photoPath, kept);
      controller.dispose();
    });

    test('a save the device refuses leaves the old avatar in place', () async {
      final (store, storage) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      const kept = '/app/support/profile_photos/avatar-kept.png';
      await store.setProfilePhoto(kept);
      final memory = MemoryPhotoStore();
      final controller = ProfilePhotoController(
        store,
        service: photoService(
          picker: FakePhotoPicker(await pngBytes(900, 900)),
          store: memory,
          initialPath: kept,
          persist: store.setProfilePhoto,
        ).service,
      );

      await controller.start(PhotoSourceKind.camera);
      storage.failWrites = true;

      expect(await controller.save(const PhotoCrop()), isFalse);
      expect(controller.hasPhoto, isTrue);
      expect(store.currentAccount!.photoPath, kept);
      // The picture the player is still wearing must not have been deleted; the
      // orphan left by the refused save is the one that goes.
      expect(memory.deleted, isNot(contains(kept)));
      expect(memory.deleted, memory.written);
      expect(controller.failureKind, PhotoFailure.persistence);
      controller.dispose();
    });

    test('remove falls back to the default avatar', () async {
      final (store, _) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      final memory = MemoryPhotoStore();
      final controller = ProfilePhotoController(
        store,
        service: photoService(
          store: memory,
          initialPath: '/app/support/profile_photos/avatar-old.png',
          persist: store.setProfilePhoto,
        ).service,
      );
      memory.written.add('/app/support/profile_photos/avatar-old.png');

      expect(await controller.remove(), isTrue);
      expect(controller.hasPhoto, isFalse);
      expect(controller.stage, PhotoFlowStage.idle);
      expect(memory.deleted, ['/app/support/profile_photos/avatar-old.png']);
      controller.dispose();
    });

    test('a busy controller ignores a second request', () async {
      final (store, _) = await flakyPhotoStore();
      await store.signIn('acc-seebu');
      final controller = ProfilePhotoController(
        store,
        service: photoService(picker: FakePhotoPicker(await pngBytes(900, 900)))
            .service,
      );

      final first = controller.start(PhotoSourceKind.camera);
      expect(await controller.start(PhotoSourceKind.gallery), isNull);
      await first;
      expect(controller.stage, PhotoFlowStage.cropping);
      controller.dispose();
    });

    test('purging sweeps every file for the reset flow', () async {
      final (store, _) = await flakyPhotoStore();
      final memory = MemoryPhotoStore();
      final controller = ProfilePhotoController(
        store,
        service: photoService(store: memory).service,
      );
      memory.written.add('/app/support/profile_photos/avatar-a.png');

      await controller.purgeStoredFiles();
      expect(memory.deleted, hasLength(1));
      controller.dispose();
    });
  });
}
