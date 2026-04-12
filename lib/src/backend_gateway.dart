import 'models.dart';

abstract class BackendGateway {
  Future<List<PresenceEntry>> loadPresence({String? channelId});
  Future<List<PttTransmission>> loadPttFeed({required String channelId});
  Future<PttStartResult> startPttTransmit({
    required String channelId,
    required String officerId,
    required String deviceId,
  });
  Future<void> stopPttTransmit({
    required String channelId,
    required String officerId,
    required int durationSeconds,
  });
  Future<void> updatePresence({
    required String username,
    required String deviceId,
    required String status,
    String? activeChannelId,
    double? latitude,
    double? longitude,
  });
  Future<Map<String, List<ChatMessage>>> loadChatThreads();
  Future<void> saveChatThreads(Map<String, List<ChatMessage>> threads);
  Future<List<IncidentReport>> loadReports();
  Future<void> saveReports(List<IncidentReport> reports);
  Future<List<ChatMessage>> appendMessage({
    required String threadName,
    required Map<String, List<ChatMessage>> currentThreads,
    required String text,
  });
  Future<List<ChatMessage>> appendAutoReply({
    required String threadName,
    required Map<String, List<ChatMessage>> currentThreads,
  });
  Future<IncidentReport> submitReport({
    required List<IncidentReport> currentReports,
    required String type,
    required String description,
    required String witness,
    required RecordingEntry recording,
  });
  List<RecordingEntry> syncOnePending(List<RecordingEntry> recordings);
  String get connectionLabel;
}
