import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// Real-time PCM playout for the ESP audio stream, mirroring the web app's
/// AudioWorklet: a small jitter buffer, silence on underrun (never a hard
/// stop), overrun drop to cap latency, plus volume/mute. The native side plays
/// at the source rate (16 kHz), so no resampling here.
class PcmPlayer {
  final int sampleRate;
  final int channels;
  PcmPlayer({this.sampleRate = 16000, this.channels = 1});

  final List<int> _pending = []; // queued int16 samples
  int _cap = 0; // max buffered samples (latency cap)
  bool _started = false;

  double volume = 1.0; // 0..1
  bool muted = false;

  Future<void> start() async {
    if (_started) return;
    _cap = sampleRate ~/ 2; // ~500 ms latency cap
    FlutterPcmSound.setLogLevel(LogLevel.error);
    await FlutterPcmSound.setup(
      sampleRate: sampleRate,
      channelCount: channels,
      iosAllowBackgroundAudio: true,
    );
    FlutterPcmSound.setFeedThreshold(sampleRate ~/ 4); // refill when < 250 ms left
    FlutterPcmSound.setFeedCallback(_onFeed);
    _started = true;
    FlutterPcmSound.start();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    FlutterPcmSound.setFeedCallback(null);
    _pending.clear();
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
  }

  /// Queue newly-arrived samples. Drops oldest audio if the buffer runs long.
  void enqueue(Int16List samples) {
    _pending.addAll(samples);
    if (_pending.length > _cap) {
      _pending.removeRange(0, _pending.length - _cap);
    }
  }

  void _onFeed(int remaining) {
    if (!_started) return;
    const feedSamples = 4000; // ~250 ms per feed
    Int16List out;
    if (muted) {
      _pending.clear(); // keep draining so latency doesn't build while muted
      out = Int16List(1600); // 100 ms silence keeps the callback loop alive
    } else if (_pending.length >= feedSamples) {
      out = _take(feedSamples);
    } else if (_pending.isNotEmpty) {
      out = _take(_pending.length);
    } else {
      out = Int16List(1600); // underrun → silence, never a hard stop
    }
    FlutterPcmSound.feed(PcmArrayInt16(bytes: out.buffer.asByteData()));
  }

  Int16List _take(int n) {
    final out = Int16List(n);
    final v = volume;
    for (var i = 0; i < n; i++) {
      final s = _pending[i];
      out[i] = v >= 0.999 ? s : (s * v).round().clamp(-32768, 32767);
    }
    _pending.removeRange(0, n);
    return out;
  }
}
