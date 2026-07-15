/// The two events a parent must never miss, as edges (not levels).
enum AlertEvent { cryStart, cryStop, offline, online }

/// Pure edge-detector for cry / disconnect alerts, split out of RoomConnection
/// so it can be unit-tested without a socket, WebRTC or the notification plugin.
///
/// A continuous cry or a lasting outage must alert ONCE, not every tick — so we
/// remember which babies are currently "crying" / "offline" and only emit on
/// the rising and falling edges. Crying re-arms only after a spell of quiet, so
/// a baby sobbing in bursts doesn't buzz the phone every couple of seconds.
class AlertTracker {
  final double cryThreshold;
  final int cryRearmMs;
  AlertTracker({this.cryThreshold = 0.5, this.cryRearmMs = 6000});

  final Set<String> _crying = {};
  final Set<String> _offline = {};

  /// Feed one baby's current state; get back the edges that just fired.
  List<AlertEvent> update({
    required String id,
    required bool stalled,
    required bool live,
    required double level,
    required int quietForMs,
  }) {
    final out = <AlertEvent>[];

    // Offline: standing state — rising edge on drop, falling edge on recovery.
    if (stalled) {
      if (_offline.add(id)) out.add(AlertEvent.offline);
    } else if (_offline.remove(id)) {
      out.add(AlertEvent.online);
    }

    // Crying: rising edge when it starts; re-arm only after enough quiet so we
    // don't fire again mid-episode.
    final crying = live && level > cryThreshold;
    if (crying) {
      if (_crying.add(id)) out.add(AlertEvent.cryStart);
    } else if (quietForMs > cryRearmMs) {
      if (_crying.remove(id)) out.add(AlertEvent.cryStop);
    }

    return out;
  }

  /// Drop all state for a baby (e.g. when the monitor closes).
  void forget(String id) {
    _crying.remove(id);
    _offline.remove(id);
  }
}
