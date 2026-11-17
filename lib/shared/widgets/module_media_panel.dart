import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportika/app/env.dart';
import 'package:sportika/core/data/module_media_store.dart';
import 'package:sportika/core/data/image_picker_photo_picker.dart';
import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

const String _matchBucket = 'match-media';

/// Public module artwork with camera/gallery, crop, replace and delete.
///
/// Hidden on builds without a backend, because there is nowhere to store the
/// bytes. [store] and [enabled] exist so the panel can be exercised without a
/// live Supabase singleton.
class ModuleMediaPanel extends StatefulWidget {
  const ModuleMediaPanel({
    super.key,
    required this.bucket,
    required this.entity,
    required this.canEdit,
    this.label = '',
    this.showEmptyArtwork = true,
    this.store,
    this.enabled,
  });
  final String bucket;
  final String entity;
  final bool canEdit;

  /// Current name of the team, tournament or match, used by the empty-state
  /// artwork so a slot without a picture is never a blank block.
  final String label;
  final bool showEmptyArtwork;

  final ModuleMediaStore? store;
  final bool? enabled;
  @override
  State<ModuleMediaPanel> createState() => _ModuleMediaPanelState();
}

class _ModuleMediaPanelState extends State<ModuleMediaPanel> {
  bool _busy = false;
  bool _authorized = false;
  String? _error;
  final Map<String, String?> _paths = {};
  ModuleMediaStore? _fallbackStore;
  ModuleMediaStore get _store =>
      widget.store ??
      (_fallbackStore ??= ModuleMediaStore(Supabase.instance.client));
  bool get _visible =>
      widget.enabled ?? (AppEnv.hasSupabase && !AppEnv.demoMode);
  List<String> get _slots => widget.bucket == _matchBucket
      ? const ['banner']
      : const ['logo', 'banner'];

  @override
  void initState() {
    super.initState();
    if (_visible) _load();
  }

