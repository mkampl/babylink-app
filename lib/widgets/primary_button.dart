import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Full-width, large, rounded primary CTA with optional loading + leading icon
/// and built-in light haptic. The backbone action on every wizard screen.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const PrimaryButton(this.label,
      {super.key, this.onPressed, this.loading = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return FilledButton(
      onPressed: enabled
          ? () {
              HapticFeedback.lightImpact();
              onPressed!();
            }
          : null,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 22), Gap.wSm],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
  }
}
