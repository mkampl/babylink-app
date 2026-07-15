import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../battery_status.dart';
import '../store/app_store.dart';
import '../theme.dart';
import '../widgets/hero_badge.dart';
import '../widgets/primary_button.dart';
import '../widgets/tip_banner.dart';
import 'baby_service.dart';
import 'webrtc_broadcaster.dart';

/// Turns this phone into a baby unit: captures the mic and streams it to the
/// room over WebRTC (as an offerer), so a parent — in this app or the web —
/// can listen. One WebRTC peer per parent.
class BabyScreen extends StatefulWidget {
  final SavedRoom room;
  const BabyScreen({super.key, required this.room});

  @override
  State<BabyScreen> createState() => _BabyScreenState();
}

enum _State { starting, denied, streaming, error }

class _BabyScreenState extends State<BabyScreen> {
  io.Socket? _socket;
  WebRtcBroadcaster? _broadcaster;
  Timer? _levelPoll;
  Timer? _batteryTimer;
  final BatteryReader _batteryReader = BatteryReader();

  _State _state = _State.starting;
  int _parents = 0;
  double _level = 0;
  bool _muted = false;

  String get _url {
    final r = widget.room;
    final scheme = r.serverPort == 443 ? 'https' : 'http';
    final authority = r.serverPort == 443 ? r.serverHost : '${r.serverHost}:${r.serverPort}';
    return '$scheme://$authority';
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (mounted) setState(() => _state = _State.denied);
      return;
    }
    BabyService.configure();
    await BabyService.start(widget.room.name);
    await WakelockPlus.enable();

    final socket = io.io(
      _url,
      io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().setReconnectionDelay(1000).build(),
    );
    _socket = socket;
    final broadcaster = WebRtcBroadcaster(socket, _url);
    _broadcaster = broadcaster;
    broadcaster.onParents = (n) {
      if (mounted) setState(() => _parents = n);
    };
    broadcaster.onLevel = (l) {
      if (mounted) setState(() => _level = (l * 6).clamp(0.0, 1.0));
    };

    try {
      await broadcaster.start(); // getUserMedia
    } catch (_) {
      if (mounted) setState(() => _state = _State.error);
      return;
    }

    socket.onConnect((_) {
      socket.emit('join', {'roomId': widget.room.roomId, 'role': 'baby', 'userName': 'Phone'});
      _reportBattery(); // let the parent know our charge right away
    });
    socket.on('room-state', (data) {
      if (data is Map && data['participants'] is List) {
        for (final p in data['participants']) {
          if (p is Map && p['role'] == 'parent') broadcaster.offerTo(p['socketId']?.toString() ?? '');
        }
      }
    });
    socket.on('participant-joined', (data) {
      if (data is Map && data['role'] == 'parent') {
        broadcaster.offerTo(data['socketId']?.toString() ?? '');
      }
    });
    socket.on('participant-left', (data) {
      if (data is Map) broadcaster.removeParent(data['socketId']?.toString() ?? '');
    });
    socket.on('signal', (data) => broadcaster.handleSignal(data));
    socket.connect();

    _levelPoll = Timer.periodic(const Duration(milliseconds: 300), (_) => broadcaster.pollLevel());
    _batteryTimer = Timer.periodic(const Duration(seconds: 60), (_) => _reportBattery());
    if (mounted) setState(() => _state = _State.streaming);
  }

  /// Tell the parent our battery so a phone-as-baby that's about to die is
  /// visible, not a silent outage. Cheap; sent on connect and once a minute.
  Future<void> _reportBattery() async {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    final status = await _batteryReader.read();
    if (status == null) return;
    socket.emit('baby-status', {'battery': status.level, 'charging': status.charging});
  }

  void _toggleMute() {
    final b = _broadcaster;
    if (b == null) return;
    setState(() => _muted = !_muted);
    b.setMuted(_muted);
  }

  @override
  void dispose() {
    _levelPoll?.cancel();
    _batteryTimer?.cancel();
    _broadcaster?.dispose();
    try {
      _socket?.dispose();
    } catch (_) {}
    BabyService.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.room.name)),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(Gap.lg), child: _body(context))),
    );
  }

  Widget _body(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.status;

    if (_state == _State.denied) {
      return _centered(context, '🎤', 'Microphone needed',
          'BabyLink needs the microphone to stream this phone as a baby unit.',
          action: PrimaryButton('Open settings', icon: Icons.settings_rounded, onPressed: openAppSettings));
    }
    if (_state == _State.error) {
      return _centered(context, '⚠️', 'Couldn’t start the mic',
          'Something went wrong grabbing the microphone. Try again.');
    }
    if (_state == _State.starting) {
      return _centered(context, '🎤', 'Starting…', 'Getting the microphone ready.');
    }

    // streaming
    final listening = _parents > 0;
    final meter = _muted ? 0.0 : _level;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        HeroBadge(emoji: _muted ? '🔇' : '🎤', pulse: !_muted && listening, size: 132),
        Gap.hLg,
        Text(
          _muted ? 'Muted' : (listening ? 'Streaming' : 'Live'),
          textAlign: TextAlign.center,
          style: t.headlineSmall!.copyWith(color: _muted ? s.danger : s.success),
        ),
        Gap.hSm,
        Text(
          listening
              ? '$_parents ${_parents == 1 ? "person is" : "people are"} listening'
              : 'Waiting for someone to listen…',
          textAlign: TextAlign.center,
          style: t.bodyMedium,
        ),
        Gap.hLg,
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: LinearProgressIndicator(
            value: meter,
            minHeight: 12,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            valueColor: AlwaysStoppedAnimation(meter > 0.5 ? s.warning : s.success),
          ),
        ),
        const Spacer(),
        if (!listening)
          const Padding(
            padding: EdgeInsets.only(bottom: Gap.md),
            child: TipBanner('Share this room so a parent phone (or the web) can listen in.',
                kind: TipKind.info),
          ),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _toggleMute,
                icon: Icon(_muted ? Icons.mic_off_rounded : Icons.mic_rounded),
                label: Text(_muted ? 'Unmute' : 'Mute'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
            ),
            Gap.wMd,
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: s.danger,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _centered(BuildContext context, String emoji, String title, String body, {Widget? action}) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroBadge(emoji: emoji, size: 132),
        Gap.hLg,
        Text(title, textAlign: TextAlign.center, style: t.headlineSmall),
        Gap.hSm,
        Text(body, textAlign: TextAlign.center, style: t.bodyMedium),
        if (action != null) ...[Gap.hXl, action],
      ],
    );
  }
}
