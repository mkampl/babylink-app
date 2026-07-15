/// Health of one baby's audio, mirroring the web never-silent contract.
enum AudioHealth { live, quiet, stalled }

/// How this baby's audio reaches us. ESP32 hardware relays PCM frames; phones
/// and browsers stream over WebRTC (the web app's only baby transport).
enum BabyKind { pcm, webrtc }

/// What the user wants to hear from a baby, overriding or following VOX:
/// - [auto]   follow the sound: PCM auto-mutes when quiet, opens on sound.
/// - [listen] force audible — "listen in" even while it's quiet (VOX off).
/// - [muted]  force silent — a hard mute.
enum ListenMode { auto, listen, muted }

/// Pure decision for whether a baby's audio should be muted right now. Split out
/// so the mute policy (and the ESP VOX threshold) is unit-testable without a
/// mixer, socket or WebRTC engine. WebRTC has no reliable receive-side level, so
/// in [ListenMode.auto] it stays OPEN (a monitor must never self-mute blindly);
/// PCM has real per-sample levels, so auto = VOX by quiet duration.
///
/// SAFETY: a crying baby (level over [cryThreshold]) is heard even through a
/// hard mute — a muted monitor must never swallow a cry. Matches the web app,
/// where crying (RED) overrides a manual mute.
bool voxEffectiveMuted({
  required ListenMode mode,
  required BabyKind kind,
  required int quietForMs,
  required double level,
  int voxHoldMs = 4000,
  double cryThreshold = 0.5,
}) {
  if (level > cryThreshold) return false; // crying overrides any mute
  switch (mode) {
    case ListenMode.muted:
      return true;
    case ListenMode.listen:
      return false;
    case ListenMode.auto:
      if (kind == BabyKind.webrtc) return false;
      return quietForMs > voxHoldMs;
  }
}

/// Per-baby state in a room: name, meter level, health, and independent
/// controls. For [BabyKind.pcm] the audio buffer lives in the shared PcmMixer;
/// for [BabyKind.webrtc] the native engine plays it and WebRtcReceiver owns it.
class BabyStream {
  final String id; // esp32 device id (PCM) or socket id (WebRTC)
  String name;
  BabyKind kind;

  /// A placeholder for the room's expected device before any audio arrives —
  /// shows "Connecting…" instead of a blank screen. It NEVER alarms: only a
  /// baby that was actually present and then dropped does.
  bool pending = false;
  bool waitedTooLong = false; // grace window passed with still no device

  double level = 0; // 0..1 latest peak
  AudioHealth health = AudioHealth.quiet;
  DateTime lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastEnergy = DateTime.fromMillisecondsSinceEpoch(0);

  ListenMode mode = ListenMode.auto; // auto (VOX) / listen (force on) / muted
  bool effectiveMuted = true; // what's actually playing right now
  double volume = 1.0;
  double sensitivity = 1.0;

  BabyStream(this.id, this.name, {this.kind = BabyKind.pcm});
}
