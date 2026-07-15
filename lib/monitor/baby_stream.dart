/// Health of one baby's audio, mirroring the web never-silent contract.
enum AudioHealth { live, quiet, stalled }

/// How this baby's audio reaches us. ESP32 hardware relays PCM frames; phones
/// and browsers stream over WebRTC (the web app's only baby transport).
enum BabyKind { pcm, webrtc }

/// Pure decision for whether a baby's audio should be muted right now. The base
/// state is always AUTO (VOX): the buttons don't latch — they set short holds
/// that expire back to auto. Split out so the policy is unit-testable without a
/// mixer, socket or WebRTC engine.
///
/// Priority (highest first):
/// 1. [listenHold] — crying (RED, held ~10s) OR a manual "listen in" tap →
///    AUDIBLE. Crying feeds this hold, so a cry is always heard, even through a
///    manual mute (matches the web, where RED overrides a manual mute).
/// 2. [muteHold] — a manual "mute" tap (held ~10s) → silent, then back to auto.
/// 3. base VOX — WebRTC stays OPEN (no reliable receive-side level; a monitor
///    must never self-mute blindly); PCM mutes once quiet for [voxHoldMs].
bool voxEffectiveMuted({
  required BabyKind kind,
  required bool listenHold,
  required bool muteHold,
  required int quietForMs,
  int voxHoldMs = 4000,
}) {
  if (listenHold) return false;
  if (muteHold) return true;
  if (kind == BabyKind.webrtc) return false;
  return quietForMs > voxHoldMs;
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

  int? battery; // last self-reported battery %, if the device reports it
  bool charging = false;

  double level = 0; // 0..1 latest peak
  AudioHealth health = AudioHealth.quiet;
  DateTime lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastEnergy = DateTime.fromMillisecondsSinceEpoch(0);

  // Temporary overrides of the auto (VOX) base — the buttons set these windows
  // and then it falls back to auto. Crying refreshes [listenHoldUntil] too.
  DateTime listenHoldUntil = DateTime.fromMillisecondsSinceEpoch(0); // audible until
  DateTime muteHoldUntil = DateTime.fromMillisecondsSinceEpoch(0); // silent until
  bool effectiveMuted = true; // what's actually playing right now
  double volume = 1.0;
  double sensitivity = 1.0;

  bool listenHoldActive(DateTime now) => now.isBefore(listenHoldUntil);
  bool muteHoldActive(DateTime now) => now.isBefore(muteHoldUntil);

  BabyStream(this.id, this.name, {this.kind = BabyKind.pcm});
}
