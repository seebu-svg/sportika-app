import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/routes.dart';
import 'package:sportika/core/data/identity_document_store.dart';
import 'package:sportika/core/data/image_picker_photo_picker.dart';
import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/core/state/profile_module_controller.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/models/profile_setup.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Me → Identity documents (optional).
///
/// CNIC for adults, B-Form for minors, both optional and neither a claim of
/// verification. The screen simply mirrors what is on file and lets the member
/// withdraw it.
class IdentityDocumentsScreen extends StatefulWidget {
  const IdentityDocumentsScreen({super.key});

  @override
  State<IdentityDocumentsScreen> createState() =>
      _IdentityDocumentsScreenState();
}

class _IdentityDocumentsScreenState extends State<IdentityDocumentsScreen> {
  final TextEditingController _number = TextEditingController();
  Uint8List? _front;
  Uint8List? _back;
  String? _imageError;
  String? _error;
  bool _picking = false;
  bool _submitting = false;
  bool _withdrawing = false;

  @override
  void initState() {
    super.initState();
    // The submit button only exists once there is something to submit, so the
    // form has to rebuild while the number is typed.
    _number.addListener(_onDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileModuleController>().ensureLoaded();
    });
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _number.removeListener(_onDraftChanged);
    _number.dispose();
    super.dispose();
  }

  Future<void> _pick(bool front) async {
    setState(() {
      _picking = true;
      _imageError = null;
    });
    try {
      final bytes = await ImagePickerPhotoPicker().grab(
        PhotoSourceKind.gallery,
      );
      if (bytes == null) return;
      final prepared = await prepareIdentityImage(bytes);
      if (!mounted) return;
      setState(() {
        if (front) {
          _front = prepared;
        } else {
          _back = prepared;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _imageError =
            'Choose a readable JPEG, PNG or WebP image under 5 MB, or skip this '
            'upload.',
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit(IdentityDocumentKind kind) async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    final module = context.read<ProfileModuleController>();
    try {
      await module.submitIdentityDocument(
        IdentitySubmission(
          kind: kind,
          number: _number.text.trim().isEmpty ? null : _number.text.trim(),
          front: _front,
          back: _back,
        ),
      );
      if (!mounted) return;
      setState(() {
        _number.clear();
        _front = null;
        _back = null;
      });
      showSnack(context, 'Identity documents saved privately');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _withdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw identity documents?'),
        content: const Text(
          'The record and its private images are deleted. Your profile stays '
          'complete without them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SportikaColors.danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final module = context.read<ProfileModuleController>();
    setState(() {
      _withdrawing = true;
      _error = null;
    });
    try {
      await module.deleteIdentityDocument();
      if (!mounted) return;
      showSnack(context, 'Identity documents withdrawn');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = context.watch<ProfileModuleController>();
    final snapshot = module.snapshot;

    final Widget body;
    if (snapshot == null) {
      body = module.error != null
          ? ErrorState(
              title: 'Your profile could not be loaded',
              message: module.error,
              onRetry: module.refresh,
            )
          : const LoadingSkeleton(rows: 3, label: 'Loading documents');
    } else {
      body = _buildBody(context, module, snapshot);
    }

    return ScreenScaffold(
      title: 'Identity documents',
      onRefresh: module.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader(
            eyebrow: 'Me · optional',
            title: 'Identity documents',
            subtitle:
                'CNIC or B-Form, only if you choose to share it. Documents are '
                'never required to play, organize or score on Sportika.',
          ),
          body,
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ProfileModuleController module,
    ProfileModuleSnapshot snapshot,
  ) {
    final record = snapshot.identity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (record != null)
          _SubmittedCard(
            record: record,
            busy: _withdrawing,
            onWithdraw: _withdraw,
          )
        else if (!module.supportsIdentityDocuments)
          const InfoBanner(
            icon: Icons.cloud_off_outlined,
            text:
                'This build keeps everything on the device, and identity '
                'documents are deliberately never written there. Sign in to a '
                'connected Sportika account to attach one — or leave it out.',
          )
        else if (snapshot.personal.dateOfBirth == null)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add your date of birth first',
                  style: SportikaType.bodyStrong,
                ),
                const SizedBox(height: 6),
                const Text(
                  'The document type follows your age: B-Form for under 18, '
                  'CNIC for adults.',
                  style: SportikaType.caption,
                ),
                const SizedBox(height: SportikaSpacing.md),
                GhostButton(
                  label: 'Open personal information',
                  icon: Icons.person_outline,
                  onPressed: () =>
                      pushRoute(context, AppRoute.personalInformation),
                ),
              ],
            ),
          )
        else
          _SubmissionForm(
            kind: identityKindFor(snapshot.personal.dateOfBirth!),
            number: _number,
            front: _front,
            back: _back,
            picking: _picking,
            busy: _submitting,
            imageError: _imageError,
            error: _error,
            onPick: _pick,
            onRemove: (front) => setState(() {
              if (front) {
                _front = null;
              } else {
                _back = null;
              }
            }),
            onSubmit: _submit,
          ),
        const SizedBox(height: SportikaSpacing.md),
        const InfoBanner(
          icon: Icons.lock_outline,
          text:
              'Images stay in a private bucket only you can read. Adding them '
              'does not verify your identity, and you can withdraw them at any '
              'time.',
        ),
      ],
    );
  }
}

class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard({
    required this.record,
    required this.busy,
    required this.onWithdraw,
  });

  final ProfileIdentityRecord record;
  final bool busy;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderColor: SportikaColors.mint.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${record.kind.label} on file',
                  style: SportikaType.bodyStrong,
                ),
              ),
              const StatusPill('Optional', color: SportikaColors.mint),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          KeyValueRow('Number', record.maskedNumber),
          KeyValueRow('Submitted', profileDateLabel(record.submittedAt)),
          KeyValueRow(
            'Images',
            [
              if (record.hasFront) 'Front',
              if (record.hasBack) 'Back',
            ].join(' · '),
          ),
          const SizedBox(height: SportikaSpacing.md),
          GhostButton(
            label: 'Withdraw documents',
            icon: Icons.delete_outline,
            tone: SportikaColors.danger,
            onPressed: busy ? null : onWithdraw,
          ),
        ],
      ),
    );
  }
}

