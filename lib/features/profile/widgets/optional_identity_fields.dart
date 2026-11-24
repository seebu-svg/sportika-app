import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sportika/core/data/identity_document_store.dart';
import 'package:sportika/core/data/image_picker_photo_picker.dart';
import 'package:sportika/core/data/profile_photo.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/models/identity_document.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

class OptionalIdentityFields extends StatefulWidget {
  const OptionalIdentityFields({super.key});
  @override
  State<OptionalIdentityFields> createState() => _OptionalIdentityFieldsState();
}

class _OptionalIdentityFieldsState extends State<OptionalIdentityFields> {
  final _number = TextEditingController();
  String? _imageError;
  bool? _pickingFront;
  bool _preparing = false;
  bool _edited = false;
  int _selection = 0;
  int? _revision;
  IdentityDocumentKind? _kind;

  void _sync(AuthFlowController flow) {
    if (_revision == flow.identityDraftRevision && _kind == flow.identityKind) {
      return;
    }
    _selection++;
    _revision = flow.identityDraftRevision;
    _kind = flow.identityKind;
    _pickingFront = null;
    _imageError = null;
    _edited = false;
    _number.text = flow.identityDocuments.number;
  }

  Future<void> _pick(bool front) async {
    FocusScope.of(context).unfocus();
    final flow = context.read<AuthFlowController>();
    final operation = ++_selection;
    final revision = flow.identityDraftRevision;
    bool current() =>
        mounted &&
        operation == _selection &&
        revision == flow.identityDraftRevision &&
        flow.identityKind == IdentityDocumentKind.cnic &&
        !flow.busy;
    setState(() {
      _pickingFront = front;
      _preparing = false;
      _imageError = null;
    });
    try {
      final bytes = await ImagePickerPhotoPicker().grab(
        PhotoSourceKind.gallery,
      );
      if (!current() || bytes == null) return;
      setState(() => _preparing = true);
      final prepared = await prepareIdentityImage(bytes);
      if (!current()) return;
      setState(() {
        if (front) {
          flow.identityDocuments.front = prepared;
        } else {
          flow.identityDocuments.back = prepared;
        }
      });
      flow.clearInline();
    } catch (error) {
      if (current()) {
        setState(
          () => _imageError = error is FormatException
              ? '${error.message} Try another image or skip for now.'
              : 'Could not open this image. Try again or skip for now.',
        );
      }
    } finally {
      if (mounted && operation == _selection) {
        setState(() => _pickingFront = null);
      }
    }
  }

