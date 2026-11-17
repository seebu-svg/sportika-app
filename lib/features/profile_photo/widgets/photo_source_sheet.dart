import 'package:flutter/material.dart';

import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// What the player picked from the source sheet.
enum PhotoSheetAction { camera, gallery, remove }

/// Camera / gallery / remove choices, in the app's own sheet chrome.
///
/// Returns null when the player dismissed the sheet without deciding, which is
/// different from a removal they cancelled at the confirmation dialog.
Future<PhotoSheetAction?> showPhotoSourceSheet(
  BuildContext context, {
  required bool hasPhoto,
}) {
  return showModalBottomSheet<PhotoSheetAction>(
    context: context,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: AppSheet(
          title: 'Profile picture',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetOption(
                icon: Icons.photo_camera_outlined,
                title: 'Take a photo',
                subtitle: 'Front camera, then crop it here',
                onTap: () =>
                    Navigator.of(sheetContext).pop(PhotoSheetAction.camera),
              ),
              SheetOption(
                icon: Icons.photo_library_outlined,
                title: 'Choose from gallery',
                subtitle: 'JPG, PNG or WebP, at least ${PhotoRules.minEdge} px',
                tone: SportikaColors.mint,
                onTap: () =>
                    Navigator.of(sheetContext).pop(PhotoSheetAction.gallery),
              ),
              if (hasPhoto)
                SheetOption(
                  icon: Icons.person_off_outlined,
                  title: 'Remove picture',
                  subtitle: 'Go back to the gradient avatar',
                  tone: SportikaColors.danger,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(PhotoSheetAction.remove),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
