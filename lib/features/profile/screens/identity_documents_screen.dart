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
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Sportika Athlete Verification.
///
/// Existing infrastructure stores optional identity documents.
/// Uploading a document does not verify the athlete.
///
/// This screen deliberately distinguishes:
/// - No document
/// - Document on file, not verified
///
/// Future verification statuses must come from a trusted backend.
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
  bool _consented = false;

  @override
  void initState() {
    super.initState();

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
    _front = null;
    _back = null;
    super.dispose();
  }

  Future<void> _pick(bool front) async {
    if (_picking || _submitting) return;

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

      setState(() {
        _imageError =
            'Unable to prepare this image. Choose a readable '
            'JPEG, PNG or WebP file under 5 MB.';
      });
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _submit(IdentityDocumentKind kind) async {
    if (_submitting || _picking || !_consented) return;

    final hasContent =
        _number.text.trim().isNotEmpty || _front != null || _back != null;

    if (!hasContent) return;

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      await context.read<ProfileModuleController>().submitIdentityDocument(
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
        _consented = false;
      });

      showSnack(context, 'Document submitted. Identity is not yet verified.');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to submit the document. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _withdraw() async {
    if (_withdrawing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw identity document?'),
        content: const Text(
          'Sportika will request removal of the stored identity '
          'record and its associated images. This does not '
          'affect your athlete account, teams or matches.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep document'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Withdraw',
              style: TextStyle(color: SportikaColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _withdrawing = true;
      _error = null;
    });

    try {
      await context.read<ProfileModuleController>().deleteIdentityDocument();

      if (!mounted) return;

      showSnack(context, 'Document withdrawal completed.');
    } on ProfileModuleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to withdraw the document.';
      });
    } finally {
      if (mounted) {
        setState(() => _withdrawing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = context.watch<ProfileModuleController>();
    final snapshot = module.snapshot;

    Widget body;

    if (snapshot == null) {
      body = module.error != null
          ? ErrorState(
              title: 'Unable to load verification information',
              message: module.error,
              onRetry: module.refresh,
            )
          : const LoadingSkeleton(rows: 3, label: 'Loading athlete identity');
    } else {
      body = _buildBody(module, snapshot);
    }

    return ScreenScaffold(
      title: 'Athlete verification',
      onRefresh: module.refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _VerificationHero(),

          const SizedBox(height: SportikaSpacing.lg),

          body,
        ],
      ),
    );
  }

  Widget _buildBody(
    ProfileModuleController module,
    ProfileModuleSnapshot snapshot,
  ) {
    final record = snapshot.identity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VerificationStatusCard(hasDocument: record != null),

        const SizedBox(height: SportikaSpacing.lg),

        const _VerificationSectionHeading(
          title: 'Identity Documents',
          subtitle: 'Choose to submit a supported identity document.',
        ),

        const SizedBox(height: SportikaSpacing.md),

        if (record != null)
          _SubmittedDocumentCard(
            record: record,
            busy: _withdrawing,
            onWithdraw: _withdraw,
          )
        else if (!module.supportsIdentityDocuments)
          const InfoBanner(
            icon: Icons.cloud_off_outlined,
            text:
                'Document submission is unavailable in this '
                'account configuration. Identity documents '
                'are not stored locally.',
          )
        else if (snapshot.personal.dateOfBirth == null)
          _DateOfBirthRequiredCard(
            onOpen: () => pushRoute(context, AppRoute.personalInformation),
          )
        else ...[
          _DocumentMethodCard(
            kind: identityKindFor(snapshot.personal.dateOfBirth!),
          ),

          const SizedBox(height: SportikaSpacing.md),

          _SubmissionForm(
            kind: identityKindFor(snapshot.personal.dateOfBirth!),
            number: _number,
            front: _front,
            back: _back,
            picking: _picking,
            busy: _submitting,
            consented: _consented,
            imageError: _imageError,
            error: _error,
            onConsentChanged: (value) {
              setState(() => _consented = value);
            },
            onPick: _pick,
            onRemove: (front) {
              setState(() {
                if (front) {
                  _front = null;
                } else {
                  _back = null;
                }
              });
            },
            onSubmit: _submit,
          ),
        ],

        if (_error != null && record != null) ...[
          const SizedBox(height: SportikaSpacing.md),
          InlineBanner(text: _error!, tone: SportikaColors.danger),
        ],

        const SizedBox(height: SportikaSpacing.lg),

        const _VerificationPrivacyCard(),

        const SizedBox(height: SportikaSpacing.md),

        const InfoBanner(
          icon: Icons.info_outline_rounded,
          text:
              'Identity documents are optional. Uploading '
              'documents does not verify identity or grant '
              'a verified-athlete badge.',
        ),
      ],
    );
  }
}

// ============================================================
// HERO
// ============================================================