  @override
  void dispose() {
    _selection++;
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    _sync(flow);
    final kind = flow.identityKind;
    final enabled = !flow.busy && _pickingFront == null;
    final error = flow.inlineField == 'documentNumber'
        ? flow.inlineError
        : _edited
        ? validateIdentityNumber(_number.text)
        : null;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2, right: 10),
                child: Icon(
                  Icons.shield_outlined,
                  size: 21,
                  color: SportikaColors.textMuted,
                ),
              ),
              Expanded(
                child: Text('Identity Documents', style: SportikaType.headline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'OPTIONAL',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: SportikaFontWeight.bold,
              color: SportikaColors.mint,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Shared privately with Sportika, never on your public passport. '
            'You can complete your profile without these details.',
            style: SportikaType.body,
          ),
          const SizedBox(height: 20),
          if (kind == null)
            const Text(
              'Add your date of birth to see the right document: '
              'CNIC for adults or B-Form for under 18.',
              style: SportikaType.body,
            )
          else ...[
            if (kind == IdentityDocumentKind.bForm) ...[
              const Text('B-Form · Under 18', style: SportikaType.bodyStrong),
              const SizedBox(height: 6),
              const Text(
                'Use the 13-digit number on your B-Form. '
                'Ask a parent or guardian if you need help. No image is needed.',
                style: SportikaType.caption,
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _number,
              enabled: !flow.busy,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [_IdentityNumberFormatter()],
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              style: SportikaType.body.copyWith(letterSpacing: 1.2),
              decoration: InputDecoration(
                labelText: '${kind.label} number (optional)',
                hintText: '12345-1234567-1',
                errorText: error,
                errorMaxLines: 3,
                helperText: '13 digits · Leave blank to skip',
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SportikaRadius.md),
                  borderSide: const BorderSide(color: SportikaColors.mint),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  flow.identityDocuments.number = value;
                  _edited = true;
                });
                flow.clearInline();
              },
            ),
            if (kind == IdentityDocumentKind.cnic) ...[
              const SizedBox(height: 20),
              const Text('Document images', style: SportikaType.bodyStrong),
              const SizedBox(height: 5),
              const Text(
                'Each side is optional. JPEG, PNG or WebP · Under 5 MB each.',
                style: SportikaType.caption,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cards = [
                    for (final front in [true, false])
                      _DocumentCard(
                        front: front,
                        bytes: front
                            ? flow.identityDocuments.front
                            : flow.identityDocuments.back,
                        processing: _pickingFront == front,
                        preparing: _preparing,
                        onPick: enabled ? () => _pick(front) : null,
                        onRemove: enabled
                            ? () {
                                setState(() {
                                  if (front) {
                                    flow.identityDocuments.front = null;
                                  } else {
                                    flow.identityDocuments.back = null;
                                  }
                                  _imageError = null;
                                });
                                flow.clearInline();
                              }
                            : null,
                      ),
                  ];
                  if (constraints.maxWidth < 440 ||
                      MediaQuery.textScalerOf(context).scale(14) > 19) {
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 10),
                        cards[1],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  );
                },
              ),
            ],
          ],
          if (_imageError != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _imageError!,
                style: const TextStyle(
                  color: SportikaColors.danger,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: SportikaColors.mint,
              minimumSize: const Size(48, 48),
            ),
            onPressed: flow.busy
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _selection++;
                      _pickingFront = null;
                      _imageError = null;
                      flow.skipIdentityDocuments();
                      _sync(flow);
                    });
                  },
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Skip for Now'),
          ),
          const Text(
            'Add documents later in Me → Identity documents.',
            style: SportikaType.caption,
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.front,
    required this.bytes,
    required this.processing,
    required this.preparing,
    required this.onPick,
    required this.onRemove,
  });
  final bool front, processing, preparing;
  final Uint8List? bytes;
  final VoidCallback? onPick, onRemove;

  @override
  Widget build(BuildContext context) {
    final label = 'CNIC ${front ? 'front' : 'back'}';
    final selected = bytes != null;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : SportikaMotion.base,
      width: double.infinity,
      decoration: BoxDecoration(
        color: SportikaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        border: Border.all(
          color: selected || processing
              ? SportikaColors.mint.withValues(alpha: .55)
              : SportikaColors.border,
        ),
      ),
      child: Material(
        color: SportikaColors.transparent,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selected)
              ExcludeSemantics(
                child: SizedBox(
                  height: 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 16,
                          sigmaY: 16,
                        ),
                        child: Image.memory(
                          bytes!,
                          fit: BoxFit.cover,
                          cacheWidth: 240,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.description_outlined),
                        ),
                      ),
                      ColoredBox(
                        color: SportikaColors.deepest.withValues(alpha: .65),
                      ),
                      const Center(
                        child: Icon(
                          Icons.lock_outline,
                          size: 20,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    front
                        ? Icons.credit_card_outlined
                        : Icons.flip_to_back_outlined,
                    color: selected
                        ? SportikaColors.mint
                        : SportikaColors.textMuted,
                    size: 24,
                  ),
                  const SizedBox(height: 10),
                  Text(label, style: SportikaType.bodyStrong),
                  const SizedBox(height: 5),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      processing
                          ? preparing
                                ? 'Preparing image…'
                                : 'Choosing image…'
                          : selected
                          ? 'Selected · Preview masked'
                          : 'No image selected',
                      style: SportikaType.caption,
                    ),
                  ),
                ],
              ),
            ),
            if (processing)
              const Padding(
                padding: EdgeInsets.all(14),
                child: LinearProgressIndicator(
                  color: SportikaColors.mint,
                  semanticsLabel: 'Preparing document image',
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: onPick,
                      style: TextButton.styleFrom(
                        foregroundColor: SportikaColors.mint,
                        minimumSize: const Size(48, 48),
                      ),
                      child: Text(
                        selected ? 'Replace image' : 'Choose image',
                        semanticsLabel:
                            '${selected ? 'Replace' : 'Choose'} $label image',
                      ),
                    ),
                    if (selected)
                      IconButton(
                        onPressed: onRemove,
                        tooltip: 'Remove $label image',
                        icon: const Icon(Icons.close, size: 19),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IdentityNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.substring(0, digits.length.clamp(0, 13));
    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i == 5 || i == 12) buffer.write('-');
      buffer.write(limited[i]);
    }
    final before = newValue.text.substring(
      0,
      newValue.selection.extentOffset.clamp(0, newValue.text.length),
    );
    final count = before.replaceAll(RegExp(r'[^0-9]'), '').length;
    final offset = count + (count > 5 ? 1 : 0) + (count > 12 ? 1 : 0);
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(
        offset: offset.clamp(0, buffer.length),
      ),
    );
  }
}
