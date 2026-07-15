import 'package:babylink_app/monitor/alert_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlertTracker cry edges', () {
    test('fires once on the rising edge, not every tick', () {
      final t = AlertTracker();
      expect(t.update(id: 'a', stalled: false, live: true, level: 0.8, quietForMs: 0),
          contains(AlertEvent.cryStart));
      // Still crying → no further event.
      expect(t.update(id: 'a', stalled: false, live: true, level: 0.9, quietForMs: 0), isEmpty);
      expect(t.update(id: 'a', stalled: false, live: true, level: 0.7, quietForMs: 0), isEmpty);
    });

    test('does not re-arm on a brief dip (bursty crying stays one alert)', () {
      final t = AlertTracker(cryRearmMs: 6000);
      t.update(id: 'a', stalled: false, live: true, level: 0.8, quietForMs: 0);
      // Quiet, but not long enough to re-arm.
      expect(t.update(id: 'a', stalled: false, live: true, level: 0.1, quietForMs: 2000), isEmpty);
      // Loud again → no new cryStart because we never re-armed.
      expect(t.update(id: 'a', stalled: false, live: true, level: 0.8, quietForMs: 0), isEmpty);
    });

    test('re-arms after a long enough quiet, then fires again', () {
      final t = AlertTracker(cryRearmMs: 6000);
      t.update(id: 'a', stalled: false, live: true, level: 0.8, quietForMs: 0);
      expect(t.update(id: 'a', stalled: false, live: false, level: 0.0, quietForMs: 7000),
          contains(AlertEvent.cryStop));
      expect(t.update(id: 'a', stalled: false, live: true, level: 0.8, quietForMs: 0),
          contains(AlertEvent.cryStart));
    });

    test('level below threshold never fires', () {
      final t = AlertTracker(cryThreshold: 0.5);
      expect(t.update(id: 'a', stalled: false, live: true, level: 0.4, quietForMs: 0), isEmpty);
    });
  });

  group('AlertTracker offline edges', () {
    test('offline then online each fire exactly once', () {
      final t = AlertTracker();
      expect(t.update(id: 'a', stalled: true, live: false, level: 0, quietForMs: 9000),
          contains(AlertEvent.offline));
      // Still offline → silent.
      expect(t.update(id: 'a', stalled: true, live: false, level: 0, quietForMs: 9000), isEmpty);
      // Recovers.
      expect(t.update(id: 'a', stalled: false, live: true, level: 0.1, quietForMs: 0),
          contains(AlertEvent.online));
    });

    test('tracks two babies independently', () {
      final t = AlertTracker();
      t.update(id: 'a', stalled: true, live: false, level: 0, quietForMs: 9000);
      // b offline is its own edge even though a is already offline.
      expect(t.update(id: 'b', stalled: true, live: false, level: 0, quietForMs: 9000),
          contains(AlertEvent.offline));
    });

    test('forget lets the next drop alert again', () {
      final t = AlertTracker();
      t.update(id: 'a', stalled: true, live: false, level: 0, quietForMs: 9000);
      t.forget('a');
      expect(t.update(id: 'a', stalled: true, live: false, level: 0, quietForMs: 9000),
          contains(AlertEvent.offline));
    });
  });
}
