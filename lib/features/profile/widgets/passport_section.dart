import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/theme/typography.dart';

/// Section head used across the passport: an uppercase label, an optional
/// quiet count, and at most one action.
class PassportSection extends StatelessWidget {
  const PassportSection({
    super.key,
    required this.title,
    required this.child,
    this.detail,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(0, 22, 0, 12),
  });

  final String title;
  final Widget child;
  final String? detail;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: padding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SportikaType.label,
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SportikaType.caption.copyWith(
                          fontSize: 11,
                          color: SportikaColors.textDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                    foregroundColor: SportikaColors.blueBright,
                  ),
                  child: Text(action!, style: SportikaType.action),
                ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}
