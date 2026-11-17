import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/core/state/profile_photo_controller.dart';
import 'package:sportika/features/profile_photo/widgets/photo_cropper.dart';
import 'package:sportika/features/profile_photo/widgets/photo_source_sheet.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/state_views.dart';

/// What one trip through the picture flow ended up doing, in the player's terms.
class PhotoFlowOutcome {
  const PhotoFlowOutcome({
    required this.message,
    this.isError = false,
    this.changed = false,
  });

  final String message;
  final bool isError;

  /// True when the account's picture actually moved, so callers can refresh
  /// anything that caches the old one.
  final bool changed;
}

/// Pick, crop, compress, store, persist — for both entry points.
///
/// Account setup and Edit Profile call this one function so the two can never
/// disagree about confirmation, error copy or the order of operations. Returns
/// null when the player backed out before the source sheet did anything.
Future<PhotoFlowOutcome?> runProfilePhotoFlow(BuildContext context) async {
  final controller = context.read<ProfilePhotoController>();
  if (controller.busy) return null;

  final action = await showPhotoSourceSheet(
    context,
    hasPhoto: controller.hasPhoto,
  );
  if (action == null || !context.mounted) return null;

  return switch (action) {
    PhotoSheetAction.camera => _import(
      context,
      controller,
      PhotoSourceKind.camera,
    ),
    PhotoSheetAction.gallery => _import(
      context,
      controller,
      PhotoSourceKind.gallery,
    ),
    PhotoSheetAction.remove => _remove(context, controller),
  };
}

Future<PhotoFlowOutcome> _import(
  BuildContext context,
  ProfilePhotoController controller,
  PhotoSourceKind source,
) async {
  // While this runs the screen shows its own progress line, so the wait for the
  // camera or the gallery is never a frozen button.
  final photo = await controller.start(source);
  if (photo == null) {
    if (controller.hasFailure) {
      return PhotoFlowOutcome(
        message: controller.failureMessage!,
        isError: true,
      );
    }
    return const PhotoFlowOutcome(
      message: 'No picture was chosen, so nothing changed.',
    );
  }
  if (!context.mounted) {
    return const PhotoFlowOutcome(message: 'Picture flow ended early.');
  }

  final crop = await PhotoCropperSheet.show(
    context,
    photo: photo,
    initials: controller.account?.initials ?? '',
  );
  if (crop == null) {
    controller.discardPending();
    return const PhotoFlowOutcome(
      message: 'Cropping abandoned. Your current picture is unchanged.',
    );
  }

  final saved = await controller.save(crop);
  if (!saved) {
    return PhotoFlowOutcome(
      message:
          controller.failureMessage ??
          'That picture could not be saved. Your previous avatar is still set.',
      isError: true,
    );
  }
  final stored = controller.lastStored;
  return PhotoFlowOutcome(
    message: stored == null
        ? 'Profile picture updated.'
        : 'Profile picture updated · ${stored.summary}',
    changed: true,
  );
}

Future<PhotoFlowOutcome> _remove(
  BuildContext context,
  ProfilePhotoController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(
        'Remove your profile picture?',
        style: SportikaType.title,
      ),
      content: const Text(
        'Your profile picture is removed and your gradient avatar with '
        'initials comes back everywhere it is shown.',
        style: SportikaType.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: SportikaColors.danger),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return const PhotoFlowOutcome(message: 'Kept your picture.');
  }

  final removed = await controller.remove();
  if (!removed) {
    return PhotoFlowOutcome(
      message:
          controller.failureMessage ??
          'This device would not remove the picture, so it is still set.',
      isError: true,
    );
  }
  return const PhotoFlowOutcome(
    message: 'Picture removed. Your gradient avatar is back.',
    changed: true,
  );
}

/// Progress and failure line for the picture flow.
///
/// Storage does not expose byte progress, so the meter stays indeterminate
/// until the upload and profile update finish.
class ProfilePhotoStatus extends StatelessWidget {
  const ProfilePhotoStatus({super.key, this.onRetry});

  /// Re-opens the source sheet when the player wants to try again.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProfilePhotoController>();
    if (controller.hasFailure) {
      return InlineBanner(
        text: controller.failureMessage ?? 'That picture could not be used.',
        tone: SportikaColors.danger,
        icon: Icons.error_outline,
        onDismiss: controller.dismissFailure,
        action: onRetry == null
            ? null
            : TextButton(onPressed: onRetry, child: const Text('Try again')),
      );
    }
    if (controller.lastStored != null && !controller.busy) {
      return InlineBanner(
        text: 'Profile picture updated · ${controller.lastStored!.summary}.',
        tone: SportikaColors.mint,
        icon: Icons.check_circle_outline,
        onDismiss: controller.dismissFailure,
      );
    }
    if (!controller.busy) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(SportikaRadius.pill),
          child: const LinearProgressIndicator(
            minHeight: 3,
            backgroundColor: SportikaColors.border,
            color: SportikaColors.mint,
          ),
        ),
        const SizedBox(height: SportikaSpacing.sm),
        Row(
          children: [
            const SizedBox(
              height: 13,
              width: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SportikaColors.mint,
              ),
            ),
            const SizedBox(width: SportikaSpacing.sm),
            Expanded(
              child: Text(controller.statusLabel, style: SportikaType.caption),
            ),
          ],
        ),
      ],
    );
  }
}
