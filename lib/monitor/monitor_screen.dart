import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../battery_status.dart';
import '../l10n/app_localizations.dart';
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
  final BatteryReader _batteryReader = BatteryReader();
  BatteryStatus? _ownBattery; // this (parent) phone's own charge
  Timer? _ownBatteryTimer;

  @override
  void initState() {
    super.initState();
    MonitorService.configure()
        .then((_) => MonitorService.start(widget.room.name));
    _conn = RoomConnection(widget.room);
    _conn.start();
    WakelockPlus.enable();
    _hardenBackground();
    _pollOwnBattery();
    _ownBatteryTimer = Timer.periodic(const Duration(seconds: 60), (_) => _pollOwnBattery());
  }

  Future<void> _pollOwnBattery() async {
    final b = await _batteryReader.read();
    if (mounted && b != null) setState(() => _ownBattery = b);
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
    _ownBatteryTimer?.cancel();
    WakelockPlus.disable();
    MonitorService.stop();
    _conn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room.name),
        actions: [if (_ownBattery != null) _ownBatteryChip(context)],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _conn,
          builder: (context, _) => _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              label: Text(l10n.silenceAlarm),
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
                          _conn.link == LinkState.connecting ? l10n.connecting : l10n.reconnectingStatus,
                          kind: TipKind.info,
                        ),
                      ),
                    for (final baby in babies) ...[
                      BabyCard(
                        baby: baby,
                        sleep: _conn.sleepFor(baby.id),
                        soloActive: _conn.soloId == baby.id,
                        onListen: () => _conn.listenIn(baby.id),
                        onMute: () => _conn.muteBriefly(baby.id),
                        onSolo: () => _conn.toggleSolo(baby.id),
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

  /// This phone is the monitor — show its own charge so the parent notices
  /// their device running low (they're often listening for hours on battery).
  Widget _ownBatteryChip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final b = _ownBattery!;
    final s = context.status;
    final color = b.level <= 15 ? s.danger : (b.level <= 30 ? s.warning : null);
    final icon = b.charging
        ? Icons.battery_charging_full_rounded
        : (b.level <= 15 ? Icons.battery_alert_rounded : Icons.battery_full_rounded);
    return Padding(
      padding: const EdgeInsets.only(right: Gap.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 3),
          Text(l10n.batteryPercent(b.level), style: Theme.of(context).textTheme.labelLarge!.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _reliabilityTip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                l10n.backgroundWarning,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: s.warning, height: 1.3),
              ),
            ),
            Gap.wSm,
            TextButton(
              onPressed: () async {
                await MonitorService.openBatterySettings();
                if (mounted) _hardenBackground(); // re-check when they come back
              },
              child: Text(l10n.fix),
            ),
          ],
        ),
      ),
    );
  }

  Widget _waiting(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          Text(connecting ? l10n.connecting : l10n.waitingForBabyDevice,
              textAlign: TextAlign.center, style: t.headlineSmall),
          Gap.hSm,
          Text(l10n.waitingForStream,
              textAlign: TextAlign.center, style: t.bodyMedium),
        ],
      ),
    );
  }
}
