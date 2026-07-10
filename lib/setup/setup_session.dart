import '../ble/babylink_ble.dart';
import '../server/babylink_server.dart';

/// Carries state across the setup wizard screens. One instance per setup run.
class SetupSession {
  final BabyLinkBle ble = BabyLinkBle();
  final BabyLinkServer server = const BabyLinkServer();

  DeviceInfo? info; // read on connect
  WifiNetwork? network; // chosen network
  String? manualSsid; // if entered by hand
  bool manualSecure = true;
  String? password;
  String roomName = ''; // what the user calls this room (home + monitor title)
  RoomCreation? room; // created on the server

  String get ssid => network?.ssid ?? manualSsid ?? '';
  bool get secure => network?.secure ?? manualSecure;

  /// The room's display name: the user's choice, or a sensible default.
  String get effectiveRoomName => roomName.trim().isNotEmpty ? roomName.trim() : deviceName;

  /// The room link to share once a room exists — role-less, so the recipient
  /// can join as a parent or as a second baby device.
  String? get roomLink {
    if (room == null) return null;
    final scheme = server.port == 443 ? 'https' : 'http';
    final authority = server.port == 443 ? server.host : '${server.host}:${server.port}';
    return '$scheme://$authority/${room!.roomId}';
  }

  /// Friendly device name derived from the MAC, shown on the parent screen.
  String get deviceName {
    final mac = info?.mac ?? '';
    final tail = mac.length >= 4 ? mac.substring(mac.length - 4).toUpperCase() : '';
    return tail.isEmpty ? 'BabyLink' : 'BabyLink $tail';
  }

  /// Build the config JSON the ESP expects (cfg_v3 shape).
  Map<String, dynamic> buildConfig() => {
        'deviceName': effectiveRoomName,
        'activeServer': 0,
        'wifi': [
          {'ssid': ssid, 'password': password ?? ''}
        ],
        'servers': [
          {
            'label': server.host,
            'host': server.host,
            'port': server.port,
            'roomId': room!.roomId,
          }
        ],
      };
}
