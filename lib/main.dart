import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/babylink_ble.dart';
import 'theme.dart';
import 'widgets/entity_tile.dart';
import 'widgets/hero_badge.dart';
import 'widgets/primary_button.dart';
import 'widgets/step_scaffold.dart';
import 'widgets/tip_banner.dart';

void main() {
  runApp(const BabyLinkApp());
}

class BabyLinkApp extends StatelessWidget {
  const BabyLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BabyLink',
      debugShowCheckedModeBanner: false,
      theme: BabyLinkTheme.light(),
      darkTheme: BabyLinkTheme.dark(),
      themeMode: ThemeMode.system,
      home: const BleSpikeScreen(),
    );
  }
}

/// Spike: scan → connect → read the BabyLink device's INFO characteristic (and
/// test the WiFi scan). Styled with the design system so it doubles as an early
/// look at the setup flow; the full wizard replaces it once BLE is validated.
class BleSpikeScreen extends StatefulWidget {
  const BleSpikeScreen({super.key});

  @override
  State<BleSpikeScreen> createState() => _BleSpikeScreenState();
}

class _BleSpikeScreenState extends State<BleSpikeScreen> {
  final _ble = BabyLinkBle();

  StreamSubscription? _scanSub;
  StreamSubscription? _isScanningSub;
  List<ScanResult> _results = [];
  bool _scanning = false;
  String? _error;

  BluetoothDevice? _connected;
  DeviceInfo? _info;
  List<WifiNetwork>? _wifi;
  bool _busy = false;

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _ble.disconnect();
    super.dispose();
  }

  static int _bars(int rssi) {
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -78) return 2;
    if (rssi >= -88) return 1;
    return 0;
  }

  Future<void> _startScan() async {
    setState(() {
      _error = null;
      _results = [];
      _info = null;
      _wifi = null;
      _connected = null;
    });

    if (!await _ble.ensurePermissions()) {
      setState(() => _error = 'Bluetooth permission is needed to find your device.');
      return;
    }
    if (!await _ble.isBluetoothOn()) {
      setState(() => _error = 'Bluetooth is off. Turn it on to find your BabyLink.');
      return;
    }

    _isScanningSub?.cancel();
    _isScanningSub = _ble.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });
    _scanSub?.cancel();
    _scanSub = _ble.scanForDevices().listen((results) {
      if (mounted) setState(() => _results = results);
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _busy = true);
    await _ble.stopScan();
    try {
      await _ble.connect(device);
      final info = await _ble.readInfo();
      setState(() {
        _connected = device;
        _info = info;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = "Couldn't connect to that device. Let's try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testWifiScan() async {
    setState(() => _busy = true);
    try {
      final nets = await _ble.scanWifi();
      setState(() => _wifi = nets);
    } catch (e) {
      setState(() => _error = 'WiFi scan failed on the device.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await _ble.disconnect();
    setState(() {
      _connected = null;
      _info = null;
      _wifi = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _connected == null ? _buildScan(context) : _buildConnected(context);
  }

  // ---- Scan / find device ----
  Widget _buildScan(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StepScaffold(
      title: 'Set up your BabyLink',
      subtitle: 'Find your device to get started. Make sure it’s powered on and nearby.',
      showBack: false,
      bottom: PrimaryButton(
        _scanning ? 'Scanning…' : (_results.isEmpty ? 'Scan for devices' : 'Scan again'),
        icon: Icons.bluetooth_searching_rounded,
        loading: _scanning,
        onPressed: _busy ? null : _startScan,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hMd,
          HeroBadge(emoji: '📡', pulse: _scanning, size: 132),
          Gap.hSm,
          Semantics(
            liveRegion: true,
            child: Text(
              _scanning
                  ? 'Searching…'
                  : (_results.isEmpty ? 'Ready when you are' : 'Found ${_results.length}'),
              textAlign: TextAlign.center,
              style: t.labelMedium,
            ),
          ),
          Gap.hLg,
          if (_error != null) ...[TipBanner(_error!, kind: TipKind.danger), Gap.hMd],
          if (_results.isEmpty && !_scanning && _error == null)
            const TipBanner(
              'Tip: if nothing shows up, plug the device in and press its button once.',
              kind: TipKind.info,
            ),
          for (final r in _results) ...[
            EntityTile(
              icon: Icons.memory_rounded,
              title: r.device.platformName.isEmpty ? 'BabyLink device' : r.device.platformName,
              subtitle: 'Tap to connect',
              signal: _bars(r.rssi),
              onTap: _busy ? null : () => _connect(r.device),
            ),
            Gap.hSm,
          ],
        ],
      ),
    );
  }

  // ---- Connected: INFO + WiFi test ----
  Widget _buildConnected(BuildContext context) {
    final info = _info!;
    final t = Theme.of(context).textTheme;
    return StepScaffold(
      title: 'Device found',
      subtitle: _connected!.platformName,
      showBack: false,
      bottom: PrimaryButton(
        'Scan WiFi networks',
        icon: Icons.wifi_find_rounded,
        loading: _busy && _wifi == null,
        onPressed: _busy ? null : _testWifiScan,
      ),
      secondary: TextButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hMd,
          HeroBadge(
            icon: Icons.check_rounded,
            tint: context.status.success,
            size: 116,
          ),
          Gap.hLg,
          if (_error != null) ...[TipBanner(_error!, kind: TipKind.danger), Gap.hMd],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Device info', style: t.titleLarge),
                  Gap.hSm,
                  _kv('Model', info.model),
                  _kv('Firmware', info.fw),
                  _kv('MAC', info.mac),
                  _kv('Configured', info.configured ? 'yes' : 'no'),
                  _kv('Provisioning', info.provOpen ? 'open' : 'locked'),
                ],
              ),
            ),
          ),
          if (info.configured && !info.provOpen) ...[
            Gap.hMd,
            const TipBanner(
              'This device is already set up. To change it, tap the button on the device once (its light blinks 3×).',
              kind: TipKind.warning,
            ),
          ],
          if (_wifi != null) ...[
            Gap.hLg,
            Text('WiFi networks (${_wifi!.length})', style: t.titleMedium),
            Gap.hSm,
            if (_wifi!.isEmpty)
              const TipBanner('No networks found. Move the device closer to your router and try again.',
                  kind: TipKind.info)
            else
              for (final n in _wifi!) ...[
                EntityTile(
                  icon: Icons.wifi_rounded,
                  title: n.ssid,
                  locked: n.secure,
                  signal: _bars(n.rssi),
                ),
                Gap.hSm,
              ],
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(k, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Expanded(
              child: Text(v,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium!
                      .copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.titleMedium!.color)),
            ),
          ],
        ),
      );
}
