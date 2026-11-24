import 'package:flutter/material.dart';
import 'package:sportika/features/matches/widgets/match_result_card.dart';

import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/layout.dart';
import 'package:sportika/shared/widgets/state_views.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Confirms the engine fold before it is frozen into a submission.
///
/// The numbers are read-only here: the workspace already owns how a score is
/// recorded, and this step only asks the scorer to agree with the fold that the
/// engines produced.
Future<bool> confirmSubmitResult(
  BuildContext context, {
  required SportMatch match,
  required MatchProgress progress,
}) async {
  final sides = match.sideNames;
  final scores = progress.scoreDisplay;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Submit this result?'),
      scrollable: true,
      icon: const Icon(Icons.fact_check_outlined, color: SportikaColors.gold),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('FINAL SCORE REVIEW', style: SportikaType.label),
          const SizedBox(height: 12),
          ResultScoreLines(
            labels: sides,
            scores: scores,
            winnerIndex: progress.isComplete ? progress.winnerIndex : -1,
            // The dialog measures this content's intrinsic height, so the review
            // panel declares its narrow layout instead of measuring for one.
            stacked: true,
          ),
          if (progress.resultLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(progress.resultLabel, style: SportikaType.bodyStrong),
          ],
          const SizedBox(height: 14),
          const Text(
            'The log closes when you submit. The organizer reviews it and '
            'publishes the final result.',
            style: SportikaType.caption,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Keep scoring'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Submit'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The payload of a published correction.
class CorrectedResult {
  const CorrectedResult({
    required this.headline,
    required this.detail,
    required this.sideScores,
    required this.sideValues,
    required this.winnerIndex,
    required this.reason,
  });

  final String headline;
  final String detail;
  final List<String> sideScores;
  final List<int> sideValues;
  final int winnerIndex;
  final String reason;
}

/// Edits a result that is already published. The server keeps the previous row
/// and the reason, so every correction stays auditable.
Future<CorrectedResult?> showCorrectResultSheet(
  BuildContext context, {
  required SportMatch match,
}) {
  return showModalBottomSheet<CorrectedResult>(
    context: context,
    useSafeArea: true,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
    ),
    builder: (_) =>
        SingleChildScrollView(child: _CorrectResultSheet(match: match)),
  );
}

class _CorrectResultSheet extends StatefulWidget {
  const _CorrectResultSheet({required this.match});

  final SportMatch match;

  @override
  State<_CorrectResultSheet> createState() => _CorrectResultSheetState();
}

class _CorrectResultSheetState extends State<_CorrectResultSheet> {
  late final TextEditingController _headline = TextEditingController(
    text: widget.match.result?.headline ?? '',
  );
  late final TextEditingController _detail = TextEditingController(
    text: widget.match.result?.detail ?? '',
  );
  final TextEditingController _reason = TextEditingController();
  late final List<TextEditingController> _scores = [
    TextEditingController(
      text: widget.match.result?.sideValues.isNotEmpty == true
          ? '${widget.match.result!.sideValues[0]}'
          : '0',
    ),
    TextEditingController(
      text: (widget.match.result?.sideValues.length ?? 0) > 1
          ? '${widget.match.result!.sideValues[1]}'
          : '0',
    ),
  ];
  late final List<TextEditingController> _displayScores = [
    for (var side = 0; side < 2; side++)
      TextEditingController(
        text: (widget.match.result?.sideScores.length ?? 0) > side
            ? widget.match.result!.sideScores[side]
            : '',
      ),
  ];
  late int _winner = widget.match.result?.winnerIndex ?? 0;
  String? _error;

  @override
  void dispose() {
    _headline.dispose();
    _detail.dispose();
    _reason.dispose();
    for (final controller in [..._scores, ..._displayScores]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Explain why the result changed.');
      return;
    }
    final values = [
      for (final controller in _scores)
        int.tryParse(controller.text.trim()) ?? -1,
    ];
    if (values.any((value) => value < 0)) {
      setState(
        () =>
            _error = 'Enter a valid non-negative numeric total for each side.',
      );
      return;
    }
    final sides = widget.match.sideNames;
    final headline = _headline.text.trim().isEmpty
        ? _winner < 0
              ? 'Match drawn'
              : '${sides[_winner.clamp(0, sides.length - 1)]} won'
        : _headline.text.trim();
    Navigator.of(context).pop(
      CorrectedResult(
        headline: headline,
        detail: _detail.text.trim(),
        sideScores: [
          for (var side = 0; side < values.length; side++)
            _displayScores[side].text.trim().isEmpty
                ? '${values[side]}'
                : _displayScores[side].text.trim(),
        ],
        sideValues: values,
        winnerIndex: _winner,
        reason: reason,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sides = widget.match.sideNames;
    return AppSheet(
      title: 'Correct result',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HelperText(
            'Keep the displayed score and its numeric total consistent. Your reason is saved with the previous result.',
          ),
          const SizedBox(height: SportikaSpacing.md),
          for (var side = 0; side < 2; side++) ...[
            Text(
              side < sides.length ? sides[side] : 'Side',
              style: SportikaType.bodyStrong,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _displayScores[side],
              decoration: const InputDecoration(
                labelText: 'Displayed score',
                hintText: 'e.g. 125/4 or 6–4, 6–3',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _scores[side],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Numeric total'),
            ),
            const SizedBox(height: SportikaSpacing.md),
          ],
          const Text('WINNER', style: SportikaType.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (var side = 0; side < sides.length; side++)
                ChoiceChip(
                  label: Text(sides[side]),
                  selected: _winner == side,
                  onSelected: (_) => setState(() => _winner = side),
                ),
              ChoiceChip(
                label: const Text('Draw'),
                selected: _winner < 0,
                onSelected: (_) => setState(() => _winner = -1),
              ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.md),
          TextField(
            controller: _headline,
            decoration: const InputDecoration(
              labelText: 'Headline',
              isDense: true,
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          TextField(
            controller: _detail,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Detail',
              isDense: true,
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          TextField(
            controller: _reason,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Why is this changing? (required)',
              isDense: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: SportikaSpacing.sm),
            InlineBanner(text: _error!, tone: SportikaColors.danger),
          ],
          const SizedBox(height: SportikaSpacing.md),
          PrimaryButton(
            label: 'Save correction',
            icon: Icons.save_outlined,
            onPressed: _save,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          const HelperText(
            'The previous result is kept with your reason, so nothing is ever '
            'silently overwritten.',
          ),
        ],
      ),
    );
  }
}

/// Winner plus reason for a walkover.
class WalkoverChoice {
  const WalkoverChoice({required this.winnerIndex, required this.reason});

  final int winnerIndex;
  final String reason;
}

Future<WalkoverChoice?> showWalkoverSheet(
  BuildContext context, {
  required SportMatch match,
}) {
  return showModalBottomSheet<WalkoverChoice>(
    context: context,
    useSafeArea: true,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
    ),
    builder: (_) => SingleChildScrollView(child: _WalkoverSheet(match: match)),
  );
}

class _WalkoverSheet extends StatefulWidget {
  const _WalkoverSheet({required this.match});

  final SportMatch match;

  @override
  State<_WalkoverSheet> createState() => _WalkoverSheetState();
}

class _WalkoverSheetState extends State<_WalkoverSheet> {
  final TextEditingController _reason = TextEditingController();
  int _winner = 0;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sides = widget.match.sideNames;
    final reason = _reason.text.trim();
    return AppSheet(
      title: 'Record a walkover',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A walkover closes the match without a played result. Choose who '
            'takes it and say why.',
            style: SportikaType.caption,
          ),
          const SizedBox(height: SportikaSpacing.md),
          Wrap(
            spacing: 8,
            children: [
              for (var side = 0; side < sides.length; side++)
                ChoiceChip(
                  label: Text(sides[side]),
                  selected: _winner == side,
                  onSelected: (_) => setState(() => _winner = side),
                ),
            ],
          ),
          const SizedBox(height: SportikaSpacing.sm),
          TextField(
            controller: _reason,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              isDense: true,
            ),
          ),
          const SizedBox(height: SportikaSpacing.md),
          PrimaryButton(
            label: 'Record walkover',
            icon: Icons.handshake_outlined,
            tone: SportikaColors.gold,
            onPressed: reason.length < 3
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(WalkoverChoice(winnerIndex: _winner, reason: reason)),
          ),
        ],
      ),
    );
  }
}

