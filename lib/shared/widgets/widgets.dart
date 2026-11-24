import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/models/models.dart';
import 'package:sportika/features/personal_games/scoring/engine.dart';
import 'package:sportika/shared/widgets/avatar_photo.dart';
import 'package:sportika/shared/widgets/avatar_presets.dart';
import 'package:sportika/shared/widgets/default_avatar.dart';
import 'package:sportika/shared/widgets/filter_chip_row.dart';
import 'package:sportika/shared/widgets/surfaces.dart';

/// Brand tint per sport, used consistently across cards, chips and charts.
Color sportColor(Sport sport) => SportIdentities.of(sport).tone;

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
        borderRadius: BorderRadius.circular(SportikaRadius.pill),
        border: Border.all(color: c.withValues(alpha: 0.38)),
      ),
      child: Text(
        sport.label.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: compact ? 9 : 10,
          fontWeight: SportikaFontWeight.extraBold,
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
        borderRadius: BorderRadius.circular(SportikaRadius.tag),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c,
                fontSize: 9.5,
                fontWeight: SportikaFontWeight.extraBold,
                letterSpacing: 0.8,
              ),
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
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: SportikaFontWeight.extraBold,
                letterSpacing: 1.5,
                color: SportikaColors.textMuted,
              ),
            ),
          ),
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
                  fontWeight: SportikaFontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Standard surface used for every card in the app.