class _VerificationHero extends StatelessWidget {
  const _VerificationHero();

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SportikaSpacing.lg),
      decoration: BoxDecoration(
        gradient: SportikaGradients.sportCoin(theme.live),
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: theme.live),
              const SizedBox(width: SportikaSpacing.sm),
              Text(
                'SPORTIKA / IDENTITY & SECURITY',
                style: SportikaType.micro.copyWith(color: theme.live),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.lg),

          const Text('ATHLETE\nVERIFICATION', style: SportikaType.title),

          const SizedBox(height: SportikaSpacing.sm),

          Text(
            'Your identity. Your privacy. Your game.',
            style: SportikaType.body.copyWith(color: theme.textBody),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// VERIFICATION STATUS
// ============================================================

class _VerificationStatusCard extends StatelessWidget {
  const _VerificationStatusCard({required this.hasDocument});

  final bool hasDocument;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            decoration: BoxDecoration(
              color: theme.surfaceSunken,
              borderRadius: BorderRadius.circular(SportikaRadius.control),
            ),
            child: Icon(
              hasDocument
                  ? Icons.description_outlined
                  : Icons.verified_user_outlined,
              color: hasDocument ? SportikaColors.gold : theme.textMuted,
            ),
          ),

          const SizedBox(width: SportikaSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Identity Status', style: SportikaType.bodyStrong),

                const SizedBox(height: SportikaSpacing.sm),

                StatusPill(
                  hasDocument ? 'Document on file' : 'Not verified',
                  color: hasDocument ? SportikaColors.gold : theme.textMuted,
                ),

                const SizedBox(height: SportikaSpacing.sm),

                Text(
                  hasDocument
                      ? 'A document is stored on your account. '
                            'It has not been verified.'
                      : 'You have not completed identity '
                            'verification. You can still use '
                            'Sportika normally.',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SECTION HEADING
// ============================================================

class _VerificationSectionHeading extends StatelessWidget {
  const _VerificationSectionHeading({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SportikaType.titleMedium),
        const SizedBox(height: SportikaSpacing.xs),
        Text(
          subtitle,
          style: SportikaType.caption.copyWith(color: theme.textMuted),
        ),
      ],
    );
  }
}

// ============================================================
// DOCUMENT METHOD
// ============================================================

class _DocumentMethodCard extends StatelessWidget {
  const _DocumentMethodCard({required this.kind});

  final IdentityDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(SportikaSpacing.md),
            decoration: BoxDecoration(
              color: theme.surfaceSunken,
              borderRadius: BorderRadius.circular(SportikaRadius.control),
            ),
            child: Icon(Icons.badge_outlined, color: theme.live),
          ),

          const SizedBox(width: SportikaSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind.label, style: SportikaType.bodyStrong),

                const SizedBox(height: SportikaSpacing.xs),

                Text(
                  kind == IdentityDocumentKind.cnic
                      ? 'Document type for eligible adults.'
                      : 'Document type for eligible minors.',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),

          const Icon(
            Icons.check_circle_outline_rounded,
            color: SportikaColors.mint,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DATE OF BIRTH REQUIRED
// ============================================================

class _DateOfBirthRequiredCard extends StatelessWidget {
  const _DateOfBirthRequiredCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add your date of birth', style: SportikaType.bodyStrong),

          const SizedBox(height: SportikaSpacing.sm),

          const Text(
            'Your date of birth determines which '
            'document type is available.',
            style: SportikaType.caption,
          ),

          const SizedBox(height: SportikaSpacing.md),

          GhostButton(
            label: 'Open Personal Information',
            icon: Icons.person_outline_rounded,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SUBMITTED DOCUMENT
// ============================================================

class _SubmittedDocumentCard extends StatelessWidget {
  const _SubmittedDocumentCard({
    required this.record,
    required this.busy,
    required this.onWithdraw,
  });

  final ProfileIdentityRecord record;
  final bool busy;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      borderColor: theme.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, color: theme.live),

              const SizedBox(width: SportikaSpacing.sm),

              Expanded(
                child: Text(
                  '${record.kind.label} on file',
                  style: SportikaType.bodyStrong,
                ),
              ),

              const StatusPill('Not verified', color: SportikaColors.gold),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          KeyValueRow('Document number', record.maskedNumber),

          KeyValueRow('Submitted', profileDateLabel(record.submittedAt)),

          KeyValueRow(
            'Images',
            [if (record.hasFront) 'Front', if (record.hasBack) 'Back'].isEmpty
                ? 'None'
                : [
                    if (record.hasFront) 'Front',
                    if (record.hasBack) 'Back',
                  ].join(' · '),
          ),

          const SizedBox(height: SportikaSpacing.md),

          GhostButton(
            label: busy ? 'Withdrawing...' : 'Withdraw Document',
            icon: Icons.delete_outline_rounded,
            tone: SportikaColors.danger,
            onPressed: busy ? null : onWithdraw,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DOCUMENT SUBMISSION
// ============================================================

class _SubmissionForm extends StatelessWidget {
  const _SubmissionForm({
    required this.kind,
    required this.number,
    required this.front,
    required this.back,
    required this.picking,
    required this.busy,
    required this.consented,
    required this.imageError,
    required this.error,
    required this.onConsentChanged,
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
  final bool consented;

  final String? imageError;
  final String? error;

  final ValueChanged<bool> onConsentChanged;
  final ValueChanged<bool> onPick;
  final ValueChanged<bool> onRemove;
  final ValueChanged<IdentityDocumentKind> onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final empty = number.text.trim().isEmpty && front == null && back == null;

    final canSubmit = !empty && !busy && !picking && consented;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthEyebrow('${kind.label.toUpperCase()} / OPTIONAL'),

          const SizedBox(height: SportikaSpacing.md),

          AuthField(
            label: '${kind.label} number',
            controller: number,
            hint: 'Enter document number',
            keyboardType: TextInputType.number,
            maxLength: 15,
            enabled: !busy && !picking,
          ),

          if (kind == IdentityDocumentKind.cnic) ...[
            const SizedBox(height: SportikaSpacing.md),

            const Text('Document Images', style: SportikaType.bodyStrong),

            const SizedBox(height: SportikaSpacing.xs),

            const Text(
              'You may attach the front and back of your '
              'document. Each image must be under 5 MB.',
              style: SportikaType.caption,
            ),

            const SizedBox(height: SportikaSpacing.md),

            _DocumentImageTile(
              label: 'Front of CNIC',
              bytes: front,
              enabled: !busy && !picking,
              onPick: () => onPick(true),
              onRemove: () => onRemove(true),
            ),

            const SizedBox(height: SportikaSpacing.sm),

            _DocumentImageTile(
              label: 'Back of CNIC',
              bytes: back,
              enabled: !busy && !picking,
              onPick: () => onPick(false),
              onRemove: () => onRemove(false),
            ),
          ],

          if (picking) ...[
            const SizedBox(height: SportikaSpacing.md),
            const LinearProgressIndicator(),
          ],

          if (imageError != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: imageError!, tone: SportikaColors.danger),
          ],

          if (error != null) ...[
            const SizedBox(height: SportikaSpacing.md),
            InlineBanner(text: error!, tone: SportikaColors.danger),
          ],

          const SizedBox(height: SportikaSpacing.md),

          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: consented,
            activeColor: theme.live,
            title: const Text(
              'I choose to submit this document',
              style: SportikaType.bodyStrong,
            ),
            subtitle: const Text(
              'I understand that uploading a document '
              'does not verify my identity.',
              style: SportikaType.caption,
            ),
            onChanged: busy || picking
                ? null
                : (value) => onConsentChanged(value ?? false),
          ),

          const SizedBox(height: SportikaSpacing.md),

          PrimaryButton(
            label: 'Submit Document',
            icon: Icons.upload_file_outlined,
            busy: busy,
            onPressed: canSubmit ? () => onSubmit(kind) : null,
          ),

          const SizedBox(height: SportikaSpacing.sm),

          const HelperText(
            'Document submission is optional and '
            'does not affect your ability to play, '
            'create teams or organize matches.',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DOCUMENT IMAGE TILE
// ============================================================

class _DocumentImageTile extends StatelessWidget {
  const _DocumentImageTile({
    required this.label,
    required this.bytes,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final String label;
  final Uint8List? bytes;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return Container(
      padding: const EdgeInsets.all(SportikaSpacing.md),
      decoration: BoxDecoration(
        color: theme.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.control),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(
            bytes == null
                ? Icons.add_photo_alternate_outlined
                : Icons.check_circle_outline_rounded,
            color: bytes == null ? theme.textMuted : SportikaColors.mint,
          ),

          const SizedBox(width: SportikaSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SportikaType.bodyStrong),
                const SizedBox(height: SportikaSpacing.xxs),
                Text(
                  bytes == null ? 'No image selected' : 'Image ready to submit',
                  style: SportikaType.caption,
                ),
              ],
            ),
          ),

          if (bytes != null)
            IconButton(
              tooltip: 'Remove $label',
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.close_rounded),
            )
          else
            IconButton(
              tooltip: 'Choose $label',
              onPressed: enabled ? onPick : null,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// PRIVACY INFORMATION
// ============================================================

class _VerificationPrivacyCard extends StatelessWidget {
  const _VerificationPrivacyCard();

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: theme.live),

              const SizedBox(width: SportikaSpacing.sm),

              const Expanded(
                child: Text(
                  'Your Privacy Matters',
                  style: SportikaType.bodyStrong,
                ),
              ),
            ],
          ),

          const SizedBox(height: SportikaSpacing.md),

          const Text(
            'Identity documents are sensitive personal '
            'information. They should not appear on your '
            'public athlete profile.',
            style: SportikaType.caption,
          ),

          const SizedBox(height: SportikaSpacing.sm),

          const Text(
            'You can request withdrawal of a submitted '
            'document. Retention, backups and deletion '
            'must follow the platform privacy policy.',
            style: SportikaType.caption,
          ),
        ],
      ),
    );
  }
}
