import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';

/// Brand tint per sport, used consistently across cards, chips and charts.
Color sportColor(Sport sport) => switch (sport) {
  Sport.cricket => SportikaColors.cricket,
  Sport.padel => SportikaColors.padel,
  Sport.futsal => SportikaColors.futsal,
  Sport.badminton => SportikaColors.badminton,
};

String timeLabel(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = that.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

String dateShort(DateTime d) => '${dayLabel(d)} · ${timeLabel(d)}';

String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return dayLabel(d);
}

/// Small sport label with its brand tint.
class SportTag extends StatelessWidget {
  const SportTag(this.sport, {super.key, this.compact = false});
  final Sport sport;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = sportColor(sport);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.38)),
      ),
      child: Text(
        sport.label.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

/// Neutral pill used for entry, fixture and tournament states.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SportikaColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: c,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

Color statusColor(String statusKey) => switch (statusKey) {
  'live' => SportikaColors.mint,
  'submitted' => SportikaColors.gold,
  'published' => SportikaColors.blueBright,
  'open' => SportikaColors.mint,
  'inProgress' => SportikaColors.gold,
  'completed' => SportikaColors.textMuted,
  'confirmed' => SportikaColors.mint,
  'pending' => SportikaColors.gold,
  'rejected' => SportikaColors.danger,
  'withdrawn' => SportikaColors.textDim,
  _ => SportikaColors.textMuted,
};

IconData statusIcon(String statusKey) => switch (statusKey) {
  'live' => Icons.sensors,
  'submitted' => Icons.hourglass_top,
  'published' => Icons.verified,
  'confirmed' => Icons.check_circle_outline,
  'pending' => Icons.pending_outlined,
  'rejected' => Icons.cancel_outlined,
  _ => Icons.circle_outlined,
};

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.padding,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(0, 22, 0, 12),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: SportikaColors.textMuted,
            ),
          ),
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                foregroundColor: SportikaColors.blueBright,
              ),
              child: Text(
                action!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Standard bordered surface used for every card in the app.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
    this.fillColor,
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? fillColor;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: fillColor ?? SportikaColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? SportikaColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.tone = SportikaColors.blue,
    this.expand = true,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Color tone;
  final bool expand;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final foreground = tone.computeLuminance() > .4
        ? SportikaColors.deepest
        : Colors.white;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) ...[
          SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                fontSize: small ? 12.5 : 14,
                color: foreground,
              ),
            ),
          ),
        ),
      ],
    );

    return SizedBox(
      height: small ? 38 : 50,
      child: Material(
        color: onPressed == null ? tone.withValues(alpha: 0.35) : tone,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: small ? 14 : 18),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = SportikaColors.textBody,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color tone;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Material(
        color: SportikaColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: SportikaColors.border),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: tone),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
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

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.body,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 22),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, color: SportikaColors.textDim, size: 26),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SportikaColors.textBody,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SportikaColors.textDim,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.initials,
    this.color = SportikaColors.blue,
    this.size = 36,
    this.badge,
  });

  final String initials;
  final Color color;
  final double size;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: size,
            width: size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            alignment: Alignment.center,
            child: Text(
              initials.toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.36,
              ),
            ),
          ),
          if (badge != null) Positioned(right: -2, bottom: -2, child: badge!),
        ],
      ),
    );
  }
}

/// One row of the engine-provided score readout.
class ScoreLineTile extends StatelessWidget {
  const ScoreLineTile({
    super.key,
    required this.line,
    this.color = SportikaColors.text,
    this.highlight = false,
  });

  final ScoreLine line;
  final Color color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? SportikaColors.surfaceAlt
            : line.leading
            ? SportikaColors.surfaceAlt
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: line.leading
              ? SportikaColors.borderStrong
              : SportikaColors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 26,
            decoration: BoxDecoration(
              color: line.leading
                  ? color
                  : SportikaColors.textDim.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: line.muted
                        ? SportikaColors.textMuted
                        : SportikaColors.text,
                  ),
                ),
                if (line.sub != null)
                  Text(
                    line.sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SportikaColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            line.value,
            style: TextStyle(
              fontSize: 26,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: line.muted ? SportikaColors.textMuted : color,
            ),
          ),
        ],
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: SportikaColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? SportikaColors.textBody,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail sheet scaffolding so all bottom sheets look alike.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: SportikaColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: SportikaColors.text,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 14),
          child,
          if (actions != null) ...[const SizedBox(height: 18), ...actions!],
        ],
      ),
    );
  }
}

void showAppSheet(BuildContext context, Widget sheet) {
  showModalBottomSheet(
    context: context,
    backgroundColor: SportikaColors.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => sheet,
  );
}

