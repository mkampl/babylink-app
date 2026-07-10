import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../store/app_store.dart';
import 'baby_stream.dart';
import 'pcm_player.dart';
import 'webrtc_receiver.dart';

enum LinkState { connecting, listening, reconnecting }

/// Connects to a room over Socket.IO as a parent and plays EVERY baby, mixed,
/// with per-baby meter/health/controls — matching the web app's multi-baby
/// monitor. ESP32 devices arrive as PCM frames (PcmMixer); phones/browsers
/// arrive over WebRTC (WebRtcReceiver). One instance per open monitor.
class RoomConnection extends ChangeNotifier {
  final SavedRoom room;
  RoomConnection(this.room);

  final PcmMixer _mixer = PcmMixer();
  WebRtcReceiver? _webrtc;
  io.Socket? _socket;
  Timer? _watchdog;
  Timer? _levelPoll;

  LinkState link = LinkState.connecting;
  final Map<String, BabyStream> _babies = {};
  final Set<String> _ackedStalls = {}; // babies whose alarm the user silenced

  static const _voxHoldMs = 4000;
  static const _soundThreshold = 0.12;
  static const _webrtcGain = 8.0; // WebRTC audioLevel (0..1 RMS) → meter scale
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

    // WebRTC path for phone/browser babies (ESP32 stays on PCM).
    final webrtc = WebRtcReceiver(socket, _url);
    _webrtc = webrtc;
    webrtc.onLive = _onWebrtcLive;
    webrtc.onLevel = _onWebrtcLevel;
    await webrtc.init();

    socket.onConnect((_) {
      link = LinkState.connecting;
      socket.emit('join', {'roomId': room.roomId, 'role': 'parent', 'userName': 'BabyLink app'});
      notifyListeners();
    });
    socket.on('room-state', (data) {
      link = LinkState.listening;
      _kickBabies(data is Map ? data['participants'] : null);
      notifyListeners();
    });
    socket.on('participant-joined', (data) {
      if (data is Map && data['role'] == 'baby') _kickBaby(data['socketId']?.toString());
      notifyListeners();
    });
    socket.on('participant-left', _onParticipantLeft);
    socket.on('signal', (data) => webrtc.handleSignal(data));
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
    _levelPoll = Timer.periodic(const Duration(milliseconds: 300), (_) => _webrtc?.pollLevels());
  }

  /// Ask every WebRTC baby in a room-state participant list to send its offer.
  void _kickBabies(dynamic participants) {
    if (participants is! List) return;
    for (final p in participants) {
      if (p is Map && p['role'] == 'baby') _kickBaby(p['socketId']?.toString());
    }
  }

  void _kickBaby(String? socketId) {
    if (socketId == null) return;
    if (WebRtcReceiver.isWebrtcBaby(socketId) && _webrtc?.has(socketId) != true) {
      _webrtc?.requestOffer(socketId);
    }
  }

  // ---- WebRTC baby callbacks ----
  void _onWebrtcLive(String id, String name) {
    _babies.remove(_pendingId);
    var baby = _babies[id];
    if (baby == null) {
      baby = BabyStream(id, name.isEmpty ? 'Baby' : name, kind: BabyKind.webrtc);
      _babies[id] = baby;
    } else {
      baby.kind = BabyKind.webrtc;
      if (name.isNotEmpty) baby.name = name;
    }
    baby.lastFrame = DateTime.now();
    _ackedStalls.remove(id);
    notifyListeners();
  }

  void _onWebrtcLevel(String id, double raw) {
    final baby = _babies[id];
    if (baby == null) return;
    final now = DateTime.now();
    baby.lastFrame = now; // a fresh stat proves the stream is still alive
    final scaled = (raw * _webrtcGain).clamp(0.0, 1.0);
    baby.level = (scaled * baby.sensitivity).clamp(0.0, 1.0);
    if (baby.level > _soundThreshold) baby.lastEnergy = now;
    _applyMute(baby);
    notifyListeners();
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
        if (baby.kind == BabyKind.webrtc) _webrtc?.remove(baby.id); // tear the dead peer down
      }
    }
    _tick(); // recompute health + alarm immediately
  }

  void _applyMute(BabyStream baby) {
    if (baby.kind == BabyKind.webrtc) {
      // WebRTC has no reliable receive-side level (getStats audioLevel is absent
      // and totalAudioEnergy is flaky), so VOX auto-muting could silence a live
      // baby. Fail open: keep audible unless the user manually mutes.
      baby.effectiveMuted = baby.manualMute;
      _webrtc?.setVolume(baby.id, baby.effectiveMuted ? 0.0 : baby.volume);
      return;
    }
    // PCM (ESP): real per-sample levels → full VOX auto-listen.
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
    if (b.kind == BabyKind.webrtc) {
      _applyMute(b); // re-applies the effective playback volume
    } else {
      _mixer.setVolume(id, b.volume);
    }
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
    _levelPoll?.cancel();
    _webrtc?.dispose();
    try {
      _socket?.dispose();
    } catch (_) {}
    _mixer.stop();
    super.dispose();
  }
}
