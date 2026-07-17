import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../widgets/entity_tile.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';
import 'gate_screen.dart';
import 'pick_wifi_screen.dart';

class ScanScreen extends StatefulWidget {
  final SetupSession session;
  const ScanScreen({super.key, required this.session});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  StreamSubscription? _scanSub, _isScanningSub;
  List<ScanResult> _results = [];
  bool _scanning = false, _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    widget.session.ble.stopScan();
    super.dispose();
  }

  static int bars(int rssi) => rssi >= -55
      ? 4
      : rssi >= -67
          ? 3
          : rssi >= -78
              ? 2
              : rssi >= -88
                  ? 1
                  : 0;

  Future<void> _startScan() async {
    setState(() {
      _error = null;
      _results = [];
    });
    final ble = widget.session.ble;
    if (!await ble.ensurePermissions()) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _error = l10n.btPermissionNeeded);
      return;
    }
    if (!await ble.isBluetoothOn()) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() => _error = l10n.btOff);
      return;
    }
    _isScanningSub?.cancel();
    _isScanningSub = ble.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });
    _scanSub?.cancel();
    _scanSub = ble.scanForDevices().listen((r) {
      if (mounted) setState(() => _results = r);
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _connecting = true);
    final s = widget.session;
    try {
      await s.ble.connect(device);
      s.info = await s.ble.readInfo();
      if (!mounted) return;
      final needsGate = s.info!.configured && !s.info!.provOpen;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => needsGate ? GateScreen(session: s) : PickWifiScreen(session: s),
      ));
    } catch (e) {
      setState(() {
        _error = "Couldn't connect. Move closer and try again.";
        _connecting = false;
      });
      _startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final empty = _results.isEmpty;
    return StepScaffold(
      title: _connecting ? l10n.connecting : l10n.lookingForYourBabylink,
      subtitle: _connecting ? null : l10n.ensurePoweredOn,
      bottom: (!_scanning && empty && !_connecting)
          ? PrimaryButton(l10n.scanAgain, icon: Icons.refresh_rounded, onPressed: _startScan)
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hMd,
          HeroBadge(emoji: _connecting ? '🔗' : '📡', pulse: _scanning || _connecting),
          Gap.hSm,
          Semantics(
            liveRegion: true,
            child: Text(
              _connecting ? l10n.sayingHello : (_scanning ? l10n.searching : (empty ? '' : l10n.foundDevices(_results.length))),
              textAlign: TextAlign.center,
              style: t.labelMedium,
            ),
          ),
          Gap.hLg,
          if (_error != null) ...[TipBanner(_error!, kind: TipKind.danger), Gap.hMd],
          if (empty && !_scanning && !_connecting && _error == null)
            TipBanner(
              l10n.scanChecklist,
              kind: TipKind.warning,
            ),
          if (!_connecting)
            for (final r in _results) ...[
              EntityTile(
                icon: Icons.memory_rounded,
                title: r.device.platformName.isEmpty ? l10n.babylinkDevice : r.device.platformName,
                subtitle: l10n.tapToConnect,
                signal: bars(r.rssi),
                onTap: () => _connect(r.device),
              ),
              Gap.hSm,
            ],
        ],
      ),
    );
  }
}
