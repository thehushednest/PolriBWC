import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum BodyWornTab { home, record, map, ptt, gallery, report }

enum RecordingUploadStatus { uploaded, pending, syncing, failed }

class OfficerSession {
  const OfficerSession({
    required this.officerName,
    required this.rankLabel,
    required this.unitName,
    required this.shiftLabel,
    required this.shiftWindow,
    required this.nrp,
    required this.deviceId,
    required this.sessionToken,
  });

  final String officerName;
  final String rankLabel;
  final String unitName;
  final String shiftLabel;
  final String shiftWindow;
  final String nrp;
  final String deviceId;
  final String sessionToken;

  String get fullName => '$rankLabel $officerName';

  Map<String, dynamic> toJson() {
    return {
      'nrp': nrp,
      'officerName': officerName,
      'rankLabel': rankLabel,
      'unitName': unitName,
      'shiftLabel': shiftLabel,
      'shiftWindow': shiftWindow,
      'deviceId': deviceId,
      'sessionToken': sessionToken,
    };
  }

  factory OfficerSession.fromJson(Map<String, dynamic> json) {
    return OfficerSession(
      nrp: json['nrp'] as String,
      officerName: json['officerName'] as String,
      rankLabel: json['rankLabel'] as String? ?? '',
      unitName: json['unitName'] as String? ?? '',
      shiftLabel: json['shiftLabel'] as String? ?? '',
      shiftWindow: json['shiftWindow'] as String? ?? '',
      deviceId: json['deviceId'] as String,
      sessionToken: json['sessionToken'] as String,
    );
  }
}

class PermissionSummary {
  const PermissionSummary({
    this.cameraGranted = false,
    this.microphoneGranted = false,
    this.locationGranted = false,
  });

  final bool cameraGranted;
  final bool microphoneGranted;
  final bool locationGranted;

  factory PermissionSummary.fromStatuses(
    Map<Permission, PermissionStatus> statuses,
  ) {
    return PermissionSummary(
      cameraGranted: statuses[Permission.camera]?.isGranted ?? false,
      microphoneGranted: statuses[Permission.microphone]?.isGranted ?? false,
      locationGranted:
          statuses[Permission.locationWhenInUse]?.isGranted ?? false,
    );
  }
}

class RecordingEntry {
  const RecordingEntry({
    required this.id,
    required this.officerName,
    required this.unitName,
    required this.recordedAtIso,
    required this.filePath,
    required this.latitude,
    required this.longitude,
    required this.source,
    required this.notes,
    required this.status,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.locationLabel,
    required this.tagLabel,
    this.relatedToCase = false,
    this.syncProgress = 0,
    this.backendStatusLabel = '',
    this.isSeeded = true,
  });

  final String id;
  final String officerName;
  final String unitName;
  final String recordedAtIso;
  final String filePath;
  final double? latitude;
  final double? longitude;
  final String source;
  final String notes;
  final RecordingUploadStatus status;
  final int durationSeconds;
  final int sizeBytes;
  final String locationLabel;
  final String tagLabel;
  final bool relatedToCase;
  final int syncProgress;
  final String backendStatusLabel;
  final bool isSeeded;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'officerName': officerName,
      'unitName': unitName,
      'recordedAtIso': recordedAtIso,
      'filePath': filePath,
      'latitude': latitude,
      'longitude': longitude,
      'source': source,
      'notes': notes,
      'status': status.name,
      'durationSeconds': durationSeconds,
      'sizeBytes': sizeBytes,
      'locationLabel': locationLabel,
      'tagLabel': tagLabel,
      'relatedToCase': relatedToCase,
      'syncProgress': syncProgress,
      'backendStatusLabel': backendStatusLabel,
    };
  }

  factory RecordingEntry.fromJson(Map<String, dynamic> json) {
    return RecordingEntry(
      id: json['id'] as String,
      officerName: json['officerName'] as String,
      unitName: json['unitName'] as String,
      recordedAtIso: json['recordedAtIso'] as String,
      filePath: json['filePath'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      source: json['source'] as String,
      notes: json['notes'] as String,
      status: RecordingUploadStatus.values.byName(json['status'] as String),
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      locationLabel:
          json['locationLabel'] as String? ?? 'Lokasi tidak tersedia',
      tagLabel: json['tagLabel'] as String? ?? 'Lainnya',
      relatedToCase: json['relatedToCase'] as bool? ?? false,
      syncProgress: json['syncProgress'] as int? ?? 0,
      backendStatusLabel: json['backendStatusLabel'] as String? ?? '',
      isSeeded: false,
    );
  }
}