/// Entity chip used in fixture rows ("vs", "·" separators).
class Dot extends StatelessWidget {
  const Dot({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: color ?? SportikaColors.textDim,
        shape: BoxShape.circle,
      ),
    ),
  );
}

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.count,
    this.color = SportikaColors.danger,
  });
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 17),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Shared card for an official or personal match row.
class FixtureRow extends StatelessWidget {
  const FixtureRow({
    super.key,
    required this.topLeft,
    required this.homeLabel,
    required this.awayLabel,
    required this.statusKey,
    required this.statusLabel,
    this.homeScore,
    this.awayScore,
    this.footer,
    this.onTap,
    this.accent,
  });

  final Widget topLeft;
  final String homeLabel;
  final String awayLabel;
  final String statusKey;
  final String statusLabel;
  final String? homeScore;
  final String? awayScore;
  final Widget? footer;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? statusColor(statusKey);
    return SurfaceCard(
      onTap: onTap,
      borderColor: statusKey == 'live'
          ? SportikaColors.mint.withValues(alpha: .4)
          : SportikaColors.border,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: topLeft),
              StatusPill(statusLabel, color: c, icon: statusIcon(statusKey)),
            ],
          ),
          const SizedBox(height: 10),
          _sideRow(homeLabel, homeScore),
          const SizedBox(height: 6),
          _sideRow(awayLabel, awayScore),
          if (footer != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            footer!,
          ],
        ],
      ),
    );
  }

  Widget _sideRow(String label, String? score) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SportikaColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
        if (score != null)
          Text(
            score,
            style: TextStyle(
              color: accent ?? SportikaColors.text,
              fontWeight: FontWeight.w800,
              fontSize: 23,
              fontFamily: 'Barlow Condensed',
              letterSpacing: 0.3,
            ),
          ),
      ],
    );
  }
}

/// Consistent app bar with an optional trailing action.
PreferredSizeWidget sportikaAppBar(
  String title, {
  List<Widget>? actions,
  Widget? leading,
  String? subtitle,
}) {
  return AppBar(
    leading: leading,
    titleSpacing: leading == null ? 20 : 4,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        if (subtitle != null)
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w600,
              color: SportikaColors.textMuted,
            ),
          ),
      ],
    ),
    actions: actions,
  );
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Sportika brand lockup, used on the splash and sign-in screens.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56, this.showWordmark = false});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: SportikaColors.mint,
        borderRadius: BorderRadius.circular(size * .22),
      ),
      alignment: Alignment.center,
      child: Text(
        'S',
        style: TextStyle(
          color: SportikaColors.deepest,
          fontStyle: FontStyle.italic,
          fontSize: size * 0.64,
          fontWeight: FontWeight.w900,
          height: 1,
          letterSpacing: -1,
        ),
      ),
    );

    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.28),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SPORTIKA',
                  style: TextStyle(
                    fontSize: size * 0.34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: size * 0.06,
                    color: SportikaColors.text,
                    height: 1.1,
                  ),
                ),
                Text(
                  'THE GAME CONNECTS US.',
                  style: TextStyle(
                    fontSize: size * 0.12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: size * 0.032,
                    color: SportikaColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fixed header used by the five root tabs so they share one rhythm.
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 8),
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BrandMark(size: 24),
                const SizedBox(width: 8),
                const Text(
                  'SPORTIKA',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                ...actions,
              ],
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Barlow Condensed',
                fontSize: 32,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: SportikaColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal sport filter shared by Home, Match Center and Tournaments.
/// Delegates to [FilterChipRow] so every sport filter in the app has the same
/// 48 dp targets and scroll behaviour.
class SportFilterBar extends StatelessWidget {
  const SportFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Sport? selected;
  final ValueChanged<Sport?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SportFilterRow(
      selected: selected,
      onChanged: onChanged,
      padding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}

/// Inline note used to explain rules, privacy or review states.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.tone = SportikaColors.blueBright,
  });

  final String text;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: SportikaColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact metric used on dashboards and tournament summaries.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.tone = SportikaColors.text,
  });

  final String value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: SportikaColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable row used inside bottom sheets.
class SheetOption extends StatelessWidget {
  const SheetOption({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = SportikaColors.blueBright,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: SportikaColors.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: SportikaColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: SportikaColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              size: 17,
              color: error ? SportikaColors.danger : SportikaColors.mint,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Account initials avatar from an [Account], with role badges.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.size = 36});
  final Account account;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PlayerAvatar(
      initials: account.initials,
      size: size,
      color: account.has(UserRole.organizer)
          ? SportikaColors.mint
          : SportikaColors.blue,
    );
  }
}
