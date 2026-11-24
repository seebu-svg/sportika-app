import 'package:flutter/material.dart';

import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/match.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Newest-first event history. Withdrawn entries remain visible for audit.
class MatchEventTimeline extends StatefulWidget {
  const MatchEventTimeline({
    super.key,
    required this.match,
    this.limit = 12,
    this.emptyMessage = 'No scoring entries yet.',
    this.showFilters = false,
    this.paginated = false,
  });
  final SportMatch match;
  final int limit;
  final String emptyMessage;
  final bool showFilters;
  final bool paginated;

  @override
  State<MatchEventTimeline> createState() => _MatchEventTimelineState();
}

class _MatchEventTimelineState extends State<MatchEventTimeline> {
  bool _keyOnly = false;
  int _visibleCount = 30;
  int _page = 0;
  late bool _oldestFirst = widget.paginated;
  static const _pageSize = 24;

  @override
  void didUpdateWidget(covariant MatchEventTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match.id != widget.match.id || !widget.showFilters) {
      _page = 0;
      _keyOnly = false;
      _visibleCount = 30;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordered = List<MatchEvent>.from(widget.match.events)
      ..sort(
        (a, b) =>
            _oldestFirst ? a.seq.compareTo(b.seq) : b.seq.compareTo(a.seq),
      );
    final keyCount = ordered.where(_isKeyMoment).length;
    final filtered = _keyOnly ? ordered.where(_isKeyMoment).toList() : ordered;
    final cap = widget.limit < 0 ? 0 : widget.limit;
    final effectiveLimit = widget.showFilters && cap > _visibleCount
        ? _visibleCount
        : cap;
    final pageCount = (filtered.length / _pageSize).ceil();
    final page = _page.clamp(0, pageCount > 0 ? pageCount - 1 : 0);
    final shown = widget.paginated
        ? filtered.skip(page * _pageSize).take(_pageSize).toList()
        : filtered.take(effectiveLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showFilters) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All entries'),
                selected: !_keyOnly,
                onSelected: (_) => setState(() {
                  _keyOnly = false;
                  _page = 0;
                }),
              ),
              ChoiceChip(
                label: Text('Key moments ($keyCount)'),
                selected: _keyOnly,
                onSelected: (_) => setState(() {
                  _keyOnly = true;
                  _page = 0;
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${ordered.length} recorded · ${_oldestFirst ? 'oldest' : 'newest'} first',
            style: SportikaType.caption,
          ),
          if (widget.paginated)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _oldestFirst = !_oldestFirst;
                  _page = 0;
                }),
                icon: const Icon(Icons.swap_vert),
                label: Text(
                  _oldestFirst ? 'Show newest first' : 'Show oldest first',
                ),
              ),
            ),
          if (widget.match.corrections.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'The official result was corrected. This log preserves the recorded events.',
              style: SportikaType.caption,
            ),
          ],
          const SizedBox(height: 16),
        ],
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 22,
                  color: SportikaColors.textDim,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _keyOnly
                        ? 'No key moments recorded yet. See All entries for the full log.'
                        : widget.emptyMessage,
                    style: SportikaType.caption,
                  ),
                ),
              ],
            ),
          ),
        for (var i = 0; i < shown.length; i++) ...[
          if (widget.showFilters &&
              (i == 0 ||
                  _eventGroup(shown[i], widget.match) !=
                      _eventGroup(shown[i - 1], widget.match)))
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Text(
                _eventGroup(shown[i], widget.match).toUpperCase(),
                style: SportikaType.micro,
              ),
            ),
          _TimelineRow(
            event: shown[i],
            match: widget.match,
            last: i == shown.length - 1,
          ),
        ],
        if (!widget.paginated && filtered.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${filtered.length - shown.length} earlier ${_keyOnly ? 'key moments' : 'entries'} kept in the log',
              style: SportikaType.caption,
            ),
          ),
        if (!widget.paginated &&
            filtered.length > shown.length &&
            shown.length < cap)
          TextButton.icon(
            onPressed: () => setState(() => _visibleCount += 30),
            icon: const Icon(Icons.expand_more),
            label: const Text('Show earlier entries'),
          ),
        if (widget.paginated && pageCount > 1) ...[
          const SizedBox(height: SportikaSpacing.md),
          Text(
            'Page ${page + 1} of $pageCount · ${filtered.length} entries',
            style: SportikaType.caption,
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: page > 0
                    ? () => setState(() => _page = page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
              TextButton.icon(
                onPressed: page + 1 < pageCount
                    ? () => setState(() => _page = page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

bool _isKeyMoment(MatchEvent event) =>
    !event.voided &&
    (const {'goal', 'card', 'penalty', 'innings_end'}.contains(event.kind) ||
        (event.kind == 'ball' &&
            (event.data['wicket'] == true ||
                event.data['runs'] == 4 ||
                event.data['runs'] == 6)) ||
        (event.kind == 'clock' &&
            const {'end_half', 'end_match'}.contains(event.data['action'])));

String _eventGroup(MatchEvent event, SportMatch match) {
  if (match.sport == Sport.futsal && event.data['half'] is int) {
    final half = event.data['half'] as int;
    if (half >= 0) return 'Period ${half + 1}';
  }
  if (match.sport == Sport.cricket &&
      event.kind == 'ball' &&
      event.side != null &&
      event.side! >= 0 &&
      event.side! < match.sideLabels.length) {
    return 'Batting · ${match.sideLabels[event.side!]}';
  }
  return 'Match events';
}

IconData _eventIcon(MatchEvent event) => switch (event.kind) {
  'goal' => Icons.sports_soccer_rounded,
  'ball' =>
    event.data['wicket'] == true
        ? Icons.sports_cricket_rounded
        : Icons.sports_baseball_outlined,
  'point' || 'rally' => Icons.sports_tennis_rounded,
  'card' => Icons.style_rounded,
  'foul' => Icons.sports_rounded,
  'substitution' => Icons.swap_horiz_rounded,
  'penalty' => Icons.adjust_rounded,
  'clock' => Icons.timer_outlined,
  'innings_end' => Icons.flag_outlined,
  'lineup' => Icons.groups_outlined,
  _ => Icons.receipt_long_outlined,
};

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.match,
    required this.last,
  });
  final MatchEvent event;
  final SportMatch match;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final side = event.side;
    final teamTone = side == 0
        ? sportColor(match.sport)
        : side == 1
        ? SportikaColors.mint
        : SportikaColors.textMuted;
    final accent = event.voided
        ? SportikaColors.textDim
        : event.kind == 'card'
        ? event.data['colour'] == 'red'
              ? SportikaColors.danger
              : SportikaColors.gold
        : teamTone;
    final detail = _readableDetail(event, match);
    final recorded = TimeOfDay.fromDateTime(event.at.toLocal()).format(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SportikaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              event.voided ? Icons.undo_rounded : _eventIcon(event),
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: SportikaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('#${event.seq} · $recorded', style: SportikaType.caption),
                Text(
                  eventTitle(event, match),
                  style: SportikaType.bodyStrong.copyWith(
                    color: event.voided
                        ? SportikaColors.textDim
                        : SportikaColors.text,
                    decoration: event.voided
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(detail, style: SportikaType.caption),
                if (event.voided)
                  const Text(
                    'Voided · excluded from score',
                    style: SportikaType.caption,
                  ),
                if (!last)
                  const Padding(
                    padding: EdgeInsets.only(top: SportikaSpacing.sm),
                    child: Divider(
                      height: 1,
                      color: SportikaColors.borderSubtle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _readableDetail(MatchEvent event, SportMatch match) {
  String? playerName(Object? id) {
    for (final player in match.participants) {
      if (player.profileId == id && player.displayName.isNotEmpty) {
        return player.displayName;
      }
    }
    return null;
  }

  final parts = <String>[];
  if (event.kind == 'substitution') {
    final incoming = playerName(event.data['inId']);
    final outgoing = playerName(event.data['outId']);
    if (incoming != null) parts.add('On: $incoming');
    if (outgoing != null) parts.add('Off: $outgoing');
  } else if (event.data['player'] == null) {
    final player = playerName(event.data['playerId']);
    if (player != null) parts.add(player);
  }
  final detail = eventDetail(event);
  if (detail.isNotEmpty) parts.add(detail);
  return parts.join(' · ');
}

/// `strike_ball` reads as "Strike ball"; a side name is appended when the
/// entry belongs to one.
String eventTitle(MatchEvent event, SportMatch match) {
  final label = event.kind == 'goal'
      ? switch (event.data['goalType']) {
          'ownGoal' => 'Own goal',
          'penalty' => 'Penalty goal',
          _ => 'Goal',
        }
      : event.kind == 'ball'
      ? switch (event.data) {
          {'wicket': true} => 'Wicket',
          {'extra': 'wide'} => 'Wide',
          {'extra': 'noball'} => 'No ball',
          {'extra': 'bye'} => 'Bye',
          {'extra': 'legbye'} => 'Leg bye',
          {'runs': 4} => 'Four',
          {'runs': 6} => 'Six',
          {'runs': 0} => 'Dot ball',
          {'runs': final num runs} => '$runs ${runs == 1 ? 'run' : 'runs'}',
          _ => 'Ball',
        }
      : event.kind == 'card'
      ? switch (event.data['colour']) {
          'red' => 'Red card',
          'yellow' => 'Yellow card',
          _ => 'Card',
        }
      : event.kind == 'clock'
      ? switch (event.data['action']) {
          'start' => 'Clock started',
          'stop' => 'Clock stopped',
          'resume' => 'Clock resumed',
          'end_half' => 'Period ended',
          'end_match' => 'Match ended',
          _ => 'Clock updated',
        }
      : event.kind == 'toss'
      ? (event.data['decision'] == 'bowl'
            ? 'Won the toss and elected to bowl'
            : 'Won the toss and elected to bat')
      : event.kind == 'innings_start'
      ? 'Innings started'
      : event.kind == 'innings_end'
      ? 'Innings closed'
      : event.kind == 'lineup'
      ? 'XI named'
      : event.kind == 'match_end'
      ? 'Match ended'
      : event.kind == 'point' || event.kind == 'rally'
      ? 'Point won'
      : humanizeEventKind(event.kind);
  final side = event.side;
  if (side == null || side < 0 || side >= match.sideNames.length) return label;
  return '$label · ${match.sideNames[side]}';
}

String humanizeEventKind(String kind) {
  if (kind.isEmpty) return 'Entry';
  final spaced = kind.split('_').join(' ');
  final head = spaced.substring(0, 1).toUpperCase();
  return '$head${spaced.substring(1)}';
}

/// The payload in a single readable line, skipping the fields a sport's engine
/// uses only for its own bookkeeping.
String eventDetail(MatchEvent event) {
  const skip = {
    'bat',
    'bowler',
    'striker',
    'server',
    'playerId',
    'inId',
    'outId',
    'goalType',
    'action',
    'dot',
    'wicket',
    'clientId',
    'decision',
    'players',
  };
  final parts = <String>[];
  for (final entry in event.data.entries) {
    final key = entry.key;
    final value = entry.value;
    if (parts.length >= 3) break;
    if (skip.contains(key) ||
        key.endsWith('Id') ||
        value == null ||
        value is Map ||
        value is List ||
        value is bool) {
      continue;
    }
    if (event.kind == 'ball' && (key == 'runs' || key == 'extra')) continue;
    parts.add(
      key == 'half' && value is int
          ? 'Period ${value + 1}'
          : key == 'player'
          ? '$value'
          : '${humanizeEventKind(key)}: $value',
    );
  }
  return parts.join(' · ');
}
