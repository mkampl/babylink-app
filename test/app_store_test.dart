import 'package:babylink_app/store/app_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backs flutter_secure_storage with an in-memory map so AppStore's room
/// persistence can be tested without a platform.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> mem;

  SavedRoom room(String id, String name, String ssid) => SavedRoom(
        roomId: id,
        ownerToken: 't',
        name: name,
        ssid: ssid,
        serverHost: 'h.example',
        serverPort: 443,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  setUp(() {
    mem = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return mem[args['key']];
        case 'write':
          mem[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          mem.remove(args['key']);
          return null;
        case 'readAll':
          return Map<String, String>.from(mem);
        case 'deleteAll':
          mem.clear();
          return null;
        case 'containsKey':
          return mem.containsKey(args['key']);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('renameRoom changes only the name, other fields untouched', () async {
    await AppStore.instance.addRoom(room('a', 'Old', 'HomeWifi'));

    await AppStore.instance.renameRoom('a', 'New Name');

    final rooms = await AppStore.instance.loadRooms();
    expect(rooms.length, 1);
    expect(rooms.single.name, 'New Name');
    expect(rooms.single.ssid, 'HomeWifi'); // untouched
    expect(rooms.single.roomId, 'a');
    expect(rooms.single.serverPort, 443);
  });

  test('renameRoom on an unknown id is a no-op', () async {
    await AppStore.instance.addRoom(room('a', 'Old', 'HomeWifi'));

    await AppStore.instance.renameRoom('does-not-exist', 'X');

    final rooms = await AppStore.instance.loadRooms();
    expect(rooms.single.name, 'Old');
  });

  test('renameRoom leaves other rooms alone', () async {
    await AppStore.instance.addRoom(room('a', 'Room A', 'wifi-a'));
    await AppStore.instance.addRoom(room('b', 'Room B', 'wifi-b'));

    await AppStore.instance.renameRoom('a', 'Renamed A');

    final rooms = await AppStore.instance.loadRooms();
    final byId = {for (final r in rooms) r.roomId: r};
    expect(byId['a']!.name, 'Renamed A');
    expect(byId['b']!.name, 'Room B');
  });
}
