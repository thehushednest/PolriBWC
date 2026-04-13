import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'ui_components.dart';

class RecordTab extends StatelessWidget {
  const RecordTab({
    super.key,
    required this.isRecording,
    required this.isMuted,
    required this.isFlashOn,
    required this.preview,
    required this.previewAspectRatio,
    required this.isBlackoutActive,
    required this.cameraReady,
    required this.cameraStatusText,
    required this.permissions,
    required this.recordingClock,
    required this.recordingDateLabel,
    required this.recordingBytes,
    required this.locationLabel,
    required this.locationCoords,
    required this.syncStatusLabel,
    required this.pttLabel,
    required this.selectedTag,
    required this.onStart,
    required this.onStop,
    required this.onToggleMute,
    required this.onToggleFlash,
    required this.onTakePhoto,
    required this.onOpenPtt,
    required this.onSelectTag,
    required this.onSos,
    required this.tags,
  });

  final bool isRecording;
  final bool isMuted;
  final bool isFlashOn;
  final Widget? preview;
  final double previewAspectRatio;
  final bool isBlackoutActive;
  final bool cameraReady;
  final String cameraStatusText;
  final PermissionSummary permissions;
  final String recordingClock;
  final String recordingDateLabel;
  final int recordingBytes;
  final String locationLabel;
  final String locationCoords;
  final String syncStatusLabel;
  final String pttLabel;
  final String selectedTag;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleFlash;
  final VoidCallback onTakePhoto;
  final VoidCallback onOpenPtt;
  final ValueChanged<String> onSelectTag;
  final VoidCallback onSos;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Fullscreen camera preview ──────────────────────────────────────
        _buildPreviewLayer(),

