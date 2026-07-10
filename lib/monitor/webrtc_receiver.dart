import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Receives phone/browser baby audio over WebRTC, mirroring the web parent
/// (`multi-stream-manager.js`): the baby is always the offerer, we are the
/// answerer, all signaling rides one Socket.IO `signal` event, and we kick
/// each baby with `requestOffer`. ESP32 devices are NOT handled here — they
/// use the PCM path (their WebRTC can't complete on current firmware).
class WebRtcReceiver {
  final io.Socket socket;
  final String baseUrl; // e.g. https://host
  WebRtcReceiver(this.socket, this.baseUrl);

  final Map<String, _Peer> _peers = {};
  Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'}
    ],
  };

  // Callbacks into RoomConnection.
  void Function(String id, String name)? onLive;
  void Function(String id, double level)? onLevel;
  void Function(String id, bool connected)? onConnected;

  /// esp32 devices go over PCM, everyone else over WebRTC.
  static bool isWebrtcBaby(String socketId) => !socketId.startsWith('esp32_');

  Future<void> init() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/api/config/webrtc'));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        if (j is Map && j['iceServers'] is List) {
          _iceConfig = {'iceServers': j['iceServers']};
        }
      }
    } catch (_) {
      // Keep the STUN default — LAN-only rooms still connect.
    }
  }

  /// Ask a baby to (re)generate its offer to us.
  void requestOffer(String babyId) {
    socket.emit('signal', {'requestOffer': true, 'to': babyId});
  }

  Future<void> handleSignal(dynamic data) async {
    if (data is! Map) return;
    final fromId = data['fromSocketId']?.toString();
    if (fromId == null || !isWebrtcBaby(fromId)) return;

    final offer = data['offer'];
    final ice = data['ice'];
    // We never send offers, so any 'answer' here is not for us — ignore.

    try {
      var peer = _peers[fromId];
      if (peer == null && offer != null) {
        peer = await _createPeer(fromId, data['fromUserName']?.toString() ?? 'Baby');
      }
      if (peer == null) return;

      if (offer is Map) {
        await peer.pc.setRemoteDescription(
            RTCSessionDescription(offer['sdp']?.toString(), offer['type']?.toString()));
        final answer = await peer.pc.createAnswer();
        await peer.pc.setLocalDescription(answer);
        socket.emit('signal', {
          'answer': {'type': answer.type, 'sdp': answer.sdp},
          'to': fromId,
        });
      }

      if (ice is Map) {
        await peer.pc.addCandidate(RTCIceCandidate(
          ice['candidate']?.toString(),
          ice['sdpMid']?.toString(),
          (ice['sdpMLineIndex'] as num?)?.toInt(),
        ));
      }
    } catch (_) {
      // esp_peer/browser can emit a malformed offer on reconnect — drop the
      // peer and ask for a fresh one (breaker caps the retries).
      if (offer != null) _retryOffer(fromId);
    }
  }

  Future<_Peer> _createPeer(String id, String name) async {
    final pc = await createPeerConnection({
      ..._iceConfig,
      'sdpSemantics': 'unified-plan',
    });
    final peer = _Peer(pc, name);
    _peers[id] = peer;

    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        socket.emit('signal', {
          'ice': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
          'to': id,
        });
      }
    };
    pc.onTrack = (RTCTrackEvent e) {
      if (e.track.kind == 'audio') {
        peer.track = e.track;
        peer.retries = 0; // success — clear the breaker
        // Route to the loudspeaker — WebRTC defaults to the quiet earpiece.
        try {
          Helper.setSpeakerphoneOn(true);
        } catch (_) {}
        onLive?.call(id, name);
      }
    };
    pc.onConnectionState = (s) {
      onConnected?.call(id, s == RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) _retryOffer(id);
    };
    return peer;
  }

  void _retryOffer(String id) {
    final peer = _peers[id];
    if (peer == null || peer.retries >= 3) return;
    peer.retries++;
    try {
      peer.pc.close();
    } catch (_) {}
    _peers.remove(id);
    requestOffer(id);
  }

  bool has(String id) => _peers.containsKey(id);

  /// Playback volume 0..1 for a baby (0 = effectively muted, but the track
  /// keeps flowing so getStats can still drive auto-listen).
  void setVolume(String id, double v) {
    final t = _peers[id]?.track;
    if (t != null) {
      try {
        Helper.setVolume(v.clamp(0.0, 1.0), t);
      } catch (_) {}
    }
  }

  /// Poll each peer's inbound audio level (0..1) for meter + auto-listen.
  Future<void> pollLevels() async {
    for (final e in _peers.entries) {
      final t = e.value.track;
      if (t == null) continue;
      try {
        final reports = await e.value.pc.getStats(t);
        double? level;
        for (final r in reports) {
          final v = r.values['audioLevel'];
          if (v is num) {
            level = v.toDouble();
            if (r.type == 'inbound-rtp') break; // prefer the RTP-level reading
          }
        }
        if (level != null) onLevel?.call(e.key, level);
      } catch (_) {}
    }
  }

  void remove(String id) {
    final peer = _peers.remove(id);
    if (peer != null) {
      try {
        peer.pc.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    for (final p in _peers.values) {
      try {
        await p.pc.close();
      } catch (_) {}
    }
    _peers.clear();
  }
}

class _Peer {
  final RTCPeerConnection pc;
  final String name;
  MediaStreamTrack? track;
  int retries = 0;
  _Peer(this.pc, this.name);
}
