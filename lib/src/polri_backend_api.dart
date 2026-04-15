import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_config.dart';
import 'backend_gateway.dart';
import 'models.dart';

typedef SessionInvalidatedHandler = void Function(String message);

class PolriBackendApi implements BackendGateway {
  PolriBackendApi({
    required AppConfig config,
    this.onSessionInvalidated,
  }) : _config = config,
       _client = ApiClient(
         baseUrl: config.rootUrl,
         timeout: Duration(seconds: config.connectTimeoutSeconds),
       );

  final AppConfig _config;
  final ApiClient _client;
  final SessionInvalidatedHandler? onSessionInvalidated;

  static const String _chatFallbackKey = 'chat_threads_api_fallback_v1';
  static const String _reportFallbackKey = 'incident_reports_api_fallback_v1';
  static const String _sosFallbackKey = 'sos_alerts_api_fallback_v1';

  String _authUsername = '';
  String _authDeviceId = '';
  String _authSessionToken = '';
  bool _sessionInvalidationNotified = false;

  @override
  String get connectionLabel => 'API ${_config.rootUrl}';

  @override
  void setAuthContext({
    required String username,
    required String deviceId,
    required String sessionToken,
  }) {
    _authUsername = username;
    _authDeviceId = deviceId;
    _authSessionToken = sessionToken;
    _sessionInvalidationNotified = false;
  }

  @override
  void clearAuthContext() {
    _authUsername = '';
    _authDeviceId = '';
    _authSessionToken = '';
    _sessionInvalidationNotified = false;
  }

  @override
  Future<List<PresenceEntry>> loadPresence({String? channelId}) async {
    final suffix = (channelId == null || channelId.isEmpty)
        ? ''
        : '?channelId=$channelId';
    try {
      final decoded =
          await _getJson('${_config.presenceEndpoint}$suffix') as List<dynamic>;
      return decoded
          .map((item) => PresenceEntry.fromJson(item as Map<String, dynamic>))
          .toList();
    } on _SessionInvalidatedException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<PttTransmission>> loadPttFeed({required String channelId}) async {
    try {
      final decoded =
          await _getJson(
                '${_config.pttFeedEndpoint}?channelId=$channelId',
              )
              as List<dynamic>;
      return decoded.map((item) {
        final json = item as Map<String, dynamic>;
        return PttTransmission(
          initials: json['initials'] as String? ?? '--',
          speakerName: json['speakerName'] as String? ?? 'Unknown',
          statusLabel: json['statusLabel'] as String? ?? '',
          timeLabel: json['timeLabel'] as String? ?? '',
          waveLevel: (json['waveLevel'] as num?)?.toDouble() ?? 0.0,
          accentColor: _parseColor(json['accentColorHex'] as String?),
          isSystem: json['isSystem'] as bool? ?? false,
        );
      }).toList();
    } on _SessionInvalidatedException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<PttStartResult> startPttTransmit({
    required String channelId,
    required String officerId,
    required String deviceId,
  }) async {
    try {
      final response = await _postJsonWithStatus(
        _config.pttTransmitStartEndpoint,
        {'channelId': channelId, 'officerId': officerId, 'deviceId': deviceId},
      );
      final body = Map<String, dynamic>.from(response.body as Map? ?? const {});
      if (response.statusCode == 409 ||
          (body['status'] as String? ?? '') == 'busy') {
        final holder = body['holderOfficerId'] as String? ?? '';
        return PttStartResult(
          granted: false,
          isBusy: true,
          holderOfficerId: holder,
          channelId: body['channelId'] as String? ?? channelId,
          sessionId: body['sessionId'] as String? ?? '',
          message: holder.isEmpty
              ? 'Channel sedang dipakai.'
              : 'Channel sedang dipakai $holder.',
        );
      }
      return PttStartResult(
        granted: true,
        channelId: body['channelId'] as String? ?? channelId,
        holderOfficerId: officerId,
        sessionId: body['sessionId'] as String? ?? '',
        message: 'Jalur PTT aktif.',
      );
    } on _SessionInvalidatedException {
      return const PttStartResult(
        granted: false,
        message: 'Sesi login sudah dipakai perangkat lain.',
      );
    } catch (_) {
      return const PttStartResult(
        granted: false,
        message: 'Gagal menghubungi server PTT.',
      );
    }
  }

  @override
  Future<void> stopPttTransmit({
    required String channelId,
    required String officerId,
    required int durationSeconds,
  }) async {
    try {
      await _postJson(_config.pttTransmitStopEndpoint, {
        'channelId': channelId,
        'officerId': officerId,
        'durationSeconds': durationSeconds,
      });
    } on _SessionInvalidatedException {
      return;
    } catch (_) {}
  }

  @override
  Future<void> updatePresence({
    required String username,
    required String deviceId,
    required String status,
    String? activeChannelId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _postJson('${_config.presenceEndpoint}/heartbeat', {
        'username': username,
        'deviceId': deviceId,
        'status': status,
        'activeChannelId': activeChannelId ?? '',
        'clientTimeIso': DateTime.now().toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
      });
    } on _SessionInvalidatedException {
      return;
    } catch (_) {}
  }

  @override
  Future<Map<String, List<ChatMessage>>> loadChatThreads() async {
    try {
      final decoded =
          await _getJson(_config.chatsEndpoint) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
              .toList(),
        ),
      );
    } on _SessionInvalidatedException {
      return _loadThreadFallback();
    } catch (_) {
      return _loadThreadFallback();
    }
  }

