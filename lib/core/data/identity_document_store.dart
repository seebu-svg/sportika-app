import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/shared/models/identity_document.dart';

abstract class IdentityDocumentStore {
  Future<void> save({
    required String accountId,
    required IdentitySubmission submission,
  });
}

/// Decode and re-encode to PNG to discard embedded metadata. No avatar crop:
/// identity documents must retain their complete rectangular image.
Future<Uint8List> prepareIdentityImage(Uint8List bytes) async {
  const limit = 5 * 1024 * 1024;
  if (bytes.length > limit || !PhotoRules.isSupportedBytes(bytes)) {
    throw const FormatException('Choose a JPEG, PNG or WebP image under 5 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 40000000) {
      throw const FormatException('Choose an image under 40 megapixels.');
    }
    final ratio = math.min(
      1.0,
      1600 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * ratio).round()),
      targetHeight: math.max(1, (descriptor.height * ratio).round()),
    );

    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes > limit) {
        throw const FormatException('Choose a smaller image, under 5 MB.');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'This image could not be opened. Choose another.',
    );
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
