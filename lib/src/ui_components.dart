import 'package:flutter/material.dart';

import 'models.dart';
import 'storage.dart';

const Color kBluePrimary = Color(0xFF2B61AE);
const Color kBlueSoft = Color(0xFF7CA6DE);
const Color kBlueLight = Color(0xFFECF3FF);
const Color kCream = Color(0xFFF3EFE5);
const Color kBorder = Color(0xFFE1E6EF);
const Color kBorderLight = Color(0xFFEEF2F8);
const Color kTextMain = Color(0xFF18202B);
const Color kTextMuted = Color(0xFF6A7688);
const Color kTextSubtle = Color(0xFF9AA6B6);
const Color kSurface = Colors.white;
const Color kGreenSuccess = Color(0xFF1A9D63);
const Color kOrangeWarn = Color(0xFFAF7A17);
const Color kRedDanger = Color(0xFFBE3D3D);

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: kTextMain,
      ),
    );
  }
}

class PermissionPill extends StatelessWidget {
  const PermissionPill({
    super.key,
    required this.label,
    required this.enabled,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFE8F5EE) : const Color(0xFFF6EEDC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: enabled ? const Color(0xFF1B8B58) : const Color(0xFFAC7B1C),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.value,
    required this.label,
    this.accentColor = kTextMain,
    this.compactValue = false,
    this.leadingIcon,
    this.footerLabel,
  });

