import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef PttStateCallback = void Function(Map<String, dynamic> event);
typedef PttErrorCallback = void Function(String message);

class PttWebRtcService {
  PttWebRtcService({required this.onState, required this.onError});

  final PttStateCallback onState;
  final PttErrorCallback onError;

  final Map<String, _PttPeer> _peers = {};
  final Map<String, MediaStream> _remoteStreams = {};

  WebSocket? _signalingSocket;
  Timer? _reconnectTimer;
  MediaStream? _localStream;
  MediaStreamTrack? _localAudioTrack;

  String _socketUrl = '';
  String _username = '';
  String _channelId = 'ch1';
  String _deviceId = '';
  String _selfClientId = '';

  bool _isManualDisconnect = false;
  bool _isTalking = false;
  bool _isConnecting = false;

  Future<void> connect({
    required String url,
    required String username,
    required String channelId,
    required String deviceId,
  }) async {
    if (_socketUrl != url || _username != username) {
      await _closeAllPeers();
      await _closeSignaling();
    }
    _socketUrl = url;
    _username = username;
    _channelId = channelId;
    _deviceId = deviceId;
    _isManualDisconnect = false;
    await _ensureLocalAudio();
    await _connectSignaling();
  }

  Future<void> updateChannel(String channelId) async {
    _channelId = channelId;
    await _closeAllPeers();
    if (_signalingSocket != null) {
      _send({
        'type': 'join',
        'username': _username,
        'channelId': _channelId,
        'deviceId': _deviceId,
      });
    } else {
      await _connectSignaling();
    }
  }

  Future<bool> startTalking() async {
    try {
      await _ensureLocalAudio();
      if (_signalingSocket == null) {
        await _connectSignaling();
      }
      if (_signalingSocket == null) {
        onError('Signaling WebRTC PTT belum tersambung.');
        return false;
      }
      _localAudioTrack?.enabled = true;
      _isTalking = true;
      _emitState(
        'recording',
        detail: 'PTT WebRTC aktif. Audio dikirim via peer connection.',
      );
      return true;
    } catch (_) {
      onError('Gagal mengaktifkan audio WebRTC PTT.');
      return false;
    }
  }

  Future<void> stopTalking() async {
    _isTalking = false;
    _localAudioTrack?.enabled = false;
    _emitState(
      _signalingSocket == null ? 'disconnected' : 'connected',
      detail: _signalingSocket == null
          ? 'Sinyal PTT terputus.'
          : 'PTT dilepas. Tetap standby di relay WebRTC.',
    );
  }

  Future<void> disconnect() async {
    _isManualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await stopTalking();
    await _closeAllPeers();
    await _closeSignaling();
    await _disposeLocalAudio();
    _emitState('disconnected', detail: 'PTT WebRTC dimatikan.');
  }

  Future<void> _ensureLocalAudio() async {
    if (_localAudioTrack != null && _localStream != null) {
      _localAudioTrack!.enabled = _isTalking;
      return;
    }
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    final audioTracks = stream.getAudioTracks();
    if (audioTracks.isEmpty) {
      throw StateError('Tidak ada track audio lokal.');
    }
    _localStream = stream;
    _localAudioTrack = audioTracks.first;
    _localAudioTrack!.enabled = false;
  }

  Future<void> _disposeLocalAudio() async {
    try {
      _localAudioTrack?.enabled = false;
    } catch (_) {}
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
  }

  Future<void> _connectSignaling() async {
    if (_socketUrl.isEmpty || _isConnecting) return;
    if (_signalingSocket != null) return;
    _isConnecting = true;
    _emitState('connecting', detail: 'Menghubungkan signaling WebRTC PTT...');
    try {
      final socket = await WebSocket.connect(_socketUrl);
      _signalingSocket = socket;
      _isConnecting = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _emitState('connected', detail: 'Signaling WebRTC PTT terhubung.');
      _send({
        'type': 'hello',
        'username': _username,
        'channelId': _channelId,
        'deviceId': _deviceId,
      });
      socket.listen(
        _handleSignalingMessage,
        onDone: _handleSignalingClosed,
        onError: (_) => _handleSignalingClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _isConnecting = false;
      _emitState(
        'reconnecting',
        detail: 'Gagal menghubungkan signaling WebRTC.',
      );
      _scheduleReconnect();
    }
  }

  void _handleSignalingClosed() {
    _signalingSocket = null;
    _isConnecting = false;
    _emitState(
      _isTalking ? 'reconnecting' : 'disconnected',
      detail: _isTalking
          ? 'Signaling WebRTC putus. Mencoba menyambung ulang...'
          : 'Signaling WebRTC terputus.',
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
          break;
        case 'peer-joined':
          final peer = Map<String, dynamic>.from(
            (message['peer'] as Map?)?.cast<String, dynamic>() ?? const {},
          );
          if ((peer['clientId'] as String? ?? '').isNotEmpty) {
            unawaited(_ensurePeer(peer));
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
    } catch (_) {}
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
      await _ensurePeer(peer);
    }
  }

  Future<void> _ensurePeer(Map<String, dynamic> peer) async {
    final clientId = peer['clientId'] as String? ?? '';
    if (clientId.isEmpty ||
        clientId == _selfClientId ||
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
    final pttPeer = _PttPeer(
      clientId: clientId,
      username: peer['username'] as String? ?? '',
      connection: pc,
    );
    _peers[clientId] = pttPeer;

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
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
    pc.onTrack = (event) {
      if (event.track.kind != 'audio') return;
      if (event.streams.isNotEmpty) {
        _remoteStreams[clientId] = event.streams.first;
      }
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        unawaited(_removePeer(clientId));
      }
    };

    if (_selfClientId.isNotEmpty && _selfClientId.compareTo(clientId) > 0) {
      await _createAndSendOffer(clientId, pc);
    }
  }

  Future<void> _createAndSendOffer(
    String clientId,
    RTCPeerConnection pc,
  ) async {
    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
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
    final peer = _peers[fromClientId];
    if (peer == null) {
      await _ensurePeer({
        'clientId': fromClientId,
        'username': envelope['fromUsername'] as String? ?? '',
      });
    }
    final currentPeer = _peers[fromClientId];
    if (currentPeer == null) return;
    final pc = currentPeer.connection;
    switch (data['kind'] as String? ?? '') {
      case 'sdp':
        final description = RTCSessionDescription(
          data['sdp'] as String? ?? '',
          data['type'] as String? ?? 'offer',
        );
        await pc.setRemoteDescription(description);
        if (description.type == 'offer') {
          final answer = await pc.createAnswer({
            'offerToReceiveAudio': true,
            'offerToReceiveVideo': false,
          });
          await pc.setLocalDescription(answer);
          _send({
            'type': 'signal',
            'targetClientId': fromClientId,
            'data': {'kind': 'sdp', 'type': answer.type, 'sdp': answer.sdp},
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
    final stream = _remoteStreams.remove(clientId);
    if (stream != null) {
      try {
        await stream.dispose();
      } catch (_) {}
    }
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
      'channelId': _channelId,
      'username': _username,
      'isCapturing': _isTalking,
      'isSocketOpen': _signalingSocket != null,
    });
  }
}

class _PttPeer {
  _PttPeer({
    required this.clientId,
    required this.username,
    required this.connection,
  });

  final String clientId;
  final String username;
  final RTCPeerConnection connection;
}
