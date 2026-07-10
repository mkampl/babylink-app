import 'dart:convert';

import 'package:http/http.dart' as http;

import '../store/app_store.dart';

/// One ESP32 device connected to a room (owner view).
class EspDevice {
  final String id;
  final String name;
  final String? clientIp;
  final int uptimeMs;
  final int? sampleRate;
  final String? deviceType;
  EspDevice.fromJson(Map j)
      : id = j['id'].toString(),
        name = (j['name'] ?? 'BabyLink').toString(),
        clientIp = j['clientIp']?.toString(),
        uptimeMs = (j['uptime'] as num?)?.toInt() ?? 0,
        sampleRate = (j['sampleRate'] as num?)?.toInt(),
        deviceType = j['deviceType']?.toString();
}

/// A room's ntfy push configuration.
class NtfyConfig {
  String? server;
  String? topic;
  bool enabled;
  bool onCrying;
  bool onDisconnect;
  bool onActivity;
  NtfyConfig({
    this.server,
    this.topic,
    this.enabled = false,
    this.onCrying = true,
    this.onDisconnect = true,
    this.onActivity = false,
  });
  factory NtfyConfig.fromJson(Map j) => NtfyConfig(
        server: j['ntfyServer']?.toString(),
        topic: j['ntfyTopic']?.toString(),
        enabled: j['ntfyEnabled'] == true,
        onCrying: j['notifyOnCrying'] != false,
        onDisconnect: j['notifyOnDisconnect'] != false,
        onActivity: j['notifyOnActivity'] == true,
      );
}

/// Result of a public PIN check.
enum PinVerify { ok, wrong, locked }

/// REST client for room management: PIN, ESP32 devices, and ntfy — matching the
/// server's owner-authenticated endpoints (`Bearer ownerToken`). Thrown errors
/// carry the server message.
class RoomAdmin {
  final SavedRoom room;
  RoomAdmin(this.room);

  String get _base {
    final scheme = room.serverPort == 443 ? 'https' : 'http';
    final authority = room.serverPort == 443 ? room.serverHost : '${room.serverHost}:${room.serverPort}';
    return '$scheme://$authority/api/rooms/${room.roomId}';
  }

  Map<String, String> get _authJson => {
        'Content-Type': 'application/json',
        if (room.ownerToken != null) 'Authorization': 'Bearer ${room.ownerToken}',
      };

  Never _fail(http.Response r) {
    String msg = 'Request failed (${r.statusCode})';
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['error'] != null) msg = j['error'].toString();
    } catch (_) {}
    throw Exception(msg);
  }

  // ---- PIN ----
  Future<bool> hasPin() async {
    final r = await http.get(Uri.parse('$_base/pin'));
    if (r.statusCode != 200) return false;
    return jsonDecode(r.body)['hasPin'] == true;
  }

  Future<PinVerify> verifyPin(String pin) async {
    final r = await http.post(Uri.parse('$_base/pin/verify'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'pin': pin}));
    if (r.statusCode == 429) return PinVerify.locked;
    if (r.statusCode != 200) return PinVerify.wrong;
    return jsonDecode(r.body)['valid'] == true ? PinVerify.ok : PinVerify.wrong;
  }

  /// Set (6–8 digits) or remove (null) the PIN. Owner only.
  Future<void> setPin(String? pin) async {
    final r = await http.post(Uri.parse('$_base/pin'), headers: _authJson, body: jsonEncode({'pin': pin}));
    if (r.statusCode != 200) _fail(r);
  }

  // ---- ESP32 devices ----
  Future<List<EspDevice>> devices() async {
    final r = await http.get(Uri.parse('$_base/esp32/devices'), headers: _authJson);
    if (r.statusCode != 200) _fail(r);
    final list = jsonDecode(r.body)['devices'];
    return (list is List ? list : []).whereType<Map>().map(EspDevice.fromJson).toList();
  }

  Future<void> renameDevice(String id, String name) async {
    final r = await http.patch(Uri.parse('$_base/esp32/$id'), headers: _authJson, body: jsonEncode({'name': name}));
    if (r.statusCode != 200) _fail(r);
  }

  Future<void> disconnectDevice(String id) async {
    final r = await http.delete(Uri.parse('$_base/esp32/$id'), headers: _authJson);
    if (r.statusCode != 200) _fail(r);
  }

  Future<void> resetDevice(String id) async {
    final r = await http.post(Uri.parse('$_base/esp32/$id/reset'), headers: _authJson);
    if (r.statusCode != 200) _fail(r);
  }

  // ---- ntfy ----
  Future<NtfyConfig> getNtfy() async {
    final r = await http.get(Uri.parse('$_base/ntfy'), headers: _authJson);
    if (r.statusCode != 200) _fail(r);
    return NtfyConfig.fromJson(jsonDecode(r.body));
  }

  Future<void> setNtfy(NtfyConfig c) async {
    final r = await http.post(Uri.parse('$_base/ntfy'),
        headers: _authJson,
        body: jsonEncode({
          'topic': c.topic,
          'ntfyServer': c.server,
          'enabled': c.enabled,
          'notifyOnCrying': c.onCrying,
          'notifyOnDisconnect': c.onDisconnect,
          'notifyOnActivity': c.onActivity,
        }));
    if (r.statusCode != 200) _fail(r);
  }

  Future<void> testNtfy() async {
    final r = await http.post(Uri.parse('$_base/ntfy/test'), headers: _authJson);
    if (r.statusCode != 200) _fail(r);
  }
}
