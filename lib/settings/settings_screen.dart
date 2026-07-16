import 'package:flutter/material.dart';

import '../server/babylink_server.dart';
import '../store/app_store.dart';
import '../theme.dart';
import '../widgets/tip_banner.dart';

/// Point the app at a self-hosted BabyLink server. itvoodoo.at is only a public
/// demo — anyone running their own instance sets its address here. Existing
/// rooms keep the server they were created on; this is the default for NEW
/// rooms and devices.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _custom = false;
  bool _testing = false;
  String? _okVersion; // set after a successful probe
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final server = await AppStore.instance.currentServer();
    final custom = await AppStore.instance.isCustomServer();
    if (!mounted) return;
    setState(() {
      _controller.text = server.baseUrl;
      _custom = custom;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  BabyLinkServer? _parsed() {
    try {
      return BabyLinkServer.parse(_controller.text);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      return null;
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _okVersion = null;
      _error = null;
    });
    final server = _parsed();
    if (server == null) {
      setState(() => _testing = false);
      return;
    }
    try {
      final version = await server.probe();
      if (mounted) setState(() => _okVersion = version);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final server = _parsed();
    if (server == null) return;
    // Insist on a successful probe before saving, so a typo can't silently
    // break every future room.
    if (_okVersion == null) {
      await _test();
      if (_okVersion == null) return;
    }
    await AppStore.instance.setServer(server.host, server.port);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server saved')));
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await AppStore.instance.resetServer();
    await _load();
    if (mounted) {
      setState(() {
        _okVersion = null;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Back to the demo server')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Server')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            Text('BabyLink server', style: t.titleLarge),
            Gap.hSm,
            Text(
              'BabyLink is self-hosted. babylink.itvoodoo.at is just a public demo — '
              'point the app at your own instance here.',
              style: t.bodyMedium,
            ),
            Gap.hLg,
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() {
                _okVersion = null;
                _error = null;
              }),
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'babylink.itvoodoo.at  or  192.168.1.50:3000',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
            ),
            Gap.hMd,
            if (_okVersion != null)
              TipBanner('Connected — BabyLink $_okVersion 🎉', kind: TipKind.success)
            else if (_error != null)
              TipBanner(_error!, kind: TipKind.danger),
            Gap.hMd,
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Test'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
              Gap.wMd,
              Expanded(
                child: FilledButton.icon(
                  onPressed: _testing ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ]),
            Gap.hSm,
            if (_custom)
              TextButton(onPressed: _reset, child: const Text('Reset to the demo server')),
            Gap.hLg,
            const TipBanner(
              'Existing rooms keep the server they were set up on. This only changes '
              'where NEW rooms and devices are created.',
              kind: TipKind.info,
            ),
          ],
        ),
      ),
    );
  }
}
