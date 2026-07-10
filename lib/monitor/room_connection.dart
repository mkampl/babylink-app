import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../store/app_store.dart';
import 'baby_stream.dart';
import 'pcm_player.dart';

enum LinkState { connecting, listening, reconnecting }

/// Connects to a room over Socket.IO as a parent and plays EVERY baby's PCM
/// audio, mixed, with per-baby meter/health/controls — matching the web app's
/// multi-baby monitor. One instance per open monitor.
class RoomConnection extends ChangeNotifier {
  final SavedRoom room;
  RoomConnection(this.room);

  final PcmMixer _mixer = PcmMixer();
  io.Socket? _socket;
  Timer? _watchdog;

  LinkState link = LinkState.connecting;
  final Map<String, BabyStream> _babies = {};
  final Set<String> _ackedStalls = {}; // babies whose alarm the user silenced

  static const _voxHoldMs = 4000;
  static const _soundThreshold = 0.12;
  static const _pendingId = '__pending__'; // the expected-device placeholder
  static const _connectGraceSec = 12; // no device by now → alarm, don't sit silent

  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);

  List<BabyStream> get babies {
    final list = _babies.values.toList();
    list.sort((a, b) => a.id.compareTo(b.id)); // stable order
    return list;
  }

  bool get anyAlarming => _babies.values.any((b) => b.health == AudioHealth.stalled);
  bool get anyUnackedAlarm =>
      _babies.values.any((b) => b.health == AudioHealth.stalled && !_ackedStalls.contains(b.id));

  String get _url {
    final scheme = room.serverPort == 443 ? 'https' : 'http';
    final authority = room.serverPort == 443 ? room.serverHost : '${room.serverHost}:${room.serverPort}';
    return '$scheme://$authority';
  }

  Future<void> start() async {
    _startedAt = DateTime.now();
    // Show the room's expected device right away so a device that's already
    // offline surfaces (and alarms) instead of an empty "waiting" screen.
    _babies[_pendingId] = BabyStream(_pendingId, room.name)
      ..pending = true
      ..lastFrame = DateTime.now();
    await _mixer.start();
    final socket = io.io(
      _url,
      io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().setReconnectionDelay(1000).build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      link = LinkState.connecting;
      socket.emit('join', {'roomId': room.roomId, 'role': 'parent', 'userName': 'BabyLink app'});
      notifyListeners();
    });
    socket.on('room-state', (_) {
      link = LinkState.listening;
      notifyListeners();
    });
    socket.on('participant-joined', (_) => notifyListeners());
    socket.on('participant-left', _onParticipantLeft);
    socket.on('esp32-audio', _onAudio);
    socket.onDisconnect((_) {
      link = LinkState.reconnecting;
      notifyListeners();
    });
    socket.onConnectError((_) {
      link = LinkState.reconnecting;
      notifyListeners();
    });
    socket.connect();

    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _onAudio(dynamic data) {
    if (data is! Map) return;
    final id = (data['fromId'] ?? 'baby').toString();
    final name = data['fromName']?.toString();

    _babies.remove(_pendingId); // a real device is streaming — drop the placeholder

    var baby = _babies[id];
    if (baby == null) {
      baby = BabyStream(id, (name == null || name.isEmpty) ? 'Baby' : name);
      _babies[id] = baby;
      _mixer.addSource(id);
      _mixer.setVolume(id, baby.volume);
      _applyMute(baby);
    } else if (name != null && name.isNotEmpty) {
      baby.name = name;
    }

    final bytes = _extractBytes(data['audio']);
    if (bytes == null || bytes.isEmpty) return;
    final aligned = bytes.lengthInBytes.isOdd ? bytes.sublist(0, bytes.length - 1) : bytes;
    final samples = aligned.buffer.asInt16List(aligned.offsetInBytes, aligned.length ~/ 2);
    _mixer.enqueue(id, samples);

    var peak = 0;
    for (final s in samples) {
      final a = s < 0 ? -s : s;
      if (a > peak) peak = a;
    }
    final now = DateTime.now();
    baby.lastFrame = now;
    baby.level = ((peak / 32768.0) * baby.sensitivity).clamp(0.0, 1.0);
    if (baby.level > _soundThreshold) baby.lastEnergy = now;
    _applyMute(baby);
    notifyListeners();
  }

  void _onParticipantLeft(dynamic data) {
    // A baby going offline must NOT vanish from the monitor — it must show
    // "no audio" and sound the alarm. So instead of removing the card, mark it
    // stalled (old last-frame) and re-arm its alarm; the tick does the rest.
    if (data is Map) {
      final id = data['socketId']?.toString();
      final baby = id == null ? null : _babies[id];
      if (baby != null) {
        baby.lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
        baby.lastEnergy = DateTime.fromMillisecondsSinceEpoch(0);
        baby.level = 0;
        _ackedStalls.remove(baby.id); // this is a fresh disconnect — beep again
      }
    }
    _tick(); // recompute health + alarm immediately
  }

  void _applyMute(BabyStream baby) {
    final quietFor = DateTime.now().difference(baby.lastEnergy).inMilliseconds;
    baby.effectiveMuted = baby.manualMute || (quietFor > _voxHoldMs);
    _mixer.setMuted(baby.id, baby.effectiveMuted);
  }

  Uint8List? _extractBytes(dynamic audio) {
    if (audio is Uint8List) return audio;
    if (audio is List<int>) return Uint8List.fromList(audio);
    if (audio is ByteBuffer) return audio.asUint8List();
    if (audio is Map && audio['data'] is List) return Uint8List.fromList(List<int>.from(audio['data']));
    return null;
  }

  void _tick() {
    final now = DateTime.now();
    for (final baby in _babies.values) {
      if (baby.id == _pendingId) continue; // the placeholder is handled below
      final sinceFrame = now.difference(baby.lastFrame).inMilliseconds;
      final sinceEnergy = now.difference(baby.lastEnergy).inMilliseconds;
      if (sinceFrame > 8000) {
        baby.health = AudioHealth.stalled;
      } else if (sinceEnergy < 900) {
        baby.health = AudioHealth.live;
      } else {
        baby.health = AudioHealth.quiet;
      }
      if (baby.level > 0 && sinceFrame > 400) baby.level = 0;
      if (baby.health != AudioHealth.stalled) _ackedStalls.remove(baby.id);
      _applyMute(baby);
    }

    // The expected-device placeholder: drop it once a real device streams;
    // otherwise, after the connect grace window with nothing, alarm on it so
    // an already-offline room is audible, not a silent "waiting" screen.
    final ph = _babies[_pendingId];
    if (ph != null) {
      final hasReal = _babies.keys.any((k) => k != _pendingId);
      if (hasReal) {
        _babies.remove(_pendingId);
      } else if (link == LinkState.listening &&
          now.difference(_startedAt).inSeconds >= _connectGraceSec) {
        ph.health = AudioHealth.stalled;
      } else {
        ph.health = AudioHealth.quiet;
      }
    }

    // Room-level audible alarm: beep while any baby is stalled and un-silenced.
    _mixer.alarm = anyUnackedAlarm;
    notifyListeners();
  }

  // ---- Per-baby controls ----
  void setBabyMuted(String id, bool m) {
    final b = _babies[id];
    if (b == null) return;
    b.manualMute = m;
    _applyMute(b);
    notifyListeners();
  }

  void setBabyVolume(String id, double v) {
    final b = _babies[id];
    if (b == null) return;
    b.volume = v.clamp(0.0, 1.0);
    _mixer.setVolume(id, b.volume);
    notifyListeners();
  }

  void setBabySensitivity(String id, double s) {
    _babies[id]?.sensitivity = s.clamp(0.5, 3.0);
    notifyListeners();
  }

  /// Silence the connection-lost beep for all currently-stalled babies.
  void silenceAlarms() {
    for (final b in _babies.values) {
      if (b.health == AudioHealth.stalled) _ackedStalls.add(b.id);
    }
    _mixer.alarm = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    try {
      _socket?.dispose();
    } catch (_) {}
    _mixer.stop();
    super.dispose();
  }
}
