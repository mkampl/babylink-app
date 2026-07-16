import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../store/app_store.dart';
import 'alert_tracker.dart';
import 'baby_stream.dart';
import 'notify_service.dart';
import 'pcm_player.dart';
import 'sleep_tracker.dart';
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
  String? soloId; // when set, only this baby is heard (mute all others)
  final Map<String, BabyStream> _babies = {};
  final Map<String, ({int? level, bool charging})> _battery = {}; // by id, may pre-date the baby
  final Map<String, SleepTracker> _sleep = {}; // per-baby sleep history
  final Set<String> _ackedStalls = {}; // babies whose alarm the user silenced
  final AlertTracker _alerts = AlertTracker(cryThreshold: _cryThreshold, cryRearmMs: _cryRearmMs);

  static const _soundThreshold = 0.12; // green→yellow (movement)
  static const _cryThreshold = 0.5; // yellow→red (crying); matches the card
  static const _cryRearmMs = 6000; // must be quiet this long before we alert again
  static const _holdMs = 10000; // manual "listen in" / "mute" hold window
  // Auto-listen (VOX) timing, matching the web (multi-baby-ui.js).
  static const _yellowDelayMs = 2000; // movement must persist this long to unmute
  static const _muteDelayMs = 5000; // quiet this long → mute
  static const _muteAfterCryMs = 10000; // …but 10s if it was just crying
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
      final parts = data is Map ? data['participants'] : null;
      _seedBattery(parts);
      _kickBabies(parts);
      notifyListeners();
    });
    socket.on('baby-status', (data) {
      if (data is! Map) return;
      // The event firing means the device reports battery; the value may be null
      // (unknown → "--%") or a 0-100 level.
      _setBattery(data['socketId']?.toString(), (data['battery'] as num?)?.toInt(), data['charging'] == true);
    });
    socket.on('participant-joined', (data) {
      if (data is Map) {
        _seedBattery(data['participants']);
        if (data['role'] == 'baby') _kickBaby(data['socketId']?.toString());
      }
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

  /// Seed per-baby battery from a participants list (room-state / joined), so a
  /// value that arrived before the baby's audio isn't lost.
  void _seedBattery(dynamic participants) {
    if (participants is! List) return;
    for (final p in participants) {
      // containsKey, not != null: a present-but-null value means "reported,
      // unknown" (→ "--%"), which must be distinguished from "not reported".
      if (p is Map && p.containsKey('battery')) {
        _setBattery(p['socketId']?.toString(), (p['battery'] as num?)?.toInt(), p['charging'] == true);
      }
    }
  }

  void _setBattery(String? id, int? level, bool charging) {
    if (id == null) return;
    _battery[id] = (level: level, charging: charging);
    final baby = _babies[id];
    if (baby != null) {
      baby.batteryReported = true;
      baby.battery = level;
      baby.charging = charging;
      notifyListeners();
    }
  }

  void _applyBattery(BabyStream b) {
    final bat = _battery[b.id];
    if (bat != null) {
      b.batteryReported = true;
      b.battery = bat.level;
      b.charging = bat.charging;
    }
  }

  /// Per-baby sleep history (mirrors the web). Created on first sight and loaded
  /// from disk so a re-opened monitor shows the baby's earlier night.
  SleepTracker? sleepFor(String id) => _sleep[id];

  void _ensureSleep(BabyStream b) {
    if (_sleep.containsKey(b.id)) return;
    final t = SleepTracker(room.roomId, b.id);
    _sleep[b.id] = t;
    t.load(); // async — fills in history when ready
    b.log(DateTime.now(), '🔌 Connected'); // first sight of this baby
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
      _applyBattery(baby);
      _ensureSleep(baby);
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
      _applyBattery(baby);
      _ensureSleep(baby);
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
    final band = bandFor(baby.level, yellow: _soundThreshold, red: _cryThreshold);

    // Track the loud/quiet episode timers the VOX state machine needs.
    if (band == Band.green) {
      if (baby.greenSince.millisecondsSinceEpoch == 0) baby.greenSince = now;
      baby.loudSince = DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      if (baby.loudSince.millisecondsSinceEpoch == 0) baby.loudSince = now;
      baby.greenSince = DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (band == Band.red) {
      baby.lastRedAt = now;
      baby.muteHoldUntil = now; // crying cancels a manual mute, like the web
    }

    final yellowHeld = band == Band.green ? 0 : now.difference(baby.loudSince).inMilliseconds;
    final greenHeld = band == Band.green ? now.difference(baby.greenSince).inMilliseconds : 0;
    final recentlyRed = now.difference(baby.lastRedAt).inMilliseconds < _muteAfterCryMs;

    final wasAutoAudible = baby.autoAudible;
    baby.autoAudible = nextAutoAudible(
      current: baby.autoAudible,
      band: band,
      yellowHeldMs: yellowHeld,
      greenHeldMs: greenHeld,
      recentlyRed: recentlyRed,
      yellowDelayMs: _yellowDelayMs,
      muteDelayMs: _muteDelayMs,
      muteAfterCryMs: _muteAfterCryMs,
    );
    // Log the auto-listen transitions (only when auto is actually in charge).
    if (baby.kind == BabyKind.pcm &&
        soloId == null &&
        !baby.listenHoldActive(now) &&
        !baby.muteHoldActive(now) &&
        baby.autoAudible != wasAutoAudible) {
      baby.log(now, baby.autoAudible ? '🔊 Auto-unmuted (movement)' : '🔇 Auto-muted (quiet)');
    }

    // Solo overrides everything: only the solo'd baby is heard.
    baby.effectiveMuted = soloId != null
        ? baby.id != soloId
        : voxEffectiveMuted(
            kind: baby.kind,
            red: band == Band.red,
            listenHold: baby.listenHoldActive(now),
            muteHold: baby.muteHoldActive(now),
            autoAudible: baby.autoAudible,
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
      // Feed the sleep history — but only while streaming, so a disconnect
      // reads as a grey "no data" gap, not as "quietly asleep".
      if (baby.health != AudioHealth.stalled) _sleep[baby.id]?.record(now, baby.level);
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
          baby.log(now, '📴 Went offline');
        case AlertEvent.online:
          NotifyService.clearDisconnected(baby.id);
          baby.log(now, '🔌 Reconnected');
        case AlertEvent.cryStart:
          NotifyService.crying(baby.id, baby.name);
          baby.log(now, '🚨 Crying');
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
    b.log(now, '🔊 Listening in');
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
    b.log(now, '🔇 Muted');
    _applyMute(b);
    notifyListeners();
  }

  /// Solo: hear only this baby (mute all others). Tapping the solo'd baby again
  /// clears it and returns everyone to auto.
  void toggleSolo(String id) {
    soloId = soloId == id ? null : id;
    final now = DateTime.now();
    _babies[id]?.log(now, soloId == null ? '🎧 Solo off' : '🎧 Solo — only this baby');
    for (final b in _babies.values) {
      _applyMute(b);
    }
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
    for (final t in _sleep.values) {
      t.dispose(); // flush sleep history to disk
    }
    NotifyService.clearAll(); // leaving the monitor clears its alerts
    super.dispose();
  }
}
