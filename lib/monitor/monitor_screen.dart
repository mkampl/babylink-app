import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../store/app_store.dart';
import '../theme.dart';
import 'monitor_service.dart';
import 'room_connection.dart';

class MonitorScreen extends StatefulWidget {
  final SavedRoom room;
  const MonitorScreen({super.key, required this.room});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  late final RoomConnection _conn;

  @override
  void initState() {
    super.initState();
    MonitorService.configure();
    MonitorService.start(widget.room.name); // keep audio alive in the background
    _conn = RoomConnection(widget.room);
    _conn.start();
    WakelockPlus.enable(); // keep the screen awake while it's in front
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    MonitorService.stop();
    _conn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.room.name)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _conn,
          builder: (context, _) => _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.status;
    final connecting = _conn.link != LinkState.listening;

    final (statusText, statusColor, crying) = switch (_conn.health) {
      _ when _conn.link == LinkState.connecting => ('Connecting…', s.info, false),
      _ when _conn.link == LinkState.reconnecting => ('Reconnecting…', s.warning, false),
      AudioHealth.stalled => ('No audio — reconnecting', s.danger, false),
      AudioHealth.live => _conn.level > 0.5
          ? ('Crying!', s.danger, true)
          : ('Listening', s.success, false),
      AudioHealth.quiet => ('Quiet', s.success, false),
    };

    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hMd,
          // Big status orb
          _StatusOrb(
            level: _conn.muted ? 0 : _conn.level,
            color: statusColor,
            pulse: crying || _conn.health == AudioHealth.stalled,
          ),
          Gap.hLg,
          Center(child: Text(statusText, style: t.headlineSmall!.copyWith(color: statusColor))),
          Gap.hSm,
          Center(
            child: Text(
              _conn.muted ? 'Muted' : 'on “${widget.room.ssid.isEmpty ? "WiFi" : widget.room.ssid}”',
              style: t.labelMedium,
            ),
          ),
          const Spacer(),

          // Level meter
          _Meter(level: _conn.muted ? 0 : _conn.level),
          Gap.hLg,

          // When disconnected the alarm beeps until acknowledged.
          if (_conn.alarming) ...[
            FilledButton.icon(
              onPressed: _conn.alarmAcked ? null : _conn.acknowledgeAlarm,
              icon: Icon(_conn.alarmAcked
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_rounded),
              label: Text(_conn.alarmAcked ? 'Alarm silenced' : 'Silence alarm'),
              style: FilledButton.styleFrom(
                backgroundColor: _conn.alarmAcked ? null : s.danger,
              ),
            ),
          ] else ...[
            // Auto-listen is always on; this is a hard mute for full silence.
            FilledButton.icon(
              onPressed: () => _conn.setManualMute(!_conn.manualMute),
              icon: Icon(_conn.manualMute ? Icons.volume_off_rounded : Icons.volume_up_rounded),
              label: Text(_conn.manualMute ? 'Unmute' : 'Mute'),
              style: FilledButton.styleFrom(
                backgroundColor: _conn.manualMute ? s.danger : null,
              ),
            ),
          ],
          Gap.hLg,

          // Volume
          _slider(context, 'Volume', Icons.volume_up_rounded, _conn.volume, 0, 1,
              (v) => _conn.setVolume(v)),
          // Sensitivity (detection only)
          _slider(context, 'Sensitivity', Icons.graphic_eq_rounded, _conn.sensitivity, 0.5, 3.0,
              (v) => _conn.setSensitivity(v)),
          Gap.hSm,
          if (connecting)
            Center(
              child: Text('Live audio starts as soon as the device connects.',
                  textAlign: TextAlign.center, style: t.labelMedium),
            ),
        ],
      ),
    );
  }

  Widget _slider(BuildContext context, String label, IconData icon, double value,
      double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).textTheme.labelMedium!.color),
        Gap.wSm,
        SizedBox(width: 84, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Expanded(
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

/// A soft glowing circle whose size/opacity tracks the current audio level.
class _StatusOrb extends StatelessWidget {
  final double level;
  final Color color;
  final bool pulse;
  const _StatusOrb({required this.level, required this.color, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final size = 120.0 + level.clamp(0.0, 1.0) * 80;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.14 + level.clamp(0.0, 1.0) * 0.25),
        ),
        child: Center(
          child: Icon(
            pulse ? Icons.notifications_active_rounded : Icons.hearing_rounded,
            size: 48,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final double level; // 0..1
  const _Meter({required this.level});

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final l = level.clamp(0.0, 1.0);
    final color = l > 0.5 ? s.danger : (l > 0.2 ? s.warning : s.success);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: LinearProgressIndicator(
        value: l,
        minHeight: 12,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
