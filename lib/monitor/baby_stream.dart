/// Health of one baby's audio, mirroring the web never-silent contract.
enum AudioHealth { live, quiet, stalled }

/// How this baby's audio reaches us. ESP32 hardware relays PCM frames; phones
/// and browsers stream over WebRTC (the web app's only baby transport).
enum BabyKind { pcm, webrtc }

/// The three loudness bands the auto-listen (VOX) reacts to, matching the web:
/// green = quiet, yellow = movement, red = crying.
enum Band { green, yellow, red }

Band bandFor(double level, {double yellow = 0.12, double red = 0.5}) {
  if (level >= red) return Band.red;
  if (level >= yellow) return Band.yellow;
  return Band.green;
}

/// The web's auto-listen state machine (multi-baby-ui.js handleAutoMuteLogic):
/// - RED  → unmute IMMEDIATELY.
/// - YELLOW → unmute only after it has stayed ≥yellow for [yellowDelayMs] (a
///   brief blip doesn't open the mic).
/// - GREEN → mute after [muteDelayMs] quiet, or [muteAfterCryMs] if it was just
///   crying (give a settling baby longer).
/// Pure so the timing is unit-testable. Returns the next "audible" latch value.
bool nextAutoAudible({
  required bool current,
  required Band band,
  required int yellowHeldMs,
  required int greenHeldMs,
  required bool recentlyRed,
  int yellowDelayMs = 2000,
  int muteDelayMs = 5000,
  int muteAfterCryMs = 10000,
}) {
  switch (band) {
    case Band.red:
      return true;
    case Band.yellow:
      return current || yellowHeldMs >= yellowDelayMs;
    case Band.green:
      final delay = recentlyRed ? muteAfterCryMs : muteDelayMs;
      if (current && greenHeldMs >= delay) return false;
      return current;
  }
}

/// Resolve what actually plays, given the manual overrides and the VOX latch.
/// Priority: crying (RED) is always heard — even through a manual mute (matches
/// the web); then a manual "listen in"; then a manual "mute"; then, for PCM, the
/// [autoAudible] latch. WebRTC has no reliable receive-side level so it stays
/// OPEN under auto (a monitor must never self-mute blindly).
bool voxEffectiveMuted({
  required BabyKind kind,
  required bool red,
  required bool listenHold,
  required bool muteHold,
  required bool autoAudible,
}) {
  if (red) return false;
  if (listenHold) return false;
  if (muteHold) return true;
  if (kind == BabyKind.webrtc) return false;
  return !autoAudible;
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

  // Battery is three-state: [batteryReported]=false → device reports none (no
  // chip); reported with [battery]==null → sense active but unreadable ("--%",
  // e.g. an ESP with no divider soldered); reported with 0-100 → a real level.
  bool batteryReported = false;
  int? battery;
  bool charging = false;

  double level = 0; // 0..1 latest peak
  AudioHealth health = AudioHealth.quiet;
  DateTime lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastEnergy = DateTime.fromMillisecondsSinceEpoch(0);

  // Auto-listen (VOX) state machine, matching the web's RED-instant /
  // YELLOW-delayed / GREEN-mute-after behaviour.
  bool autoAudible = false; // the latch: is auto currently opening the mic?
  DateTime loudSince = DateTime.fromMillisecondsSinceEpoch(0); // ≥yellow episode start
  DateTime greenSince = DateTime.fromMillisecondsSinceEpoch(0); // quiet episode start
  DateTime lastRedAt = DateTime.fromMillisecondsSinceEpoch(0); // last crying moment

  // Temporary MANUAL overrides of the auto base — buttons set these windows and
  // then it falls back to auto.
  DateTime listenHoldUntil = DateTime.fromMillisecondsSinceEpoch(0); // audible until
  DateTime muteHoldUntil = DateTime.fromMillisecondsSinceEpoch(0); // silent until
  bool effectiveMuted = true; // what's actually playing right now
  double volume = 1.0;
  double sensitivity = 1.0;

  bool listenHoldActive(DateTime now) => now.isBefore(listenHoldUntil);
  bool muteHoldActive(DateTime now) => now.isBefore(muteHoldUntil);

  BabyStream(this.id, this.name, {this.kind = BabyKind.pcm});
}
