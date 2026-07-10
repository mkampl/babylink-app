import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../server/babylink_server.dart';

/// A room the user created for a device, with everything needed to share it and
/// (later) manage it.
class SavedRoom {
  final String roomId;
  final String? ownerToken; // for future management (rename, PIN, delete)
  final String name; // device / room name
  final String ssid; // the WiFi it was put on
  final String serverHost;
  final int serverPort;
  final DateTime createdAt;

  SavedRoom({
    required this.roomId,
    required this.ownerToken,
    required this.name,
    required this.ssid,
    required this.serverHost,
    required this.serverPort,
    required this.createdAt,
  });

  /// The room link to share. Deliberately role-less (no ?role=parent) so the
  /// recipient lands on the role picker and can join as a parent OR use their
  /// phone as a second baby device.
  String get roomLink {
    final scheme = serverPort == 443 ? 'https' : 'http';
    final authority = serverPort == 443 ? serverHost : '$serverHost:$serverPort';
    return '$scheme://$authority/$roomId';
  }

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'ownerToken': ownerToken,
        'name': name,
        'ssid': ssid,
        'serverHost': serverHost,
        'serverPort': serverPort,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedRoom.fromJson(Map<String, dynamic> j) => SavedRoom(
        roomId: j['roomId'].toString(),
        ownerToken: j['ownerToken']?.toString(),
        name: (j['name'] ?? 'BabyLink').toString(),
        ssid: (j['ssid'] ?? '').toString(),
        serverHost: (j['serverHost'] ?? 'babylink.itvoodoo.at').toString(),
        serverPort: (j['serverPort'] is num) ? (j['serverPort'] as num).toInt() : 443,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// Local, encrypted persistence for rooms + saved WiFi credentials.
class AppStore {
  AppStore._();
  static final AppStore instance = AppStore._();

  static const _storage = FlutterSecureStorage();
  static const _kRooms = 'rooms_v1';
  static const _kWifi = 'wifi_v1';
  static const _kServer = 'server_v1';

  // ---- Server (self-hosting): the default instance for NEW rooms/devices.
  // itvoodoo.at is just the public demo; existing rooms keep their own server.
  Future<BabyLinkServer> currentServer() async {
    final raw = await _storage.read(key: _kServer);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw) as Map;
        final host = j['host']?.toString();
        final port = (j['port'] as num?)?.toInt();
        if (host != null && host.isNotEmpty && port != null) {
          return BabyLinkServer(host: host, port: port);
        }
      } catch (_) {}
    }
    return const BabyLinkServer();
  }

  Future<bool> isCustomServer() async {
    final raw = await _storage.read(key: _kServer);
    return raw != null && raw.isNotEmpty;
  }

  Future<void> setServer(String host, int port) async {
    await _storage.write(key: _kServer, value: jsonEncode({'host': host, 'port': port}));
  }

  Future<void> resetServer() async => _storage.delete(key: _kServer);

  // ---- Rooms ----
  Future<List<SavedRoom>> loadRooms() async {
    final raw = await _storage.read(key: _kRooms);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final rooms = list.whereType<Map<String, dynamic>>().map(SavedRoom.fromJson).toList();
      rooms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rooms;
    } catch (_) {
      return [];
    }
  }

  Future<void> addRoom(SavedRoom room) async {
    final rooms = await loadRooms();
    rooms.removeWhere((r) => r.roomId == room.roomId);
    rooms.insert(0, room);
    await _storage.write(key: _kRooms, value: jsonEncode(rooms.map((r) => r.toJson()).toList()));
  }

  Future<void> deleteRoom(String roomId) async {
    final rooms = await loadRooms();
    rooms.removeWhere((r) => r.roomId == roomId);
    await _storage.write(key: _kRooms, value: jsonEncode(rooms.map((r) => r.toJson()).toList()));
  }

  // ---- Saved WiFi credentials (ssid -> password) ----
  Future<Map<String, String>> _wifiMap() async {
    final raw = await _storage.read(key: _kWifi);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveWifi(String ssid, String password) async {
    if (ssid.isEmpty) return;
    final map = await _wifiMap();
    map[ssid] = password;
    await _storage.write(key: _kWifi, value: jsonEncode(map));
  }

  Future<String?> wifiPassword(String ssid) async => (await _wifiMap())[ssid];

  Future<List<String>> savedSsids() async => (await _wifiMap()).keys.toList();

  Future<void> forgetWifi(String ssid) async {
    final map = await _wifiMap();
    map.remove(ssid);
    await _storage.write(key: _kWifi, value: jsonEncode(map));
  }
}
