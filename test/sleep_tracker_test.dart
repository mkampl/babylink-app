import 'package:babylink_app/monitor/baby_stream.dart';
import 'package:babylink_app/monitor/sleep_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({}); // record() may trigger a save
  });

  final base = DateTime.utc(2026, 1, 1, 12, 0, 0); // minute-aligned

  test('summary counts seconds per level', () {
    final tr = SleepTracker('r', 'b');
    for (var i = 0; i < 10; i++) {
      tr.record(base.add(Duration(seconds: i)), 0.05); // green
    }
    for (var i = 10; i < 14; i++) {
      tr.record(base.add(Duration(seconds: i)), 0.3); // yellow
    }
    for (var i = 14; i < 16; i++) {
      tr.record(base.add(Duration(seconds: i)), 0.8); // red
    }
    final s = tr.getSummary(base.add(const Duration(seconds: 20)), 15 * 60 * 1000);
    expect(s.g, 10);
    expect(s.y, 4);
    expect(s.r, 2);
  });

  test('getSlots aggregates with highest-colour-wins dominant', () {
    final tr = SleepTracker('r', 'b');
    tr.record(base, 0.05); // green
    tr.record(base.add(const Duration(seconds: 1)), 0.8); // red in the same 15s slot
    final slots = tr.getSlots(base.add(const Duration(seconds: 30)), 60000, 15000);
    final withData = slots.where((s) => s.hasData).toList();
    expect(withData.length, 1);
    expect(withData.first.dominant, Band.red); // red wins over green
    expect(withData.first.g, 1);
    expect(withData.first.r, 1);
  });

  test('empty spans read as grey (no data), not asleep', () {
    final tr = SleepTracker('r', 'b');
    tr.record(base, 0.05);
    final slots = tr.getSlots(base.add(const Duration(minutes: 5)), 5 * 60 * 1000, 15000);
    expect(slots.any((s) => !s.hasData), isTrue);
    expect(slots.firstWhere((s) => !s.hasData).dominant, isNull);
  });

  test('wake count = green→non-green minute transitions', () {
    final tr = SleepTracker('r', 'b');
    for (var i = 0; i < 10; i++) {
      tr.record(base.add(Duration(seconds: i)), 0.05); // minute 0: green (asleep)
    }
    for (var i = 0; i < 10; i++) {
      tr.record(base.add(Duration(minutes: 1, seconds: i)), 0.3); // minute 1: movement (wake)
    }
    for (var i = 0; i < 10; i++) {
      tr.record(base.add(Duration(minutes: 2, seconds: i)), 0.05); // minute 2: green again
    }
    expect(tr.getWakeCount(base.add(const Duration(minutes: 3)), 15 * 60 * 1000), 1);
  });
}
