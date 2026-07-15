import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../store/app_store.dart';
import 'alert_tracker.dart';
import 'baby_stream.dart';
import 'notify_service.dart';
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
  bool _mixerStarted = false; // only spin up flutter_pcm_sound when PCM/alarm needs it
  WebRtcReceiver? _webrtc;
  io.Socket? _socket;
  Timer? _watchdog;
  Timer? _levelPoll;

  LinkState link = LinkState.connecting;
  final Map<String, BabyStream> _babies = {};
  final Set<String> _ackedStalls = {}; // babies whose alarm the user silenced
  final AlertTracker _alerts = AlertTracker(cryThreshold: _cryThreshold, cryRearmMs: _cryRearmMs);

  static const _voxHoldMs = 4000;
  static const _soundThreshold = 0.12;
  static const _cryThreshold = 0.5; // matches the card's "Crying!" line
  static const _cryRearmMs = 6000; // must be quiet this long before we alert again
  static const _holdMs = 10000; // "listen in" / "mute" / crying hold window
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
    await NotifyService.init(); // local cry/disconnect alerts, no server needed
    // Show the room's expected device right away so a device that's already
    // offline surfaces (and alarms) instead of an empty "waiting" screen.
    _babies[_pendingId] = BabyStream(_pendingId, room.name)
      ..pending = true
      ..lastFrame = DateTime.now();
    // NOTE: don't start the PCM engine here. flutter_pcm_sound is a global
    // singleton output; running it alongside a WebRTC audio track silences the
    // WebRTC audio. Start it lazily only when a PCM (ESP) baby or the alarm
    // actually needs it (see _ensureMixer).
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

    _ensureMixer(); // a PCM device is streaming — we need the PCM engine now

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

  /// Spin up flutter_pcm_sound on demand (idempotent). Kept off for WebRTC-only
  /// rooms so it can't fight the WebRTC audio output.
  void _ensureMixer() {
    if (_mixerStarted) return;
    _mixerStarted = true;
    _mixer.start();
  }

  void _applyMute(BabyStream baby) {
    final now = DateTime.now();
    // Crying keeps the audio on for a rolling 10s window (not just the loud
    // instant), so a cry is heard even through a manual mute.
    if (baby.level > _cryThreshold) {
      baby.listenHoldUntil = now.add(const Duration(milliseconds: _holdMs));
    }
    final quietFor = now.difference(baby.lastEnergy).inMilliseconds;
    baby.effectiveMuted = voxEffectiveMuted(
      kind: baby.kind,
      listenHold: baby.listenHoldActive(now),
      muteHold: baby.muteHoldActive(now),
      quietForMs: quietFor,
      voxHoldMs: _voxHoldMs,
    );
    if (baby.kind == BabyKind.webrtc) {
      _webrtc?.setVolume(baby.id, baby.effectiveMuted ? 0.0 : baby.volume);
    } else {
      _mixer.setMuted(baby.id, baby.effectiveMuted);
    }
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
      _checkNotify(baby, now);
      _applyMute(baby);
    }

    // The expected-device placeholder: drop it once a real device streams.
    // It NEVER alarms — a room that never had a device just shows "Connecting…"
    // (then a calm "no device yet"). Only a baby that was present and dropped
    // alarms (handled by the stalled logic above + participant-left).
    final ph = _babies[_pendingId];
    if (ph != null) {
      final hasReal = _babies.keys.any((k) => k != _pendingId);
      if (hasReal) {
        _babies.remove(_pendingId);
      } else {
        ph.health = AudioHealth.quiet;
        if (link == LinkState.listening && now.difference(_startedAt).inSeconds >= _connectGraceSec) {
          ph.waitedTooLong = true;
        }
      }
    }

    // Room-level audible alarm: beep while any baby is stalled and un-silenced.
    // A WebRTC baby that dropped has no audio track left, so starting the PCM
    // engine now to beep doesn't fight anything.
    final alarm = anyUnackedAlarm;
    if (alarm) _ensureMixer();
    _mixer.alarm = alarm;
    notifyListeners();
  }

  /// Fire (and later clear) local notifications on the two events a parent must
  /// never miss: a baby crying, and a device dropping. Edge-triggered via sets
  /// so a continuous cry or a lasting outage alerts once, not every second.
  void _checkNotify(BabyStream baby, DateTime now) {
    final events = _alerts.update(
      id: baby.id,
      stalled: baby.health == AudioHealth.stalled,
      live: baby.health == AudioHealth.live,
      level: baby.level,
      quietForMs: now.difference(baby.lastEnergy).inMilliseconds,
    );
    for (final e in events) {
      switch (e) {
        case AlertEvent.offline:
          NotifyService.disconnected(baby.id, baby.name);
        case AlertEvent.online:
          NotifyService.clearDisconnected(baby.id);
        case AlertEvent.cryStart:
          NotifyService.crying(baby.id, baby.name);
        case AlertEvent.cryStop:
          NotifyService.clearCry(baby.id);
      }
    }
  }

  // ---- Per-baby controls (momentary — they set a 10s window, then auto) ----
  /// Force this baby audible for ~10s even while quiet ("listen in"), then it
  /// falls back to auto (VOX). Cancels any active mute.
  void listenIn(String id) {
    final b = _babies[id];
    if (b == null) return;
    final now = DateTime.now();
    b.listenHoldUntil = now.add(const Duration(milliseconds: _holdMs));
    b.muteHoldUntil = now; // clear a mute
    _applyMute(b);
    notifyListeners();
  }

  /// Silence this baby for ~10s, then back to auto. Crying still overrides it.
  void muteBriefly(String id) {
    final b = _babies[id];
    if (b == null) return;
    final now = DateTime.now();
    b.muteHoldUntil = now.add(const Duration(milliseconds: _holdMs));
    b.listenHoldUntil = now; // clear a listen
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
      if (b.health == AudioHealth.stalled) {
        _ackedStalls.add(b.id);
        NotifyService.clearDisconnected(b.id); // acknowledged — drop the heads-up too
      }
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
    NotifyService.clearAll(); // leaving the monitor clears its alerts
    super.dispose();
  }
}
