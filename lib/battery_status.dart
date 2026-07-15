import 'package:battery_plus/battery_plus.dart';

/// A device's battery, as reported by a baby to the parent (or read for the
/// parent's own display). Small and JSON-friendly for the `baby-status` event.
class BatteryStatus {
  final int level; // 0..100
  final bool charging;
  const BatteryStatus(this.level, this.charging);
}

/// Thin wrapper over battery_plus so callers don't repeat the state mapping.
class BatteryReader {
  final Battery _battery = Battery();

  Future<BatteryStatus?> read() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final charging = state == BatteryState.charging || state == BatteryState.full;
      return BatteryStatus(level, charging);
    } catch (_) {
      return null; // some devices/emulators don't expose battery
    }
  }
}
