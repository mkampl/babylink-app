import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

/// One tile type for both discovered BLE devices and WiFi networks: a soft
/// tinted icon square, title + subtitle, and trailing signal bars / lock /
/// chevron / check.
class EntityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool locked;
  final int? signal; // 0..4 bars, null = hide

  const EntityTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.locked = false,
    this.signal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.08) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.rMd,
        side: BorderSide(
          color: selected ? cs.primary : Theme.of(context).dividerColor,
          width: selected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(icon, color: cs.primary, size: 24),
              ),
              Gap.wMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              Gap.wSm,
              if (locked) Icon(Icons.lock_rounded, size: 16, color: t.labelMedium!.color),
              if (signal != null) ...[const SizedBox(width: 6), _Signal(signal!)],
              if (trailing != null)
                ...[const SizedBox(width: 6), trailing!]
              else if (onTap != null && !selected)
                Icon(Icons.chevron_right_rounded, color: t.labelMedium!.color),
              if (selected) Icon(Icons.check_circle_rounded, color: cs.primary, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// 4 WiFi-style bars, filled up to [level] (0..4).
class _Signal extends StatelessWidget {
  final int level;
  const _Signal(this.level);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.signalLevel(level),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          final on = i < level;
          return Container(
            width: 4,
            height: 7.0 + i * 4,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: on ? cs.primary : cs.primary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
