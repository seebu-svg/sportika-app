import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/widgets/fixture_tile.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/live/screens/notifications_screen.dart';

/// Match Center (spec §5): live, upcoming and completed official matches, with
/// the published result on every finished card.
class MatchCenterTab extends StatefulWidget {
  const MatchCenterTab({super.key});

  @override
  State<MatchCenterTab> createState() => _MatchCenterTabState();
}

class _MatchCenterTabState extends State<MatchCenterTab> {
  int _view = 0;
  Sport? _sport;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final live = _filter(state.liveFixtures, _sport);
    final upcoming = _filter(
      state.scheduledFixtures
          .where((f) => f.status != FixtureStatus.live)
          .toList(),
      _sport,
    );
    final completed = _filter(state.completedFixtures, _sport);

    final items = switch (_view) {
      0 => live,
      1 => upcoming,
      _ => completed,
    };

    return Column(
      children: [
        TabHeader(
          title: 'Match Center',
          subtitle:
              '${live.length} live · ${upcoming.length} upcoming · '
              '${completed.length} results',
          actions: const [NotificationBell(), SizedBox(width: 16)],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: _ViewSwitcher(
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            counts: [live.length, upcoming.length, completed.length],
          ),
        ),
        SportFilterBar(
          selected: _sport,
          onChanged: (s) => setState(() => _sport = s),
        ),
        Expanded(
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: EmptyState(
                    title: switch (_view) {
                      0 => 'No matches live',
                      1 => 'Nothing upcoming',
                      _ => 'No results in this filter',
                    },
                    body: _view == 0
                        ? 'Live scorecards show up here the moment a scorer records '
                              'the first entry.'
                        : 'Try another sport, or check back after the next round.',
                    icon: _view == 0 ? Icons.sensors_off : Icons.event_busy,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      officialFixtureTile(context, items[i]),
                ),
        ),
      ],
    );
  }

  List<Fixture> _filter(List<Fixture> source, Sport? sport) {
    if (sport == null) return source;
    return source
        .where((f) => context.read<AppState>().tournamentOf(f)?.sport == sport)
        .toList();
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({
    required this.value,
    required this.onChanged,
    required this.counts,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final List<int> counts;

  static const _labels = ['Live', 'Upcoming', 'Results'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SportikaColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: value == i
                        ? SportikaColors.surfaceAlt
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: value == i
                          ? SportikaColors.borderStrong
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _labels[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: value == i
                              ? SportikaColors.text
                              : SportikaColors.textMuted,
                        ),
                      ),
                      if (counts[i] > 0) ...[
                        const SizedBox(width: 5),
                        Text(
                          '${counts[i]}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: value == i
                                ? SportikaColors.blueBright
                                : SportikaColors.textDim,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
