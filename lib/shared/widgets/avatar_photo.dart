import 'dart:io';

import 'package:flutter/material.dart';

import 'package:sportika/core/data/profile_photo.dart';

/// The circular picture an avatar shows once a player has imported one.
///
/// Every surface that can carry a profile picture goes through [avatarFace], so
/// a picture is framed, decoded and (when the file is gone) replaced by the
/// initials face exactly the same way on Home, in Me, on Teams, in the player
/// directory and on match screens.
class AvatarPhoto extends StatelessWidget {
  const AvatarPhoto({
    super.key,
    required this.path,
    required this.size,
    required this.fallback,
  });

  final String path;
  final double size;

  /// Shown while the file decodes and whenever it cannot be read, so a missing
  /// picture degrades to the default avatar instead of a grey box.
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    // Decoding at the drawn size keeps a full 512 px square out of the memory
    // cache for every 22 px list tile that shows the same player.
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final target = (size * ratio).clamp(48.0, PhotoRules.storedEdge.toDouble());
    return Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: target.round(),
      // A replaced picture swaps in without flashing the fallback first.
      gaplessPlayback: true,
      semanticLabel: 'Profile picture',
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// The picture the server holds, shown when this device has no local copy.
///
/// Same framing and same fallback as [AvatarPhoto]; only the source differs. That
/// is what makes a fresh install or a second device draw the member's face
/// instead of their initials.
class AvatarNetworkPhoto extends StatelessWidget {
  const AvatarNetworkPhoto({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
  });

  final String url;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final target = (size * ratio).clamp(48.0, PhotoRules.storedEdge.toDouble());
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: target.round(),
      gaplessPlayback: true,
      semanticLabel: 'Profile picture',
      // The initials stay up until the first frame is decoded, and forever if
      // the object was deleted or the device is offline.
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// The picture at [photoPath] when the profile photo store really issued it,
/// otherwise [photoUrl] when the server has one, otherwise [fallback].
///
/// The account document is plain JSON on the device, so a hand-edited or
/// corrupted reference must never be handed to `Image.file`: anything that does
/// not look like a managed file is treated as "no picture".
Widget avatarFace({
  required String? photoPath,
  String? photoUrl,
  required double size,
  required Widget fallback,
}) {
  if (looksLikeManagedPhotoPath(photoPath)) {
    return ClipOval(
      child: AvatarPhoto(
        path: photoPath!,
        size: size,
        fallback: (photoUrl?.trim().isNotEmpty ?? false)
            ? AvatarNetworkPhoto(
                url: photoUrl!.trim(),
                size: size,
                fallback: fallback,
              )
            : fallback,
      ),
    );
  }
  final url = photoUrl?.trim() ?? '';
  if (url.isEmpty) return fallback;
  return ClipOval(
    child: AvatarNetworkPhoto(url: url, size: size, fallback: fallback),
  );
}
