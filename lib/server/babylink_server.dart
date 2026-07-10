import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to the BabyLink server so the app can create a room for the device
/// automatically — the user never has to know a server address or room id.
class BabyLinkServer {
  /// Default deployment. (Later: make this configurable in app settings.)
  final String host;
  final int port;

  const BabyLinkServer({this.host = 'babylink.itvoodoo.at', this.port = 443});

  /// Parse a user-entered address into a server. Accepts `host`, `host:port`,
  /// or a full `scheme://host:port` URL. Convention (used app-wide): port 443 =
  /// https, anything else = http — which covers a reverse-proxied instance on
  /// 443 and a plain LAN instance on a custom port.
  factory BabyLinkServer.parse(String input) {
    var s = input.trim();
    if (s.isEmpty) throw const HttpException('Enter a server address');
    if (!s.contains('://')) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) {
      throw const HttpException('That doesn’t look like a valid address');
    }
    final port = uri.hasPort ? uri.port : (uri.scheme == 'http' ? 80 : 443);
    return BabyLinkServer(host: uri.host, port: port);
  }

  bool get _https => port == 443;
  Uri _uri(String path) => _https
      ? Uri.https(host, path)
      : Uri(scheme: 'http', host: host, port: port, path: path);

  /// The base URL a person types/sees, e.g. https://host or http://host:3000.
  String get baseUrl => _https ? 'https://$host' : 'http://$host:$port';

  /// Probe a server to confirm it's a reachable BabyLink instance. Returns the
  /// reported version; throws with a friendly message otherwise.
  Future<String> probe() async {
    final http.Response res;
    try {
      res = await http.get(_uri('/health')).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw const HttpException('Couldn’t reach that server');
    }
    if (res.statusCode != 200) throw HttpException('Server returned ${res.statusCode}');
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'healthy') throw const HttpException('Not a BabyLink server');
      return (data['version'] ?? '?').toString();
    } catch (e) {
      if (e is HttpException) rethrow;
      throw const HttpException('That server didn’t respond like BabyLink');
    }
  }

  /// Create a room. Returns {roomId, ownerToken}. Throws on failure.
  Future<RoomCreation> createRoom(String name) async {
    final res = await http
        .post(
          _uri('/api/rooms'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw HttpException('Server returned ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final roomId = data['roomId']?.toString();
    if (roomId == null || roomId.isEmpty) {
      throw const HttpException('Server did not return a room id');
    }
    return RoomCreation(roomId: roomId, ownerToken: data['ownerToken']?.toString());
  }

  /// After the device reboots, poll until it shows up in the room. Returns true
  /// once online, false on timeout. (Uses the participants a joining client
  /// would see — the device appears as a 'baby'/esp32 participant.)
  Future<bool> waitForDeviceOnline(String roomId,
      {Duration timeout = const Duration(seconds: 40)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final res = await http
            .get(_uri('/api/esp32/status'))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final total = (data['totalClients'] as num?)?.toInt() ?? 0;
          if (total > 0) return true; // a device is connected to the server
        }
      } catch (_) {
        // keep polling
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }
}

class RoomCreation {
  final String roomId;
  final String? ownerToken;
  const RoomCreation({required this.roomId, this.ownerToken});
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
