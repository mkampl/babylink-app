import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// Single native audio output (flutter_pcm_sound is a global singleton) that
/// MIXES multiple per-baby PCM sources — each with its own jitter buffer,
/// volume and mute — into one stream, mirroring how the web app lets several
/// babies play at once. Silence on underrun, overrun latency cap, and a
/// room-level connection-lost alarm tone mixed on top.
class PcmMixer {
  final int sampleRate;
  final int channels;
  PcmMixer({this.sampleRate = 16000, this.channels = 1});

  final Map<String, _Src> _srcs = {};
  int _cap = 0;
  bool _started = false;

  /// Room-level "connection lost" beep, overrides everything so it's heard.
  bool alarm = false;
  int _alarmPos = 0;

  Future<void> start() async {
    if (_started) return;
    _cap = sampleRate ~/ 2; // ~500 ms per-source latency cap
    FlutterPcmSound.setLogLevel(LogLevel.error);
    await FlutterPcmSound.setup(
      sampleRate: sampleRate,
      channelCount: channels,
      iosAllowBackgroundAudio: true,
    );
    FlutterPcmSound.setFeedThreshold(sampleRate ~/ 4);
    FlutterPcmSound.setFeedCallback(_onFeed);
    _started = true;
    FlutterPcmSound.start();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    FlutterPcmSound.setFeedCallback(null);
    _srcs.clear();
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
  }

  void addSource(String id) => _srcs.putIfAbsent(id, () => _Src());
  void removeSource(String id) => _srcs.remove(id);
  void setMuted(String id, bool m) => _srcs[id]?.muted = m;
  void setVolume(String id, double v) => _srcs[id]?.volume = v.clamp(0.0, 1.0);

  void enqueue(String id, Int16List samples) {
    final src = _srcs[id];
    if (src == null) return;
    src.buf.addAll(samples);
    if (src.buf.length > _cap) {
      src.buf.removeRange(0, src.buf.length - _cap);
    }
  }

  void _onFeed(int remaining) {
    if (!_started) return;
    const n = 4000; // ~250 ms per feed
    final mix = Int32List(n);
    for (final src in _srcs.values) {
      if (src.muted) continue; // keep its recent buffer (capped) for VOX unmute
      final take = src.buf.length >= n ? n : src.buf.length;
      final v = src.volume;
      for (var i = 0; i < take; i++) {
        mix[i] += (src.buf[i] * v).round();
      }
      if (take > 0) src.buf.removeRange(0, take);
    }
    if (alarm) _addAlarm(mix, n);
    final out = Int16List(n);
    for (var i = 0; i < n; i++) {
      out[i] = mix[i].clamp(-32768, 32767);
    }
    FlutterPcmSound.feed(PcmArrayInt16(bytes: out.buffer.asByteData()));
  }

  void _addAlarm(Int32List mix, int n) {
    final period = (sampleRate * 1.2).round();
    final toneLen = (sampleRate * 0.35).round();
    const freq = 1000.0;
    const amp = 0.4 * 32767;
    for (var i = 0; i < n; i++) {
      final pos = (_alarmPos + i) % period;
      if (pos < toneLen) {
        mix[i] += (amp * sin(2 * pi * freq * pos / sampleRate)).round();
      }
    }
    _alarmPos = (_alarmPos + n) % period;
  }
}

class _Src {
  final List<int> buf = [];
  double volume = 1.0;
  bool muted = false;
}
