import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'storage.dart';
import 'ui_components.dart';

class RecordingDetailSheet extends StatefulWidget {
  const RecordingDetailSheet({
    super.key,
    required this.entry,
    required this.formatDate,
    required this.onUseForReport,
  });

  final RecordingEntry entry;
  final String Function(String iso) formatDate;
  final VoidCallback onUseForReport;

  @override
  State<RecordingDetailSheet> createState() => _RecordingDetailSheetState();
}

class _RecordingDetailSheetState extends State<RecordingDetailSheet> {
  VideoPlayerController? _controller;
  bool _videoReady = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _prepareVideo();
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepareVideo() async {
    final path = widget.entry.filePath;
    if (path.startsWith('mock/')) {
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      return;
    }
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    controller.setLooping(true);
    controller.addListener(_handleVideoTick);
    if (!mounted) {
      controller.removeListener(_handleVideoTick);
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _videoReady = true;
      _duration = controller.value.duration;
    });
  }

  void _handleVideoTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (_position != value.position || _duration != value.duration) {
      setState(() {
        _position = value.position;
        _duration = value.duration;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFD),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7DEEA),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.entry.id,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: kTextMain,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.formatDate(widget.entry.recordedAtIso),
                          style: const TextStyle(
                            color: kTextMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(
                    label: _statusLabel(widget.entry),
                    state: widget.entry.status,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 224,
                decoration: BoxDecoration(
                  color: const Color(0xFF10141B),
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_videoReady && _controller != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _controller!.value.size.width,
                          height: _controller!.value.size.height,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    else
                      Container(
                        color: const Color(0xFF161B24),
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Color(0xFF7E8AA0),
                            size: 56,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          widget.entry.tagLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (_videoReady && _controller != null)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_controller!.value.isPlaying) {
                                  _controller!.pause();
                                } else {
                                  _controller!.play();
                                }
                              });
                            },
                            child: Center(
                              child: AnimatedOpacity(
                                opacity: _controller!.value.isPlaying ? 0 : 1,
                                duration: const Duration(milliseconds: 180),
                                child: const Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 64,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_videoReady && _controller != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () {
                        setState(() {
                          if (_controller!.value.isPlaying) {
                            _controller!.pause();
                          } else {
                            _controller!.play();
                          }
                        });
                      },
                      icon: Icon(
                        _controller!.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              min: 0,
                              max: _duration.inMilliseconds.toDouble() <= 0
                                  ? 1
                                  : _duration.inMilliseconds.toDouble(),
                              value: _position.inMilliseconds
                                  .toDouble()
                                  .clamp(
                                    0,
                                    _duration.inMilliseconds.toDouble() <= 0
                                        ? 1
                                        : _duration.inMilliseconds.toDouble(),
                                  ),
                              onChanged: (value) {
                                _controller!.seekTo(
                                  Duration(milliseconds: value.round()),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              children: [
                                Text(
                                  _clock(_position),
                                  style: const TextStyle(
                                    color: kTextMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _clock(_duration),
                                  style: const TextStyle(
                                    color: kTextMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DetailMetric(
                      label: 'Durasi',
                      value: _durationText(widget.entry.durationSeconds),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DetailMetric(
                      label: 'Ukuran',
                      value: formatStorage(widget.entry.sizeBytes),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DetailMetric(
                      label: 'Sumber',
                      value: widget.entry.source == 'LIVE_RECORD_CAPTURE'
                          ? 'Live'
                          : 'Intent',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Metadata rekaman',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: kTextMain,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MetaRow(label: 'Lokasi', value: widget.entry.locationLabel),
                    _MetaRow(
                      label: 'Koordinat',
                      value: widget.entry.latitude == null
                          ? 'Belum tersedia'
                          : '${widget.entry.latitude!.toStringAsFixed(4)}, ${widget.entry.longitude!.toStringAsFixed(4)}',
                    ),
                    _MetaRow(
                      label: 'Status backend',
                      value: widget.entry.backendStatusLabel.isEmpty
                          ? 'Belum ada status'
                          : widget.entry.backendStatusLabel,
                    ),
                    _MetaRow(label: 'Catatan', value: widget.entry.notes),
                    _MetaRow(label: 'Path', value: widget.entry.filePath),
                    _MetaRow(
                      label: 'Kasus',
                      value: widget.entry.relatedToCase ? 'Terkait kasus' : 'Belum dikaitkan',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.onUseForReport,
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Gunakan Untuk Laporan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(RecordingEntry entry) {
    return switch (entry.status) {
      RecordingUploadStatus.uploaded => 'Up',
      RecordingUploadStatus.pending => 'Pend',
      RecordingUploadStatus.syncing => '${entry.syncProgress}%',
      RecordingUploadStatus.failed => 'Fail',
    };
  }

  String _durationText(int seconds) {
    final minutes = seconds ~/ 60;
    final remain = seconds % 60;
    if (minutes == 0) return '${remain}dt';
    return '${minutes}m ${remain}dt';
  }

  String _clock(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: kTextMuted,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: kTextMain,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 102,
            child: Text(
              label,
              style: const TextStyle(
                color: kTextMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: kTextMain,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
