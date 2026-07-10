import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../store/app_store.dart';
import 'pcm_player.dart';

enum LinkState { connecting, listening, reconnecting }

/// Health of the audio, mirroring the web app's honest never-silent contract.
enum AudioHealth { live, quiet, stalled }

/// Connects to a room over Socket.IO as a parent, plays the ESP's PCM audio,
/// and reports honest status. One instance per open monitor.
class RoomConnection extends ChangeNotifier {
  final SavedRoom room;
  RoomConnection(this.room);

  final PcmPlayer _player = PcmPlayer();
  io.Socket? _socket;
  Timer? _watchdog;

  LinkState link = LinkState.connecting;
  AudioHealth health = AudioHealth.quiet;
  String babyName = '';
  double level = 0; // 0..1 peak of the latest audio
  bool get muted => _player.muted;
  double get volume => _player.volume;
  double sensitivity = 1.0;

  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastEnergy = DateTime.fromMillisecondsSinceEpoch(0);

  String get _url {
    final scheme = room.serverPort == 443 ? 'https' : 'http';
    final authority = room.serverPort == 443 ? room.serverHost : '${room.serverHost}:${room.serverPort}';
    return '$scheme://$authority';
  }

  Future<void> start() async {
    await _player.start();
    babyName = room.name;
    final socket = io.io(
      _url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setReconnectionDelay(1000)
          .build(),
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

  int _frames = 0;
  void _onAudio(dynamic data) {
    if (data is! Map) {
      if (_frames++ < 3) debugPrint('[babylink] esp32-audio not a Map: ${data.runtimeType}');
      return;
    }
    final name = data['fromName']?.toString();
    if (name != null && name.isNotEmpty) babyName = name;

    final bytes = _extractBytes(data['audio']);
    if (_frames++ < 3) {
      debugPrint('[babylink] audio field=${data['audio'].runtimeType} '
          'bytes=${bytes?.lengthInBytes} sr=${data['sampleRate']}');
    }
    if (bytes == null || bytes.isEmpty) return;
    // Interpret as little-endian int16 PCM.
    final aligned = (bytes.lengthInBytes.isOdd) ? bytes.sublist(0, bytes.length - 1) : bytes;
    final samples = aligned.buffer.asInt16List(aligned.offsetInBytes, aligned.length ~/ 2);

    _player.enqueue(samples);

    // Meter: peak amplitude (0..1), scaled by sensitivity for detection.
    var peak = 0;
    for (final s in samples) {
      final a = s < 0 ? -s : s;
      if (a > peak) peak = a;
    }
    final now = DateTime.now();
    _lastFrame = now;
    final lvl = (peak / 32768.0) * sensitivity;
    level = lvl.clamp(0.0, 1.0);
    if (level > 0.03) _lastEnergy = now;
    notifyListeners();
  }

  /// The 'audio' payload can arrive as raw bytes or a JSON-serialized Buffer.
  Uint8List? _extractBytes(dynamic audio) {
    if (audio is Uint8List) return audio;
    if (audio is List<int>) return Uint8List.fromList(audio);
    if (audio is ByteBuffer) return audio.asUint8List();
    if (audio is Map && audio['data'] is List) {
      return Uint8List.fromList(List<int>.from(audio['data']));
    }
    return null;
  }

  void _tick() {
    final now = DateTime.now();
    final sinceFrame = now.difference(_lastFrame).inMilliseconds;
    final sinceEnergy = now.difference(_lastEnergy).inMilliseconds;
    final prev = health;
    if (sinceFrame > 8000) {
      health = AudioHealth.stalled; // no audio arriving at all
    } else if (sinceEnergy < 900) {
      health = AudioHealth.live;
    } else {
      health = AudioHealth.quiet;
    }
    if (level > 0 && sinceFrame > 400) {
      level = 0; // decay the meter when frames pause
    }
    if (prev != health || true) notifyListeners();
  }

  void setMuted(bool m) {
    _player.muted = m;
    notifyListeners();
  }

  void setVolume(double v) {
    _player.volume = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setSensitivity(double s) {
    sensitivity = s.clamp(0.5, 3.0);
    notifyListeners();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    try {
      _socket?.dispose();
    } catch (_) {}
    _player.stop();
    super.dispose();
  }
}
