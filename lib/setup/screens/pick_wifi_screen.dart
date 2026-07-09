import 'package:flutter/material.dart';

import '../../ble/babylink_ble.dart';
import '../../theme.dart';
import '../../widgets/entity_tile.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';
import 'applying_screen.dart';
import 'password_screen.dart';

class PickWifiScreen extends StatefulWidget {
  final SetupSession session;
  const PickWifiScreen({super.key, required this.session});

  @override
  State<PickWifiScreen> createState() => _PickWifiScreenState();
}

class _PickWifiScreenState extends State<PickWifiScreen> {
  List<WifiNetwork>? _nets;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
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

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final nets = await widget.session.ble.scanWifi();
      // Drop hidden/blank SSIDs — you can't pick a nameless network.
      final visible = nets.where((n) => n.ssid.trim().isNotEmpty).toList();
      setState(() {
        _nets = visible;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Couldn’t scan for WiFi. Move the device closer and try again.';
        _loading = false;
      });
    }
  }

  void _pick(WifiNetwork n) {
    final s = widget.session;
    s.network = n;
    s.manualSsid = null;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => n.secure ? PasswordScreen(session: s) : ApplyingScreen(session: s),
    ));
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final ssid = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter network name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'WiFi network name (SSID)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Next')),
        ],
      ),
    );
    if (ssid == null || ssid.isEmpty) return;
    final s = widget.session;
    s.network = null;
    s.manualSsid = ssid;
    s.manualSecure = true;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PasswordScreen(session: s)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StepScaffold(
      title: 'Choose your WiFi',
      subtitle: 'Pick the network your BabyLink should join.',
      actions: [
        IconButton(
          onPressed: _loading ? null : _scan,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) ...[
            Gap.hXl,
            const HeroBadge(emoji: '📶', pulse: true),
            Gap.hSm,
            Center(child: Text('Looking for networks…', style: t.labelMedium)),
          ] else if (_error != null) ...[
            Gap.hMd,
            TipBanner(_error!, kind: TipKind.danger),
          ] else if ((_nets ?? []).isEmpty) ...[
            Gap.hMd,
            const TipBanner(
              'No networks found. Move your BabyLink closer to your router, then refresh.',
              kind: TipKind.info,
            ),
          ] else ...[
            for (final n in _nets!) ...[
              EntityTile(
                icon: Icons.wifi_rounded,
                title: n.ssid,
                locked: n.secure,
                signal: bars(n.rssi),
                onTap: () => _pick(n),
              ),
              Gap.hSm,
            ],
            Gap.hSm,
            EntityTile(
              icon: Icons.keyboard_rounded,
              title: 'Enter network name manually',
              onTap: _manualEntry,
            ),
          ],
        ],
      ),
    );
  }
}
