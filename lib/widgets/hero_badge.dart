import 'package:flutter/material.dart';

/// An emoji or Icon in a large tinted circle, with an optional gentle breathing
/// pulse for "in progress" states. No image assets — renders in both themes.
class HeroBadge extends StatefulWidget {
  final String? emoji;
  final IconData? icon;
  final Color? tint;
  final bool pulse;
  final double size;

  const HeroBadge({
    super.key,
    this.emoji,
    this.icon,
    this.tint,
    this.pulse = false,
    this.size = 132,
  });

  @override
  State<HeroBadge> createState() => _HeroBadgeState();
}

class _HeroBadgeState extends State<HeroBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant HeroBadge old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulse && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint ?? Theme.of(context).colorScheme.primary;
    final noMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final content = widget.emoji != null
        ? Text(widget.emoji!, style: TextStyle(fontSize: widget.size * 0.42))
        : Icon(widget.icon, size: widget.size * 0.44, color: tint);

    return Center(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final animate = widget.pulse && !noMotion;
          final s = animate ? 1 + _c.value * 0.05 : 1.0;
          final glow = animate ? 0.10 + _c.value * 0.12 : 0.14;
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tint.withValues(alpha: glow)),
            child: Transform.scale(scale: s, child: Center(child: content)),
          );
        },
      ),
    );
  }
}
