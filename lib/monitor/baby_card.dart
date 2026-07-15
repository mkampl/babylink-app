import 'package:flutter/material.dart';

import '../theme.dart';
import 'baby_stream.dart';

/// One baby's card in the room monitor: name, live status + level meter, and
/// independent listen-mode / volume / sensitivity — the per-baby controls the
/// web has. The mode control makes the auto-listen (VOX) state visible and lets
/// the user "listen in" (force audio on) or hard-mute, mirroring the web app.
class BabyCard extends StatelessWidget {
  final BabyStream baby;
  final ValueChanged<ListenMode> onMode;
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onSensitivity;

  const BabyCard({
    super.key,
    required this.baby,
    required this.onMode,
    required this.onVolume,
    required this.onSensitivity,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.status;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final level = baby.level; // show real activity even while muted
    final mutedNow = baby.effectiveMuted;

    // A placeholder for the room's expected device (no audio yet): we're
    // already connected to the room — just waiting for a device. Never an alarm.
    final (statusText, statusColor) = baby.pending
        ? (baby.waitedTooLong
            ? ('No device yet — is it on?', muted)
            : ('Waiting for a device', muted))
        : switch (baby.health) {
            AudioHealth.stalled => ('No audio — reconnecting', s.danger),
            _ when baby.mode == ListenMode.muted => ('Muted', muted),
            _ when mutedNow => ('Auto-muted (quiet)', muted), // VOX has it silent
            AudioHealth.live => baby.level > 0.5 ? ('Crying!', s.danger) : ('Listening', s.success),
            AudioHealth.quiet => ('Listening', s.success),
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
              ],
            ),
            if (!baby.pending) ...[
              Gap.hSm,
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: level.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  valueColor: AlwaysStoppedAnimation(
                    mutedNow ? muted : (level > 0.5 ? s.danger : (level > 0.2 ? s.warning : s.success)),
                  ),
                ),
              ),
              Gap.hSm,
              _modeControl(context),
              Gap.hSm,
              _slider(context, Icons.volume_up_rounded, baby.volume, 0, 1, onVolume),
              _slider(context, Icons.graphic_eq_rounded, baby.sensitivity, 0.5, 3.0, onSensitivity),
            ],
          ],
        ),
      ),
    );
  }

  /// Auto (VOX) / Listen in (force audio) / Mute — the current mode is visible,
  /// so a quiet-muted baby no longer looks the same as a silent one.
  Widget _modeControl(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ListenMode>(
        segments: const [
          ButtonSegment(value: ListenMode.auto, label: Text('Auto'), icon: Icon(Icons.hearing_rounded)),
          ButtonSegment(value: ListenMode.listen, label: Text('Listen'), icon: Icon(Icons.volume_up_rounded)),
          ButtonSegment(value: ListenMode.muted, label: Text('Mute'), icon: Icon(Icons.volume_off_rounded)),
        ],
        selected: {baby.mode},
        showSelectedIcon: false,
        onSelectionChanged: (sel) => onMode(sel.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelMedium),
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
