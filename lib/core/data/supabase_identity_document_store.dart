import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportika/core/data/identity_document_store.dart';
import 'package:sportika/shared/models/identity_document.dart';

/// Only private bucket paths are persisted; never public or signed image URLs.
class SupabaseIdentityDocumentStore implements IdentityDocumentStore {
  SupabaseIdentityDocumentStore(this.client);
  final SupabaseClient client;
  static const bucket = 'identity-documents';

  @override
  Future<void> save({
    required String accountId,
    required IdentitySubmission submission,
  }) async {
    if (submission.isEmpty) return;
    if (client.auth.currentUser?.id != accountId) {
      throw StateError('A verified owner session is required.');
    }
    if (validateIdentityNumber(submission.number ?? '') != null ||
        (submission.kind == IdentityDocumentKind.bForm &&
            (submission.front != null || submission.back != null))) {
      throw const FormatException('Invalid optional identity details.');
    }
    final storage = client.storage.from(bucket);
    final uploaded = <String>[];
    try {
      String? frontPath, backPath;
      for (final part in [
        ('front', submission.front),
        ('back', submission.back),
      ]) {
        if (part.$2 == null) continue;
        final bytes = await prepareIdentityImage(part.$2!);
        // The owner's folder is enforced by Storage RLS. Names contain no PII.
        final random = Random.secure();
        final token = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        final path = '$accountId/${part.$1}-$token.png';
        await storage.uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: false,
          ),
        );
        uploaded.add(path);
        if (part.$1 == 'front') {
          frontPath = path;
        } else {
          backPath = path;
        }
      }
      if (client.auth.currentUser?.id != accountId) {
        throw StateError('The owner session changed.');
      }
      // Setup submits once. A unique owner row prevents accidental overwrites.
      await client.from('profile_identity_documents').insert({
        'profile_id': accountId,
        'document_type': submission.kind.key,
        'document_number':
            submission.number == null || submission.number!.isEmpty
            ? null
            : normalizeIdentityNumber(submission.number!),
        'front_path': frontPath,
        'back_path': backPath,
      });
    } catch (_) {
      // A rejected DB write must not leave unattached images behind. Never log
      // the error: transport errors can include submitted identity values.
      if (uploaded.isNotEmpty) {
        try {
          await storage.remove(uploaded);
        } catch (_) {
          /* Best effort. */
        }
      }
      rethrow;
    }
  }
}