///
/// [style] defaults to the solid [SportikaSurfaceStyle.standard] card so lists
/// and forms stay flat; important widgets opt into `elevated` and brand moments
/// opt into `signature`.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
    this.fillColor,
    this.margin,
    this.style = SportikaSurfaceStyle.standard,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? fillColor;
  final EdgeInsets? margin;
  final SportikaSurfaceStyle style;

  @override
  Widget build(BuildContext context) => SportikaSurface(
    style: style,
    padding: padding,
    margin: margin,
    onTap: onTap,
    fillColor: fillColor,
    borderColor: borderColor,
    child: child,
  );
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
    final metallic = tone == SportikaColors.mint;
    final enabled = onPressed != null;
    final foreground = tone.computeLuminance() > .4
        ? SportikaColors.onMint
        : SportikaColors.onAccent;
    final gradient = metallic
        ? SportikaGradients.metallicMint
        : SportikaGradients.accentFill(tone);
    final glow = metallic
        ? SportikaShadows.glow(SportikaColors.mint, strength: .7)
        : SportikaShadows.glow(tone, strength: .8);
    final borderRadius = BorderRadius.circular(SportikaRadius.md);
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
                fontWeight: SportikaFontWeight.extraBold,
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
      child: SportikaPressable(
        enabled: enabled,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: enabled ? glow : null,
          ),
          child: Material(
            color: enabled ? tone : tone.withValues(alpha: 0.35),
            borderRadius: borderRadius,
            child: Ink(
              decoration: enabled
                  ? BoxDecoration(
                      gradient: gradient,
                      borderRadius: borderRadius,
                    )
                  : null,
              child: InkWell(
                onTap: onPressed,
                borderRadius: borderRadius,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: small ? 14 : 18),
                  child: Center(child: child),
                ),
              ),
            ),
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
    final theme = context.sportika;
    final borderRadius = BorderRadius.circular(SportikaRadius.control);
    return SizedBox(
      height: 38,
      child: SportikaPressable(
        enabled: onPressed != null,
        child: Material(
          color: theme.surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: theme.border),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: borderRadius,
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
                  // Labels are allowed to shrink rather than overflow: a long
                  // translation, a wide fallback font or textScale 1.3 must not
                  // push this row past the space it was given.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: tone,
                          fontWeight: SportikaFontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: SportikaSpacing.lg,
          horizontal: SportikaSpacing.md,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: sportikaMaxContentWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    color: SportikaColors.textMuted,
                    size: SportikaSpacing.xl,
                  ),
                ),
                const SizedBox(height: SportikaSpacing.sm),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: SportikaType.bodyStrong,
                  ),
                ),
                if (body != null && body!.trim().isNotEmpty) ...[
                  const SizedBox(height: SportikaSpacing.xs),
                  Text(
                    body!,
                    textAlign: TextAlign.center,
                    style: SportikaType.body,
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: SportikaSpacing.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: kMinInteractiveDimension,
                    ),
                    child: action!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A player's round identity tile: the imported picture when there is one, the
/// initials/preset avatar otherwise, and the branded default portrait when the
/// slot has neither.
///
/// The default portrait never replaces real initials: the colour preset a
/// member picks at setup keeps identifying them until a photo is added.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.initials,
    this.color = SportikaColors.blue,
    this.size = 36,
    this.badge,
    this.photoPath,
    this.photoUrl,
    this.gradient,
    this.ink,
    this.ring,
    this.figure,
  });

  final String initials;
  final Color color;
  final double size;
  final Widget? badge;

  /// Reference handed out by the profile photo store. Null, or anything that did
  /// not come from the store, shows the drawn face instead.
  final String? photoPath;

  /// Uploaded copy of the same picture, used when this device has no local file
  /// (a fresh install, or a picture changed on another device).
  final String? photoUrl;

  /// The gradient the player chose at setup. When null the flat [color] style is
  /// used, which is what team and sport faces keep.
  final List<Color>? gradient;

  /// Initials colour that belongs to [gradient].
  final Color? ink;

  /// Border colour. Defaults to [color], so an account can keep its role tint as
  /// the ring while the face shows the gradient the player chose.
  final Color? ring;

  /// The default portrait drawn when this member has no picture and no usable
  /// initials. Null keeps the neutral silhouette; teams and sport monograms
  /// never reach it because their initials always carry identity.
  final DefaultAvatarFigure? figure;

  @override
  Widget build(BuildContext context) {
    final palette = gradient;
    final hasPhoto = hasAvatarPhoto(photoPath: photoPath, photoUrl: photoUrl);
    // Initials stay the identity the player chose during setup; the default
    // portrait only takes over when there are no letters to draw.
    final hasInitials = hasAvatarInitials(initials);
    final defaultFigure = hasInitials
        ? null
        : (figure ?? DefaultAvatarFigure.neutral);

    final initialsFace = Text(
      initials.toUpperCase(),
      style: TextStyle(
        color: palette == null ? color : (ink ?? SportikaColors.onAccent),
        fontWeight: SportikaFontWeight.extraBold,
        fontSize: size * 0.36,
      ),
    );
    final photoFallback = hasInitials
        ? initialsFace
        : BrandedDefaultAvatar(
            size: size,
            figure: defaultFigure ?? DefaultAvatarFigure.neutral,
            ring: false,
          );

    // With nothing but a default portrait to show, the disc paints its own
    // brand ring; keeping the preset gradient behind it would show through as
    // the very gradient the default avatar replaces.
    final disc = !hasPhoto && defaultFigure != null
        ? BrandedDefaultAvatar(size: size, figure: defaultFigure)
        : Container(
            height: size,
            width: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette == null ? color.withValues(alpha: 0.18) : null,
              gradient: palette == null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette,
                    ),
              shape: BoxShape.circle,
              border: Border.all(
                color: (ring ?? color).withValues(alpha: 0.45),
              ),
            ),
            alignment: Alignment.center,
            child: avatarFace(
              photoPath: photoPath,
              photoUrl: photoUrl,
              size: size,
              fallback: photoFallback,
            ),
          );

    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          disc,
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
            : SportikaColors.transparent,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
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
              borderRadius: BorderRadius.circular(SportikaRadius.xxs),
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
                    fontWeight: SportikaFontWeight.bold,
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
              fontWeight: SportikaFontWeight.extraBold,
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
                fontWeight: SportikaFontWeight.bold,
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
                borderRadius: BorderRadius.circular(SportikaRadius.xxs),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: SportikaFontWeight.extraBold,
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
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SportikaRadius.xl),
      ),
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
        borderRadius: BorderRadius.circular(SportikaRadius.badge),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: SportikaColors.onAccent,
          fontSize: 10,
          fontWeight: SportikaFontWeight.extraBold,
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
    this.scoreboard,
  });

  final Widget? scoreboard;
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
          if (scoreboard != null)
            scoreboard!
          else ...[
            _sideRow(homeLabel, homeScore),
            const SizedBox(height: 6),
            _sideRow(awayLabel, awayScore),
          ],
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
              fontWeight: SportikaFontWeight.bold,
              fontSize: 13.5,
            ),
          ),
        ),
        if (score != null)
          Text(
            score,
            style: TextStyle(
              color: accent ?? SportikaColors.text,
              fontWeight: SportikaFontWeight.extraBold,
              fontSize: 23,
              fontFamily: SportikaType.displayFamily,
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
              fontWeight: SportikaFontWeight.semibold,
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
    final mark = Image.asset(
      'assets/branding/brand-mark.png',
      height: size,
      width: size,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Sportika logo',
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
                    fontWeight: SportikaFontWeight.black,
                    letterSpacing: size * 0.06,
                    color: SportikaColors.text,
                    height: 1.1,
                  ),
                ),
                Text(
                  'THE GAME CONNECTS US.',
                  style: TextStyle(
                    fontSize: size * 0.12,
                    fontWeight: SportikaFontWeight.bold,
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
                    fontWeight: SportikaFontWeight.black,
                  ),
                ),
                const Spacer(),
                ...actions,
              ],
            ),
            const SizedBox(height: 20),
            Text(title, style: SportikaType.hero),
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
        borderRadius: BorderRadius.circular(SportikaRadius.md),
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
        borderRadius: BorderRadius.circular(SportikaRadius.md),
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
              fontWeight: SportikaFontWeight.extraBold,
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
              fontWeight: SportikaFontWeight.bold,
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
      color: SportikaColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SportikaRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(SportikaRadius.sm),
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
                        fontWeight: SportikaFontWeight.bold,
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