/// Cancels a match. Returns the reason, which the lifecycle log keeps.
Future<String?> showCancelMatchDialog(BuildContext context) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Cancel this match?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Invited players lose the fixture and nothing can be recorded '
            'afterwards.',
            style: SportikaType.caption,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Keep the match'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: SportikaColors.danger),
          onPressed: () => Navigator.pop(dialog, controller.text.trim()),
          child: const Text('Cancel match'),
        ),
      ],
    ),
  );
  controller.dispose();
  return reason;
}

/// Pauses scoring without ending the match. Returns the optional reason (an
/// empty string pauses without one), or null when the scorer backs out.
///
/// The server keeps the reason on the match and in the lifecycle log, and
/// refuses a reason shorter than 3 characters, so the dialog says so up front.
Future<String?> showPauseMatchDialog(BuildContext context) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Pause scoring?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'The match stays live and the score is kept, but no point can be '
            'recorded until the organizer or the official scorer resumes it.',
            style: SportikaType.caption,
          ),
          const SizedBox(height: SportikaSpacing.sm),
          TextField(
            controller: controller,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Reason (optional, 3 to 200 characters)',
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Keep scoring'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: SportikaColors.gold),
          onPressed: () => Navigator.pop(dialog, controller.text.trim()),
          child: const Text('Pause scoring'),
        ),
      ],
    ),
  );
  controller.dispose();
  return reason;
}

