import 'package:flutter/material.dart';

import '../theme.dart';
import 'baby_stream.dart';

/// One baby's card in the room monitor: name, live status + level meter, and
/// independent mute / volume / sensitivity — the per-baby controls the web has.
class BabyCard extends StatelessWidget {
  final BabyStream baby;
  final ValueChanged<bool> onMute;
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onSensitivity;

  const BabyCard({
    super.key,
    required this.baby,
    required this.onMute,
    required this.onVolume,
    required this.onSensitivity,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.status;
    final level = baby.effectiveMuted ? 0.0 : baby.level;

    final (statusText, statusColor) = switch (baby.health) {
      AudioHealth.stalled => ('No audio — reconnecting', s.danger),
      AudioHealth.live => baby.level > 0.5 ? ('Crying!', s.danger) : ('Listening', s.success),
      AudioHealth.quiet => ('Quiet', s.success),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                Gap.wSm,
                Expanded(
                  child: Text(baby.name, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text(statusText, style: t.labelMedium!.copyWith(color: statusColor)),
                Gap.wSm,
                IconButton(
                  onPressed: () => onMute(!baby.manualMute),
                  icon: Icon(baby.manualMute ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                  color: baby.manualMute ? s.danger : null,
                  tooltip: baby.manualMute ? 'Unmute' : 'Mute',
                ),
              ],
            ),
            Gap.hSm,
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: level.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                valueColor: AlwaysStoppedAnimation(
                  level > 0.5 ? s.danger : (level > 0.2 ? s.warning : s.success),
                ),
              ),
            ),
            Gap.hSm,
            _slider(context, Icons.volume_up_rounded, baby.volume, 0, 1, onVolume),
            _slider(context, Icons.graphic_eq_rounded, baby.sensitivity, 0.5, 3.0, onSensitivity),
          ],
        ),
      ),
    );
  }

  Widget _slider(BuildContext context, IconData icon, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).textTheme.labelMedium!.color),
        Gap.wSm,
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}
