import '../ble/babylink_ble.dart';
import '../server/babylink_server.dart';
import '../store/app_store.dart';

/// Carries state across the setup wizard screens. One instance per setup run.
class SetupSession {
  final BabyLinkBle ble = BabyLinkBle();

  /// When set, we provision the device into this EXISTING room instead of
  /// creating a new one (the "add a device to a room" flow).
  final SavedRoom? targetRoom;
  SetupSession({this.targetRoom});

  /// Provision against the target room's own server (so a self-hosted room
  /// points its device at the right instance).
  BabyLinkServer get server => targetRoom != null
      ? BabyLinkServer(host: targetRoom!.serverHost, port: targetRoom!.serverPort)
      : const BabyLinkServer();

  DeviceInfo? info; // read on connect
  WifiNetwork? network; // chosen network
  String? manualSsid; // if entered by hand
  bool manualSecure = true;
  String? password;
  String roomName = ''; // what the user calls this room (home + monitor title)
  RoomCreation? room; // created on the server (only in the create-room flow)

  /// The room id we provision the device with — the existing room, or the
  /// freshly-created one.
  String get provisionRoomId => targetRoom?.roomId ?? room!.roomId;

  String get ssid => network?.ssid ?? manualSsid ?? '';
  bool get secure => network?.secure ?? manualSecure;

  /// The room's display name: the existing room, the user's choice, or a default.
  String get effectiveRoomName =>
      targetRoom?.name ?? (roomName.trim().isNotEmpty ? roomName.trim() : deviceName);

  /// The room link to share once a room exists — role-less, so the recipient
  /// can join as a parent or as a second baby device.
  String? get roomLink {
    final id = targetRoom?.roomId ?? room?.roomId;
    if (id == null) return null;
    final host = targetRoom?.serverHost ?? server.host;
    final port = targetRoom?.serverPort ?? server.port;
    final scheme = port == 443 ? 'https' : 'http';
    final authority = port == 443 ? host : '$host:$port';
    return '$scheme://$authority/$id';
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
            'roomId': provisionRoomId,
          }
        ],
      };
}