  @override
  Future<void> saveChatThreads(Map<String, List<ChatMessage>> threads) async {
    try {
      await _postJson(_config.chatsEndpoint, {
        'threads': threads.map(
          (key, value) =>
              MapEntry(key, value.map((item) => item.toJson()).toList()),
        ),
      });
    } on _SessionInvalidatedException {
      return;
    } catch (_) {
      await _saveThreadFallback(threads);
    }
  }

  @override
  Future<List<IncidentReport>> loadReports() async {
    try {
      final decoded = await _getJson(_config.reportsEndpoint) as List<dynamic>;
      return decoded
          .map((item) => IncidentReport.fromJson(item as Map<String, dynamic>))
          .toList();
    } on _SessionInvalidatedException {
      return _loadReportsFallback();
    } catch (_) {
      return _loadReportsFallback();
    }
  }

  @override
  Future<void> saveReports(List<IncidentReport> reports) async {
    try {
      await _postJson(_config.reportsEndpoint, {
        'reports': reports.map((item) => item.toJson()).toList(),
      });
    } on _SessionInvalidatedException {
      return;
    } catch (_) {
      await _saveReportsFallback(reports);
    }
  }

  @override
  Future<List<SosAlert>> loadSosAlerts() async {
    try {
      final decoded = await _getJson(_config.sosEndpoint) as List<dynamic>;
      return decoded
          .map((item) => SosAlert.fromJson(item as Map<String, dynamic>))
          .toList();
    } on _SessionInvalidatedException {
      return _loadSosFallback();
    } catch (_) {
      return _loadSosFallback();
    }
  }

