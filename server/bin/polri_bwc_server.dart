import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultHost = '0.0.0.0';
const _defaultPort = 8787;

Future<void> main(List<String> args) async {
  final options = _ServerOptions.fromArgs(args);
  final store = await LocalServerStore.load();
  final server = await HttpServer.bind(options.host, options.port);
  final audioRelay = PttAudioRelayServer(
    host: options.host,
    port: options.port + 1,
    canRelayAudio: (channelId, username) {
      final session = _activeSessionForChannel(store.state, channelId);
      if (session == null) return false;
      return (session['officerId'] as String? ?? '') == username;
    },
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
    unawaited(_handleRequest(request, store));
  }
}

Future<void> _handleRequest(HttpRequest request, LocalServerStore store) async {
  final response = request.response;
  _applyCors(response);

  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }

  final path = request.uri.path;
  final method = request.method.toUpperCase();

  try {
    if (method == 'GET' && path == '/api/v1/health') {
      return _writeJson(response, {
        'status': 'ok',
        'service': 'polri-bwc-local-server',
        'time': DateTime.now().toUtc().toIso8601String(),
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
      final updated = {
        ...store.state.presence,
        username: {
          'username': username,
          'deviceId': body['deviceId'] ?? '',
          'status': body['status'] ?? 'online',
          'activeChannelId': body['activeChannelId'] ?? '',
          'clientTimeIso': body['clientTimeIso'] ?? '',
          'lastSeenIso': DateTime.now().toUtc().toIso8601String(),
        },
      };
      store.state = store.state.copyWith(presence: updated);
      await store.save();
      _printPresenceSnapshot(store, reason: 'heartbeat');
      return _writeJson(response, {'status': 'ok'});
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
      final activeSession = _activeSessionForChannel(store.state, channelId);
      if (activeSession == null) {
        return _writeJson(response, {
          'status': 'idle',
          'channelId': channelId,
        });
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

Future<void> _writeJson(HttpResponse response, Object payload) async {
  response.write(jsonEncode(payload));
  await response.close();
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
                  ((_activeSessionForChannel(store.state, activeChannelId)?['officerId']
                              as String? ??
                          '') ==
                      username),
              'resolvedStatus': isOnline ? 'online' : 'offline',
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
  if ((legacy['channelId'] as String? ?? '') == channelId && legacy.isNotEmpty) {
    return legacy;
  }
  return null;
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
    final dir = Directory('server/data');
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
    required this.chatThreads,
    required this.reports,
    required this.recordings,
    required this.presence,
    required this.pttChannels,
    required this.pttFeeds,
    required this.activePttSession,
    required this.activePttSessions,
  });

  final Map<String, List<Map<String, dynamic>>> chatThreads;
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> recordings;
  final Map<String, Map<String, dynamic>> presence;
  final List<Map<String, dynamic>> pttChannels;
  final Map<String, List<Map<String, dynamic>>> pttFeeds;
  final Map<String, dynamic> activePttSession;
  final Map<String, Map<String, dynamic>> activePttSessions;

  factory LocalServerState.seed() {
    return LocalServerState(
      chatThreads: const {},
      reports: const [],
      recordings: const [],
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
      recordings: List<Map<String, dynamic>>.from(
        (json['recordings'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
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
        (key, value) => MapEntry(
          key.toString(),
          Map<String, dynamic>.from(value as Map),
        ),
      ),
    );
  }

  LocalServerState copyWith({
    Map<String, List<Map<String, dynamic>>>? chatThreads,
    List<Map<String, dynamic>>? reports,
    List<Map<String, dynamic>>? recordings,
    Map<String, Map<String, dynamic>>? presence,
    List<Map<String, dynamic>>? pttChannels,
    Map<String, List<Map<String, dynamic>>>? pttFeeds,
    Map<String, dynamic>? activePttSession,
    Map<String, Map<String, dynamic>>? activePttSessions,
  }) {
    return LocalServerState(
      chatThreads: chatThreads ?? this.chatThreads,
      reports: reports ?? this.reports,
      recordings: recordings ?? this.recordings,
      presence: presence ?? this.presence,
      pttChannels: pttChannels ?? this.pttChannels,
      pttFeeds: pttFeeds ?? this.pttFeeds,
      activePttSession: activePttSession ?? this.activePttSession,
      activePttSessions: activePttSessions ?? this.activePttSessions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chatThreads': chatThreads,
      'reports': reports,
      'recordings': recordings,
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
      return;
    }
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