class _SubmissionForm extends StatelessWidget {
  const _SubmissionForm({
    required this.kind,
    required this.number,
    required this.front,
    required this.back,
    required this.picking,
    required this.busy,
    required this.imageError,
    required this.error,
    required this.onPick,
    required this.onRemove,
    required this.onSubmit,
  });

  final IdentityDocumentKind kind;
  final TextEditingController number;
  final Uint8List? front;
  final Uint8List? back;
  final bool picking;
  final bool busy;
  final String? imageError;
  final String? error;
  final ValueChanged<bool> onPick;
  final ValueChanged<bool> onRemove;
  final ValueChanged<IdentityDocumentKind> onSubmit;

  @override
  Widget build(BuildContext context) {
    final empty = number.text.trim().isEmpty && front == null && back == null;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthEyebrow('${kind.label.toUpperCase()} · OPTIONAL'),
          const SizedBox(height: 10),
          AuthField(
            label: '${kind.label} number (optional)',
            controller: number,
            hint: '12345-1234567-1',
            keyboardType: TextInputType.number,
            maxLength: 15,
            enabled: !busy && !picking,
          ),
          if (kind == IdentityDocumentKind.cnic) ...[
            const SizedBox(height: 10),
            const AuthMicro(
              'Front and back images are each optional. Maximum 5 MB each.',
            ),
            const SizedBox(height: 8),
            for (final isFront in [true, false])
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: busy || picking ? null : () => onPick(isFront),
                    icon: Icon(
                      (isFront ? front : back) == null
                          ? Icons.add_photo_alternate_outlined
                          : Icons.check_circle_outline,
                    ),
                    label: Text(
                      'CNIC ${isFront ? 'front' : 'back'} (optional)',
                    ),
                  ),
                  if ((isFront ? front : back) != null)
                    IconButton(
                      tooltip: 'Remove CNIC ${isFront ? 'front' : 'back'}',
                      onPressed: busy || picking
                          ? null
                          : () => onRemove(isFront),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
          ],
          if (picking) const LinearProgressIndicator(),
          if (imageError != null) ...[
            const SizedBox(height: 8),
            Text(
              imageError!,
              style: const TextStyle(color: SportikaColors.danger),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: SportikaColors.danger)),
          ],
          const SizedBox(height: SportikaSpacing.md),
          PrimaryButton(
            label: 'Submit documents',
            icon: Icons.upload_file_outlined,
            busy: busy,
            onPressed: busy || picking || empty ? null : () => onSubmit(kind),
          ),
          const SizedBox(height: 6),
          const HelperText(
            'You can also leave this blank. Nothing else in Sportika changes.',
          ),
        ],
      ),
    );
  }
}
