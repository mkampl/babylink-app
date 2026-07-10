/// Health of one baby's audio, mirroring the web never-silent contract.
enum AudioHealth { live, quiet, stalled }

/// Per-baby state in a room: name, meter level, health, and independent
/// controls. The audio buffer itself lives in the shared PcmMixer, keyed by id.
class BabyStream {
  final String id; // esp32 device id (the frame's fromId)
  String name;

  /// A placeholder for the room's expected device before any audio arrives —
  /// so an already-offline device shows + alarms instead of an empty screen.
  bool pending = false;

  double level = 0; // 0..1 latest peak
  AudioHealth health = AudioHealth.quiet;
  DateTime lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastEnergy = DateTime.fromMillisecondsSinceEpoch(0);

  bool manualMute = false; // hard mute (overrides auto-listen)
  bool effectiveMuted = true; // manual OR auto-listen-quiet
  double volume = 1.0;
  double sensitivity = 1.0;

  BabyStream(this.id, this.name);
}
