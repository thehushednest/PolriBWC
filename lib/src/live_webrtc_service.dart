import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef LiveStateCallback = void Function(Map<String, dynamic> event);
typedef LiveErrorCallback = void Function(String message);

class LiveWebRtcService {
  LiveWebRtcService({required this.onState, required this.onError});

  final LiveStateCallback onState;
  final LiveErrorCallback onError;

  final Map<String, _LivePeer> _peers = {};

  WebSocket? _signalingSocket;
  Timer? _reconnectTimer;
  MediaStream? _localStream;
  MediaStreamTrack? _localAudioTrack;
  MediaStreamTrack? _localVideoTrack;
  RTCVideoRenderer? _localRenderer;

  String _socketUrl = '';
  String _username = '';
  String _sessionId = '';
  String _deviceId = '';
  String _selfClientId = '';

  bool _isManualDisconnect = false;
  bool _isConnecting = false;

  RTCVideoRenderer? get localRenderer => _localRenderer;

  Future<bool> connect({
    required String url,
    required String username,
    required String sessionId,
    required String deviceId,
  }) async {
    if (_socketUrl != url || _sessionId != sessionId || _username != username) {
      await disconnect();
    }
    _socketUrl = url;
    _username = username;
    _sessionId = sessionId;
    _deviceId = deviceId;
    _isManualDisconnect = false;

    try {
      await _ensureLocalMedia();
      await _connectSignaling();
      return _signalingSocket != null && _localStream != null;
    } catch (error) {
      onError('Gagal menyiapkan Live Cam WebRTC: $error');
      return false;
    }
  }

  Future<void> disconnect() async {
    _isManualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeAllPeers();
    await _closeSignaling();
    await _disposeLocalMedia();
    _selfClientId = '';
    _emitState('disconnected', detail: 'Live Cam WebRTC dimatikan.');
  }

