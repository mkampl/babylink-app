import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../store/app_store.dart';
import '../theme.dart';
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
    _conn = RoomConnection(widget.room);
    _conn.start();
    WakelockPlus.enable(); // keep the phone awake while monitoring
  }

  @override
  void dispose() {
    WakelockPlus.disable();
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

          // Auto-listen (VOX): auto-mute when quiet, unmute on sound.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-listen'),
            subtitle: const Text('Only play when the baby makes a sound'),
            value: _conn.autoListen,
            onChanged: (v) => _conn.setAutoListen(v),
          ),
          if (!_conn.autoListen) ...[
            Gap.hSm,
            FilledButton.icon(
              onPressed: () => _conn.setManualMute(!_conn.manualMute),
              icon: Icon(_conn.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
              label: Text(_conn.muted ? 'Unmute' : 'Mute'),
              style: FilledButton.styleFrom(backgroundColor: _conn.muted ? s.danger : null),
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
