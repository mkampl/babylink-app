import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../store/app_store.dart';
import '../theme.dart';
import '../widgets/hero_badge.dart';
import '../widgets/tip_banner.dart';
import 'baby_card.dart';
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
  bool _batteryOk = true; // hide the reliability tip until we know otherwise

  @override
  void initState() {
    super.initState();
    MonitorService.configure();
    MonitorService.start(widget.room.name);
    _conn = RoomConnection(widget.room);
    _conn.start();
    WakelockPlus.enable();
    _hardenBackground();
  }

  /// Keep the monitor alive when backgrounded: ask the OS to exempt us from
  /// battery optimization (Doze), then reflect whether we're protected so the
  /// user can fix it if they dismissed the dialog.
  Future<void> _hardenBackground() async {
    await MonitorService.ensureBatteryExemption();
    final ok = await MonitorService.isBatteryUnrestricted();
    if (mounted) setState(() => _batteryOk = ok);
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
    final babies = _conn.babies;

    return Column(
      children: [
        // Reliability nudge: without a battery-optimization exemption the OS can
        // freeze this monitor in the background and a cry goes unheard.
        if (!_batteryOk) _reliabilityTip(context),

        // Room-level alarm banner when any baby dropped.
        if (_conn.anyUnackedAlarm)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
            child: FilledButton.icon(
              onPressed: _conn.silenceAlarms,
              icon: const Icon(Icons.notifications_active_rounded),
              label: const Text('Silence alarm'),
              style: FilledButton.styleFrom(
                backgroundColor: context.status.danger,
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),

        Expanded(
          child: babies.isEmpty
              ? _waiting(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
                  children: [
                    if (_conn.link != LinkState.listening)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.md),
                        child: TipBanner(
                          _conn.link == LinkState.connecting ? 'Connecting…' : 'Reconnecting…',
                          kind: TipKind.info,
                        ),
                      ),
                    for (final baby in babies) ...[
                      BabyCard(
                        baby: baby,
                        onListen: () => _conn.listenIn(baby.id),
                        onMute: () => _conn.muteBriefly(baby.id),
                        onVolume: (v) => _conn.setBabyVolume(baby.id, v),
                        onSensitivity: (s) => _conn.setBabySensitivity(baby.id, s),
                      ),
                      Gap.hMd,
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _reliabilityTip(BuildContext context) {
    final s = context.status;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: s.warningBg,
          borderRadius: Radii.rMd,
          border: Border.all(color: s.warning.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.battery_alert_rounded, color: s.warning, size: 22),
            Gap.wMd,
            Expanded(
              child: Text(
                'For reliable alerts, allow BabyLink to run unrestricted in the background.',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: s.warning, height: 1.3),
              ),
            ),
            Gap.wSm,
            TextButton(
              onPressed: () async {
                await MonitorService.openBatterySettings();
                if (mounted) _hardenBackground(); // re-check when they come back
              },
              child: const Text('Fix'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _waiting(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final connecting = _conn.link != LinkState.listening;
    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeroBadge(emoji: '👂', pulse: true, size: 132),
          Gap.hLg,
          Text(connecting ? 'Connecting…' : 'Waiting for a baby device',
              textAlign: TextAlign.center, style: t.headlineSmall),
          Gap.hSm,
          Text('Audio and controls appear here as soon as a device is streaming to this room.',
              textAlign: TextAlign.center, style: t.bodyMedium),
        ],
      ),
    );
  }
}