  Future<void> _load() async {
    try {
      final paths = <String, String?>{};
      for (final slot in _slots) {
        paths[slot] = await _store.path(widget.bucket, widget.entity, slot);
      }
      var authorized = false;
      if (widget.canEdit) {
        // A squad or tournament exists only on the device that created it, so
        // the creator claims the entity once. That claim is what turns "I am
        // the captain here" into a Storage permission, and it is a no-op on
        // every later visit. Match banners derive authority from the match row.
        if (widget.bucket != _matchBucket) {
          await _store.claim(widget.bucket, widget.entity);
        }
        authorized = await _store.canManage(widget.bucket, widget.entity);
      }
      if (mounted) {
        setState(() {
          _paths.addAll(paths);
          _authorized = authorized;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _readMessage(error));
    }
  }

  /// Refusals and outages arrive the same way, so only the SQLSTATEs this app
  /// raises get their own copy; everything else is a retryable failure.
  String _readMessage(Object error) {
    if (error is PostgrestException) {
      return switch (error.code) {
        '23514' => 'You have added too much artwork today. Try again tomorrow.',
        '22023' => 'This item cannot hold artwork.',
        '28000' => 'Sign in again to manage this artwork.',
        _ => 'Media is unavailable. Try again.',
      };
    }
    return 'Media is unavailable. Check your connection, then retry.';
  }

  String _saveMessage(Object error) =>
      error is PostgrestException || error is StorageException
      ? 'Artwork was not saved. Check your permissions, then retry.'
      : 'Media could not be saved. Check your connection, then retry.';

  Future<void> _change(String slot, {bool remove = false}) async {
    if (_busy) return;
    Uint8List? prepared;
    try {
      if (!remove) {
        final source = await showModalBottomSheet<PhotoSourceKind>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Camera'),
                  onTap: () => Navigator.pop(context, PhotoSourceKind.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () => Navigator.pop(context, PhotoSourceKind.gallery),
                ),
              ],
            ),
          ),
        );
        if (source == null) return;
        final bytes = await ImagePickerPhotoPicker().grab(source);
        if (bytes == null || !mounted) return;
        prepared = await showDialog<Uint8List>(
          context: context,
          builder: (_) => _MediaCrop(bytes: bytes, banner: slot == 'banner'),
        );
        if (prepared == null || !mounted) return;
      }
      if (!mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      await _store.save(widget.bucket, widget.entity, slot, prepared);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _saveMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: SportikaSpacing.xs),
          const Text('Uploading artwork…', style: SportikaType.caption),
        ],
        if (_error != null)
          TextButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(_error!),
          ),
        for (final slot in _slots) ...[
          if (widget.showEmptyArtwork || _paths[slot] != null)
            _ArtworkFrame(
              banner: slot == 'banner',
              url: _paths[slot] == null
                  ? null
                  : _store.publicUrl(widget.bucket, _paths[slot]!),
              label: widget.label,
            ),
          if (_authorized)
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _change(slot),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    '${_paths[slot] == null ? 'Add' : 'Replace'} $slot',
                  ),
                ),
                if (_paths[slot] != null)
                  IconButton(
                    tooltip: 'Delete $slot',
                    onPressed: _busy ? null : () => _change(slot, remove: true),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

/// One artwork slot: the uploaded picture, or brand placeholder art that keeps
/// the card's height stable and explains what belongs here.
class _ArtworkFrame extends StatelessWidget {
  const _ArtworkFrame({
    required this.banner,
    required this.url,
    required this.label,
  });
  final bool banner;
  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final uploaded = url;
    final art = uploaded == null
        ? _ArtworkPlaceholder(banner: banner, label: label)
        : Image.network(
            uploaded,
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) =>
                _ArtworkPlaceholder(banner: banner, label: label),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: banner
            // A 16:9 slot that follows the full column width would tower over
            // the card on a tablet, so the ratio holds but the height is capped.
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SportikaRadius.lg),
                  child: AspectRatio(aspectRatio: 16 / 9, child: art),
                ),
              )
            : ClipOval(child: SizedBox.square(dimension: 96, child: art)),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.banner, required this.label});
  final bool banner;
  final String label;

  String get _initial {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return 'S';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  static const LinearGradient _surface = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [SportikaColors.surfaceAlt, SportikaColors.surfaceSunken],
  );

  @override
  Widget build(BuildContext context) {
    if (!banner) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _surface,
          border: Border.all(color: SportikaColors.borderStrong),
        ),
        child: Center(
          child: Text(
            _initial,
            style: SportikaType.title.copyWith(color: SportikaColors.textMuted),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SportikaRadius.lg),
        gradient: _surface,
        border: Border.all(color: SportikaColors.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_outlined,
              color: SportikaColors.textDim,
              size: 28,
            ),
            const SizedBox(height: SportikaSpacing.xs),
            Text(
              label.trim().isEmpty ? 'Cover image' : label.trim(),
              style: SportikaType.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Text('No cover image yet', style: SportikaType.caption),
          ],
        ),
      ),
    );
  }
}

class _MediaCrop extends StatefulWidget {
  const _MediaCrop({required this.bytes, required this.banner});
  final Uint8List bytes;
  final bool banner;
  @override
  State<_MediaCrop> createState() => _MediaCropState();
}

class _MediaCropState extends State<_MediaCrop> {
  double _x = .5, _y = .5;
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Crop image'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: widget.banner ? 16 / 9 : 1,
            child: Image.memory(
              widget.bytes,
              fit: BoxFit.cover,
              alignment: Alignment(_x * 2 - 1, _y * 2 - 1),
            ),
          ),
          const Text('Horizontal position'),
          Slider(
            value: _x,
            onChanged: _busy ? null : (v) => setState(() => _x = v),
          ),
          const Text('Vertical position'),
          Slider(
            value: _y,
            onChanged: _busy ? null : (v) => setState(() => _y = v),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  final bytes = await ModuleMediaStore.prepare(
                    widget.bytes,
                    widget.banner,
                    _x,
                    _y,
                  );
                  if (context.mounted) Navigator.pop(context, bytes);
                } catch (_) {
                  if (mounted) {
                    setState(() {
                      _error =
                          'Choose a readable JPEG, PNG or WebP under 12 MB.';
                      _busy = false;
                    });
                  }
                }
              },
        child: const Text('Use image'),
      ),
    ],
  );
}