  Future<void> _ensureLocalMedia() async {
    if (_localStream != null && _localRenderer != null) {
      return;
    }

    final renderer = _localRenderer ?? RTCVideoRenderer();
    if (_localRenderer == null) {
      await renderer.initialize();
      _localRenderer = renderer;
    }

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': {
        'facingMode': 'environment',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 15},
      },
    });
    final audioTracks = stream.getAudioTracks();
    final videoTracks = stream.getVideoTracks();
    if (audioTracks.isEmpty || videoTracks.isEmpty) {
      throw StateError('Track kamera atau mikrofon tidak tersedia.');
    }

    _localStream = stream;
    _localAudioTrack = audioTracks.first;
    _localVideoTrack = videoTracks.first;
    _localRenderer?.srcObject = stream;
    _emitState(
      'preview-ready',
      detail: 'Preview Live Cam kamera+mic sudah siap.',
    );
  }

  Future<void> _disposeLocalMedia() async {
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream.dispose();
      } catch (_) {}
    }
    _localStream = null;
    _localAudioTrack = null;
    _localVideoTrack = null;
    final renderer = _localRenderer;
    _localRenderer = null;
    if (renderer != null) {
      try {
        renderer.srcObject = null;
      } catch (_) {}
      try {
        await renderer.dispose();
      } catch (_) {}
    }
  }

  Future<void> _connectSignaling() async {
    if (_socketUrl.isEmpty || _isConnecting) return;
    if (_signalingSocket != null) return;
    _isConnecting = true;
    _emitState('connecting', detail: 'Menghubungkan signaling Live Cam...');
    try {
      final socket = await WebSocket.connect(_socketUrl);
      _signalingSocket = socket;
      _isConnecting = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _emitState('connected', detail: 'Signaling Live Cam tersambung.');
      _send({
        'type': 'hello',
        'sessionId': _sessionId,
        'username': _username,
        'deviceId': _deviceId,
        'role': 'broadcaster',
      });
      socket.listen(
        _handleSignalingMessage,
        onDone: _handleSignalingClosed,
        onError: (_) => _handleSignalingClosed(),
        cancelOnError: true,
      );
    } catch (error) {
      _isConnecting = false;
      _emitState('reconnecting', detail: 'Gagal menghubungkan Live Cam.');
      onError('Signaling Live Cam gagal: $error');
      _scheduleReconnect();
    }
  }

  void _handleSignalingClosed() {
    _signalingSocket = null;
    _isConnecting = false;
    unawaited(_closeAllPeers());
    _emitState(
      'reconnecting',
      detail: 'Signaling Live Cam terputus, mencoba menyambung ulang...',
    );
    if (!_isManualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isManualDisconnect || _reconnectTimer != null || _socketUrl.isEmpty) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _reconnectTimer = null;
      unawaited(_connectSignaling());
    });
  }

  void _handleSignalingMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      switch (message['type'] as String? ?? '') {
        case 'hello-ack':
          _selfClientId = message['clientId'] as String? ?? '';
          final peers = (message['peers'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    Map<String, dynamic>.from(item.cast<String, dynamic>()),
              )
              .toList();
          unawaited(_syncPeers(peers));
          _emitState(
            'streaming',
            detail: 'Live Cam standby realtime ke dashboard.',
          );
          break;
        case 'peer-joined':
          final peer = Map<String, dynamic>.from(
            (message['peer'] as Map?)?.cast<String, dynamic>() ?? const {},
          );
          if ((peer['clientId'] as String? ?? '').isNotEmpty) {
            unawaited(_ensurePeer(peer, createOffer: true));
          }
          break;
        case 'peer-left':
          final clientId = message['clientId'] as String? ?? '';
          if (clientId.isNotEmpty) {
            unawaited(_removePeer(clientId));
          }
          break;
        case 'signal':
          final fromClientId = message['fromClientId'] as String? ?? '';
          final data = Map<String, dynamic>.from(
            (message['data'] as Map?)?.cast<String, dynamic>() ?? const {},
          );
          if (fromClientId.isNotEmpty && data.isNotEmpty) {
            unawaited(_handlePeerSignal(fromClientId, data, message));
          }
          break;
        case 'ping':
          _send({'type': 'pong'});
          break;
      }
    } catch (error) {
      onError('Pesan signaling Live Cam tidak valid: $error');
    }
  }

  Future<void> _syncPeers(List<Map<String, dynamic>> peers) async {
    final liveIds = peers
        .map((item) => item['clientId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final clientId in _peers.keys.toList()) {
      if (!liveIds.contains(clientId)) {
        await _removePeer(clientId);
      }
    }
    for (final peer in peers) {
      await _ensurePeer(peer, createOffer: true);
    }
  }

  Future<void> _ensurePeer(
    Map<String, dynamic> peer, {
    required bool createOffer,
  }) async {
    final clientId = peer['clientId'] as String? ?? '';
    final role = peer['role'] as String? ?? 'viewer';
    if (clientId.isEmpty ||
        clientId == _selfClientId ||
        role == 'broadcaster' ||
        _peers.containsKey(clientId)) {
      return;
    }
    final pc = await createPeerConnection({
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
      'sdpSemantics': 'unified-plan',
    });
    final livePeer = _LivePeer(
      clientId: clientId,
      role: role,
      connection: pc,
    );
    _peers[clientId] = livePeer;

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _send({
        'type': 'signal',
        'targetClientId': clientId,
        'data': {'kind': 'candidate', 'candidate': candidate.toMap()},
      });
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        unawaited(_removePeer(clientId));
      }
    };

    if (createOffer) {
      await _createAndSendOffer(clientId, pc);
    }
  }

  Future<void> _createAndSendOffer(
    String clientId,
    RTCPeerConnection pc,
  ) async {
    final offer = await pc.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    await pc.setLocalDescription(offer);
    _send({
      'type': 'signal',
      'targetClientId': clientId,
      'data': {'kind': 'sdp', 'type': offer.type, 'sdp': offer.sdp},
    });
  }

  Future<void> _handlePeerSignal(
    String fromClientId,
    Map<String, dynamic> data,
    Map<String, dynamic> envelope,
  ) async {
    final existing = _peers[fromClientId];
    if (existing == null) {
      await _ensurePeer({
        'clientId': fromClientId,
        'role': envelope['fromRole'] as String? ?? 'viewer',
      }, createOffer: false);
    }
    final peer = _peers[fromClientId];
    if (peer == null) return;
    final pc = peer.connection;
    switch (data['kind'] as String? ?? '') {
      case 'sdp':
        final description = RTCSessionDescription(
          data['sdp'] as String? ?? '',
          data['type'] as String? ?? 'answer',
        );
        await pc.setRemoteDescription(description);
        if (description.type == 'offer') {
          final answer = await pc.createAnswer({
            'offerToReceiveAudio': false,
            'offerToReceiveVideo': false,
          });
          await pc.setLocalDescription(answer);
          _send({
            'type': 'signal',
            'targetClientId': fromClientId,
            'data': {
              'kind': 'sdp',
              'type': answer.type,
              'sdp': answer.sdp,
            },
          });
        }
        break;
      case 'candidate':
        final candidateMap = Map<String, dynamic>.from(
          (data['candidate'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
        final candidate = RTCIceCandidate(
          candidateMap['candidate'] as String?,
          candidateMap['sdpMid'] as String?,
          candidateMap['sdpMLineIndex'] as int?,
        );
        await pc.addCandidate(candidate);
        break;
    }
  }

  Future<void> _removePeer(String clientId) async {
    final peer = _peers.remove(clientId);
    if (peer != null) {
      try {
        await peer.connection.close();
      } catch (_) {}
    }
    _emitState(
      _signalingSocket == null ? 'reconnecting' : 'streaming',
      detail: _peers.isEmpty
          ? 'Live Cam aktif, menunggu viewer dashboard.'
          : 'Live Cam aktif ke ${_peers.length} viewer.',
    );
  }

  Future<void> _closeAllPeers() async {
    for (final clientId in _peers.keys.toList()) {
      await _removePeer(clientId);
    }
  }

  Future<void> _closeSignaling() async {
    final socket = _signalingSocket;
    _signalingSocket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  void _send(Map<String, dynamic> payload) {
    final socket = _signalingSocket;
    if (socket == null) return;
    try {
      socket.add(jsonEncode(payload));
    } catch (_) {
      _handleSignalingClosed();
    }
  }

  void _emitState(String state, {String detail = ''}) {
    onState({
      'state': state,
      'detail': detail,
      'sessionId': _sessionId,
      'isSocketOpen': _signalingSocket != null,
      'peerCount': _peers.length,
    });
  }
}

class _LivePeer {
  _LivePeer({
    required this.clientId,
    required this.role,
    required this.connection,
  });

  final String clientId;
  final String role;
  final RTCPeerConnection connection;
}