class PersonnelStatus {
  const PersonnelStatus({
    required this.initials,
    required this.name,
    required this.detail,
    required this.status,
    required this.statusColor,
    required this.dotColor,
    this.distanceLabel = '',
    this.signalLabel = 'Online',
  });

  final String initials;
  final String name;
  final String detail;
  final String status;
  final Color statusColor;
  final Color dotColor;
  final String distanceLabel;
  final String signalLabel;
}

class ChatMessage {
  const ChatMessage({
    required this.fromMe,
    required this.text,
    required this.timeLabel,
  });

  final bool fromMe;
  final String text;
  final String timeLabel;

  Map<String, dynamic> toJson() {
    return {'fromMe': fromMe, 'text': text, 'timeLabel': timeLabel};
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      fromMe: json['fromMe'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      timeLabel: json['timeLabel'] as String? ?? '',
    );
  }
}

class IncidentReport {
  const IncidentReport({
    required this.id,
    required this.type,
    required this.description,
    required this.witness,
    required this.recordingId,
    required this.recordedAtIso,
    required this.locationLabel,
    this.deliveryStatus = 'Terkirim',
  });

  final String id;
  final String type;
  final String description;
  final String witness;
  final String recordingId;
  final String recordedAtIso;
  final String locationLabel;
  final String deliveryStatus;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'witness': witness,
      'recordingId': recordingId,
      'recordedAtIso': recordedAtIso,
      'locationLabel': locationLabel,
      'deliveryStatus': deliveryStatus,
    };
  }

  factory IncidentReport.fromJson(Map<String, dynamic> json) {
    return IncidentReport(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'Lainnya',
      description: json['description'] as String? ?? '',
      witness: json['witness'] as String? ?? '',
      recordingId: json['recordingId'] as String? ?? '',
      recordedAtIso: json['recordedAtIso'] as String? ?? '',
      locationLabel:
          json['locationLabel'] as String? ?? 'Lokasi tidak tersedia',
      deliveryStatus: json['deliveryStatus'] as String? ?? 'Terkirim',
    );
  }
}

class SosAlert {
  const SosAlert({
    required this.id,
    required this.officerId,
    required this.officerName,
    required this.deviceId,
    required this.channelId,
    required this.status,
    required this.triggeredAtIso,
    required this.locationLabel,
    required this.source,
    this.latitude,
    this.longitude,
    this.recordingId = '',
    this.targetOfficerId = '',
    this.notes = '',
  });

