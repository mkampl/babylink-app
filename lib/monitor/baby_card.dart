import 'package:flutter/material.dart';

import '../theme.dart';
import 'baby_stream.dart';

/// One baby's card in the room monitor: name, live status + level meter, and
/// per-baby controls. The base state is always auto-listen (VOX); "Listen in"
/// and "Mute" are momentary overrides (~10s) that fall back to auto — they don't
/// latch. A cry overrides everything and is always heard.
class BabyCard extends StatelessWidget {
  final BabyStream baby;
  final VoidCallback onListen; // force audible ~10s
  final VoidCallback onMute; // silence ~10s
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onSensitivity;

  const BabyCard({
    super.key,
    required this.baby,
    required this.onListen,
    required this.onMute,
    required this.onVolume,
    required this.onSensitivity,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.status;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final level = baby.level; // show real activity even while muted
    final mutedNow = baby.effectiveMuted;
    final crying = baby.health == AudioHealth.live && baby.level > 0.5;
    final listenActive = baby.listenHoldActive(now);
    final muteActive = baby.muteHoldActive(now);

    // A placeholder for the room's expected device (no audio yet): we're
    // already connected to the room — just waiting for a device. Never an alarm.
    final (statusText, statusColor) = baby.pending
        ? (baby.waitedTooLong
            ? ('No device yet — is it on?', muted)
            : ('Waiting for a device', muted))
        : baby.health == AudioHealth.stalled
            ? ('No audio — reconnecting', s.danger)
            : crying
                ? ('Crying!', s.danger)
                : listenActive
                    ? ('Listening', s.success) // manual listen-in or crying hold
                    : muteActive
                        ? ('Muted', muted)
                        : mutedNow
                            // Distinguish the brief "movement, not yet unmuted"
                            // window (yellow) from true quiet, like the web.
                            ? (bandFor(level) == Band.yellow
                                ? ('Movement', muted)
                                : ('Auto-muted (quiet)', muted))
                            : ('Listening', s.success);

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
                if (baby.batteryReported) ...[_battery(context), Gap.wSm],
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
              _actions(context, now, listenActive, muteActive),
              Gap.hSm,
              _slider(context, Icons.volume_up_rounded, baby.volume, 0, 1, onVolume),
              _slider(context, Icons.graphic_eq_rounded, baby.sensitivity, 0.5, 3.0, onSensitivity),
            ],
          ],
        ),
      ),
    );
  }

  /// The baby device's self-reported battery — so a phone-as-baby about to die
  /// is visible, not a silent outage. Low levels go warning/danger coloured.
  Widget _battery(BuildContext context) {
    final b = baby.battery; // null = reported but unreadable → "--%"
    final s = context.status;
    final neutral = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = b == null ? neutral : (b <= 15 ? s.danger : (b <= 30 ? s.warning : neutral));
    final icon = b == null
        ? Icons.battery_unknown_rounded
        : (baby.charging
            ? Icons.battery_charging_full_rounded
            : (b <= 15 ? Icons.battery_alert_rounded : Icons.battery_full_rounded));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 2),
        Text(b == null ? '--%' : '$b%',
            style: Theme.of(context).textTheme.labelMedium!.copyWith(color: color)),
      ],
    );
  }

  /// Two momentary actions. Highlighted with a seconds countdown while their
  /// hold is active, then they revert — auto-listen (VOX) is the resting state.
  Widget _actions(BuildContext context, DateTime now, bool listenActive, bool muteActive) {
    final listenLeft = baby.listenHoldUntil.difference(now).inSeconds + 1;
    final muteLeft = baby.muteHoldUntil.difference(now).inSeconds + 1;
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            context,
            icon: Icons.volume_up_rounded,
            label: listenActive ? 'Listening ${listenLeft.clamp(1, 99)}s' : 'Listen in',
            active: listenActive,
            onTap: onListen,
          ),
        ),
        Gap.wSm,
        Expanded(
          child: _actionButton(
            context,
            icon: Icons.volume_off_rounded,
            label: muteActive ? 'Muted ${muteLeft.clamp(1, 99)}s' : 'Mute',
            active: muteActive,
            onTap: onMute,
          ),
        ),
      ],
    );
  }

  Widget _actionButton(BuildContext context,
      {required IconData icon, required String label, required bool active, required VoidCallback onTap}) {
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelMedium),
    );
    return active
        ? FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label), style: style)
        : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label), style: style);
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