        // ── Top gradient + status bar ──────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopOverlay(),
        ),

        // ── Bottom gradient + controls ─────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomOverlay(),
        ),

        // ── Camera-not-ready status (center) ──────────────────────────────
        if (!cameraReady && !isBlackoutActive)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PreviewBadge(),
                const SizedBox(height: 8),
                Text(
                  cameraStatusText,
                  style: const TextStyle(
                    color: Color(0xFF707887),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

        // ── Proximity blackout ─────────────────────────────────────────────
        if (isBlackoutActive)
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Text(
                'Blackout aktif — sensor depan terhalang',
                style: TextStyle(
                  color: Color(0xFF9AA5B9),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewLayer() {
    return ColoredBox(
      color: const Color(0xFF0A0D12),
      child: preview != null
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 9,
                  height: 16,
                  child: preview!,
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }

  Widget _buildTopOverlay() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          // REC indicator + timer
          if (isRecording) ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFFF4545),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              recordingClock,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
          ] else
            const Text(
              'SIAP LIVE CAM',
              style: TextStyle(
                color: Color(0xFFABB8CC),
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.8,
              ),
            ),
          const Spacer(),
          // Resolution chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: const Text(
              '1080p · 30fps',
              style: TextStyle(
                color: Color(0xFFDBE4F5),
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // PTT channel chip
          GestureDetector(
            onTap: onOpenPtt,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4545).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFFF4545).withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                pttLabel,
                style: const TextStyle(
                  color: Color(0xFFFF9C9C),
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomOverlay() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xE6000000), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // GPS + tag row
          Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 13,
                color: Color(0xFF62EAC9),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  locationCoords,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB0BFDA),
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B4F47).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF2BC39D).withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  selectedTag,
                  style: const TextStyle(
                    color: Color(0xFF7AE5C0),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Tag chips row
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tags.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final tag = tags[i];
                final active = selectedTag == tag;
                return GestureDetector(
                  onTap: () => onSelectTag(tag),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF1B4F47)
                          : Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF2BC39D)
                            : Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: active
                            ? const Color(0xFFB4F6E3)
                            : const Color(0xFFCDD6E8),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                syncStatusLabel,
                style: const TextStyle(
                  color: Color(0xFFB7C7E1),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Action buttons row + record button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _OverlayAction(
                icon: isMuted ? Icons.mic_off : Icons.mic,
                label: isMuted ? 'Muted' : 'Audio',
                active: isMuted,
                activeColor: const Color(0xFFFF6B6B),
                onTap: onToggleMute,
              ),
              _OverlayAction(
                icon: isFlashOn ? Icons.flash_on : Icons.flash_off,
                label: isFlashOn ? 'Flash ON' : 'Flash',
                active: isFlashOn,
                activeColor: const Color(0xFFFFD166),
                onTap: onToggleFlash,
              ),

              // Record button (center, bigger)
              GestureDetector(
                onTap: isRecording ? onStop : onStart,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isRecording ? 28 : 56,
                      height: isRecording ? 28 : 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B3B),
                        borderRadius: BorderRadius.circular(
                          isRecording ? 6 : 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              _OverlayAction(
                icon: Icons.photo_camera_outlined,
                label: 'Foto',
                onTap: onTakePhoto,
              ),
              _OverlayAction(
                icon: Icons.sos,
                label: 'SOS',
                active: true,
                activeColor: const Color(0xFFFF3B3B),
                onTap: onSos,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MapTab extends StatelessWidget {
  const MapTab({
    super.key,
    required this.team,
    required this.onlineOfficers,
    required this.coordinateLabel,
    required this.onChat,
    required this.onSos,
    this.currentLat,
    this.currentLng,
  });

  final List<PersonnelStatus> team;
  final List<PresenceEntry> onlineOfficers;
  final String coordinateLabel;
  final ValueChanged<PersonnelStatus> onChat;
  final ValueChanged<PersonnelStatus> onSos;
  final double? currentLat;
  final double? currentLng;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: _MapOverviewPill(
                  label: 'Aktif',
                  value: '${team.where((item) => item.status == 'Rec').length}',
                  tint: const Color(0xFF18A66A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MapOverviewPill(
                  label: 'Standby',
                  value:
                      '${team.where((item) => item.status == 'Standby').length}',
                  tint: kBluePrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MapOverviewPill(
                  label: 'Weak',
                  value:
                      '${team.where((item) => item.status == 'Weak').length}',
                  tint: const Color(0xFFE5A126),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: AppSectionTitle('Peta patroli')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE7FBF0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Live',
                style: TextStyle(
                  color: Color(0xFF0FAE64),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: _OfficerMap(
              onlineOfficers: onlineOfficers,
              currentLat: currentLat,
              currentLng: currentLng,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Personel aktif',
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          padding: const EdgeInsets.all(14),
          child: team.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Belum ada personel aktif yang terhubung.',
                    style: TextStyle(color: kTextMuted, fontSize: 12.5),
                  ),
                )
              : Column(
                  children: [
                    for (int index = 0; index < team.length; index++) ...[
                      PersonnelTile(
                        personnel: team[index],
                        onChat: () => onChat(team[index]),
                        onSos: () => onSos(team[index]),
                      ),
                      if (index != team.length - 1) const Divider(height: 22),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FB),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.my_location, size: 16, color: kBluePrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  coordinateLabel,
                  style: const TextStyle(color: kTextMuted, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '-6.2088 LS, 106.8456 BT - +/-4m - 2d lalu',
            style: TextStyle(color: kTextMuted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

class PttTab extends StatelessWidget {
  const PttTab({
    super.key,
    required this.channels,
    required this.selectedChannelId,
    required this.transmissions,
    required this.onlineUsers,
    required this.channelStatusLabel,
    required this.signalWeak,
    required this.talkTimeLabel,
    required this.isTalking,
    required this.isConnected,
    required this.onSelectChannel,
    required this.onPttPress,
    required this.onPttRelease,
  });

  final List<PttChannel> channels;
  final String selectedChannelId;
  final List<PttTransmission> transmissions;
  final List<PresenceEntry> onlineUsers;
  final String channelStatusLabel;
  final bool signalWeak;
  final String talkTimeLabel;
  final bool isTalking;
  final bool isConnected;
  final ValueChanged<String> onSelectChannel;
  final VoidCallback onPttPress;
  final VoidCallback onPttRelease;

  @override
  Widget build(BuildContext context) {
    final selectedChannel = channels.firstWhere(
      (channel) => channel.id == selectedChannelId,
      orElse: () => channels.first,
    );

    return Container(
      color: const Color(0xFF10141B),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PTT / HT Digital',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                        ],
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: signalWeak
                            ? const Color(0xFFF0A72F)
                            : const Color(0xFF1BC47D),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      signalWeak ? 'Sinyal Lemah' : 'Saluran Aman',
                      style: TextStyle(
                        color: signalWeak
                            ? const Color(0xFFF0A72F)
                            : const Color(0xFF5DE2A8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  channelStatusLabel,
                  style: const TextStyle(
                    color: Color(0xFF7F8BA1),
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171C27),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF262C3B)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: signalWeak
                                    ? const Color(0xFFF0A72F)
                                    : const Color(0xFF1BC47D),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Siap bicara di ${selectedChannel.label}',
                                style: const TextStyle(
                                  color: Color(0xFFD9E2F1),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF20283A),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF2B3550)),
                        ),
                        child: Text(
                          talkTimeLabel,
                          style: const TextStyle(
                            color: Color(0xFF9AA5BC),
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (int index = 0; index < channels.length; index++) ...[
                      Expanded(
                        child: _PttChannelButton(
                          channel: channels[index],
                          isSelected: selectedChannelId == channels[index].id,
                          onTap: () => onSelectChannel(channels[index].id),
                        ),
                      ),
                      if (index != channels.length - 1)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                const _PttSectionLabel(
                  title: 'Personel online',
                  caption: 'Anggota aktif di kanal yang sedang dipilih',
                ),
                const SizedBox(height: 10),
                if (onlineUsers.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2030),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Belum ada personel online di ${selectedChannelId.toUpperCase()}.',
                      style: const TextStyle(
                        color: Color(0xFF8D97AC),
                        fontSize: 12.5,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151B28),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF232B3D)),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < onlineUsers.length; i++) ...[
                          _PttOnlineUserCard(entry: onlineUsers[i]),
                          if (i != onlineUsers.length - 1)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: Color(0xFF202739),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                const _PttSectionLabel(
                  title: 'Riwayat siaran',
                  caption: 'Log transmisi radio digital terbaru',
                ),
                const SizedBox(height: 10),
                if (transmissions.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2030),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Belum ada riwayat siaran pada kanal ini.',
                      style: TextStyle(
                        color: Color(0xFF8D97AC),
                        fontSize: 12.5,
                      ),
                    ),
                  )
                else
                  ...transmissions.map(
                    (transmission) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PttTransmissionCard(transmission: transmission),
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF202534),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2C3346)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '•••••',
                        style: TextStyle(
                          color: Color(0xFF5F6982),
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isTalking
                              ? 'Sedang bicara di ${selectedChannelId.toUpperCase()}'
                              : 'Siap bicara di ${selectedChannelId.toUpperCase()}',
                          style: const TextStyle(
                            color: Color(0xFFCDD6E7),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        talkTimeLabel,
                        style: const TextStyle(
                          color: Color(0xFF8C97AB),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  signalWeak
                      ? 'Berjalan di background | Sinyal terenkripsi | Audio menurun'
                      : 'Berjalan di background | Sinyal terenkripsi',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF6C758A),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => onPttPress(),
                onTapUp: (_) => onPttRelease(),
                onTapCancel: onPttRelease,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 228,
                  height: 228,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF24293A),
                    border: Border.all(
                      color: isTalking
                          ? const Color(0xFFFF6A6A)
                          : const Color(0xFF7A3945),
                      width: 3,
                    ),
                    boxShadow: isTalking
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFFFF6A6A,
                              ).withValues(alpha: 0.2),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isTalking
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_none_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isTalking ? 'SEDANG BICARA' : 'TAHAN BICARA',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GalleryTab extends StatelessWidget {
  const GalleryTab({
    super.key,
    required this.searchController,
    required this.selectedFilter,
    required this.recordings,
    required this.recordingCountLabel,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onSelectRecording,
    required this.formatTime,
  });

  final TextEditingController searchController;
  final String selectedFilter;
  final List<RecordingEntry> recordings;
  final String recordingCountLabel;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<RecordingEntry> onSelectRecording;
  final String Function(String iso) formatTime;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<RecordingEntry>>{};
    final orderedDates = <DateTime>[];
    for (final entry in recordings) {
      final date = DateTime.parse(entry.recordedAtIso).toLocal();
      final day = DateTime(date.year, date.month, date.day);
      final key = DateFormat('yyyy-MM-dd').format(day);
      grouped.putIfAbsent(key, () => []).add(entry);
      if (!orderedDates.any((item) => item == day)) {
        orderedDates.add(day);
      }
    }
    orderedDates.sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSectionTitle('Rekaman saya'),
                  const SizedBox(height: 2),
                  Text(
                    recordingCountLabel,
                    style: const TextStyle(color: kTextMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Ketuk kartu untuk preview dan metadata',
                    style: TextStyle(color: Color(0xFF8A96A8), fontSize: 11.5),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Filter'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, color: kTextSubtle, size: 20),
            hintText: 'Cari tanggal, lokasi, atau ID...',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final filter in const [
              'Semua',
              'Pending',
              'Uploaded',
              'Kasus',
            ])
              ChoiceChip(
                label: Text(filter),
                selected: selectedFilter == filter,
                onSelected: (_) => onFilterChanged(filter),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (grouped.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Belum ada rekaman yang cocok.'),
            ),
          ),
        for (final date in orderedDates) ...[
          if (grouped[DateFormat('yyyy-MM-dd').format(date)]
              case final items?) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _sectionLabel(date),
                style: const TextStyle(
                  color: kTextMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...items.map(
              (recording) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () => onSelectRecording(recording),
                  child: GalleryCard(entry: recording, formatTime: formatTime),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  String _sectionLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(date.year, date.month, date.day);
    final label = DateFormat('d MMMM yyyy').format(target);
    if (target == today) return 'Hari ini - $label';
    if (target == yesterday) return 'Kemarin - $label';
    return label;
  }
}

class ReportTab extends StatelessWidget {
  const ReportTab({
    super.key,
    required this.selectedType,
    required this.selectedRecording,
    required this.reports,
    required this.descriptionController,
    required this.witnessController,
    required this.onTypeChanged,
    required this.onPickRecording,
    required this.onSubmit,
  });

  final String selectedType;
  final RecordingEntry? selectedRecording;
  final List<IncidentReport> reports;
  final TextEditingController descriptionController;
  final TextEditingController witnessController;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onPickRecording;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      children: [
        const AppSectionTitle('Laporan insiden baru'),
        const SizedBox(height: 12),
        const Text(
          'Jenis insiden',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in const [
              'Penangkapan',
              'Kecelakaan',
              'Razia',
              'Lainnya',
            ])
              SizedBox(
                width: 150,
                child: ChoiceChip(
                  label: Center(child: Text(type)),
                  selected: selectedType == type,
                  onSelected: (_) => onTypeChanged(type),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Rekaman terkait',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorderLight),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: selectedRecording != null
                      ? const Color(0xFFDCEBFA)
                      : const Color(0xFFEAECF0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.videocam_rounded,
                  size: 24,
                  color: selectedRecording != null
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
                      selectedRecording?.id ?? 'Belum dipilih',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      selectedRecording == null
                          ? 'Pilih rekaman dari galeri'
                          : '${selectedRecording!.notes} - ${selectedRecording!.locationLabel}',
                      style: const TextStyle(color: kTextMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onPickRecording,
                child: const Text('Ganti'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Deskripsi singkat',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: descriptionController,
          minLines: 4,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Deskripsikan kejadian...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tersangka / Saksi',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: witnessController,
          decoration: const InputDecoration(
            hintText: 'Nama / NIK (opsional)',
            prefixIcon: Icon(Icons.person_outline, color: kTextSubtle, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAEFD8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'Laporan dikunci setelah dikirim. GPS dan timestamp otomatis disertakan.',
            style: TextStyle(
              color: Color(0xFF835E1A),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
        if (reports.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Riwayat laporan',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...reports
              .take(3)
              .map(
                (report) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              report.id,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            report.type,
                            style: const TextStyle(
                              color: kBluePrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        report.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kTextMain, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${report.locationLabel} - ${report.recordingId}',
                        style: const TextStyle(
                          color: kTextMuted,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        report.deliveryStatus,
                        style: const TextStyle(
                          color: kBluePrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onSubmit,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Kirim Laporan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kTextMain,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayAction extends StatelessWidget {
  const _OverlayAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor = const Color(0xFFFF6B6B),
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? activeColor.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              icon,
              color: active ? activeColor : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: active ? activeColor : Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4A5260)),
      ),
      child: const Icon(Icons.circle, color: Color(0xFF565F6F), size: 12),
    );
  }
}

class _OfficerMap extends StatelessWidget {
  const _OfficerMap({
    required this.onlineOfficers,
    this.currentLat,
    this.currentLng,
  });

  final List<PresenceEntry> onlineOfficers;
  final double? currentLat;
  final double? currentLng;

  static const _defaultCenter = LatLng(-6.2088, 106.8456);

  Color _markerColor(PresenceEntry e) {
    if (e.isTalking) return const Color(0xFFFF6A6A);
    if (e.status == 'recording') return const Color(0xFF3FB950);
    if (e.resolvedStatus == 'online') return const Color(0xFF2F81F7);
    return const Color(0xFF7D8590);
  }

  @override
  Widget build(BuildContext context) {
    final withLocation = onlineOfficers.where((e) => e.hasLocation).toList();

    LatLng center = _defaultCenter;
    double zoom = 13;
    if (currentLat != null && currentLng != null) {
      center = LatLng(currentLat!, currentLng!);
      zoom = 15;
    } else if (withLocation.isNotEmpty) {
      center = LatLng(withLocation.first.latitude!, withLocation.first.longitude!);
      zoom = 14;
    }

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: zoom),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.polri.bodyworn',
        ),
        MarkerLayer(
          markers: [
            // Posisi pengguna saat ini
            if (currentLat != null && currentLng != null)
              Marker(
                point: LatLng(currentLat!, currentLng!),
                width: 44,
                height: 44,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F66B4),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF2F66B4).withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.my_location, color: Colors.white, size: 20),
                ),
              ),
            // Marker petugas lain
            for (final e in withLocation)
              Marker(
                point: LatLng(e.latitude!, e.longitude!),
                width: 38,
                height: 38,
                child: Tooltip(
                  message: '${e.username} · ${e.signalLabel}',
                  child: Container(
                    decoration: BoxDecoration(
                      color: _markerColor(e),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      e.initials,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MapOverviewPill extends StatelessWidget {
  const _MapOverviewPill({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: kTextMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: tint,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}

class _PttChannelButton extends StatelessWidget {
  const _PttChannelButton({
    required this.channel,
    required this.isSelected,
    required this.onTap,
  });

  final PttChannel channel;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF261D27) : const Color(0xFF191E28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF6A6A)
                : const Color(0xFF343B4F),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              channel.label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFFFF7B7B)
                    : const Color(0xFFB7C0D3),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (channel.subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                channel.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFFA4A4)
                      : const Color(0xFF7D879A),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PttOnlineUserCard extends StatelessWidget {
  const _PttOnlineUserCard({required this.entry});

  final PresenceEntry entry;

  @override
  Widget build(BuildContext context) {
    final accent = entry.isTalking
        ? const Color(0xFFFF8B6B)
        : entry.resolvedStatus == 'online'
        ? const Color(0xFF57E4C2)
        : const Color(0xFF7A8598);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.85)),
          ),
          alignment: Alignment.center,
          child: Text(
            entry.initials,
            style: TextStyle(color: accent, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2030),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: entry.isTalking
                    ? const Color(0x66FF8B6B)
                    : const Color(0xFF232A3B),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.username,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    Text(
                      entry.isTalking
                          ? 'LIVE'
                          : entry.activeChannelId.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF8D97AC),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  entry.isTalking
                      ? 'Transmit aktif'
                      : entry.resolvedStatus == 'online'
                      ? 'Standby radio'
                      : 'Status tidak aktif',
                  style: const TextStyle(
                    color: Color(0xFF8C97AB),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 2.5,
                    value: entry.isTalking ? 0.92 : 0.22,
                    backgroundColor: const Color(0xFF2E3446),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PttSectionLabel extends StatelessWidget {
  const _PttSectionLabel({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: const TextStyle(color: Color(0xFF7F8BA1), fontSize: 11.5),
        ),
      ],
    );
  }
}

class _PttTransmissionCard extends StatelessWidget {
  const _PttTransmissionCard({required this.transmission});

  final PttTransmission transmission;

  @override
  Widget build(BuildContext context) {
    if (transmission.isSystem) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2030),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF252C40),
              child: Text(
                transmission.initials,
                style: const TextStyle(
                  color: Color(0xFF8892A8),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transmission.speakerName,
                    style: const TextStyle(
                      color: Color(0xFF7F8AA0),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    transmission.statusLabel,
                    style: const TextStyle(
                      color: Color(0xFF697389),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              transmission.timeLabel,
              style: const TextStyle(color: Color(0xFF697389), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFF171C29),
          child: Text(
            transmission.initials,
            style: TextStyle(
              color: transmission.accentColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2232),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        transmission.speakerName,
                        style: TextStyle(
                          color: transmission.accentColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      transmission.timeLabel,
                      style: const TextStyle(
                        color: Color(0xFF76809B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: transmission.waveLevel.clamp(0, 1),
                    minHeight: 3,
                    backgroundColor: const Color(0xFF2C344A),
                    valueColor: AlwaysStoppedAnimation(
                      transmission.accentColor,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    transmission.statusLabel,
                    style: const TextStyle(
                      color: Color(0xFF8D97AC),
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
