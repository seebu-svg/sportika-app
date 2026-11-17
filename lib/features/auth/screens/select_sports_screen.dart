import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 11 · Select preferred sports. A photographic grid, multi-select, with the
/// count always visible so the user knows what comes next.
class SelectSportsScreen extends StatelessWidget {
  const SelectSportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final count = flow.sports.length;
    final allSelected = count == Sport.values.length;

    return AuthPage(
      showBack: true,
      onBack: flow.back,
      sport: Sport.padel,
      photoAlignment: const Alignment(0, -.45),
      stepLabel: 'PROFILE SETUP',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'CONTINUE',
            onPressed: count == 0 ? null : flow.submitSports,
          ),
          const SizedBox(height: 8),
          Text(
            count == 0
                ? 'Pick at least one sport to continue.'
                : '$count ready. Next: your playing level.',
            style: TextStyle(
              fontSize: 10.5,
              color: count == 0
                  ? SportikaColors.textDim
                  : SportikaColors.textMuted,
            ),
          ),
        ],
      ),
      children: [
        const SizedBox(height: 8),
        const AuthStepRail(
          current: 2,
          labels: ['Basics', 'Photo', 'Sports', 'Play', 'Review'],
        ),
        const SizedBox(height: 26),
        const AuthEyebrow('PREFERRED SPORTS'),
        const SizedBox(height: 14),
        const AuthHeadline('WHAT DO YOU', accent: 'PLAY?', size: 42),
        const SizedBox(height: 14),
        const AuthLead(
          'Choose every sport you want on your profile. You can change this '
          'whenever your game does.',
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              '$count OF ${Sport.values.length} SELECTED',
              style: authDisplay(
                10.5,
                color: count == 0
                    ? SportikaColors.textDim
                    : SportikaColors.mint,
                letterSpacing: 1.5,
              ),
            ),
            AuthLink(
              allSelected ? 'Clear all' : 'Select all',
              tone: SportikaColors.textMuted,
              onTap: flow.selectAllSports,
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .92,
          children: [
            for (final sport in Sport.values)
              _SportTile(
                sport: sport,
                selected: flow.sports.contains(sport),
                onTap: () => flow.toggleSport(sport),
              ),
          ],
        ),
        if (flow.inlineField == 'sports') ...[
          const SizedBox(height: 10),
          Text(
            flow.inlineError ?? '',
            style: const TextStyle(fontSize: 11, color: SportikaColors.danger),
          ),
        ],
        const SizedBox(height: 16),
        const AuthMicro(
          'One account to play, follow sports and create your own events.',
          icon: Icons.emoji_events_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SportTile extends StatelessWidget {
  const _SportTile({
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  final Sport sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = sportColor(sport);
    return Semantics(
      button: true,
      selected: selected,
      label: sport.label,
      child: Material(
        color: SportikaColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? tone : SportikaColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AuthPhoto(sport: sport, alignment: Alignment.center),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x59061426),
                        Color(0x33061426),
                        Color(0xE6061426),
                      ],
                      stops: [0, .4, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 20,
                            width: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? tone : const Color(0x66061426),
                              border: Border.all(
                                color: selected
                                    ? tone
                                    : Colors.white.withValues(alpha: .35),
                              ),
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check,
                                    size: 12,
                                    color: SportikaColors.deepest,
                                  )
                                : null,
                          ),
                          const Spacer(),
                          Icon(
                            sportGlyph(sport),
                            size: 16,
                            color: Colors.white.withValues(alpha: .72),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        sport.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: authDisplay(20, height: 1, letterSpacing: .2),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        selected ? 'ON YOUR PROFILE' : 'TAP TO ADD',
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: selected ? tone : SportikaColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