  final String id;
  final String officerId;
  final String officerName;
  final String deviceId;
  final String channelId;
  final String status;
  final String triggeredAtIso;
  final String locationLabel;
  final String source;
  final double? latitude;
  final double? longitude;
  final String recordingId;
  final String targetOfficerId;
  final String notes;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'officerId': officerId,
      'officerName': officerName,
      'deviceId': deviceId,
      'channelId': channelId,
      'status': status,
      'triggeredAtIso': triggeredAtIso,
      'locationLabel': locationLabel,
      'source': source,
      'latitude': latitude,
      'longitude': longitude,
      'recordingId': recordingId,
      'targetOfficerId': targetOfficerId,
      'notes': notes,
    };
  }

  factory SosAlert.fromJson(Map<String, dynamic> json) {
    return SosAlert(
      id: json['id'] as String? ?? '',
      officerId: json['officerId'] as String? ?? '',
      officerName: json['officerName'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
      status: json['status'] as String? ?? 'new',
      triggeredAtIso: json['triggeredAtIso'] as String? ?? '',
      locationLabel:
          json['locationLabel'] as String? ?? 'Lokasi tidak tersedia',
      source: json['source'] as String? ?? 'app',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      recordingId: json['recordingId'] as String? ?? '',
      targetOfficerId: json['targetOfficerId'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}

class PttChannel {
  const PttChannel({
    required this.id,
    required this.label,
    required this.subtitle,
    this.isSelected = false,
  });

  final String id;
  final String label;
  final String subtitle;
  final bool isSelected;
}

class PttTransmission {
  const PttTransmission({
    required this.initials,
    required this.speakerName,
    required this.statusLabel,
    required this.timeLabel,
    required this.waveLevel,
    required this.accentColor,
    this.isSystem = false,
  });

  final String initials;
  final String speakerName;
  final String statusLabel;
  final String timeLabel;
  final double waveLevel;
  final Color accentColor;
  final bool isSystem;
}

class PttStartResult {
  const PttStartResult({
    required this.granted,
    this.isBusy = false,
    this.holderOfficerId = '',
    this.channelId = '',
    this.sessionId = '',
    this.message = '',
  });

  final bool granted;
  final bool isBusy;
  final String holderOfficerId;
  final String channelId;
  final String sessionId;
  final String message;
}

class PresenceEntry {
  const PresenceEntry({
    required this.username,
    required this.deviceId,
    required this.status,
    required this.activeChannelId,
    required this.lastSeenIso,
    required this.resolvedStatus,
    this.latitude,
    this.longitude,
    this.isTalking = false,
    this.signalLabel = 'Online',
  });

  final String username;
  final String deviceId;
  final String status;
  final String activeChannelId;
  final String lastSeenIso;
  final String resolvedStatus;
  final double? latitude;
  final double? longitude;
  final bool isTalking;
  final String signalLabel;

  bool get hasLocation => latitude != null && longitude != null;

  factory PresenceEntry.fromJson(Map<String, dynamic> json) {
    return PresenceEntry(
      username: json['username'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      status: json['status'] as String? ?? 'offline',
      activeChannelId: json['activeChannelId'] as String? ?? '',
      lastSeenIso: json['lastSeenIso'] as String? ?? '',
      resolvedStatus: json['resolvedStatus'] as String? ?? 'offline',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isTalking: json['isTalking'] as bool? ?? false,
      signalLabel: json['signalLabel'] as String? ?? 'Online',
    );
  }

  String get initials {
    if (username.isEmpty) return '--';
    final compact = username.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (compact.length <= 2) return compact.toUpperCase();
    return compact.substring(0, 2).toUpperCase();
  }
}

class LiveStreamSession {
  const LiveStreamSession({
    required this.sessionId,
    required this.officerId,
    required this.officerName,
    required this.deviceId,
    required this.status,
    required this.startedAtIso,
    required this.locationLabel,
    this.tagLabel = 'Lainnya',
    this.channelId = '',
    this.latitude,
    this.longitude,
    this.lastFrameAtIso = '',
    this.frameDataUrl = '',
    this.frameCount = 0,
    this.transport = 'snapshot',
    this.signalingUrl = '',
    this.viewerUrl = '',
    this.signalingState = 'idle',
  });

  final String sessionId;
  final String officerId;
  final String officerName;
  final String deviceId;
  final String status;
  final String startedAtIso;
  final String locationLabel;
  final String tagLabel;
  final String channelId;
  final double? latitude;
  final double? longitude;
  final String lastFrameAtIso;
  final String frameDataUrl;
  final int frameCount;
  final String transport;
  final String signalingUrl;
  final String viewerUrl;
  final String signalingState;

  factory LiveStreamSession.fromJson(Map<String, dynamic> json) {
    return LiveStreamSession(
      sessionId: json['sessionId'] as String? ?? '',
      officerId: json['officerId'] as String? ?? '',
      officerName: json['officerName'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      status: json['status'] as String? ?? 'idle',
      startedAtIso: json['startedAtIso'] as String? ?? '',
      locationLabel:
          json['locationLabel'] as String? ?? 'Lokasi tidak tersedia',
      tagLabel: json['tagLabel'] as String? ?? 'Lainnya',
      channelId: json['channelId'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      lastFrameAtIso: json['lastFrameAtIso'] as String? ?? '',
      frameDataUrl: json['frameDataUrl'] as String? ?? '',
      frameCount: json['frameCount'] as int? ?? 0,
      transport: json['transport'] as String? ?? 'snapshot',
      signalingUrl: json['signalingUrl'] as String? ?? '',
      viewerUrl: json['viewerUrl'] as String? ?? '',
      signalingState: json['signalingState'] as String? ?? 'idle',
    );
  }
}
