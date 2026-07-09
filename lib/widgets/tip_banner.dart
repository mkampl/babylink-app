import 'package:flutter/material.dart';

import '../theme.dart';

enum TipKind { info, warning, success, danger }

/// Soft, rounded, tinted-by-kind callout. Used for guidance ("press the button
/// on your device"), errors, and success notes.
class TipBanner extends StatelessWidget {
  final String message;
  final TipKind kind;
  final IconData? icon;

  const TipBanner(this.message, {super.key, this.kind = TipKind.info, this.icon});

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final (bg, fg, defIcon) = switch (kind) {
      TipKind.info => (s.infoBg, s.info, Icons.lightbulb_outline_rounded),
      TipKind.warning => (s.warningBg, s.warning, Icons.info_outline_rounded),
      TipKind.success => (s.successBg, s.success, Icons.check_circle_outline_rounded),
      TipKind.danger => (s.dangerBg, s.danger, Icons.error_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Radii.rMd,
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defIcon, color: fg, size: 22),
          Gap.wMd,
          Expanded(
            child: Text(message,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: fg, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