/// Account avatar: the imported picture when the player set one, otherwise the
/// branded default portrait that matches their stated gender. Role tints the
/// ring so an organizer still reads as one at a glance.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.account,
    this.size = SportikaSpacing.xxl,
    this.ring,
  });
  final Account account;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final preset = avatarOptionFor(account.avatar);
    return PlayerAvatar(
      initials: account.initials,
      figure: defaultAvatarFigureFor(account.gender),
      size: size,
      photoPath: account.photoPath,
      photoUrl: account.photoUrl,
      gradient: preset.colors,
      ink: preset.ink,
      ring: ring,
      color: SportikaColors.blue,
    );
  }
}

/// Row or Column child that scales its content down instead of overflowing.
///
/// [Row] lays out every non-flexible child at its intrinsic width before the
/// flexible ones get a say, so a trailing pill, button or icon pair that is
/// wider than the space left by its [Expanded] sibling overflows on narrow
/// phones and at the 1.3 text ceiling. Making the child flexible gives it only
/// the space that is actually left, and [FittedBox] with [BoxFit.scaleDown]
/// shrinks it in place rather than clipping or ellipsising the copy.
///
/// With room to spare the child keeps its natural size, so the layout is
/// unchanged; [expand] claims the leftover space the way [Expanded] does.
class FittedFlex extends StatelessWidget {
  const FittedFlex({
    super.key,
    required this.child,
    this.expand = false,
    this.flex = 1,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final bool expand;
  final int flex;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final Widget fitted = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: child,
    );
    return expand
        ? Expanded(flex: flex, child: fitted)
        : Flexible(flex: flex, child: fitted);
  }
}

/// Trailing cluster of a label-plus-action row: pinned to the right edge and
/// scaled down instead of overflowing.
///
/// A [Row] hands its non-flexible children an unbounded main axis, so a pill,
/// button or icon pair sitting next to an [Expanded] label can only overflow
/// once the copy grows (narrow column, 1.3 text ceiling). [TrailingRow] keeps
/// the usual "label left, action right" rhythm: [leading] is laid out first
/// and may contain flex children such as [Expanded], while [trailing] is laid
/// out as one cluster capped to [maxFraction] of the row's own width and
/// shrunk in place when it still needs more than that.
///
/// Prefer it over making the cluster [Flexible]: a flexible sibling splits the
/// leftover space by flex factor, which pulls the cluster away from the right
/// edge and squeezes the label even when there is room for both.
class TrailingRow extends StatelessWidget {
  const TrailingRow({
    super.key,
    required this.leading,
    this.trailing = const <Widget>[],
    this.maxFraction = 0.55,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.textDirection,
  });

  /// Everything that renders before the cluster, flex children included.
  final List<Widget> leading;

  /// The right-hand cluster; laid out at its natural size, then scaled down.
  final List<Widget> trailing;
  final double maxFraction;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Unbounded main axis means there is nothing to cap against, so the
        // cluster simply keeps its natural size.
        final double cap = constraints.maxWidth.isFinite
            ? constraints.maxWidth * maxFraction
            : double.infinity;
        return Row(
          mainAxisAlignment: mainAxisAlignment,
          crossAxisAlignment: crossAxisAlignment,
          textDirection: textDirection,
          children: [
            ...leading,
            if (trailing.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cap),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: trailing,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
