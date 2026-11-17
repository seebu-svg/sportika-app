import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sportika/core/data/profile_photo.dart';

/// The only place `image_picker` is touched.
///
/// Everything above this adapter works on bytes, which is what lets the
/// validators, the cropper and the store be tested without a camera, a gallery
/// or a platform channel.
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Camera goes through the system capture intent, so the app never needs the
  /// CAMERA permission in its own manifest; gallery uses the system picker for
  /// the same reason.
  @override
  Future<Uint8List?> grab(PhotoSourceKind source) async {
    final XFile picked;
    try {
      final result = await _picker.pickImage(
        source: source == PhotoSourceKind.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        preferredCameraDevice: CameraDevice.front,
        requestFullMetadata: false,
        // Downscale and re-encode on the way in, so a 12 MP camera JPEG never
        // reaches the cropper. This is the first of the two compression passes.
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (result == null) return null;
      picked = result;
    } on PlatformException catch (error) {
      throw PhotoException(
        PhotoFailure.sourceUnavailable,
        _pickerMessage(source, error),
      );
    }
    try {
      return await File(picked.path).readAsBytes();
    } on FileSystemException {
      throw const PhotoException(
        PhotoFailure.unreadable,
        'That picture disappeared before it could be read. Take it again.',
      );
    }
  }

  /// The plugin reports a handful of distinct codes; only the permission ones
  /// deserve their own sentence, everything else is "this device will not open
  /// a picker".
  static String _pickerMessage(
    PhotoSourceKind source,
    PlatformException error,
  ) {
    final what = source == PhotoSourceKind.camera ? 'camera' : 'photo picker';
    final code = error.code.toLowerCase();
    if (code.contains('permission') ||
        code.contains('denied') ||
        code.contains('canceled_permission')) {
      return 'Sportika was denied access to the $what. Allow it in the system '
          'settings, or pick a picture instead.';
    }
    return 'This device could not open the $what. Try again, or choose a '
        'picture from the gallery.';
  }
}
