import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _defaultHost = '0.0.0.0';
const _defaultPort = 8787;

// Resolusi path data/ relatif terhadap lokasi file script ini,
// sehingga server bisa dijalankan dari direktori manapun.
// Mengembalikan path ke file di dalam direktori data/ server,
// atau direktori data/ itu sendiri jika filename kosong.
String _dataPath([String filename = '']) {
  final scriptDir = File(Platform.script.toFilePath()).parent.parent;
  final base = '${scriptDir.path}/data';
  return filename.isEmpty ? base : '$base/$filename';
}

String _resolvePublicWebSocketUrl(HttpRequest request, String path) {
  final forwardedProto = request.headers.value('x-forwarded-proto');
  final scheme = forwardedProto == 'https' ? 'wss' : 'ws';
  final host = request.headers.host ?? request.requestedUri.host;
  final prefix = request.headers.value('x-forwarded-prefix') ?? '';
  final normalizedPrefix = prefix.endsWith('/')
      ? prefix.substring(0, prefix.length - 1)
      : prefix;
  return '$scheme://$host$normalizedPrefix$path';
}

const _dashboardSessionCookieName = 'polri_bwc_dashboard_session';
const _dashboardOtpCookieName = 'polri_bwc_dashboard_otp';
const _dashboardAdminUsername = 'admin';
const _dashboardAdminPassword = 'admin';
const _dashboardAdminPhoneDisplay = '08131850060';
const _dashboardAdminPhoneWhatsApp = '628131850060';
const _dashboardOtpHttpBaseUrl = 'http://127.0.0.1:8030';
const _dashboardOtpHttpBearerToken =
    'f7a10e21ab3b9af1024aae4930007d721e9d18e4771c2f3b90ba581f62dca0aa';

Future<void> main(List<String> args) async {
  final options = _ServerOptions.fromArgs(args);
  final store = await LocalServerStore.load();
  final dashboardAuth = DashboardAuthManager();
  final server = await HttpServer.bind(options.host, options.port);
  final canRelayAudio = (String channelId, String username) {
    final session = _activeSessionForChannel(store.state, channelId);
    if (session == null) return false;
    return (session['officerId'] as String? ?? '') == username;
  };
  final audioRelay = PttAudioRelayServer(
    host: options.host,
    port: options.port + 1,
    canRelayAudio: canRelayAudio,
  );
  final audioWebSocketRelay = PttAudioWebSocketRelay(
    canRelayAudio: canRelayAudio,
  );
  final pttSignalingRelay = PttWebRtcSignalingRelay();
  final liveSignalingRelay = LiveWebRtcSignalingRelay();
  final liveWebSocketRelay = LiveMonitorWebSocketRelay(
    initialSessions: _resolvedLiveSessions(store),
  );
  await audioRelay.start();
  Timer.periodic(const Duration(seconds: 8), (_) {
    _printPresenceSnapshot(store, reason: 'monitor');
  });

  stdout.writeln(
    'Polri BWC local server berjalan di http://${options.host}:${options.port}/api/v1',
  );
  stdout.writeln(
    'Polri BWC PTT audio relay berjalan di tcp://${options.host}:${options.port + 1}',
  );
  _printPresenceSnapshot(store, reason: 'startup');

  await for (final request in server) {
    unawaited(
      _handleRequest(
        request,
        store,
        audioWebSocketRelay,
        pttSignalingRelay,
        liveSignalingRelay,
        liveWebSocketRelay,
        dashboardAuth,
      ),
    );
  }
}