  final String value;
  final String label;
  final Color accentColor;
  final bool compactValue;
  final IconData? leadingIcon;
  final String? footerLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 16, color: accentColor),
            const SizedBox(height: 8),
          ],
          Text(
            value,
            style: TextStyle(
              fontSize: compactValue ? 15 : 18,
              height: 1,
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF556274),
              fontSize: 12,
              height: 1.15,
            ),
          ),
          if (footerLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              footerLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8A96A8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RecentRecordingCard extends StatelessWidget {
  const RecentRecordingCard({
    super.key,
    required this.entry,
    required this.formatDate,
  });

  final RecordingEntry entry;
  final String Function(String iso) formatDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: entry.status == RecordingUploadStatus.uploaded
                  ? const Color(0xFFDCEBFA)
                  : const Color(0xFFEAECF0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.videocam_rounded,
              size: 22,
              color: entry.status == RecordingUploadStatus.uploaded
                  ? kBluePrimary
                  : kTextSubtle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.id,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F1724),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatDate(entry.recordedAtIso)} - ${entry.notes}',
                  style: const TextStyle(
                    color: kTextMuted,
                    fontSize: 12.5,
                  ),
                ),
                if (entry.backendStatusLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.backendStatusLabel,
                    style: const TextStyle(
                      color: kBluePrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (entry.status == RecordingUploadStatus.syncing) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: entry.syncProgress / 100,
                      backgroundColor: const Color(0xFFE3E9F3),
                      valueColor: const AlwaysStoppedAnimation(kBluePrimary),
                    ),
                  ),
                ],
                if (entry.relatedToCase) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Terkait kasus',
                    style: TextStyle(
                      color: kBluePrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          StatusChip(label: _statusLabel(entry), state: entry.status),
        ],
      ),
    );
  }

  String _statusLabel(RecordingEntry entry) {
    return switch (entry.status) {
      RecordingUploadStatus.uploaded => 'Selesai',
      RecordingUploadStatus.pending => 'Tertunda',
      RecordingUploadStatus.syncing => '${entry.syncProgress}%',
      RecordingUploadStatus.failed => 'Gagal',
    };
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.state,
  });

  final String label;
  final RecordingUploadStatus state;

  @override
  Widget build(BuildContext context) {
    final uploaded = state == RecordingUploadStatus.uploaded;
    final syncing = state == RecordingUploadStatus.syncing;
    final failed = state == RecordingUploadStatus.failed;

    final bgColor = uploaded
        ? const Color(0xFFE5F7EC)
        : failed
            ? const Color(0xFFFBE6E6)
            : syncing
                ? const Color(0xFFE8F0FF)
                : const Color(0xFFF9EED6);
    final fgColor = uploaded
        ? kGreenSuccess
        : failed
            ? kRedDanger
            : syncing
                ? kBluePrimary
                : kOrangeWarn;
    final iconData = uploaded
        ? Icons.cloud_done_rounded
        : failed
            ? Icons.error_outline_rounded
            : syncing
                ? Icons.sync_rounded
                : Icons.schedule_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class RecordMetric extends StatelessWidget {
  const RecordMetric({
    super.key,
    required this.title,
    required this.value,
    this.accent = Colors.white,
    this.onTap,
  });

  final String title;
  final String value;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF202636),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF75809C),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class PersonnelTile extends StatelessWidget {
  const PersonnelTile({
    super.key,
    required this.personnel,
    this.onChat,
    this.onSos,
  });

  final PersonnelStatus personnel;
  final VoidCallback? onChat;
  final VoidCallback? onSos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: personnel.dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFE7EFFA),
              child: Text(
                personnel.initials,
                style: const TextStyle(
                  color: Color(0xFF3365B1),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    personnel.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    personnel.detail,
                    style: const TextStyle(
                      color: kTextMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  if (personnel.distanceLabel.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${personnel.distanceLabel} - ${personnel.signalLabel}',
                      style: const TextStyle(
                        color: Color(0xFF8B97A8),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: personnel.statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                personnel.status,
                style: TextStyle(
                  color: personnel.statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        if (onChat != null || onSos != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (onChat != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onChat,
                    icon: const Icon(Icons.chat_bubble_outline, size: 15),
                    label: const Text(
                      'Chat',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kBluePrimary,
                      side: const BorderSide(color: Color(0xFFB8CEED)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
              if (onChat != null && onSos != null) const SizedBox(width: 8),
              if (onSos != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSos,
                    icon: const Icon(Icons.sos_rounded, size: 15),
                    label: const Text(
                      'SOS',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kRedDanger,
                      side: const BorderSide(color: Color(0xFFEDC0C0)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class GalleryCard extends StatelessWidget {
  const GalleryCard({
    super.key,
    required this.entry,
    required this.formatTime,
  });

  final RecordingEntry entry;
  final String Function(String iso) formatTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: entry.status == RecordingUploadStatus.uploaded
                  ? const Color(0xFFDCEBFA)
                  : entry.status == RecordingUploadStatus.syncing
                      ? const Color(0xFFD8E6FC)
                      : const Color(0xFFEAECF0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.videocam_rounded,
              size: 24,
              color: entry.status == RecordingUploadStatus.uploaded ||
                      entry.status == RecordingUploadStatus.syncing
                  ? kBluePrimary
                  : kTextSubtle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.id,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F1724),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatTime(entry.recordedAtIso)} - ${_durationText(entry.durationSeconds)} - ${formatStorage(entry.sizeBytes)}',
                  style: const TextStyle(
                    color: kTextMuted,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.tagLabel} - ${entry.locationLabel}',
                  style: const TextStyle(
                    color: Color(0xFF8B97A8),
                    fontSize: 11.5,
                  ),
                ),
                if (entry.backendStatusLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.backendStatusLabel,
                    style: const TextStyle(
                      color: kBluePrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                if (entry.status == RecordingUploadStatus.syncing) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: entry.syncProgress / 100,
                      backgroundColor: const Color(0xFFE3E9F3),
                      valueColor: const AlwaysStoppedAnimation(kBluePrimary),
                    ),
                  ),
                ],
                if (entry.relatedToCase) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Terkait kasus',
                    style: TextStyle(
                      color: kBluePrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          StatusChip(label: _statusLabel(entry), state: entry.status),
        ],
      ),
    );
  }

  String _statusLabel(RecordingEntry entry) {
    return switch (entry.status) {
      RecordingUploadStatus.uploaded => 'Selesai',
      RecordingUploadStatus.pending => 'Tertunda',
      RecordingUploadStatus.syncing => '${entry.syncProgress}%',
      RecordingUploadStatus.failed => 'Gagal',
    };
  }

  String _durationText(int seconds) {
    final minutes = seconds ~/ 60;
    final remain = seconds % 60;
    if (minutes == 0) return '${remain}dt';
    return '${minutes}m ${remain}d';
  }
}
