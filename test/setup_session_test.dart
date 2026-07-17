import 'package:babylink_app/setup/setup_session.dart';
import 'package:babylink_app/store/app_store.dart';
import 'package:flutter_test/flutter_test.dart';

SavedRoom _room(String name) => SavedRoom(
      roomId: 'r1',
      ownerToken: 't',
      name: name,
      ssid: 'HomeWifi',
      serverHost: 'h.example',
      serverPort: 443,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('create-room flow (no target room)', () {
    test('device is named after the room', () {
      final s = SetupSession();
      s.roomName = '  Nursery  ';
      expect(s.effectiveRoomName, 'Nursery');
      expect(s.provisionDeviceName, 'Nursery');
    });

    test('empty room name falls back to the MAC-derived default', () {
      final s = SetupSession();
      // no info/mac in a unit test → default 'BabyLink'
      expect(s.effectiveRoomName, 'BabyLink');
      expect(s.provisionDeviceName, 'BabyLink');
    });
  });

  group('add-device flow (existing target room)', () {
    test('room keeps its name; the device takes the baby name', () {
      final s = SetupSession(targetRoom: _room('Kids Room'));
      s.babyName = '  Emma  ';
      // The room's display name is unchanged...
      expect(s.effectiveRoomName, 'Kids Room');
      // ...but the DEVICE provisions under the (trimmed) baby name, so multiple
      // devices in one room are told apart on the monitor.
      expect(s.provisionDeviceName, 'Emma');
    });

    test('no baby name → device falls back to the room name', () {
      final s = SetupSession(targetRoom: _room('Kids Room'));
      expect(s.provisionDeviceName, 'Kids Room');
    });

    test('buildConfig carries the per-device name', () {
      final s = SetupSession(targetRoom: _room('Kids Room'));
      s.babyName = 'Max';
      s.manualSsid = 'HomeWifi';
      final cfg = s.buildConfig();
      expect(cfg['deviceName'], 'Max');
      expect((cfg['servers'] as List).single['roomId'], 'r1');
    });
  });
}