  @override
  Future<List<LiveStreamSession>> loadLiveSessions() async {
    try {
      final decoded =
          await _getJson(_config.liveSessionsEndpoint) as List<dynamic>;
      return decoded
          .map(
            (item) => LiveStreamSession.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } on _SessionInvalidatedException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<LiveStreamSession?> startLiveStream({
    required String officerId,
    required String officerName,
    required String deviceId,
    required String channelId,
    required String tagLabel,
    required String preferredTransport,
    required String fallbackTransport,
    required String signalingUrl,
    double? latitude,
    double? longitude,
    String? locationLabel,
  }) async {
    try {
      final response = await _postJson(_config.liveSessionsEndpoint, {
        'officerId': officerId,
        'officerName': officerName,
        'deviceId': deviceId,
        'channelId': channelId,
        'tagLabel': tagLabel,
        'preferredTransport': preferredTransport,
        'fallbackTransport': fallbackTransport,
        'signalingUrl': signalingUrl,
        'clientCapabilities': const [
          'webrtc-signaling',
          'snapshot-upload',
          'dashboard-viewer',
        ],
        'latitude': latitude,
        'longitude': longitude,
        'locationLabel': locationLabel ?? 'Lokasi tidak tersedia',
      });
      return LiveStreamSession.fromJson(response as Map<String, dynamic>);
    } on _SessionInvalidatedException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> pushLiveFrame({
    required String sessionId,
    required String officerId,
    required String frameDataUrl,
    double? latitude,
    double? longitude,
    String? locationLabel,
  }) async {
    try {
      await _postJson('${_config.liveSessionsEndpoint}/frame', {
        'sessionId': sessionId,
        'officerId': officerId,
        'frameDataUrl': frameDataUrl,
        'latitude': latitude,
        'longitude': longitude,
        'locationLabel': locationLabel ?? 'Lokasi tidak tersedia',
      });
    } on _SessionInvalidatedException {
      return;
    } catch (_) {}
  }

  @override
  Future<void> stopLiveStream({
    required String sessionId,
    required String officerId,
  }) async {
    try {
      await _postJson('${_config.liveSessionsEndpoint}/stop', {
        'sessionId': sessionId,
        'officerId': officerId,
      });
    } on _SessionInvalidatedException {
      return;
    } catch (_) {}
  }

  @override
  Future<SosAlert?> triggerSos({
    required String officerId,
    required String officerName,
    required String deviceId,
    required String channelId,
    required String source,
    String recordingId = '',
    String targetOfficerId = '',
    double? latitude,
    double? longitude,
    String? locationLabel,
    String? notes,
  }) async {
    final payload = {
      'officerId': officerId,
      'officerName': officerName,
      'deviceId': deviceId,
      'channelId': channelId,
      'source': source,
      'recordingId': recordingId,
      'targetOfficerId': targetOfficerId,
      'latitude': latitude,
      'longitude': longitude,
      'locationLabel': locationLabel ?? 'Lokasi tidak tersedia',
      'notes': notes ?? '',
    };
    try {
      final response = await _postJson(_config.sosEndpoint, payload);
      final alert = SosAlert.fromJson(response as Map<String, dynamic>);
      final existing = await _loadSosFallback();
      await _saveSosFallback([alert, ...existing]);
      return alert;
    } on _SessionInvalidatedException {
      return null;
    } catch (_) {
      final alert = SosAlert(
        id: 'SOS_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
        officerId: officerId,
        officerName: officerName,
        deviceId: deviceId,
        channelId: channelId,
        status: 'queued',
        triggeredAtIso: DateTime.now().toIso8601String(),
        locationLabel: locationLabel ?? 'Lokasi tidak tersedia',
        source: source,
        latitude: latitude,
        longitude: longitude,
        recordingId: recordingId,
        targetOfficerId: targetOfficerId,
        notes: notes ?? '',
      );
      final existing = await _loadSosFallback();
      await _saveSosFallback([alert, ...existing]);
      return alert;
    }
  }

  @override
  Future<List<ChatMessage>> appendMessage({
    required String threadName,
    required Map<String, List<ChatMessage>> currentThreads,
    required String text,
  }) async {
    final now = DateFormat('HH:mm').format(DateTime.now());
    final updated = [
      ...(currentThreads[threadName] ?? const <ChatMessage>[]),
      ChatMessage(fromMe: true, text: text, timeLabel: now),
    ];
    currentThreads[threadName] = updated;

    try {
      await _postJson('${_config.chatsEndpoint}/message', {
        'threadName': threadName,
        'message': {'fromMe': true, 'text': text, 'timeLabel': now},
      });
    } on _SessionInvalidatedException {
      return currentThreads[threadName] ?? const <ChatMessage>[];
    } catch (_) {}

    await _saveThreadFallback(currentThreads);
    return updated;
  }

  @override
  Future<List<ChatMessage>> appendAutoReply({
    required String threadName,
    required Map<String, List<ChatMessage>> currentThreads,
  }) async {
    try {
      final response = await _postJson('${_config.chatsEndpoint}/auto-reply', {
        'threadName': threadName,
      });
      final items = (response['messages'] as List<dynamic>)
          .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
          .toList();
      currentThreads[threadName] = items;
      await _saveThreadFallback(currentThreads);
      return items;
    } on _SessionInvalidatedException {
      return currentThreads[threadName] ?? const <ChatMessage>[];
    } catch (_) {
      final fallback = ChatMessage(
        fromMe: false,
        text: _autoReplies[DateTime.now().millisecond % _autoReplies.length],
        timeLabel: DateFormat('HH:mm').format(DateTime.now()),
      );
      final updated = [
        ...(currentThreads[threadName] ?? const <ChatMessage>[]),
        fallback,
      ];
      currentThreads[threadName] = updated;
      await _saveThreadFallback(currentThreads);
      return updated;
    }
  }

  @override
  Future<IncidentReport> submitReport({
    required List<IncidentReport> currentReports,
    required String type,
    required String description,
    required String witness,
    required RecordingEntry recording,
  }) async {
    final report = IncidentReport(
      id: 'IR_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      type: type,
      description: description,
      witness: witness,
      recordingId: recording.id,
      recordedAtIso: DateTime.now().toIso8601String(),
      locationLabel: recording.locationLabel,
      deliveryStatus: 'Dikirim ke endpoint',
    );

    try {
      await _postJson(_config.reportsEndpoint, report.toJson());
    } on _SessionInvalidatedException {
      return report;
    } catch (_) {}

    final updated = [report, ...currentReports];
    await _saveReportsFallback(updated);
    return report;
  }

  @override
  List<RecordingEntry> syncOnePending(List<RecordingEntry> recordings) {
    final activeIndex = recordings.indexWhere(
      (item) =>
          item.status == RecordingUploadStatus.pending ||
          item.status == RecordingUploadStatus.syncing,
    );
    if (activeIndex == -1) return recordings;
    final active = recordings[activeIndex];
    final nextProgress = switch (active.status) {
      RecordingUploadStatus.pending => 28,
      RecordingUploadStatus.syncing => (active.syncProgress + 36).clamp(0, 100),
      _ => active.syncProgress,
    };
    final nextStatus = nextProgress >= 100
        ? RecordingUploadStatus.uploaded
        : RecordingUploadStatus.syncing;
    final deliveryStatus = nextStatus == RecordingUploadStatus.uploaded
        ? 'Tersinkron ke server'
        : 'Upload chunk ${nextProgress.toString().padLeft(2, '0')}%';

    final updatedEntry = RecordingEntry(
      id: active.id,
      officerName: active.officerName,
      unitName: active.unitName,
      recordedAtIso: active.recordedAtIso,
      filePath: active.filePath,
      latitude: active.latitude,
      longitude: active.longitude,
      source: active.source,
      notes: active.notes,
      status: nextStatus,
      durationSeconds: active.durationSeconds,
      sizeBytes: active.sizeBytes,
      locationLabel: active.locationLabel,
      tagLabel: active.tagLabel,
      relatedToCase: active.relatedToCase,
      syncProgress: nextStatus == RecordingUploadStatus.uploaded
          ? 100
          : nextProgress,
      backendStatusLabel: deliveryStatus,
      isSeeded: active.isSeeded,
    );
    final updated = [...recordings];
    updated[activeIndex] = updatedEntry;
    return updated;
  }

  Map<String, String>? _authHeaders() {
    if (_authUsername.isEmpty ||
        _authDeviceId.isEmpty ||
        _authSessionToken.isEmpty) {
      return null;
    }
    return {
      'X-Auth-Username': _authUsername,
      'X-Auth-Device-Id': _authDeviceId,
      'X-Auth-Session-Token': _authSessionToken,
    };
  }

  Future<dynamic> _getJson(String endpoint) async {
    final response = await _client.getJsonWithStatus(
      endpoint,
      headers: _authHeaders(),
    );
    if (response.statusCode == 401) {
      _handleUnauthorized(response.body);
      throw const _SessionInvalidatedException();
    }
    return response.body;
  }

  Future<ApiResponse> _postJsonWithStatus(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.postJsonWithStatus(
      endpoint,
      body,
      headers: _authHeaders(),
    );
    if (response.statusCode == 401) {
      _handleUnauthorized(response.body);
      throw const _SessionInvalidatedException();
    }
    return response;
  }

  Future<dynamic> _postJson(String endpoint, Map<String, dynamic> body) async {
    final response = await _postJsonWithStatus(endpoint, body);
    return response.body;
  }

  void _handleUnauthorized(dynamic body) {
    if (_sessionInvalidationNotified) return;
    _sessionInvalidationNotified = true;
    final json = body is Map ? Map<String, dynamic>.from(body) : const {};
    final code = json['code'] as String? ?? '';
    final message = json['error'] as String? ?? '';
    onSessionInvalidated?.call(
      code == 'session_taken_over'
          ? (message.isEmpty
                ? 'Sesi akun ini sudah diambil alih perangkat lain.'
                : message)
          : (message.isEmpty
                ? 'Sesi login tidak lagi valid. Silakan login ulang.'
                : message),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) {
      return const Color(0xFF6DE7C6);
    }
    final normalized = hex.replaceFirst('#', '');
    final value = int.tryParse(
      normalized.length == 6 ? 'FF$normalized' : normalized,
      radix: 16,
    );
    return Color(value ?? 0xFF6DE7C6);
  }

  Future<Map<String, List<ChatMessage>>> _loadThreadFallback() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatFallbackKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(
        key,
        (value as List<dynamic>)
            .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
            .toList(),
      ),
    );
  }

  Future<void> _saveThreadFallback(
    Map<String, List<ChatMessage>> threads,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      threads.map(
        (key, value) =>
            MapEntry(key, value.map((item) => item.toJson()).toList()),
      ),
    );
    await prefs.setString(_chatFallbackKey, encoded);
  }

  Future<List<IncidentReport>> _loadReportsFallback() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reportFallbackKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => IncidentReport.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveReportsFallback(List<IncidentReport> reports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _reportFallbackKey,
      jsonEncode(reports.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<SosAlert>> _loadSosFallback() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sosFallbackKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => SosAlert.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveSosFallback(List<SosAlert> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sosFallbackKey,
      jsonEncode(alerts.map((item) => item.toJson()).toList()),
    );
  }

  static const List<String> _autoReplies = [
    'Diterima di endpoint komando.',
    'Packet status aman, lanjutkan patroli.',
    'Siap. Telemetri sudah masuk.',
    'Command center menerima update Anda.',
  ];
}

class _SessionInvalidatedException implements Exception {
  const _SessionInvalidatedException();
}