Future<void> _handleRequest(
  HttpRequest request,
  LocalServerStore store,
  PttAudioWebSocketRelay audioWebSocketRelay,
  PttWebRtcSignalingRelay pttSignalingRelay,
  LiveWebRtcSignalingRelay liveSignalingRelay,
  LiveMonitorWebSocketRelay liveWebSocketRelay,
  DashboardAuthManager dashboardAuth,
) async {
  final response = request.response;

  final path = request.uri.path;
  final method = request.method.toUpperCase();
  final dashboardBasePath = _dashboardBasePath(request);

  try {
    if (path == '/api/v1/ptt/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await audioWebSocketRelay.handleUpgrade(request);
      return;
    }

    if (path == '/api/v1/ptt/signal/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await pttSignalingRelay.handleUpgrade(request);
      return;
    }

    if (path == '/api/v1/live/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await liveWebSocketRelay.handleUpgrade(request);
      return;
    }

    if (path == '/api/v1/live/signal/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await liveSignalingRelay.handleUpgrade(request);
      return;
    }

    _applyCors(response);

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    if (method == 'GET' && path == '/dashboard/login') {
      final otpToken = _readCookie(request, _dashboardOtpCookieName);
      final otpChallenge = dashboardAuth._lookupOtpChallenge(otpToken);
      response.headers.contentType = ContentType.html;
      response.write(
        _buildDashboardLoginPage(
          dashboardBasePath: dashboardBasePath,
          invalidCredentials: request.uri.queryParameters['error'] == 'invalid',
          otpRequested: otpChallenge != null,
          invalidOtp: request.uri.queryParameters['error'] == 'otp',
          otpDeliveryFailed: request.uri.queryParameters['error'] == 'delivery',
        ),
      );
      await response.close();
      return;
    }

    if (method == 'POST' && path == '/dashboard/login') {
      final form = await _readForm(request);
      final otpCode = (form['otp'] ?? '').trim();
      final otpToken = _readCookie(request, _dashboardOtpCookieName);

      if (otpCode.isNotEmpty && otpToken.isNotEmpty) {
        final verified = dashboardAuth.verifyOtp(otpToken, otpCode);
        if (verified) {
          final token = dashboardAuth.issueToken();
          response.cookies.add(
            Cookie(_dashboardSessionCookieName, token)
              ..httpOnly = true
              ..sameSite = SameSite.lax
              ..path = dashboardBasePath.isEmpty ? '/' : '$dashboardBasePath/',
          );
          response.cookies.add(
            Cookie(_dashboardOtpCookieName, '')
              ..expires = DateTime.fromMillisecondsSinceEpoch(0)
              ..httpOnly = true
              ..sameSite = SameSite.lax
              ..path = dashboardBasePath.isEmpty ? '/' : '$dashboardBasePath/',
          );
          response.statusCode = HttpStatus.found;
          response.headers.set(
            'Location',
            _withDashboardBase(dashboardBasePath, '/dashboard'),
          );
          await response.close();
          return;
        }
        response.statusCode = HttpStatus.found;
        response.headers.set(
          'Location',
          _withDashboardBase(dashboardBasePath, '/dashboard/login?error=otp'),
        );
        await response.close();
        return;
      }

      final username = (form['username'] ?? '').trim();
      final password = (form['password'] ?? '').trim();
      if (username == _dashboardAdminUsername &&
          password == _dashboardAdminPassword) {
        final challenge = dashboardAuth._issueOtpChallenge(
          phoneNumber: _dashboardAdminPhoneWhatsApp,
        );
        final sent = await _sendDashboardOtpViaWhatsApp(challenge.code);
        if (!sent) {
          dashboardAuth._revokeOtpChallenge(challenge.challengeToken);
          response.statusCode = HttpStatus.found;
          response.headers.set(
            'Location',
            _withDashboardBase(
              dashboardBasePath,
              '/dashboard/login?error=delivery',
            ),
          );
          await response.close();
          return;
        }
        response.cookies.add(
          Cookie(_dashboardOtpCookieName, challenge.challengeToken)
            ..httpOnly = true
            ..sameSite = SameSite.lax
            ..path = dashboardBasePath.isEmpty ? '/' : '$dashboardBasePath/',
        );
        response.statusCode = HttpStatus.found;
        response.headers.set(
          'Location',
          _withDashboardBase(dashboardBasePath, '/dashboard/login'),
        );
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.found;
      response.headers.set(
        'Location',
        _withDashboardBase(dashboardBasePath, '/dashboard/login?error=invalid'),
      );
      await response.close();
      return;
    }

    if (method == 'GET' && path == '/dashboard/logout') {
      final existingToken = _readCookie(request, _dashboardSessionCookieName);
      if (existingToken.isNotEmpty) {
        dashboardAuth.revokeToken(existingToken);
      }
      response.cookies.add(
        Cookie(_dashboardSessionCookieName, '')
          ..expires = DateTime.fromMillisecondsSinceEpoch(0)
          ..httpOnly = true
          ..sameSite = SameSite.lax
          ..path = dashboardBasePath.isEmpty ? '/' : '$dashboardBasePath/',
      );
      response.cookies.add(
        Cookie(_dashboardOtpCookieName, '')
          ..expires = DateTime.fromMillisecondsSinceEpoch(0)
          ..httpOnly = true
          ..sameSite = SameSite.lax
          ..path = dashboardBasePath.isEmpty ? '/' : '$dashboardBasePath/',
      );
      response.statusCode = HttpStatus.found;
      response.headers.set(
        'Location',
        _withDashboardBase(dashboardBasePath, '/dashboard/login'),
      );
      await response.close();
      return;
    }

    if (method == 'GET' && path == '/dashboard') {
      final token = _readCookie(request, _dashboardSessionCookieName);
      if (!dashboardAuth.isValid(token)) {
        response.statusCode = HttpStatus.found;
        response.headers.set(
          'Location',
          _withDashboardBase(dashboardBasePath, '/dashboard/login'),
        );
        await response.close();
        return;
      }
      final htmlFile = File(_dataPath('dashboard.html'));
      if (!await htmlFile.exists()) {
        response.statusCode = HttpStatus.notFound;
        response.write('Dashboard file not found');
        await response.close();
        return;
      }
      response.headers.contentType = ContentType.html;
      response.write(await htmlFile.readAsString());
      await response.close();
      return;
    }

    if (method == 'GET' && path == '/api/v1/health') {
      return _writeJson(response, {
        'status': 'ok',
        'service': 'polri-bwc-local-server',
        'time': DateTime.now().toUtc().toIso8601String(),
        'onlineCount': _resolvedPresenceEntries(
          store,
        ).where((e) => e['resolvedStatus'] == 'online').length,
        'totalDevices': store.state.presence.length,
        'liveCount': _resolvedLiveSessions(store).length,
        'recordingCount': store.state.recordings.length,
        'reportCount': store.state.reports.length,
      });
    }

    if (method == 'POST' && path == '/api/v1/auth/login') {
      final body = await _readJson(request);
      final username = (body['username'] as String? ?? '').trim();
      final password = (body['password'] as String? ?? '').trim();
      if (username.isEmpty || password.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        return _writeJson(response, {
          'error': 'username dan password wajib diisi',
        });
      }
      final user = store.state.users[username];
      if (user == null || (user['password'] as String? ?? '') != password) {
        response.statusCode = HttpStatus.unauthorized;
        return _writeJson(response, {'error': 'Username atau password salah'});
      }
      stdout.writeln('[${_clockNow()}][auth] login berhasil: $username');
      return _writeJson(response, {
        'officerName': user['officerName'],
        'rankLabel': user['rankLabel'],
        'unitName': user['unitName'],
        'shiftLabel': user['shiftLabel'],
        'shiftWindow': user['shiftWindow'],
        'nrp': user['nrp'] ?? username,
      });
    }

    if (method == 'GET' && path == '/api/v1/presence') {
      final channelId = request.uri.queryParameters['channelId'] ?? '';
      final items = _resolvedPresenceEntries(store, channelId: channelId);
      return _writeJson(response, items);
    }

    if (method == 'POST' && path == '/api/v1/presence/heartbeat') {
      final body = await _readJson(request);
      final username = body['username'] as String? ?? '';
      if (username.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        return _writeJson(response, {'error': 'username required'});
      }
      final existing = store.state.presence[username] ?? const {};
      final updated = {
        ...store.state.presence,
        username: {
          'username': username,
          'deviceId': body['deviceId'] ?? '',
          'status': body['status'] ?? 'online',
          'activeChannelId': body['activeChannelId'] ?? '',
          'clientTimeIso': body['clientTimeIso'] ?? '',
          'lastSeenIso': DateTime.now().toUtc().toIso8601String(),
          // Pertahankan koordinat lama jika tidak ada yang baru dikirim
          'latitude': body['latitude'] ?? existing['latitude'],
          'longitude': body['longitude'] ?? existing['longitude'],
        },
      };
      var nextState = store.state.copyWith(presence: updated);
      nextState = _cleanupStalePttSessions(nextState);
      final status = body['status'] as String? ?? 'online';
      if (status == 'offline') {
        nextState = _releaseOfficerFloor(nextState, username);
        nextState = _releaseOfficerLiveSessions(nextState, username);
      }
      store.state = nextState;
      await store.save();
      _printPresenceSnapshot(store, reason: 'heartbeat');
      return _writeJson(response, {'status': 'ok'});
    }

    if (method == 'GET' && path == '/api/v1/live/sessions') {
      return _writeJson(response, _resolvedLiveSessions(store));
    }

    if (method == 'POST' && path == '/api/v1/live/sessions') {
      final body = await _readJson(request);
      final officerId = body['officerId'] as String? ?? '';
      if (officerId.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        return _writeJson(response, {'error': 'officerId required'});
      }
      final preferredTransport =
          body['preferredTransport'] as String? ?? 'snapshot';
      final fallbackTransport =
          body['fallbackTransport'] as String? ?? 'snapshot';
      final transport = preferredTransport == 'webrtc'
          ? 'webrtc'
          : fallbackTransport;
      final signalingUrl =
          body['signalingUrl'] as String? ??
          _resolvePublicWebSocketUrl(request, '/api/v1/live/signal/ws');
      final sessionId =
          'LIVE_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:.TZ]'), '')}';
      final liveSession = <String, dynamic>{
        'sessionId': sessionId,
        'officerId': officerId,
        'officerName': body['officerName'] as String? ?? officerId,
        'deviceId': body['deviceId'] as String? ?? '',
        'status': 'live',
        'startedAtIso': DateTime.now().toUtc().toIso8601String(),
        'locationLabel':
            body['locationLabel'] as String? ?? 'Lokasi tidak tersedia',
        'tagLabel': body['tagLabel'] as String? ?? 'Lainnya',
        'channelId': body['channelId'] as String? ?? '',
        'latitude': body['latitude'],
        'longitude': body['longitude'],
        'lastFrameAtIso': '',
        'frameDataUrl': '',
        'frameCount': 0,
        'transport': transport,
        'signalingUrl': signalingUrl,
        'viewerUrl': '${dashboardBasePath.isEmpty ? '' : dashboardBasePath}/dashboard',
        'signalingState': transport == 'webrtc' ? 'ready' : 'snapshot',
      };
      final updatedLive =
          Map<String, Map<String, dynamic>>.from(store.state.liveSessions)
            ..removeWhere(
              (_, value) => (value['officerId'] as String? ?? '') == officerId,
            )
            ..[sessionId] = liveSession;
      store.state = store.state.copyWith(liveSessions: updatedLive);
      await store.save();
      liveWebSocketRelay.broadcastSnapshot(_resolvedLiveSessions(store));
      stdout.writeln(
        '[${_clockNow()}][live-start] $officerId membuka live session $sessionId',
      );
      return _writeJson(response, liveSession);
    }

    if (method == 'POST' && path == '/api/v1/live/sessions/frame') {
      final body = await _readJson(request);
      final sessionId = body['sessionId'] as String? ?? '';
      if (sessionId.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        return _writeJson(response, {'error': 'sessionId required'});
      }
      final current = store.state.liveSessions[sessionId];
      if (current == null || current.isEmpty) {
        response.statusCode = HttpStatus.notFound;
        return _writeJson(response, {'error': 'live session not found'});
      }
      final updatedLive = Map<String, Map<String, dynamic>>.from(
        store.state.liveSessions,
      );
      final frameCount = (current['frameCount'] as int? ?? 0) + 1;
      updatedLive[sessionId] = {
        ...current,
        'frameDataUrl': body['frameDataUrl'] as String? ?? '',
        'lastFrameAtIso': DateTime.now().toUtc().toIso8601String(),
        'frameCount': frameCount,
        'latitude': body['latitude'] ?? current['latitude'],
        'longitude': body['longitude'] ?? current['longitude'],
        'locationLabel': body['locationLabel'] ?? current['locationLabel'],
        'tagLabel': body['tagLabel'] ?? current['tagLabel'],
      };
      store.state = store.state.copyWith(liveSessions: updatedLive);
      stdout.writeln(
        '[${_clockNow()}][live-frame] session=$sessionId officer=${current['officerId'] ?? '-'} frame=$frameCount bytes=${(body['frameDataUrl'] as String? ?? '').length}',
      );
      liveWebSocketRelay.broadcastFrame(updatedLive[sessionId]!);
      return _writeJson(response, {
        'status': 'ok',
        'sessionId': sessionId,
        'frameCount': frameCount,
      });
    }

    if (method == 'POST' && path == '/api/v1/live/sessions/stop') {
      final body = await _readJson(request);
      final sessionId = body['sessionId'] as String? ?? '';
      final officerId = body['officerId'] as String? ?? '';
      final updatedLive = Map<String, Map<String, dynamic>>.from(
        store.state.liveSessions,
      );
      var removed = false;
      if (sessionId.isNotEmpty && updatedLive.remove(sessionId) != null) {
        removed = true;
      } else if (officerId.isNotEmpty) {
        final targetKey = updatedLive.entries
            .firstWhere(
              (entry) =>
                  (entry.value['officerId'] as String? ?? '') == officerId,
              orElse: () => const MapEntry('', <String, dynamic>{}),
            )
            .key;
        if (targetKey.isNotEmpty) {
          updatedLive.remove(targetKey);
          removed = true;
        }
      }
      store.state = store.state.copyWith(liveSessions: updatedLive);
      await store.save();
      liveWebSocketRelay.broadcastSnapshot(_resolvedLiveSessions(store));
      stdout.writeln(
        '[${_clockNow()}][live-stop] ${(officerId.isEmpty ? sessionId : officerId)} menghentikan live session',
      );
      return _writeJson(response, {'status': removed ? 'stopped' : 'idle'});
    }

    if (method == 'GET' && path == '/api/v1/chats') {
      return _writeJson(response, store.state.chatThreads);
    }

    if (method == 'POST' && path == '/api/v1/chats') {
      final body = await _readJson(request);
      final threads = (body['threads'] as Map<String, dynamic>? ?? {}).map(
        (key, value) =>
            MapEntry(key, List<Map<String, dynamic>>.from(value as List)),
      );
      store.state = store.state.copyWith(chatThreads: threads);
      await store.save();
      return _writeJson(response, {'status': 'saved'});
    }

    if (method == 'POST' && path == '/api/v1/chats/message') {
      final body = await _readJson(request);
      final threadName = body['threadName'] as String? ?? 'Unknown';
      final message = Map<String, dynamic>.from(body['message'] as Map? ?? {});
      final current = [
        ...(store.state.chatThreads[threadName] ?? <Map<String, dynamic>>[]),
      ];
      current.add(message);
      final updated = {...store.state.chatThreads, threadName: current};
      store.state = store.state.copyWith(chatThreads: updated);
      await store.save();
      return _writeJson(response, {'status': 'appended'});
    }

    if (method == 'POST' && path == '/api/v1/chats/auto-reply') {
      final body = await _readJson(request);
      final threadName = body['threadName'] as String? ?? 'Unknown';
      final current = [
        ...(store.state.chatThreads[threadName] ?? <Map<String, dynamic>>[]),
      ];
      current.add({
        'fromMe': false,
        'text': _autoReplies[DateTime.now().millisecond % _autoReplies.length],
        'timeLabel': _clockNow(),
      });
      final updated = {...store.state.chatThreads, threadName: current};
      store.state = store.state.copyWith(chatThreads: updated);
      await store.save();
      return _writeJson(response, {'messages': current});
    }

    if (method == 'GET' && path == '/api/v1/reports') {
      return _writeJson(response, store.state.reports);
    }

    if (method == 'POST' && path == '/api/v1/reports') {
      final body = await _readJson(request);
      final reports = [Map<String, dynamic>.from(body), ...store.state.reports];
      store.state = store.state.copyWith(reports: reports);
      await store.save();
      return _writeJson(response, {'status': 'saved'});
    }

    if (method == 'GET' && path == '/api/v1/sos') {
      return _writeJson(response, store.state.sosAlerts);
    }

    if (method == 'POST' && path == '/api/v1/sos') {
      final body = await _readJson(request);
      final officerId = body['officerId'] as String? ?? '';
      final officerName = body['officerName'] as String? ?? officerId;
      final channelId = body['channelId'] as String? ?? '';
      final locationLabel =
          body['locationLabel'] as String? ?? 'Lokasi tidak tersedia';
      final alert = <String, dynamic>{
        'id':
            'SOS_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:.TZ]'), '')}',
        'officerId': officerId,
        'officerName': officerName,
        'deviceId': body['deviceId'] as String? ?? '',
        'channelId': channelId,
        'status': 'new',
        'triggeredAtIso': DateTime.now().toUtc().toIso8601String(),
        'locationLabel': locationLabel,
        'source': body['source'] as String? ?? 'app',
        'latitude': body['latitude'],
        'longitude': body['longitude'],
        'recordingId': body['recordingId'] as String? ?? '',
        'targetOfficerId': body['targetOfficerId'] as String? ?? '',
        'notes': body['notes'] as String? ?? '',
      };
      final alerts = [alert, ...store.state.sosAlerts].take(50).toList();
      store.state = store.state.copyWith(sosAlerts: alerts);
      await store.save();
      stdout.writeln(
        '[${_clockNow()}][SOS] ${officerId.isEmpty ? 'unknown' : officerId} @ ${channelId.isEmpty ? '-' : channelId.toUpperCase()} | $locationLabel',
      );
      return _writeJson(response, alert);
    }

    if (method == 'GET' && path == '/api/v1/recordings') {
      return _writeJson(response, store.state.recordings);
    }

    if (method == 'POST' && path == '/api/v1/recordings') {
      final body = await _readJson(request);
      final recordings = [
        Map<String, dynamic>.from(body),
        ...store.state.recordings,
      ];
      store.state = store.state.copyWith(recordings: recordings);
      await store.save();
      return _writeJson(response, {'status': 'saved'});
    }

    if (method == 'POST' && path == '/api/v1/recordings/upload') {
      final body = await _readJson(request);
      return _writeJson(response, {
        'recordingId': body['recordingId'],
        'status': 'syncing',
        'syncProgress': body['chunkCount'] == null
            ? 25
            : (((body['chunkIndex'] as int? ?? 1) /
                          (body['chunkCount'] as int? ?? 4)) *
                      100)
                  .round(),
        'backendStatusLabel': 'Upload chunk diterima server lokal',
      });
    }

    if (method == 'GET' && path == '/api/v1/ptt/channels') {
      return _writeJson(response, store.state.pttChannels);
    }

    if (method == 'GET' && path == '/api/v1/ptt/feed') {
      final channelId = request.uri.queryParameters['channelId'] ?? 'ch3';
      return _writeJson(response, store.state.pttFeeds[channelId] ?? const []);
    }

    if (method == 'POST' && path == '/api/v1/ptt/transmit/start') {
      final body = await _readJson(request);
      final officerId = body['officerId'] as String? ?? '';
      final channelId = body['channelId'] as String? ?? 'ch3';
      if (officerId.isEmpty) {
        response.statusCode = HttpStatus.badRequest;
        return _writeJson(response, {'error': 'officerId required'});
      }
      store.state = _cleanupStalePttSessions(store.state);
      final activeSession = _activeSessionForChannel(store.state, channelId);
      if (activeSession != null) {
        final currentHolder = activeSession['officerId'] as String? ?? '';
        if (currentHolder == officerId) {
          return _writeJson(response, {
            'sessionId': activeSession['sessionId'],
            'status': 'talking',
            'channelId': channelId,
            'holderOfficerId': currentHolder,
          });
        }
        stdout.writeln(
          '[${_clockNow()}][ptt-busy] $officerId ditolak di ${channelId.toUpperCase()} karena dipakai $currentHolder',
        );
        response.statusCode = HttpStatus.conflict;
        return _writeJson(response, {
          'status': 'busy',
          'channelId': channelId,
          'holderOfficerId': currentHolder,
          'sessionId': activeSession['sessionId'],
        });
      }
      final sessionId =
          'PTT_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:.TZ]'), '')}';
      final updatedPresence = {...store.state.presence};
      final currentPresence = Map<String, dynamic>.from(
        updatedPresence[officerId] ?? const {},
      );
      updatedPresence[officerId] = {
        ...currentPresence,
        'username': officerId,
        'deviceId': body['deviceId'] ?? currentPresence['deviceId'] ?? '',
        'status': 'online',
        'activeChannelId': channelId,
        'clientTimeIso': DateTime.now().toUtc().toIso8601String(),
        'lastSeenIso': DateTime.now().toUtc().toIso8601String(),
      };
      final newSession = {
        'sessionId': sessionId,
        'channelId': channelId,
        'officerId': officerId,
        'deviceId': body['deviceId'] ?? '',
        'startedAtIso': DateTime.now().toUtc().toIso8601String(),
      };
      final updatedSessions = {
        ...store.state.activePttSessions,
        channelId: newSession,
      };
      store.state = store.state.copyWith(
        presence: updatedPresence,
        activePttSession: newSession,
        activePttSessions: updatedSessions,
      );
      await store.save();
      _printPresenceSnapshot(store, reason: 'ptt-start');
      return _writeJson(response, {
        'sessionId': sessionId,
        'status': 'talking',
      });
    }

    if (method == 'POST' && path == '/api/v1/ptt/transmit/stop') {
      final body = await _readJson(request);
      final channelId = body['channelId'] as String? ?? 'ch3';
      final requestedOfficerId = body['officerId'] as String? ?? '';
      store.state = _cleanupStalePttSessions(store.state);
      final activeSession = _activeSessionForChannel(store.state, channelId);
      if (activeSession == null) {
        return _writeJson(response, {'status': 'idle', 'channelId': channelId});
      }
      final officerId =
          activeSession['officerId'] as String? ?? requestedOfficerId;
      if (requestedOfficerId.isNotEmpty && requestedOfficerId != officerId) {
        response.statusCode = HttpStatus.conflict;
        return _writeJson(response, {
          'status': 'ignored',
          'reason': 'not_floor_holder',
          'channelId': channelId,
          'holderOfficerId': officerId,
        });
      }
      final initialsLength = officerId.length < 2 ? officerId.length : 2;
      final currentFeed = [
        ...(store.state.pttFeeds[channelId] ?? const <Map<String, dynamic>>[]),
      ];
      currentFeed.insert(0, {
        'initials': officerId.substring(0, initialsLength).toUpperCase(),
        'speakerName': officerId,
        'statusLabel': '${body['durationSeconds'] ?? 0}d',
        'timeLabel': _clockNow(),
        'waveLevel': 0.74,
        'accentColorHex': '#FF6A6A',
        'isSystem': false,
      });
      final updatedFeeds = {
        ...store.state.pttFeeds,
        channelId: currentFeed.take(10).toList(),
      };
      final updatedSessions = {...store.state.activePttSessions}
        ..remove(channelId);
      store.state = store.state.copyWith(
        activePttSession: _primaryActiveSession(updatedSessions),
        activePttSessions: updatedSessions,
        pttFeeds: updatedFeeds,
      );
      await store.save();
      _printPresenceSnapshot(store, reason: 'ptt-stop');
      return _writeJson(response, {'status': 'completed'});
    }

    response.statusCode = HttpStatus.notFound;
    await _writeJson(response, {'error': 'Not found'});
  } catch (error, stackTrace) {
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    response.statusCode = HttpStatus.internalServerError;
    await _writeJson(response, {'error': '$error'});
  }
}