/// What the scorer asked for when they retired a badminton match.
class MatchRetireRequest {
  const MatchRetireRequest({required this.winnerIndex, required this.reason});

  final int winnerIndex;
  final String reason;
}

/// Retires a badminton match that will not reach the winning game.
///
/// The partial score is shown, not typed: it comes from the rally log, and the
/// server writes the same thing. The reason is required because a retirement is
/// the only way to decide an unfinished match, and the winner is the side that
/// takes the result. Returns null when the scorer backs out.
Future<MatchRetireRequest?> showMatchRetireSheet(
  BuildContext context, {
  required SportMatch match,
  required MatchProgress progress,
}) async {
  final controller = TextEditingController();
  final scores = progress.scoreDisplay;
  final partial = scores[0] == '-' ? 'no game completed' : scores.join(' / ');
  var winner = progress.scoreValues[0] >= progress.scoreValues[1] ? 0 : 1;

  final request = await showDialog<MatchRetireRequest>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setLocal) {
        final reason = controller.text.trim();
        return AlertDialog(
          title: const Text('Retire this match?'),
          scrollable: true,
          icon: const Icon(Icons.flag_outlined, color: SportikaColors.danger),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('RETIREMENT', style: SportikaType.label),
              const SizedBox(height: 8),
              Text(
                'Recorded so far: $partial. The games and the winner of a '
                'retirement are read from the rally log, so this is the score '
                'the result will carry.',
                style: SportikaType.caption,
              ),
              const SizedBox(height: SportikaSpacing.sm),
              const Text('WHO TAKES THE RESULT', style: SportikaType.label),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var side = 0; side < 2; side++)
                    ChoiceChip(
                      label: Text(
                        match.sideNames.length > side
                            ? match.sideNames[side]
                            : 'Side ${side + 1}',
                      ),
                      selected: winner == side,
                      onSelected: (_) => setLocal(() => winner = side),
                    ),
                ],
              ),
              const SizedBox(height: SportikaSpacing.sm),
              TextField(
                controller: controller,
                maxLength: 200,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(
                  labelText: 'Reason (3 to 200 characters)',
                  hintText: 'Injury, walk-off, no players left',
                  isDense: true,
                ),
              ),
              const Text(
                'The organizer and the scorer are told, and the reason is kept '
                'in the match history.',
                style: SportikaType.caption,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Keep scoring'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SportikaColors.danger,
              ),
              onPressed: reason.length < 3
                  ? null
                  : () => Navigator.pop(
                      dialog,
                      MatchRetireRequest(winnerIndex: winner, reason: reason),
                    ),
              child: const Text('Retire & award'),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return request;
}
