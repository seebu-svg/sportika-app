import 'package:sportika/shared/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/onboarding.dart';
import 'package:sportika/shared/models/profile_setup.dart';
import 'package:sportika/shared/widgets/editorial.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// Sport-specific playing preferences, reused during setup and later edits.
class ProfileSportPreferences extends StatelessWidget {
  const ProfileSportPreferences({
    super.key,
    required this.sport,
    required this.level,
    required this.position,
    required this.onLevelChanged,
    required this.onPositionChanged,
    this.refined = false,
  });

  final Sport sport;
  final bool refined;
  final PlayingLevel level;
  final String? position;
  final ValueChanged<PlayingLevel> onLevelChanged;
  final ValueChanged<String?> onPositionChanged;

  @override
  Widget build(BuildContext context) {
    final tone = refined ? SportikaColors.mint : sportColor(sport);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: refined
            ? Colors.transparent
            : SportikaColors.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(16),
        border: refined ? null : Border.all(color: SportikaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 30,
                width: 30,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: tone.withValues(alpha: .35)),
                ),
                child: Icon(sportGlyph(sport), size: 16, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      refined ? sport.label : sport.label.toUpperCase(),
                      style: authDisplay(17, height: 1.05, letterSpacing: .2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      level.blurb,
                      style: const TextStyle(
                        fontSize: 10,
                        color: SportikaColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                refined ? level.label : level.label.toUpperCase(),
                style: TextStyle(
                  fontSize: refined ? 11 : 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: refined ? 0 : 1.1,
                  color: tone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in PlayingLevel.values)
                AuthChoicePill(
                  label: option.label,
                  dense: true,
                  tone: tone,
                  selected: level == option,
                  onTap: () => onLevelChanged(option),
                ),
            ],
          ),
          if (playingPositionsFor(sport).isNotEmpty) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('${sport.key}-$position'),
              style: refined
                  ? const TextStyle(fontSize: 15, color: SportikaColors.text)
                  : null,
              initialValue: playingPositionsFor(sport).contains(position)
                  ? position
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: sport == Sport.padel
                    ? 'Preferred court side (optional)'
                    : 'Preferred position (optional)',
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('No preference'),
                ),
                for (final value in playingPositionsFor(sport))
                  DropdownMenuItem(value: value, child: Text(value)),
              ],
              onChanged: onPositionChanged,
            ),
          ],
        ],
      ),
    );
  }
}
