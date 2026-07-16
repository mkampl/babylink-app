import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'baby_stream.dart';

/// One aggregated display slot for the timeline.
class SleepSlot {
  final int g, y, r; // seconds at each level within the slot
  const SleepSlot(this.g, this.y, this.r);
  bool get hasData => g + y + r > 0;
  int get total => g + y + r;

  /// Highest-colour-wins for the stripe: red if any crying, else yellow if any
  /// movement, else green if any quiet, else null (no observation → grey).
  Band? get dominant => r > 0
      ? Band.red
      : y > 0
          ? Band.yellow
          : g > 0
              ? Band.green
              : null;
}

/// Parent-side sleep tracker, mirroring the web's sleep-tracker.js. Classifies
/// each second's level into green/yellow/red (via [bandFor], the same bands the
/// meter/VOX use), accumulates per-second time in 15s slots, persists to
/// SharedPreferences, and aggregates into the two-tier timeline: a 15-minute
/// detail bar (15s slots) and a 12–24h history bar (1-minute slots). A slot with
/// no data (parent was closed) reads as grey, not "asleep".
class SleepTracker {
  final String roomId;
  final String babyId;

  static const int detailSlotMs = 15 * 1000;
  static const int retentionMs = 24 * 3600 * 1000;

  final Map<int, List<int>> _slots = {}; // slotIdx → [g, y, r] seconds
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _dirty = false;

  SleepTracker(this.roomId, this.babyId);

  String get _key => 'babylink-sleep-$roomId-$babyId';

  /// Fold one second's observation into the current slot.
  void record(DateTime now, double level) {
    final band = bandFor(level);
    final idx = now.millisecondsSinceEpoch ~/ detailSlotMs;
    final slot = _slots.putIfAbsent(idx, () => [0, 0, 0]);
    slot[band.index] += 1; // Band: green=0, yellow=1, red=2 → [g, y, r]
    _dirty = true;
    if (now.difference(_lastSave).inMilliseconds >= 30000) {
      _prune(now);
      save();
      _lastSave = now;
    }
  }

  void _prune(DateTime now) {
    final cutoff = (now.millisecondsSinceEpoch - retentionMs) ~/ detailSlotMs;
    _slots.removeWhere((idx, _) => idx < cutoff);
  }

  /// Aggregate the internal 15s store into [windowMs]/[slotMs] display slots.
  List<SleepSlot> getSlots(DateTime now, int windowMs, int slotMs) {
    final nowMs = now.millisecondsSinceEpoch;
    final start = nowMs - windowMs;
    final out = <SleepSlot>[];
    for (var t = start; t < nowMs; t += slotMs) {
      var g = 0, y = 0, r = 0;
      final fromIdx = t ~/ detailSlotMs;
      final toIdx = (t + slotMs + detailSlotMs - 1) ~/ detailSlotMs; // ceil
      for (var i = fromIdx; i < toIdx; i++) {
        final s = _slots[i];
        if (s == null) continue;
        g += s[0];
        y += s[1];
        r += s[2];
      }
      out.add(SleepSlot(g, y, r));
    }
    return out;
  }

  /// Total seconds at each level over the window.
  SleepSlot getSummary(DateTime now, int windowMs) {
    final cutoff = (now.millisecondsSinceEpoch - windowMs) ~/ detailSlotMs;
    var g = 0, y = 0, r = 0;
    _slots.forEach((idx, s) {
      if (idx < cutoff) return;
      g += s[0];
      y += s[1];
      r += s[2];
    });
    return SleepSlot(g, y, r);
  }

  /// Transitions from a green-dominant minute to a non-green one — "wake events".
  int getWakeCount(DateTime now, int windowMs) {
    final slots = getSlots(now, windowMs, 60 * 1000);
    var count = 0;
    Band? prev;
    for (final s in slots) {
      if (!s.hasData) {
        prev = null;
        continue;
      }
      if (prev == Band.green && s.dominant != Band.green) count++;
      prev = s.dominant;
    }
    return count;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final data = jsonDecode(raw);
      final slots = data['slots'];
      if (slots is List) {
        _slots.clear();
        for (final entry in slots) {
          if (entry is List && entry.length == 2 && entry[1] is List) {
            _slots[entry[0] as int] = List<int>.from(entry[1] as List);
          }
        }
      }
      _prune(DateTime.now());
    } catch (_) {/* corrupt/unavailable — start fresh */}
  }

  Future<void> save() async {
    if (!_dirty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'slots': _slots.entries.map((e) => [e.key, e.value]).toList(),
          'savedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      _dirty = false;
    } catch (_) {/* ignore */}
  }

  void dispose() {
    _prune(DateTime.now());
    save();
  }
}
