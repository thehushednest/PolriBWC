import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum BodyWornTab {
  home,
  record,
  map,
  ptt,
  gallery,
  report,
}

enum RecordingUploadStatus {
  uploaded,
  pending,
  syncing,
  failed,
}

class OfficerSession {
  const OfficerSession({
    required this.officerName,
    required this.rankLabel,
    required this.unitName,
    required this.shiftLabel,
    required this.shiftWindow,
    required this.nrp,
  });

  final String officerName;
  final String rankLabel;
  final String unitName;
  final String shiftLabel;
  final String shiftWindow;
  final String nrp;

  String get fullName => '$rankLabel $officerName';
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
      locationGranted: statuses[Permission.locationWhenInUse]?.isGranted ?? false,
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
      locationLabel: json['locationLabel'] as String? ?? 'Lokasi tidak tersedia',
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
    return {
      'fromMe': fromMe,
      'text': text,
      'timeLabel': timeLabel,
    };
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
      locationLabel: json['locationLabel'] as String? ?? 'Lokasi tidak tersedia',
      deliveryStatus: json['deliveryStatus'] as String? ?? 'Terkirim',
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
    this.isTalking = false,
    this.signalLabel = 'Online',
  });

  final String username;
  final String deviceId;
  final String status;
  final String activeChannelId;
  final String lastSeenIso;
  final String resolvedStatus;
  final bool isTalking;
  final String signalLabel;

  factory PresenceEntry.fromJson(Map<String, dynamic> json) {
    return PresenceEntry(
      username: json['username'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      status: json['status'] as String? ?? 'offline',
      activeChannelId: json['activeChannelId'] as String? ?? '',
      lastSeenIso: json['lastSeenIso'] as String? ?? '',
      resolvedStatus: json['resolvedStatus'] as String? ?? 'offline',
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