void _applyCors(HttpResponse response) {
  response.headers.contentType = ContentType.json;
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization',
  );
  response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  if (raw.trim().isEmpty) return {};
  return Map<String, dynamic>.from(jsonDecode(raw) as Map);
}

Future<Map<String, String>> _readForm(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  if (raw.trim().isEmpty) return {};
  return Uri.splitQueryString(raw);
}

Future<void> _writeJson(HttpResponse response, Object payload) async {
  response.write(jsonEncode(payload));
  await response.close();
}

Future<bool> _sendDashboardOtpViaWhatsApp(String code) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 4);
  try {
    final uri = Uri.parse('$_dashboardOtpHttpBaseUrl/send-admin-otp');
    final request = await client.postUrl(uri).timeout(
      const Duration(seconds: 4),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $_dashboardOtpHttpBearerToken',
    );
    request.write(
      jsonEncode({
        'code': code,
        'purpose': 'admin_login',
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 6));
    await response.drain<void>();
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (error) {
    stdout.writeln('[${_clockNow()}][dashboard-otp] gagal kirim OTP: $error');
    return false;
  } finally {
    client.close(force: true);
  }
}

String _readCookie(HttpRequest request, String name) {
  for (final cookie in request.cookies) {
    if (cookie.name == name) return cookie.value;
  }
  return '';
}

String _dashboardBasePath(HttpRequest request) {
  final forwardedPrefix =
      request.headers.value('X-Forwarded-Prefix')?.trim() ?? '';
  if (forwardedPrefix.isEmpty || forwardedPrefix == '/') return '';
  final normalized = forwardedPrefix.startsWith('/')
      ? forwardedPrefix
      : '/$forwardedPrefix';
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

String _withDashboardBase(String basePath, String routePath) {
  if (basePath.isEmpty) return routePath;
  if (routePath == '/') return basePath;
  return '$basePath$routePath';
}

String _buildDashboardLoginPage({
  required String dashboardBasePath,
  bool invalidCredentials = false,
  bool otpRequested = false,
  bool invalidOtp = false,
  bool otpDeliveryFailed = false,
}) {
  final errorBanner = invalidCredentials
      ? '''
        <div class="notice">Username atau password salah.</div>
      '''
      : invalidOtp
      ? '''
        <div class="notice">Kode OTP salah atau sudah kedaluwarsa.</div>
      '''
      : otpDeliveryFailed
      ? '''
        <div class="notice">OTP gagal dikirim ke WhatsApp admin. Pastikan service bot aktif dan session WhatsApp tidak bentrok.</div>
      '''
      : otpRequested
      ? '''
        <div class="notice success">OTP sudah dikirim ke WhatsApp admin ($_dashboardAdminPhoneDisplay). Masukkan kode untuk membuka dashboard.</div>
      '''
      : '';
  final loginAction = _withDashboardBase(dashboardBasePath, '/dashboard/login');
  return '''
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Login Dashboard Polri BWC</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root{
      --bg:#f7fbff;
      --bg2:#eef6ff;
      --surface:#ffffff;
      --surface-2:#f3f8ff;
      --border:#d7e5f3;
      --text:#17365d;
      --muted:#7c94b0;
      --accent:#72b8ff;
      --sidebar-top:#435456;
      --sidebar-bottom:#3d4d4f;
      --success:#12c26a;
      --danger:#f04040;
    }
    *{box-sizing:border-box}
    body{
      margin:0;
      min-height:100vh;
      font-family:'Geist','Segoe UI',system-ui,-apple-system,sans-serif;
      color:var(--text);
      background:
        linear-gradient(130deg, rgba(78, 172, 108, .16) 0 26%, transparent 26% 100%),
        repeating-linear-gradient(90deg, rgba(78,172,108,.12) 0 1px, transparent 1px 28px),
        linear-gradient(180deg, #fdfefe 0%, #f5faff 58%, #edf5ff 100%);
      display:grid;
      place-items:center;
      padding:32px 20px;
    }
    .frame{
      width:min(1120px,100%);
      min-height:min(720px,calc(100vh - 40px));
      display:grid;
      grid-template-columns:minmax(320px, 420px) 1fr;
      background:rgba(255,255,255,.94);
      border:1px solid #dbe7f3;
      border-radius:30px;
      box-shadow:0 32px 80px rgba(150,175,208,.18);
      overflow:hidden;
    }
    .panel{
      background:linear-gradient(180deg,var(--sidebar-top) 0%,var(--sidebar-bottom) 100%);
      color:#ffffff;
      padding:34px 28px;
      display:flex;
      flex-direction:column;
    }
    .brand{
      display:flex;
      align-items:center;
      gap:12px;
      margin-bottom:26px;
    }
    .brand-icon{
      width:50px;
      height:50px;
      border-radius:16px;
      background:linear-gradient(180deg,#ffffff,#f3f8ff);
      display:flex;
      align-items:center;
      justify-content:center;
      border:1px solid #d5e3f2;
      box-shadow:0 18px 34px rgba(0,0,0,.08);
      color:#17365d;
      font-size:12px;
      font-weight:800;
      letter-spacing:.08em;
    }
    .brand-name{
      font-size:24px;
      font-weight:500;
      letter-spacing:.15px;
    }
    .brand-sub{
      font-size:11px;
      color:#dbe7ea;
      font-weight:700;
      letter-spacing:.8px;
      text-transform:uppercase;
      margin-top:4px;
    }
    .eyebrow{
      display:inline-flex;
      align-items:center;
      gap:8px;
      width:max-content;
      font-size:10px;
      font-weight:700;
      letter-spacing:.08em;
      text-transform:uppercase;
      color:#edf4f6;
      background:rgba(255,255,255,.10);
      border:1px solid rgba(255,255,255,.16);
      border-radius:999px;
      padding:8px 12px;
    }
    h1{
      margin:22px 0 10px;
      font-size:32px;
      line-height:1.1;
    }
    .lead{
      margin:0 0 24px;
      color:#d7e3e6;
      line-height:1.6;
      max-width:30ch;
    }
    .meta{
      display:grid;
      gap:12px;
      margin-top:auto;
    }
    .meta-card{
      background:rgba(255,255,255,.06);
      border:1px solid rgba(255,255,255,.10);
      border-radius:18px;
      padding:16px;
    }
    .meta-kicker{
      font-size:10px;
      font-weight:800;
      letter-spacing:.08em;
      text-transform:uppercase;
      color:#dbe7ea;
      margin-bottom:8px;
    }
    .meta-text{
      font-size:13px;
      line-height:1.6;
      color:#ffffff;
    }
    .card{
      background:linear-gradient(180deg,#ffffff,#f4f9ff);
      padding:34px 34px 30px;
      display:flex;
      flex-direction:column;
      justify-content:center;
    }
    .card-shell{
      width:min(420px,100%);
      margin:0 auto;
    }
    .card-kicker{
      display:inline-flex;
      align-items:center;
      gap:8px;
      font-size:10px;
      font-weight:800;
      letter-spacing:.08em;
      text-transform:uppercase;
      color:#2b4d76;
      background:#ffffff;
      border:1px solid #cfe0f1;
      border-radius:20px;
      padding:10px 14px;
      box-shadow:0 12px 24px rgba(150,175,208,.10);
    }
    .card-title{
      margin:18px 0 8px;
      font-size:30px;
      line-height:1.08;
      color:var(--text);
      font-weight:600;
    }
    .card-copy{
      margin:0 0 22px;
      color:var(--muted);
      line-height:1.65;
    }
    label{
      display:block;
      font-size:13px;
      font-weight:700;
      margin:0 0 8px;
      color:#29496f;
    }
    .field{margin-bottom:16px}
    input{
      width:100%;
      border:1px solid #cfe0f1;
      border-radius:16px;
      padding:14px 16px;
      font-size:15px;
      color:var(--text);
      background:#fbfdff;
      outline:none;
      font-family:inherit;
    }
    input:focus{
      border-color:#b9d3ea;
      box-shadow:0 0 0 4px rgba(114,184,255,.16);
    }
    button{
      width:100%;
      border:1px solid rgba(255,255,255,.86);
      border-radius:18px;
      padding:15px 18px;
      font-size:15px;
      font-weight:800;
      color:#0f315f;
      background:linear-gradient(180deg, #fefefe 0%, #edf6ff 100%);
      cursor:pointer;
      box-shadow:0 10px 22px rgba(66,151,255,.20);
      font-family:inherit;
    }
    .hint{
      margin-top:14px;
      font-size:12px;
      color:var(--muted);
      text-align:left;
    }
    .notice{
      margin:0 0 18px;
      border:1px solid rgba(240,64,64,.16);
      background:rgba(240,64,64,.08);
      color:#b93a3a;
      border-radius:16px;
      padding:12px 14px;
      font-size:14px;
      font-weight:700;
    }
    .notice.success{
      border-color:rgba(18,194,106,.18);
      background:rgba(18,194,106,.10);
      color:#18734a;
    }
    @media (max-width: 860px){
      .frame{grid-template-columns:1fr}
      .panel{padding:24px 22px}
      .meta{margin-top:18px}
      .card{padding:28px 22px 24px}
      .card-shell{width:100%}
    }
  </style>
</head>
<body>
  <div class="frame">
    <section class="panel">
      <div class="brand">
        <div class="brand-icon">BWC</div>
        <div>
          <div class="brand-name">Polri BWC</div>
          <div class="brand-sub">Command Center</div>
        </div>
      </div>
      <div class="eyebrow">Dashboard Access</div>
      <h1>Masuk ke pusat komando live monitoring.</h1>
      <p class="lead">Gunakan akun admin dashboard untuk membuka peta patroli, live cam, status perangkat, dan feed operasional petugas.</p>
      <div class="meta">
        <div class="meta-card">
          <div class="meta-kicker">Operasional</div>
          <div class="meta-text">Akses ini melindungi dashboard command center dari kunjungan publik langsung di jalur deployment sementara.</div>
        </div>
        <div class="meta-card">
          <div class="meta-kicker">Mode Aktif</div>
          <div class="meta-text">Monitoring perangkat, live cam, SOS, rekaman, dan status kanal PTT.</div>
        </div>
      </div>
    </section>
    <section class="card">
      <div class="card-shell">
        <div class="card-kicker">Secure Sign-In</div>
        <div class="card-title">${otpRequested ? 'Verifikasi OTP' : 'Login Dashboard'}</div>
        <p class="card-copy">${otpRequested ? 'Kredensial benar. Lanjutkan dengan OTP WhatsApp yang dikirim ke nomor admin tetap untuk membuka dashboard Polri BWC.' : 'Masukkan kredensial administrator untuk melanjutkan ke dashboard Polri BWC.'}</p>
        $errorBanner
        <form method="post" action="$loginAction">
          ${otpRequested ? '''
          <div class="field">
            <label for="otp">Kode OTP WhatsApp</label>
            <input id="otp" name="otp" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" required>
          </div>
          <button type="submit">Verifikasi & Masuk</button>
          ''' : '''
          <div class="field">
            <label for="username">Username</label>
            <input id="username" name="username" type="text" autocomplete="username" required>
          </div>
          <div class="field">
            <label for="password">Password</label>
            <input id="password" name="password" type="password" autocomplete="current-password" required>
          </div>
          <button type="submit">Kirim OTP ke WhatsApp Admin</button>
          '''}
        </form>
        <div class="hint">${otpRequested ? 'OTP dikirim ke nomor admin yang sudah ditentukan dari awal: <strong>$_dashboardAdminPhoneDisplay</strong>' : 'Credentials sementara: <strong>admin</strong> / <strong>admin</strong>. Setelah benar, sistem akan mengirim OTP ke WhatsApp admin <strong>$_dashboardAdminPhoneDisplay</strong>.'}</div>
      </div>
    </section>
  </div>
</body>
</html>
''';
}

class DashboardAuthManager {
  final Map<String, DateTime> _activeTokens = {};
  final Map<String, _DashboardOtpChallenge> _otpChallenges = {};
  final Random _random = Random.secure();

  String issueToken() {
    _pruneExpired();
    final token = _issueOpaqueToken();
    _activeTokens[token] = DateTime.now().toUtc().add(
      const Duration(hours: 12),
    );
    return token;
  }

  bool isValid(String token) {
    if (token.isEmpty) return false;
    _pruneExpired();
    final expiresAt = _activeTokens[token];
    if (expiresAt == null) return false;
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      _activeTokens.remove(token);
      return false;
    }
    return true;
  }

  void revokeToken(String token) {
    if (token.isEmpty) return;
    _activeTokens.remove(token);
  }

  _DashboardOtpChallenge _issueOtpChallenge({required String phoneNumber}) {
    _pruneExpired();
    final challengeToken = _issueOpaqueToken(length: 18);
    final code = List<int>.generate(6, (_) => _random.nextInt(10)).join();
    final challenge = _DashboardOtpChallenge(
      challengeToken: challengeToken,
      phoneNumber: phoneNumber,
      code: code,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      attemptsLeft: 5,
    );
    _otpChallenges[challengeToken] = challenge;
    return challenge;
  }

  _DashboardOtpChallenge? _lookupOtpChallenge(String token) {
    if (token.isEmpty) return null;
    _pruneExpired();
    return _otpChallenges[token];
  }

  bool verifyOtp(String challengeToken, String code) {
    if (challengeToken.isEmpty || code.isEmpty) return false;
    _pruneExpired();
    final challenge = _otpChallenges[challengeToken];
    if (challenge == null) return false;
    if (challenge.code != code) {
      challenge.attemptsLeft -= 1;
      if (challenge.attemptsLeft <= 0) {
        _otpChallenges.remove(challengeToken);
      }
      return false;
    }
    _otpChallenges.remove(challengeToken);
    return true;
  }

  void _revokeOtpChallenge(String token) {
    if (token.isEmpty) return;
    _otpChallenges.remove(token);
  }

  void _pruneExpired() {
    final now = DateTime.now().toUtc();
    _activeTokens.removeWhere((_, expiresAt) => expiresAt.isBefore(now));
    _otpChallenges.removeWhere(
      (_, challenge) => challenge.expiresAt.isBefore(now),
    );
  }

  String _issueOpaqueToken({int length = 24}) {
    final bytes = List<int>.generate(length, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class _DashboardOtpChallenge {
  _DashboardOtpChallenge({
    required this.challengeToken,
    required this.phoneNumber,
    required this.code,
    required this.expiresAt,
    required this.attemptsLeft,
  });

  final String challengeToken;
  final String phoneNumber;
  final String code;
  final DateTime expiresAt;
  int attemptsLeft;
}

String _clockNow() {
  final now = DateTime.now();
  final hh = now.hour.toString().padLeft(2, '0');
  final mm = now.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

List<Map<String, dynamic>> _resolvedPresenceEntries(
  LocalServerStore store, {
  String channelId = '',
}) {
  final now = DateTime.now().toUtc();
  final items =
      store.state.presence.values
          .map((entry) {
            final lastSeenIso = entry['lastSeenIso'] as String? ?? '';
            final lastSeen = DateTime.tryParse(lastSeenIso)?.toUtc();
            final activeChannelId = entry['activeChannelId'] as String? ?? '';
            final username = entry['username'] as String? ?? '';
            final isOnline =
                lastSeen != null &&
                now.difference(lastSeen) <= const Duration(seconds: 45) &&
                (entry['status'] as String? ?? 'offline') != 'offline';
            return {
              ...entry,
              'signalLabel': isOnline ? 'Online' : 'Offline',
              'isTalking':
                  isOnline &&
                  ((_activeSessionForChannel(
                                store.state,
                                activeChannelId,
                              )?['officerId']
                              as String? ??
                          '') ==
                      username),
              'resolvedStatus': isOnline ? 'online' : 'offline',
              if (entry['latitude'] != null) 'latitude': entry['latitude'],
              if (entry['longitude'] != null) 'longitude': entry['longitude'],
            };
          })
          .where((entry) {
            if (channelId.isEmpty) return true;
            return (entry['activeChannelId'] as String? ?? '') == channelId;
          })
          .toList()
        ..sort(
          (a, b) => (b['lastSeenIso'] as String).compareTo(
            a['lastSeenIso'] as String,
          ),
        );
  return items;
}

void _printPresenceSnapshot(LocalServerStore store, {required String reason}) {
  final all = _resolvedPresenceEntries(store);
  final online = all
      .where((entry) => (entry['resolvedStatus'] as String? ?? '') == 'online')
      .toList();
  final time = _clockNow();
  if (online.isEmpty) {
    stdout.writeln('[$time][$reason] Online users: 0 | tidak ada user aktif');
    return;
  }

  final summary = online
      .map((entry) {
        final username = entry['username'] as String? ?? 'unknown';
        final channel = (entry['activeChannelId'] as String? ?? '-')
            .toUpperCase();
        final talking = (entry['isTalking'] as bool? ?? false) ? ' TX' : '';
        return '$username@$channel$talking';
      })
      .join(', ');

  final perChannel = <String, int>{};
  for (final entry in online) {
    final channel = (entry['activeChannelId'] as String? ?? '-').toUpperCase();
    perChannel[channel] = (perChannel[channel] ?? 0) + 1;
  }
  final channelSummary = perChannel.entries
      .map((entry) => '${entry.key}:${entry.value}')
      .join(' | ');

  stdout.writeln(
    '[$time][$reason] Online users: ${online.length} | $channelSummary',
  );
  stdout.writeln('[$time][$reason] $summary');
}

Map<String, dynamic>? _activeSessionForChannel(
  LocalServerState state,
  String channelId,
) {
  if (channelId.isEmpty) return null;
  final sessions = state.activePttSessions[channelId];
  if (sessions != null && sessions.isNotEmpty) {
    return sessions;
  }
  final legacy = state.activePttSession;
  if ((legacy['channelId'] as String? ?? '') == channelId &&
      legacy.isNotEmpty) {
    return legacy;
  }
  return null;
}

List<Map<String, dynamic>> _resolvedLiveSessions(LocalServerStore store) {
  final sessions =
      _cleanupStaleLiveSessions(store.state).liveSessions.values.toList()..sort(
        (a, b) => (b['startedAtIso'] as String? ?? '').compareTo(
          a['startedAtIso'] as String? ?? '',
        ),
      );
  return sessions;
}

LocalServerState _cleanupStalePttSessions(LocalServerState state) {
  if (state.activePttSessions.isEmpty) return state;
  final cleaned = <String, Map<String, dynamic>>{};
  for (final entry in state.activePttSessions.entries) {
    final session = entry.value;
    final officerId = session['officerId'] as String? ?? '';
    if (_isOfficerOnline(state, officerId)) {
      cleaned[entry.key] = session;
    }
  }
  if (cleaned.length == state.activePttSessions.length) {
    return state;
  }
  return state.copyWith(
    activePttSessions: cleaned,
    activePttSession: _primaryActiveSession(cleaned),
  );
}

LocalServerState _cleanupStaleLiveSessions(LocalServerState state) {
  if (state.liveSessions.isEmpty) return state;
  final cleaned = <String, Map<String, dynamic>>{};
  for (final entry in state.liveSessions.entries) {
    final officerId = entry.value['officerId'] as String? ?? '';
    if (_isOfficerOnline(state, officerId)) {
      cleaned[entry.key] = entry.value;
    }
  }
  if (cleaned.length == state.liveSessions.length) {
    return state;
  }
  return state.copyWith(liveSessions: cleaned);
}

LocalServerState _releaseOfficerFloor(
  LocalServerState state,
  String officerId,
) {
  if (officerId.isEmpty || state.activePttSessions.isEmpty) return state;
  final cleaned = <String, Map<String, dynamic>>{};
  for (final entry in state.activePttSessions.entries) {
    final holder = entry.value['officerId'] as String? ?? '';
    if (holder != officerId) {
      cleaned[entry.key] = entry.value;
    }
  }
  if (cleaned.length == state.activePttSessions.length) {
    return state;
  }
  return state.copyWith(
    activePttSessions: cleaned,
    activePttSession: _primaryActiveSession(cleaned),
  );
}

LocalServerState _releaseOfficerLiveSessions(
  LocalServerState state,
  String officerId,
) {
  if (officerId.isEmpty || state.liveSessions.isEmpty) return state;
  final cleaned = <String, Map<String, dynamic>>{};
  for (final entry in state.liveSessions.entries) {
    final holder = entry.value['officerId'] as String? ?? '';
    if (holder != officerId) {
      cleaned[entry.key] = entry.value;
    }
  }
  if (cleaned.length == state.liveSessions.length) {
    return state;
  }
  return state.copyWith(liveSessions: cleaned);
}

bool _isOfficerOnline(LocalServerState state, String officerId) {
  if (officerId.isEmpty) return false;
  final presence = state.presence[officerId];
  if (presence == null || presence.isEmpty) return false;
  final status = presence['status'] as String? ?? 'offline';
  if (status == 'offline') return false;
  final lastSeenIso = presence['lastSeenIso'] as String? ?? '';
  final lastSeen = DateTime.tryParse(lastSeenIso)?.toUtc();
  if (lastSeen == null) return false;
  return DateTime.now().toUtc().difference(lastSeen) <=
      const Duration(seconds: 45);
}

Map<String, dynamic> _primaryActiveSession(
  Map<String, Map<String, dynamic>> sessions,
) {
  if (sessions.isEmpty) return {};
  final firstKey = sessions.keys.first;
  return sessions[firstKey] ?? {};
}

class _ServerOptions {
  const _ServerOptions({required this.host, required this.port});

  final String host;
  final int port;

  factory _ServerOptions.fromArgs(List<String> args) {
    var host = _defaultHost;
    var port = _defaultPort;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--host':
          if (i + 1 < args.length) host = args[++i];
        case '--port':
          if (i + 1 < args.length) {
            port = int.tryParse(args[++i]) ?? _defaultPort;
          }
      }
    }
    return _ServerOptions(host: host, port: port);
  }
}

class LocalServerStore {
  LocalServerStore._(this.file, this.state);

  final File file;
  LocalServerState state;

  static Future<LocalServerStore> load() async {
    final dir = Directory(_dataPath(''));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/state.json');
    if (!await file.exists()) {
      final initial = LocalServerState.seed();
      await file.writeAsString(jsonEncode(initial.toJson()));
      return LocalServerStore._(file, initial);
    }
    final raw = await file.readAsString();
    final decoded = raw.trim().isEmpty
        ? LocalServerState.seed().toJson()
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return LocalServerStore._(file, LocalServerState.fromJson(decoded));
  }

  Future<void> save() async {
    await file.writeAsString(jsonEncode(state.toJson()));
  }
}

class LocalServerState {
  const LocalServerState({
    required this.users,
    required this.chatThreads,
    required this.reports,
    required this.sosAlerts,
    required this.recordings,
    required this.liveSessions,
    required this.presence,
    required this.pttChannels,
    required this.pttFeeds,
    required this.activePttSession,
    required this.activePttSessions,
  });

  final Map<String, Map<String, dynamic>> users;
  final Map<String, List<Map<String, dynamic>>> chatThreads;
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> sosAlerts;
  final List<Map<String, dynamic>> recordings;
  final Map<String, Map<String, dynamic>> liveSessions;
  final Map<String, Map<String, dynamic>> presence;
  final List<Map<String, dynamic>> pttChannels;
  final Map<String, List<Map<String, dynamic>>> pttFeeds;
  final Map<String, dynamic> activePttSession;
  final Map<String, Map<String, dynamic>> activePttSessions;

  factory LocalServerState.seed() {
    return LocalServerState(
      users: const {
        'test1': {
          'username': 'test1',
          'password': 'test1',
          'officerName': 'Test Satu',
          'rankLabel': '',
          'unitName': 'Satuan Alpha',
          'shiftLabel': 'Shift Pagi Aktif',
          'shiftWindow': '07:00–15:00',
          'nrp': 'test1',
        },
        'test2': {
          'username': 'test2',
          'password': 'test2',
          'officerName': 'Test Dua',
          'rankLabel': '',
          'unitName': 'Satuan Bravo',
          'shiftLabel': 'Shift Siang Aktif',
          'shiftWindow': '15:00–23:00',
          'nrp': 'test2',
        },
        'test3': {
          'username': 'test3',
          'password': 'test3',
          'officerName': 'Test Tiga',
          'rankLabel': '',
          'unitName': 'Satuan Charlie',
          'shiftLabel': 'Shift Malam Aktif',
          'shiftWindow': '23:00–07:00',
          'nrp': 'test3',
        },
        'test4': {
          'username': 'test4',
          'password': 'test4',
          'officerName': 'Test Empat',
          'rankLabel': '',
          'unitName': 'Satuan Delta',
          'shiftLabel': 'Shift Pagi Aktif',
          'shiftWindow': '07:00–15:00',
          'nrp': 'test4',
        },
        'test5': {
          'username': 'test5',
          'password': 'test5',
          'officerName': 'Test Lima',
          'rankLabel': '',
          'unitName': 'Satuan Echo',
          'shiftLabel': 'Shift Siang Aktif',
          'shiftWindow': '15:00–23:00',
          'nrp': 'test5',
        },
        'test6': {
          'username': 'test6',
          'password': 'test6',
          'officerName': 'Test Enam',
          'rankLabel': '',
          'unitName': 'Satuan Foxtrot',
          'shiftLabel': 'Shift Malam Aktif',
          'shiftWindow': '23:00–07:00',
          'nrp': 'test6',
        },
        'test7': {
          'username': 'test7',
          'password': 'test7',
          'officerName': 'Test Tujuh',
          'rankLabel': '',
          'unitName': 'Satuan Golf',
          'shiftLabel': 'Shift Pagi Aktif',
          'shiftWindow': '07:00–15:00',
          'nrp': 'test7',
        },
        'test8': {
          'username': 'test8',
          'password': 'test8',
          'officerName': 'Test Delapan',
          'rankLabel': '',
          'unitName': 'Satuan Hotel',
          'shiftLabel': 'Shift Siang Aktif',
          'shiftWindow': '15:00–23:00',
          'nrp': 'test8',
        },
        'test9': {
          'username': 'test9',
          'password': 'test9',
          'officerName': 'Test Sembilan',
          'rankLabel': '',
          'unitName': 'Satuan India',
          'shiftLabel': 'Shift Malam Aktif',
          'shiftWindow': '23:00–07:00',
          'nrp': 'test9',
        },
        'test10': {
          'username': 'test10',
          'password': 'test10',
          'officerName': 'Test Sepuluh',
          'rankLabel': '',
          'unitName': 'Satuan Juliet',
          'shiftLabel': 'Shift Pagi Aktif',
          'shiftWindow': '07:00–15:00',
          'nrp': 'test10',
        },
      },
      chatThreads: const {},
      reports: const [],
      sosAlerts: const [],
      recordings: const [],
      liveSessions: const {},
      presence: const {},
      pttChannels: const [
        {'id': 'ch1', 'label': 'Ch 1', 'subtitle': ''},
        {'id': 'ch2', 'label': 'Ch 2', 'subtitle': ''},
        {'id': 'ch3', 'label': 'Ch 3', 'subtitle': ''},
        {'id': 'ch4', 'label': 'Ch 4', 'subtitle': ''},
      ],
      pttFeeds: const {},
      activePttSession: const {},
      activePttSessions: const {},
    );
  }

  factory LocalServerState.fromJson(Map<String, dynamic> json) {
    return LocalServerState(
      users: (json['users'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      ),
      chatThreads: (json['chatThreads'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key,
          List<Map<String, dynamic>>.from(
            (value as List).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          ),
        ),
      ),
      reports: List<Map<String, dynamic>>.from(
        (json['reports'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
      sosAlerts: List<Map<String, dynamic>>.from(
        (json['sosAlerts'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
      recordings: List<Map<String, dynamic>>.from(
        (json['recordings'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
      liveSessions: (json['liveSessions'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      ),
      presence: (json['presence'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      ),
      pttChannels: List<Map<String, dynamic>>.from(
        (json['pttChannels'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
      pttFeeds: (json['pttFeeds'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key,
          List<Map<String, dynamic>>.from(
            (value as List).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          ),
        ),
      ),
      activePttSession: Map<String, dynamic>.from(
        json['activePttSession'] as Map? ?? const {},
      ),
      activePttSessions: (json['activePttSessions'] as Map? ?? const {}).map(
        (key, value) =>
            MapEntry(key.toString(), Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  LocalServerState copyWith({
    Map<String, Map<String, dynamic>>? users,
    Map<String, List<Map<String, dynamic>>>? chatThreads,
    List<Map<String, dynamic>>? reports,
    List<Map<String, dynamic>>? sosAlerts,
    List<Map<String, dynamic>>? recordings,
    Map<String, Map<String, dynamic>>? liveSessions,
    Map<String, Map<String, dynamic>>? presence,
    List<Map<String, dynamic>>? pttChannels,
    Map<String, List<Map<String, dynamic>>>? pttFeeds,
    Map<String, dynamic>? activePttSession,
    Map<String, Map<String, dynamic>>? activePttSessions,
  }) {
    return LocalServerState(
      users: users ?? this.users,
      chatThreads: chatThreads ?? this.chatThreads,
      reports: reports ?? this.reports,
      sosAlerts: sosAlerts ?? this.sosAlerts,
      recordings: recordings ?? this.recordings,
      liveSessions: liveSessions ?? this.liveSessions,
      presence: presence ?? this.presence,
      pttChannels: pttChannels ?? this.pttChannels,
      pttFeeds: pttFeeds ?? this.pttFeeds,
      activePttSession: activePttSession ?? this.activePttSession,
      activePttSessions: activePttSessions ?? this.activePttSessions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'users': users,
      'chatThreads': chatThreads,
      'reports': reports,
      'sosAlerts': sosAlerts,
      'recordings': recordings,
      'liveSessions': liveSessions,
      'presence': presence,
      'pttChannels': pttChannels,
      'pttFeeds': pttFeeds,
      'activePttSession': activePttSession,
      'activePttSessions': activePttSessions,
    };
  }
}

const _autoReplies = [
  'Diterima server lokal.',
  'Komando menerima update Anda.',
  'Packet telemetri aman.',
  'Sinyal diterima. Lanjutkan patroli.',
];

class PttAudioRelayServer {
  PttAudioRelayServer({
    required this.host,
    required this.port,
    required this.canRelayAudio,
  });

  final String host;
  final int port;
  final bool Function(String channelId, String username) canRelayAudio;
  final List<_PttClientConnection> _clients = [];
  ServerSocket? _serverSocket;

  Future<void> start() async {
    _serverSocket = await ServerSocket.bind(host, port);
    unawaited(_acceptLoop());
  }

  Future<void> _acceptLoop() async {
    final serverSocket = _serverSocket;
    if (serverSocket == null) return;
    await for (final socket in serverSocket) {
      final client = _PttClientConnection(
        socket: socket,
        onDisconnect: _removeClient,
        onAudioPacket: _relayPacket,
      );
      _clients.add(client);
      stdout.writeln(
        '[${_clockNow()}][audio-connect] client ${socket.remoteAddress.address}:${socket.remotePort}',
      );
      client.start();
    }
  }

  void _relayPacket(_PttClientConnection sender, Map<String, dynamic> packet) {
    final channelId = packet['channelId'] as String? ?? '';
    final username = packet['username'] as String? ?? sender.username;
    if (!canRelayAudio(channelId, username)) {
      sender.deniedPacketCount += 1;
      if (sender.deniedPacketCount == 1 || sender.deniedPacketCount % 50 == 0) {
        stdout.writeln(
          '[${_clockNow()}][audio-drop] $username@$channelId bukan floor holder',
        );
      }
      if (sender.deniedPacketCount == 1) {
        sender.send({
          'type': 'floor_lost',
          'channelId': channelId,
          'username': username,
          'reason': 'not_floor_holder',
        });
      }
      return;
    }
    sender.deniedPacketCount = 0;
    sender.audioPacketCount += 1;
    if (sender.audioPacketCount == 1 || sender.audioPacketCount % 50 == 0) {
      stdout.writeln(
        '[${_clockNow()}][audio-in] $username@$channelId packets=${sender.audioPacketCount}',
      );
    }

    var relayed = 0;
    for (final client in _clients.toList()) {
      if (identical(client, sender)) continue;
      if (client.channelId != channelId) continue;
      client.send(packet);
      relayed += 1;
    }
    if (sender.audioPacketCount == 1 || sender.audioPacketCount % 50 == 0) {
      stdout.writeln(
        '[${_clockNow()}][audio-out] $username@$channelId relayed=$relayed',
      );
    }
  }

  void _removeClient(_PttClientConnection client) {
    _clients.remove(client);
    final safeUsername = client.username.isEmpty ? 'unknown' : client.username;
    stdout.writeln(
      '[${_clockNow()}][audio-disconnect] $safeUsername@${client.channelId}',
    );
  }
}

class PttAudioWebSocketRelay {
  PttAudioWebSocketRelay({required this.canRelayAudio});

  final bool Function(String channelId, String username) canRelayAudio;
  final List<_PttWebSocketConnection> _clients = [];

  Future<void> handleUpgrade(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final client = _PttWebSocketConnection(
      socket: socket,
      onDisconnect: _removeClient,
      onAudioPacket: _relayPacket,
    );
    _clients.add(client);
    stdout.writeln(
      '[${_clockNow()}][audio-ws-connect] client ${request.connectionInfo?.remoteAddress.address ?? 'unknown'}',
    );
    client.start();
  }

  void _relayPacket(
    _PttWebSocketConnection sender,
    Map<String, dynamic> packet,
  ) {
    final channelId = packet['channelId'] as String? ?? '';
    final username = packet['username'] as String? ?? sender.username;
    if (!canRelayAudio(channelId, username)) {
      sender.deniedPacketCount += 1;
      if (sender.deniedPacketCount == 1 || sender.deniedPacketCount % 50 == 0) {
        stdout.writeln(
          '[${_clockNow()}][audio-ws-drop] $username@$channelId bukan floor holder',
        );
      }
      // Beri tahu klien sekali (di paket pertama yang ditolak) agar bisa
      // membersihkan state transmit-nya dan tidak terus membanjiri relay.
      if (sender.deniedPacketCount == 1) {
        sender.send({
          'type': 'floor_lost',
          'channelId': channelId,
          'username': username,
          'reason': 'not_floor_holder',
        });
      }
      return;
    }
    // Reset penghitung kalau sebelumnya sempat ditolak.
    sender.deniedPacketCount = 0;
    sender.audioPacketCount += 1;
    if (sender.audioPacketCount == 1 || sender.audioPacketCount % 50 == 0) {
      stdout.writeln(
        '[${_clockNow()}][audio-ws-in] $username@$channelId packets=${sender.audioPacketCount}',
      );
    }

    var relayed = 0;
    for (final client in _clients.toList()) {
      if (identical(client, sender)) continue;
      if (client.channelId != channelId) continue;
      client.send(packet);
      relayed += 1;
    }
    if (sender.audioPacketCount == 1 || sender.audioPacketCount % 50 == 0) {
      stdout.writeln(
        '[${_clockNow()}][audio-ws-out] $username@$channelId relayed=$relayed',
      );
    }
  }

  void _removeClient(_PttWebSocketConnection client) {
    _clients.remove(client);
    final safeUsername = client.username.isEmpty ? 'unknown' : client.username;
    stdout.writeln(
      '[${_clockNow()}][audio-ws-disconnect] $safeUsername@${client.channelId}',
    );
  }
}

class PttWebRtcSignalingRelay {
  final List<_PttSignalingClient> _clients = [];

  Future<void> handleUpgrade(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final client = _PttSignalingClient(
      clientId:
          'ptt_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}',
      socket: socket,
      onDisconnect: _removeClient,
      onJoin: _handleJoin,
      onSignal: _relaySignal,
    );
    _clients.add(client);
    client.start();
  }

  void _handleJoin(_PttSignalingClient client, Map<String, dynamic> message) {
    final previousChannel = client.channelId;
    final previousUsername = client.username;
    client.username = message['username'] as String? ?? client.username;
    client.channelId = message['channelId'] as String? ?? client.channelId;
    client.deviceId = message['deviceId'] as String? ?? client.deviceId;

    if (previousChannel.isNotEmpty &&
        previousChannel != client.channelId &&
        previousUsername.isNotEmpty) {
      for (final peer in _clients.toList()) {
        if (identical(peer, client)) continue;
        if (peer.channelId != previousChannel) continue;
        peer.send({
          'type': 'peer-left',
          'clientId': client.clientId,
          'username': client.username,
          'channelId': previousChannel,
        });
      }
    }

    final peers = _clients
        .where(
          (peer) =>
              !identical(peer, client) &&
              peer.channelId == client.channelId &&
              peer.username.isNotEmpty,
        )
        .map(
          (peer) => {
            'clientId': peer.clientId,
            'username': peer.username,
            'channelId': peer.channelId,
            'deviceId': peer.deviceId,
          },
        )
        .toList();

    client.send({
      'type': 'hello-ack',
      'clientId': client.clientId,
      'channelId': client.channelId,
      'peers': peers,
    });

    for (final peer in _clients.toList()) {
      if (identical(peer, client)) continue;
      if (peer.channelId != client.channelId) continue;
      peer.send({
        'type': 'peer-joined',
        'peer': {
          'clientId': client.clientId,
          'username': client.username,
          'channelId': client.channelId,
          'deviceId': client.deviceId,
        },
      });
    }
  }

  void _relaySignal(_PttSignalingClient sender, Map<String, dynamic> message) {
    final targetClientId = message['targetClientId'] as String? ?? '';
    if (targetClientId.isEmpty) return;
    _PttSignalingClient? target;
    for (final client in _clients) {
      if (client.clientId == targetClientId) {
        target = client;
        break;
      }
    }
    if (target == null) return;
    target.send({
      'type': 'signal',
      'fromClientId': sender.clientId,
      'fromUsername': sender.username,
      'channelId': sender.channelId,
      'data': message['data'],
    });
  }

  void _removeClient(_PttSignalingClient client) {
    _clients.remove(client);
    for (final peer in _clients.toList()) {
      if (peer.channelId != client.channelId) continue;
      peer.send({
        'type': 'peer-left',
        'clientId': client.clientId,
        'username': client.username,
        'channelId': client.channelId,
      });
    }
  }
}

class LiveMonitorWebSocketRelay {
  LiveMonitorWebSocketRelay({
    required List<Map<String, dynamic>> initialSessions,
  }) : _latestSessions = List<Map<String, dynamic>>.from(initialSessions);

  final List<WebSocket> _clients = [];
  List<Map<String, dynamic>> _latestSessions;

  Future<void> handleUpgrade(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    _clients.add(socket);
    socket.add(jsonEncode({'type': 'snapshot', 'sessions': _latestSessions}));
    socket.listen(
      (_) {},
      onDone: () => _clients.remove(socket),
      onError: (_) => _clients.remove(socket),
      cancelOnError: true,
    );
  }

  void broadcastSnapshot(List<Map<String, dynamic>> sessions) {
    _latestSessions = List<Map<String, dynamic>>.from(sessions);
    _broadcast({'type': 'snapshot', 'sessions': _latestSessions});
  }

  void broadcastFrame(Map<String, dynamic> session) {
    final sessionId = session['sessionId'] as String? ?? '';
    final index = _latestSessions.indexWhere(
      (item) => (item['sessionId'] as String? ?? '') == sessionId,
    );
    if (index >= 0) {
      _latestSessions[index] = session;
    } else {
      _latestSessions = [session, ..._latestSessions];
    }
    _broadcast({'type': 'frame', 'session': session});
  }

  void _broadcast(Map<String, dynamic> payload) {
    final raw = jsonEncode(payload);
    for (final client in _clients.toList()) {
      try {
        client.add(raw);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }
}

class LiveWebRtcSignalingRelay {
  final List<_LiveSignalingClient> _clients = [];

  Future<void> handleUpgrade(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final client = _LiveSignalingClient(
      clientId:
          'live_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}',
      socket: socket,
      onDisconnect: _removeClient,
      onJoin: _handleJoin,
      onSignal: _relaySignal,
    );
    _clients.add(client);
    client.start();
  }

  void _handleJoin(_LiveSignalingClient client, Map<String, dynamic> message) {
    final previousSessionId = client.sessionId;
    client.username = message['username'] as String? ?? client.username;
    client.sessionId = message['sessionId'] as String? ?? client.sessionId;
    client.deviceId = message['deviceId'] as String? ?? client.deviceId;
    client.role = message['role'] as String? ?? client.role;

    if (previousSessionId.isNotEmpty && previousSessionId != client.sessionId) {
      for (final peer in _clients.toList()) {
        if (identical(peer, client)) continue;
        if (peer.sessionId != previousSessionId) continue;
        peer.send({
          'type': 'peer-left',
          'clientId': client.clientId,
          'username': client.username,
          'sessionId': previousSessionId,
          'role': client.role,
        });
      }
    }

    final peers = _clients
        .where(
          (peer) =>
              !identical(peer, client) &&
              peer.sessionId == client.sessionId &&
              peer.username.isNotEmpty,
        )
        .map(
          (peer) => {
            'clientId': peer.clientId,
            'username': peer.username,
            'sessionId': peer.sessionId,
            'deviceId': peer.deviceId,
            'role': peer.role,
          },
        )
        .toList();

    client.send({
      'type': 'hello-ack',
      'clientId': client.clientId,
      'sessionId': client.sessionId,
      'role': client.role,
      'peers': peers,
    });

    for (final peer in _clients.toList()) {
      if (identical(peer, client)) continue;
      if (peer.sessionId != client.sessionId) continue;
      peer.send({
        'type': 'peer-joined',
        'peer': {
          'clientId': client.clientId,
          'username': client.username,
          'sessionId': client.sessionId,
          'deviceId': client.deviceId,
          'role': client.role,
        },
      });
    }
  }

  void _relaySignal(_LiveSignalingClient sender, Map<String, dynamic> message) {
    final targetClientId = message['targetClientId'] as String? ?? '';
    if (targetClientId.isEmpty) return;
    _LiveSignalingClient? target;
    for (final client in _clients) {
      if (client.clientId == targetClientId) {
        target = client;
        break;
      }
    }
    if (target == null) return;
    target.send({
      'type': 'signal',
      'fromClientId': sender.clientId,
      'fromUsername': sender.username,
      'fromRole': sender.role,
      'sessionId': sender.sessionId,
      'data': message['data'],
    });
  }

  void _removeClient(_LiveSignalingClient client) {
    _clients.remove(client);
    for (final peer in _clients.toList()) {
      if (peer.sessionId != client.sessionId) continue;
      peer.send({
        'type': 'peer-left',
        'clientId': client.clientId,
        'username': client.username,
        'sessionId': client.sessionId,
        'role': client.role,
      });
    }
  }
}

class _LiveSignalingClient {
  _LiveSignalingClient({
    required this.clientId,
    required this.socket,
    required this.onDisconnect,
    required this.onJoin,
    required this.onSignal,
  });

  final String clientId;
  final WebSocket socket;
  final void Function(_LiveSignalingClient client) onDisconnect;
  final void Function(_LiveSignalingClient client, Map<String, dynamic> message)
  onJoin;
  final void Function(_LiveSignalingClient client, Map<String, dynamic> message)
  onSignal;

  String username = '';
  String sessionId = '';
  String deviceId = '';
  String role = 'viewer';

  void start() {
    socket.listen(
      (raw) {
        if (raw is! String) return;
        final message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        switch (message['type'] as String? ?? '') {
          case 'hello':
          case 'join':
            onJoin(this, message);
            break;
          case 'signal':
            onSignal(this, message);
            break;
          case 'ping':
            send({'type': 'pong'});
            break;
        }
      },
      onDone: () => onDisconnect(this),
      onError: (_) => onDisconnect(this),
      cancelOnError: true,
    );
  }

  void send(Map<String, dynamic> payload) {
    try {
      socket.add(jsonEncode(payload));
    } catch (_) {}
  }
}

class _PttSignalingClient {
  _PttSignalingClient({
    required this.clientId,
    required this.socket,
    required this.onDisconnect,
    required this.onJoin,
    required this.onSignal,
  });

  final String clientId;
  final WebSocket socket;
  final void Function(_PttSignalingClient client) onDisconnect;
  final void Function(_PttSignalingClient client, Map<String, dynamic> message)
  onJoin;
  final void Function(_PttSignalingClient client, Map<String, dynamic> message)
  onSignal;

  String username = '';
  String channelId = '';
  String deviceId = '';

  void start() {
    socket.listen(
      (raw) {
        if (raw is! String) return;
        final message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        switch (message['type'] as String? ?? '') {
          case 'hello':
          case 'join':
            onJoin(this, message);
            break;
          case 'signal':
            onSignal(this, message);
            break;
          case 'ping':
            send({'type': 'pong'});
            break;
        }
      },
      onDone: () => onDisconnect(this),
      onError: (_) => onDisconnect(this),
      cancelOnError: true,
    );
  }

  void send(Map<String, dynamic> payload) {
    try {
      socket.add(jsonEncode(payload));
    } catch (_) {}
  }
}

class _PttClientConnection {
  _PttClientConnection({
    required this.socket,
    required this.onDisconnect,
    required this.onAudioPacket,
  });

  final Socket socket;
  final void Function(_PttClientConnection client) onDisconnect;
  final void Function(_PttClientConnection sender, Map<String, dynamic> packet)
  onAudioPacket;

  String username = '';
  String channelId = 'ch3';
  int audioPacketCount = 0;
  int deniedPacketCount = 0;

  void start() {
    unawaited(_listen());
  }

  Future<void> _listen() async {
    try {
      await for (final raw
          in utf8.decoder.bind(socket).transform(const LineSplitter())) {
        final message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final type = message['type'] as String? ?? '';
        switch (type) {
          case 'hello':
          case 'join':
            username = message['username'] as String? ?? username;
            channelId = message['channelId'] as String? ?? channelId;
            final safeUsername = username.isEmpty ? 'unknown' : username;
            stdout.writeln(
              '[${_clockNow()}][audio-$type] $safeUsername@$channelId',
            );
            break;
          case 'audio':
            onAudioPacket(this, {
              ...message,
              'username': message['username'] ?? username,
              'channelId': message['channelId'] ?? channelId,
            });
            break;
          default:
            break;
        }
      }
    } catch (_) {
    } finally {
      try {
        await socket.close();
      } catch (_) {}
      onDisconnect(this);
    }
  }

  void send(Map<String, dynamic> payload) {
    try {
      socket.write('${jsonEncode(payload)}\n');
    } catch (_) {}
  }
}

class _PttWebSocketConnection {
  _PttWebSocketConnection({
    required this.socket,
    required this.onDisconnect,
    required this.onAudioPacket,
  });

  final WebSocket socket;
  final void Function(_PttWebSocketConnection client) onDisconnect;
  final void Function(
    _PttWebSocketConnection sender,
    Map<String, dynamic> packet,
  )
  onAudioPacket;

  String username = '';
  String channelId = 'ch3';
  int audioPacketCount = 0;
  int deniedPacketCount = 0;

  void start() {
    socket.listen(
      (raw) {
        if (raw is! String) return;
        final message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final type = message['type'] as String? ?? '';
        switch (type) {
          case 'hello':
          case 'join':
            username = message['username'] as String? ?? username;
            channelId = message['channelId'] as String? ?? channelId;
            final safeUsername = username.isEmpty ? 'unknown' : username;
            stdout.writeln(
              '[${_clockNow()}][audio-ws-$type] $safeUsername@$channelId',
            );
            break;
          case 'audio':
            onAudioPacket(this, {
              ...message,
              'username': message['username'] ?? username,
              'channelId': message['channelId'] ?? channelId,
            });
            break;
          default:
            break;
        }
      },
      onDone: () => onDisconnect(this),
      onError: (_) => onDisconnect(this),
      cancelOnError: true,
    );
  }

  void send(Map<String, dynamic> payload) {
    try {
      socket.add(jsonEncode(payload));
    } catch (_) {}
  }
}
