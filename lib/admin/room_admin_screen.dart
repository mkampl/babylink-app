import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store/app_store.dart';
import '../theme.dart';
import 'room_admin.dart';

/// Owner console for a room: manage its ESP32 devices, its PIN, and ntfy push
/// notifications — all via the server's owner-authenticated endpoints.
class RoomAdminScreen extends StatefulWidget {
  final SavedRoom room;
  const RoomAdminScreen({super.key, required this.room});

  @override
  State<RoomAdminScreen> createState() => _RoomAdminScreenState();
}

class _RoomAdminScreenState extends State<RoomAdminScreen> {
  late final RoomAdmin _api = RoomAdmin(widget.room);

  bool _loading = true;
  String? _error;
  bool _hasPin = false;
  List<EspDevice> _devices = [];
  NtfyConfig _ntfy = NtfyConfig();

  final _topic = TextEditingController();
  final _server = TextEditingController();
  bool _savingNtfy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _topic.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.hasPin(),
        _api.devices().catchError((_) => <EspDevice>[]),
        _api.getNtfy(),
      ]);
      if (!mounted) return;
      setState(() {
        _hasPin = results[0] as bool;
        _devices = results[1] as List<EspDevice>;
        _ntfy = results[2] as NtfyConfig;
        _topic.text = _ntfy.topic ?? '';
        _server.text = _ntfy.server ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      _snack(ok);
      await _refresh();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Manage ${widget.room.name}')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState(context)
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
                      children: [
                        _devicesCard(context),
                        Gap.hMd,
                        _pinCard(context),
                        Gap.hMd,
                        _ntfyCard(context),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _errorState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Couldn’t load room settings.\n$_error', textAlign: TextAlign.center),
            Gap.hMd,
            FilledButton(onPressed: _refresh, child: const Text('Retry')),
          ]),
        ),
      );

  // ---- Devices ----
  Widget _devicesCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Devices', style: t.titleLarge),
          Gap.hSm,
          if (_devices.isEmpty)
            Text('No devices are connected to this room right now.', style: t.bodyMedium)
          else
            for (final d in _devices) _deviceTile(context, d),
        ]),
      ),
    );
  }

  Widget _deviceTile(BuildContext context, EspDevice d) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.memory_rounded),
      title: Text(d.name),
      subtitle: Text([
        if (d.clientIp != null) d.clientIp,
        'up ${_uptime(d.uptimeMs)}',
      ].join(' · ')),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => switch (v) {
          'rename' => _renameDevice(d),
          'disconnect' => _run(() => _api.disconnectDevice(d.id), 'Device disconnected'),
          _ => _resetDevice(d),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
          PopupMenuItem(value: 'reset', child: Text('Factory reset')),
        ],
      ),
    );
  }

  Future<void> _renameDevice(EspDevice d) async {
    final controller = TextEditingController(text: d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _run(() => _api.renameDevice(d.id, name), 'Renamed');
  }

  Future<void> _resetDevice(EspDevice d) async {
    final ok = await _confirm('Factory-reset ${d.name}?',
        'The device reboots into setup mode and forgets its WiFi + room. You’ll set it up again.');
    if (ok) await _run(() => _api.resetDevice(d.id), 'Reset command sent');
  }

  // ---- PIN ----
  Widget _pinCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lock_rounded),
            Gap.wSm,
            Text('PIN', style: t.titleLarge),
            const Spacer(),
            Text(_hasPin ? 'On' : 'Off',
                style: t.labelLarge!.copyWith(color: _hasPin ? context.status.success : t.bodySmall!.color)),
          ]),
          Gap.hSm,
          Text(
            _hasPin
                ? 'People who open the room link must enter this PIN. You (the owner) don’t.'
                : 'Add a PIN to stop anyone with the link from listening without it.',
            style: t.bodyMedium,
          ),
          Gap.hSm,
          Row(children: [
            FilledButton.tonal(
              onPressed: _setPin,
              child: Text(_hasPin ? 'Change PIN' : 'Set a PIN'),
            ),
            if (_hasPin) ...[
              Gap.wSm,
              TextButton(
                onPressed: () => _run(() => _api.setPin(null), 'PIN removed'),
                child: const Text('Remove'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Future<void> _setPin() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_hasPin ? 'Change PIN' : 'Set a PIN'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '6–8 digits'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (pin == null) return;
    if (pin.length < 6 || pin.length > 8) {
      _snack('PIN must be 6–8 digits');
      return;
    }
    await _run(() => _api.setPin(pin), 'PIN saved');
  }

  // ---- ntfy ----
  Widget _ntfyCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.notifications_active_rounded),
            Gap.wSm,
            Text('Push alerts (ntfy)', style: t.titleLarge),
          ]),
          Gap.hSm,
          Text('Get a push on your phone even when the app is closed, via ntfy.sh. '
              'Install the ntfy app and subscribe to your topic.', style: t.bodyMedium),
          Gap.hMd,
          TextField(
            controller: _topic,
            decoration: const InputDecoration(labelText: 'Topic', hintText: 'e.g. babylink-7fa3c2'),
          ),
          Gap.hSm,
          TextField(
            controller: _server,
            decoration: const InputDecoration(labelText: 'Server (optional)', hintText: 'https://ntfy.sh'),
          ),
          Gap.hSm,
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            value: _ntfy.enabled,
            onChanged: (v) => setState(() => _ntfy.enabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('When crying is detected'),
            value: _ntfy.onCrying,
            onChanged: (v) => setState(() => _ntfy.onCrying = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('When a device disconnects'),
            value: _ntfy.onDisconnect,
            onChanged: (v) => setState(() => _ntfy.onDisconnect = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('On any activity'),
            value: _ntfy.onActivity,
            onChanged: (v) => setState(() => _ntfy.onActivity = v),
          ),
          Gap.hSm,
          Row(children: [
            FilledButton(
              onPressed: _savingNtfy ? null : _saveNtfy,
              child: _savingNtfy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
            Gap.wSm,
            TextButton(
              onPressed: () => _run(() => _api.testNtfy(), 'Test push sent'),
              child: const Text('Send test'),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _saveNtfy() async {
    if (_topic.text.trim().isEmpty) {
      _snack('Enter a topic first');
      return;
    }
    setState(() => _savingNtfy = true);
    _ntfy.topic = _topic.text.trim();
    _ntfy.server = _server.text.trim().isEmpty ? null : _server.text.trim();
    try {
      await _api.setNtfy(_ntfy);
      _snack('Notifications saved');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingNtfy = false);
    }
  }

  // ---- helpers ----
  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    return ok ?? false;
  }

  String _uptime(int ms) {
    final m = ms ~/ 60000;
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    return h < 24 ? '${h}h ${m % 60}m' : '${h ~/ 24}d ${h % 24}h';
  }
}
