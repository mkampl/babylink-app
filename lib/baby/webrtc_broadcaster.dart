import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Streams this phone's microphone to a room as a "baby", mirroring the web
/// baby (app.js `createPeerConnectionToParent`): we are the WebRTC OFFERER, one
/// peer connection per parent, all signaling over the single `signal` event.
class WebRtcBroadcaster {
  final io.Socket socket;
  final String baseUrl;
  WebRtcBroadcaster(this.socket, this.baseUrl);

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {}; // parentSocketId -> pc
  Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'}
    ],
  };
  bool _muted = false;

  void Function(double level)? onLevel; // local mic level 0..1
  void Function(int parents)? onParents;

  bool get muted => _muted;
  int get parentCount => _peers.length;

  /// Grab the mic and ICE config. Throws if the mic permission is denied.
  Future<void> start() async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/api/config/webrtc'));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        if (j is Map && j['iceServers'] is List) _iceConfig = {'iceServers': j['iceServers']};
      }
    } catch (_) {}
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    _applyMuteToTracks();
  }

  /// Offer our mic to a parent (idempotent — the web sends both a join event
  /// and a requestOffer, so guard against a double peer).
  Future<void> offerTo(String parentId) async {
    if (_localStream == null || _peers.containsKey(parentId)) return;
    final pc = await createPeerConnection({..._iceConfig, 'sdpSemantics': 'unified-plan'});
    _peers[parentId] = pc;
    for (final t in _localStream!.getTracks()) {
      await pc.addTrack(t, _localStream!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        socket.emit('signal', {
          'ice': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
          'to': parentId,
        });
      }
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        removeParent(parentId);
      }
    };
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket.emit('signal', {
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'to': parentId,
    });
    onParents?.call(parentCount);
  }

  Future<void> handleSignal(dynamic data) async {
    if (data is! Map) return;
    final fromId = data['fromSocketId']?.toString();
    if (fromId == null) return;
    if (data['requestOffer'] == true) {
      await offerTo(fromId);
      return;
    }
    final pc = _peers[fromId];
    if (pc == null) return;
    try {
      final answer = data['answer'];
      if (answer is Map) {
        await pc.setRemoteDescription(
            RTCSessionDescription(answer['sdp']?.toString(), answer['type']?.toString()));
      }
      final ice = data['ice'];
      if (ice is Map) {
        await pc.addCandidate(RTCIceCandidate(
          ice['candidate']?.toString(),
          ice['sdpMid']?.toString(),
          (ice['sdpMLineIndex'] as num?)?.toInt(),
        ));
      }
    } catch (_) {}
  }

  void removeParent(String id) {
    final pc = _peers.remove(id);
    if (pc != null) {
      try {
        pc.close();
      } catch (_) {}
      onParents?.call(parentCount);
    }
  }

  void setMuted(bool m) {
    _muted = m;
    _applyMuteToTracks();
  }

  void _applyMuteToTracks() {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_muted);
  }

  /// Local mic level (0..1) from the send-side media-source audioLevel — needs
  /// at least one peer connection to report stats.
  Future<void> pollLevel() async {
    if (_peers.isEmpty) return;
    try {
      final reports = await _peers.values.first.getStats();
      for (final r in reports) {
        if (r.type == 'media-source') {
          final al = r.values['audioLevel'];
          if (al is num) {
            onLevel?.call(al.toDouble());
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
  }
}
