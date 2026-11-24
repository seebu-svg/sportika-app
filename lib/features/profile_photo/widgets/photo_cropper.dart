import 'package:flutter/material.dart';

import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Squares, pans and zooms a freshly picked picture before it is stored.
///
/// The crop numbers are authored in the same viewport units
/// [PhotoCrop.viewportEdge] that [renderCroppedPhoto] renders with, so what the
/// player frames here is literally what gets written: the preview and the output
/// share one coordinate system instead of approximating each other.
class PhotoCropperSheet extends StatefulWidget {
  const PhotoCropperSheet({
    super.key,
    required this.photo,
    required this.initials,
  });

  final PickedPhoto photo;
  final String initials;

  /// Opens the cropper and returns the chosen crop, or null when abandoned.
  static Future<PhotoCrop?> show(
    BuildContext context, {
    required PickedPhoto photo,
    required String initials,
  }) {
    return showDialog<PhotoCrop>(
      context: context,
      barrierColor: SportikaColors.deepest.withValues(alpha: .92),
      builder: (_) => PhotoCropperSheet(photo: photo, initials: initials),
    );
  }

  @override
  State<PhotoCropperSheet> createState() => _PhotoCropperSheetState();
}

class _PhotoCropperSheetState extends State<PhotoCropperSheet> {
  static const double _edge = PhotoCrop.viewportEdge;

  double _scale = 1;
  double _dx = 0;
  double _dy = 0;

  /// Zoom the pinch gesture started from, so [ScaleGestureRecognizer] deltas
  /// compose instead of compounding.
  double _scaleAtStart = 1;

  @override
  void initState() {
    super.initState();
    _center();
  }

  Size get _drawn => PhotoCrop.drawnSize(
    widget.photo.width.toDouble(),
    widget.photo.height.toDouble(),
    scale: _scale,
  );

  void _center() {
    final drawn = PhotoCrop.drawnSize(
      widget.photo.width.toDouble(),
      widget.photo.height.toDouble(),
      scale: _scale,
    );
    _dx = (_edge - drawn.width) / 2;
    _dy = (_edge - drawn.height) / 2;
  }

  /// Applies the current pan/zoom through the clamp that keeps the frame full,
  /// so the picture can never be dragged off the crop area and leave a gap.
  void _apply({double? scale, double? dx, double? dy}) {
    final next = PhotoCrop.clamped(
      imageWidth: widget.photo.width.toDouble(),
      imageHeight: widget.photo.height.toDouble(),
      scale: scale ?? _scale,
      dx: dx ?? _dx,
      dy: dy ?? _dy,
    );
    setState(() {
      _scale = next.scale;
      _dx = next.dx;
      _dy = next.dy;
    });
  }

  PhotoCrop get _crop => PhotoCrop(scale: _scale, dx: _dx, dy: _dy);

  @override
  Widget build(BuildContext context) {
    final drawn = _drawn;
    final photo = widget.photo;
    // Decoding the preview wider than the frame keeps it sharp while zoomed in,
    // without pulling the whole 2048 px bitmap into the tree.
    final previewWidth = (drawn.width * 2).clamp(_edge, 1024.0).round();

    return Dialog(
      backgroundColor: SportikaColors.surfaceElevated,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SportikaRadius.xl),
        side: const BorderSide(color: SportikaColors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'FRAME YOUR PICTURE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: SportikaFontWeight.extraBold,
                      letterSpacing: 1.4,
                      color: SportikaColors.textMuted,
                    ),
                  ),
                ),
                IconAction(
                  icon: Icons.close,
                  label: 'Cancel cropping',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: GestureDetector(
                  onScaleStart: (_) => setState(() => _scaleAtStart = _scale),
                  onScaleUpdate: (details) => _apply(
                    scale: _scaleAtStart * details.scale,
                    dx: _dx + details.focalPointDelta.dx,
                    dy: _dy + details.focalPointDelta.dy,
                  ),
                  child: ClipOval(
                    child: Container(
                      height: _edge,
                      width: _edge,
                      color: SportikaColors.deepest,
                      child: Stack(
                        children: [
                          Positioned(
                            left: _dx,
                            top: _dy,
                            child: SizedBox(
                              height: drawn.height,
                              width: drawn.width,
                              child: Image.memory(
                                photo.bytes,
                                fit: BoxFit.fill,
                                cacheWidth: previewWidth,
                                semanticLabel: 'Picture being cropped',
                                errorBuilder: (_, _, _) =>
                                    const _DecodeFailure(),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(painter: _CropGuidePainter()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.zoom_out_map,
                  size: 15,
                  color: SportikaColors.textDim,
                ),
                Expanded(
                  child: Slider(
                    value: _scale,
                    min: 1,
                    max: PhotoRules.maxZoom.toDouble(),
                    activeColor: SportikaColors.mint,
                    inactiveColor: SportikaColors.border,
                    label: '${_scale.toStringAsFixed(1)}x',
                    onChanged: (value) => _apply(scale: value),
                  ),
                ),
                Text(
                  '${_scale.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: SportikaFontWeight.bold,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            InfoBanner(
              icon: Icons.crop_free,
              text:
                  'Drag or pinch to reframe. The circle is what every avatar in '
                  'the app will show, so keep your face inside it. '
                  '${photo.sourceSizeLabel} source, saved as a '
                  '${PhotoRules.storedEdge} px square.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'CANCEL',
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'USE PICTURE',
                    icon: Icons.check,
                    onPressed: () => Navigator.of(context).pop(_crop),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown if the picked bytes refuse to decode in the preview. The save path
/// reports the real failure with its own copy.
class _DecodeFailure extends StatelessWidget {
  const _DecodeFailure();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.broken_image_outlined, color: SportikaColors.textDim),
    );
  }
}

/// Rule-of-thirds guides plus the circle the picture is clipped to.
class _CropGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = SportikaColors.onAccent.withValues(alpha: .28)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final at = size.width * i / 3;
      canvas.drawLine(Offset(at, 0), Offset(at, size.height), line);
      canvas.drawLine(Offset(0, at), Offset(size.width, at), line);
    }
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = SportikaColors.mint.withValues(alpha: .85),
    );
  }

  @override
  bool shouldRepaint(_CropGuidePainter oldDelegate) => false;
}
