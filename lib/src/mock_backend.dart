import 'dart:async';
import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_gateway.dart';
import 'models.dart';

class MockBackendService implements BackendGateway {
  MockBackendService();

  static const String _chatPrefsKey = 'chat_threads_v1';
  static const String _reportPrefsKey = 'incident_reports_v1';

  @override
  String get connectionLabel => 'Mock backend lokal';

  @override
  Future<List<PresenceEntry>> loadPresence({String? channelId}) async => const [];

  @override
  Future<List<PttTransmission>> loadPttFeed({required String channelId}) async => const [];

  @override
  Future<PttStartResult> startPttTransmit({
    required String channelId,
    required String officerId,
    required String deviceId,
  }) async => PttStartResult(
    granted: true,
    channelId: channelId,
    holderOfficerId: officerId,
    message: 'Jalur PTT mock aktif.',
  );

  @override
  Future<void> stopPttTransmit({
    required String channelId,
    required String officerId,
    required int durationSeconds,
  }) async {}

  @override
  Future<void> updatePresence({
    required String username,
    required String deviceId,
    required String status,
    String? activeChannelId,
  }) async {}

  @override
  Future<Map<String, List<ChatMessage>>> loadChatThreads() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatPrefsKey);
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

  @override
  Future<void> saveChatThreads(Map<String, List<ChatMessage>> threads) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      threads.map(
        (key, value) => MapEntry(
          key,
          value.map((message) => message.toJson()).toList(),
        ),
      ),
    );
    await prefs.setString(_chatPrefsKey, encoded);
  }

  @override
  Future<List<IncidentReport>> loadReports() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reportPrefsKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => IncidentReport.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveReports(List<IncidentReport> reports) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(reports.map((item) => item.toJson()).toList());
    await prefs.setString(_reportPrefsKey, encoded);
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
    await saveChatThreads(currentThreads);
    return updated;
  }

  @override
  Future<List<ChatMessage>> appendAutoReply({
    required String threadName,
    required Map<String, List<ChatMessage>> currentThreads,
  }) async {
    final reply = _autoReplies[DateTime.now().millisecond % _autoReplies.length];
    final updated = [
      ...(currentThreads[threadName] ?? const <ChatMessage>[]),
      ChatMessage(
        fromMe: false,
        text: reply,
        timeLabel: DateFormat('HH:mm').format(DateTime.now()),
      ),
    ];
    currentThreads[threadName] = updated;
    await saveChatThreads(currentThreads);
    return updated;
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
      deliveryStatus: 'Diteruskan ke command center',
    );
    final updated = [report, ...currentReports];
    await saveReports(updated);
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
      RecordingUploadStatus.pending => 32,
      RecordingUploadStatus.syncing => (active.syncProgress + 34).clamp(0, 100),
      _ => active.syncProgress,
    };
    final nextStatus = nextProgress >= 100
        ? RecordingUploadStatus.uploaded
        : RecordingUploadStatus.syncing;
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
      backendStatusLabel: nextStatus == RecordingUploadStatus.uploaded
          ? 'Sinkron lokal selesai'
          : 'Menyiapkan upload ${nextProgress.toString().padLeft(2, '0')}%',
      isSeeded: active.isSeeded,
    );
    final updated = [...recordings];
    updated[activeIndex] = updatedEntry;
    return updated;
  }

  static const List<String> _autoReplies = [
    'Diterima, siap.',
    'Oke, copy.',
    'Siap Bripda.',
    'Posisi aman.',
    'Noted, akan ditindaklanjuti.',
  ];
}
