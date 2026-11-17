import 'package:flutter/material.dart';
import 'package:sportika/shared/models/profile_module.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';
import 'package:sportika/shared/widgets/widgets.dart';

class MatchSheetIntro extends StatelessWidget {
  const MatchSheetIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: SportikaSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: SportikaColors.blueBright),
        const SizedBox(width: SportikaSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SportikaType.headline),
              const SizedBox(height: SportikaSpacing.xs),
              Text(body, style: SportikaType.body),
            ],
          ),
        ),
      ],
    ),
  );
}

class MatchMemberSearchTile extends StatelessWidget {
  const MatchMemberSearchTile({
    super.key,
    required this.player,
    this.selected = false,
    this.note,
    this.onTap,
    this.inviting = false,
  });
  final ProfileSummary player;
  final bool selected;
  final String? note;
  final VoidCallback? onTap;
  final bool inviting;
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tone = selected
        ? SportikaColors.mint
        : enabled
        ? SportikaColors.blueBright
        : SportikaColors.textDim;
    final username = player.username.trim();
    final city = player.city.trim();

    return Semantics(
      selected: selected,
      enabled: enabled,
      button: true,
      child: Material(
        color: selected ? SportikaColors.mintSubtle : SportikaColors.surface,
        borderRadius: BorderRadius.circular(SportikaRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SportikaRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SportikaSpacing.sm,
              vertical: SportikaSpacing.md,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: SportikaColors.borderSubtle),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PlayerAvatar(
                  initials: initialsOf(player.label),
                  photoUrl: player.avatarUrl,
                  size: 48,
                  color: tone,
                ),
                const SizedBox(width: SportikaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.bodyStrong.copyWith(
                          color: enabled || selected
                              ? SportikaColors.text
                              : SportikaColors.textMuted,
                        ),
                      ),
                      if (username.isNotEmpty || city.isNotEmpty) ...[
                        const SizedBox(height: SportikaSpacing.xs),
                        if (username.isNotEmpty)
                          Text(
                            '@$username',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SportikaType.caption,
                          ),
                        if (city.isNotEmpty)
                          Text(
                            city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SportikaType.caption,
                          ),
                      ],
                      if (note != null) ...[
                        const SizedBox(height: SportikaSpacing.xs),
                        Text(
                          note!,
                          style: SportikaType.caption.copyWith(color: tone),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: SportikaSpacing.sm),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : !enabled
                      ? Icons.block_outlined
                      : inviting
                      ? Icons.person_add_alt
                      : Icons.radio_button_unchecked,
                  color: tone,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
