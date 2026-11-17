import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportika/core/data/profile_photo.dart';

/// Public module artwork only. Identity and dispute files never enter here.
class ModuleMediaStore {
  ModuleMediaStore(this.client);
  final SupabaseClient client;

  Future<String?> path(String bucket, String entity, String slot) async {
    final row = await client
        .from('module_media')
        .select('object_path')
        .eq('bucket_id', bucket)
        .eq('entity_id', entity)
        .eq('slot', slot)
        .maybeSingle();
    return row?['object_path'] as String?;
  }

  /// Teams and tournaments are still device-local, so their creator registers
  /// ownership once. Idempotent for that owner, false for everyone else, and
  /// never true for a public match banner (that authority comes from the match
  /// row itself).
  Future<bool> claim(String bucket, String entity) async =>
      await client.rpc(
        'claim_media_entity',
        params: {'p_bucket': bucket, 'p_entity': entity},
      ) ==
      true;

  Future<bool> canManage(String bucket, String entity) async =>
      await client.rpc(
        'can_manage_media',
        params: {'p_bucket': bucket, 'p_entity': entity},
      ) ==
      true;

  String publicUrl(String bucket, String path) =>
      client.storage.from(bucket).getPublicUrl(path);

  Future<void> save(
    String bucket,
    String entity,
    String slot,
    Uint8List? bytes,
  ) async {
    final previous = await path(bucket, entity, slot);
    String? next;
    final storage = client.storage.from(bucket);
    if (bytes != null) {
      if (bytes.isEmpty ||
          bytes.length > 5 * 1024 * 1024 ||
          !(bytes.length >= 8 &&
              bytes[0] == 137 &&
              bytes[1] == 80 &&
              bytes[2] == 78 &&
              bytes[3] == 71)) {
        throw const FormatException('Choose an image under 5 MB.');
      }
      final token = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      next = '$entity/$slot/$token.png';
      await storage.uploadBinary(
        next,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/png'),
      );
    }
    try {
      if (next == null) {
        await client
            .from('module_media')
            .delete()
            .eq('bucket_id', bucket)
            .eq('entity_id', entity)
            .eq('slot', slot);
      } else {
        await client.from('module_media').upsert({
          'bucket_id': bucket,
          'entity_id': entity,
          'slot': slot,
          'object_path': next,
        });
      }
    } catch (_) {
      // A transport failure can happen after commit. Re-read before cleanup.
      if (next != null) {
        try {
          if (await path(bucket, entity, slot) != next) {
            await storage.remove([next]);
          }
        } catch (_) {
          /* retain for reconciliation */
        }
      }
      rethrow;
    }
    if (previous != null && previous != next) {
      try {
        await storage.remove([previous]);
      } catch (_) {
        /* retry via orphan reconciliation */
      }
    }
  }

  /// Render the selected viewport and strip metadata; cap decoded dimensions.
  static Future<Uint8List> prepare(
    Uint8List bytes,
    bool banner,
    double x,
    double y,
  ) async {
    if (bytes.length > PhotoRules.maxSourceBytes ||
        !PhotoRules.isSupportedBytes(bytes)) {
      throw const FormatException('Choose a JPEG, PNG or WebP under 12 MB.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 40000000) {
        throw const FormatException('Choose an image under 40 megapixels.');
      }
      final factor = min(1.0, 2048 / max(descriptor.width, descriptor.height));
      codec = await descriptor.instantiateCodec(
        targetWidth: max(1, (descriptor.width * factor).round()),
        targetHeight: max(1, (descriptor.height * factor).round()),
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final ratio = banner ? 16 / 9 : 1.0;
        final width = min(image.width.toDouble(), image.height * ratio);
        final height = width / ratio;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final outWidth = banner ? 1280.0 : 512.0;
        final outHeight = banner ? 720.0 : 512.0;
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
            (image.width - width) * x.clamp(0, 1),
            (image.height - height) * y.clamp(0, 1),
            width,
            height,
          ),
          ui.Rect.fromLTWH(0, 0, outWidth, outHeight),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        final picture = recorder.endRecording();
        try {
          final output = await picture.toImage(
            outWidth.toInt(),
            outHeight.toInt(),
          );
          try {
            return (await output.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
          } finally {
            output.dispose();
          }
        } finally {
          picture.dispose();
        }
      } finally {
        image.dispose();
      }
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
