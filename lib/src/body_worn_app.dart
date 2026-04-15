import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_config.dart';
import 'backend_gateway.dart';
import 'live_webrtc_service.dart';
import 'live_frame_encoder.dart';
import 'models.dart';
import 'navigation.dart';
import 'polri_backend_api.dart';
import 'ptt_webrtc_service.dart';
import 'storage.dart';
import 'tabs_primary.dart';
import 'tabs_secondary.dart';

class BodyWornApp extends StatelessWidget {
  const BodyWornApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Polri Body Worn',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2B61AE),
          secondary: Color(0xFF7CA6DE),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2B61AE), width: 1.5),
          ),
          hintStyle: const TextStyle(color: Color(0xFF9AA6B6), fontSize: 14),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1C2333),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: const BorderSide(color: Color(0xFFDDE3EE)),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFEEF2F8),
          thickness: 0.8,
        ),
      ),
      home: const BodyWornHomePage(),
    );
  }
}

class BodyWornHomePage extends StatefulWidget {
  const BodyWornHomePage({super.key});

  @override
  State<BodyWornHomePage> createState() => _BodyWornHomePageState();
}

class _BodyWornHomePageState extends State<BodyWornHomePage>
    with WidgetsBindingObserver {
  static const Duration _liveFrameInterval = Duration(seconds: 1);
  static const int _liveFrameWarmupMs = 1200;
  final RecordingStorage _storage = RecordingStorage();
  final DateFormat _fullDateFormat = DateFormat('dd MMM yyyy HH:mm');
  final DateFormat _compactTimeFormat = DateFormat('HH:mm');
  final TextEditingController _nrpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _witnessController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  OfficerSession? _session;
  PermissionSummary _permissions = const PermissionSummary();
  List<RecordingEntry> _recordings = const [];
  List<PresenceEntry> _presenceEntries = const [];
  double? _currentLat;
  double? _currentLng;
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isMuted = false;
  bool _isCameraInitializing = false;
  BodyWornTab _currentTab = BodyWornTab.home;
  DateTime? _recordingStartedAt;
  Timer? _ticker;
  Timer? _presenceTimer;
  Timer? _pttRefreshTimer;
  Timer? _sosPollTimer;
  Timer? _liveRefreshTimer;
  String _selectedGalleryFilter = 'Semua';
  String _selectedReportType = 'Penangkapan';
  String? _selectedRecordingId;
  String? _cameraError;
  CameraController? _cameraController;
  CameraDescription? _rearCamera;
  bool _isFlashOn = false;
  bool _isBlackoutActive = false;
  bool _isProximityNear = false;
  final Battery _battery = Battery();
  int _batteryPercent = 100;
  String _selectedTag = 'Penangkapan';
  bool _isTalking = false;
  bool _isPttConnected = false;
  String _selectedPttChannelId = 'ch1';
  String? _pttTalkingChannelId;
  DateTime? _pttStartedAt;
  List<PttTransmission> _pttFeed = const [];
  List<SosAlert> _sosAlerts = const [];
  List<IncidentReport> _incidentReports = const [];
  final Set<String> _seenSosAlertIds = <String>{};
  String? _activeSosDialogId;
  String? _activeLiveSessionId;
  bool _isSendingLiveFrame = false;
  bool _isLiveImageStreamActive = false;
  DateTime? _lastLiveFrameSentAt;
  int _liveFrameCount = 0;
  String _liveFrameStatus = 'Belum ada frame live';
  String _liveTransportMode = 'snapshot';
  String _liveSignalingStatus = 'Signaling belum aktif';
  late final AppConfig _config;
  late final BackendGateway _backend;
  late final PttWebRtcService _pttWebRtcService;
  late final LiveWebRtcService _liveWebRtcService;

  static const _kDeviceChannel = MethodChannel('polri_bwc/device');

  final List<PttChannel> _pttChannels = const [
    PttChannel(id: 'ch1', label: 'Ch 1', subtitle: ''),
    PttChannel(id: 'ch2', label: 'Ch 2', subtitle: ''),
    PttChannel(id: 'ch3', label: 'Ch 3', subtitle: ''),
    PttChannel(id: 'ch4', label: 'Ch 4', subtitle: ''),
  ];

  final List<String> _recordingTags = const [
    'Penangkapan',
    'Razia',
    'Patroli',
    'Lainnya',
  ];

  List<PersonnelStatus> get _patrolTeam => _presenceEntries.map((entry) {
    final ch = entry.activeChannelId.isEmpty
        ? '-'
        : entry.activeChannelId.toUpperCase();
    final detail = entry.hasLocation
        ? '${entry.latitude!.toStringAsFixed(4)}, ${entry.longitude!.toStringAsFixed(4)} · $ch'
        : '$ch · ${entry.signalLabel}';
    final isRecording = entry.status == 'recording';
    return PersonnelStatus(
      initials: entry.initials,
      name: entry.username,
      detail: detail,
      status: entry.isTalking
          ? 'PTT'
          : isRecording
          ? 'Live'
          : entry.resolvedStatus == 'online'
          ? 'Standby'
          : 'Offline',
      statusColor: entry.isTalking
          ? const Color(0xFFFF6A6A)
          : isRecording
          ? const Color(0xFF19A66A)
          : entry.resolvedStatus == 'online'
          ? const Color(0xFF4A88E6)
          : const Color(0xFF9EA8B6),
      dotColor: entry.resolvedStatus == 'online'
          ? const Color(0xFF1BA467)
          : const Color(0xFF9EA8B6),
    );
  }).toList();

  @override
  void initState() {
    super.initState();
    _config = AppConfig.fromEnvironment();
    _backend = PolriBackendApi(config: _config);
    _pttWebRtcService = PttWebRtcService(
      onState: _handlePttStateEvent,
      onError: _handlePttErrorEvent,
    );
    _liveWebRtcService = LiveWebRtcService(
      onState: _handleLiveStateEvent,
      onError: _handleLiveErrorEvent,
    );
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    // Proximity sensor dinonaktifkan sementara.
    // _startProximitySensor();
    _kDeviceChannel.setMethodCallHandler(_onNativeDeviceEvent);
  }

  /// Handles events pushed from MainActivity via MethodChannel.
  Future<void> _onNativeDeviceEvent(MethodCall call) async {
    switch (call.method) {
      case 'proximityChanged':
        final arguments = Map<String, dynamic>.from(
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {},
        );
        final near = arguments['near'] as bool? ?? false;
        _handleProximityChanged(near);
        return;
      case 'hardwarePtt':
        final arguments = Map<String, dynamic>.from(
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {},
        );
        final state = arguments['state'] as String?;
        if (state == 'down' && !_isTalking) {
          await _startNativePtt();
        } else if (state == 'up' && _isTalking) {
          await _stopNativePtt();
        }
        return;
      case 'pttAudioState':
        _handlePttStateEvent(
          Map<String, dynamic>.from(
            (call.arguments as Map?)?.cast<String, dynamic>() ?? const {},
          ),
        );
        return;
      case 'pttAudioError':
        _handlePttErrorEvent(
          (Map<String, dynamic>.from(
                    (call.arguments as Map?)?.cast<String, dynamic>() ??
                        const {},
                  ))['message']
                  as String? ??
              '',
        );
        return;
    }
  }

  void _handlePttStateEvent(Map<String, dynamic> arguments) {
    final state = arguments['state'] as String? ?? '';
    final isCapturing = arguments['isCapturing'] as bool? ?? false;
    if (!mounted) return;
    setState(() {
      _isPttConnected =
          state == 'connected' ||
          state == 'recording' ||
          state == 'reconnecting';
      if (isCapturing && !_isTalking) {
        _isTalking = true;
        _pttTalkingChannelId ??= _selectedPttChannelId;
        _pttStartedAt ??= DateTime.now();
      } else if (!isCapturing && _isTalking && state == 'disconnected') {
        _isTalking = false;
        _pttTalkingChannelId = null;
        _pttStartedAt = null;
      }
    });
  }

  void _handlePttErrorEvent(String message) {
    if (!mounted) return;
    final session = _session;
    final talkChannelId = _pttTalkingChannelId ?? _selectedPttChannelId;
    final startedAt = _pttStartedAt;
    final wasTalking = _isTalking;
    setState(() {
      _isPttConnected = false;
      _isTalking = false;
      _pttTalkingChannelId = null;
      _pttStartedAt = null;
    });
    if (wasTalking && session != null) {
      final durationSeconds = startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inSeconds;
      unawaited(() async {
        try {
          await _pttWebRtcService.stopTalking();
        } catch (_) {}
        try {
          await _backend.stopPttTransmit(
            channelId: talkChannelId,
            officerId: session.nrp,
            durationSeconds: durationSeconds,
          );
        } catch (_) {}
        await _refreshPttData();
      }());
    }
    if (message.isNotEmpty) {
      _showMessage(message);
    }
  }

  void _handleLiveStateEvent(Map<String, dynamic> arguments) {
    if (!mounted) return;
    final state = arguments['state'] as String? ?? '';
    final detail = arguments['detail'] as String? ?? '';
    setState(() {
      if (detail.isNotEmpty) {
        _liveSignalingStatus = detail;
      }
      if (state == 'streaming') {
        _liveTransportMode = 'webrtc';
        _liveFrameStatus = 'Streaming kamera + mikrofon ke dashboard.';
      } else if (state == 'preview-ready' && _liveFrameStatus.isEmpty) {
        _liveFrameStatus = 'Preview Live Cam siap.';
      }
    });
  }

  void _handleLiveErrorEvent(String message) {
    if (!mounted) return;
    setState(() {
      _liveSignalingStatus = message.isEmpty
          ? 'Live Cam WebRTC bermasalah.'
          : message;
      if (_liveTransportMode == 'webrtc') {
        _liveFrameStatus = 'Live Cam WebRTC gagal tersambung.';
      }
    });
  }

  bool get _canUseBlackout {
    final cameraReady = _cameraController?.value.isInitialized == true;
    return _currentTab == BodyWornTab.record && (cameraReady || _isRecording);
  }

  void _handleProximityChanged(bool near) {
    _isProximityNear = near;
    final shouldBlackout = near && _canUseBlackout;
    if (!mounted || _isBlackoutActive == shouldBlackout) {
      return;
    }
    setState(() {
      _isBlackoutActive = shouldBlackout;
    });
  }

  void _syncBlackoutState() {
    final shouldBlackout = _isProximityNear && _canUseBlackout;
    if (!mounted || _isBlackoutActive == shouldBlackout) {
      return;
    }
    setState(() {
      _isBlackoutActive = shouldBlackout;
    });
  }

  Future<void> _startNativePtt() async {
    if (_isTalking) return;
    final session = _session;
    if (session == null) return;
    if (_isMuted) {
      _showMessage(
        'Audio PTT sedang dimatikan. Aktifkan audio untuk transmit.',
      );
      return;
    }
    final talkChannelId = _selectedPttChannelId;
    final result = await _backend.startPttTransmit(
      channelId: talkChannelId,
      officerId: session.nrp,
      deviceId: 'android_${session.nrp}',
    );
    if (!result.granted) {
      if (result.message.isNotEmpty) {
        _showMessage(result.message);
      }
      await _refreshPttData();
      return;
    }

    try {
      final started = await _pttWebRtcService.startTalking();
      if (!started) {
        await _backend.stopPttTransmit(
          channelId: talkChannelId,
          officerId: session.nrp,
          durationSeconds: 0,
        );
        await _refreshPttData();
        return;
      }
      if (mounted) {
        setState(() {
          _isTalking = true;
          _pttTalkingChannelId = talkChannelId;
          _pttStartedAt = DateTime.now();
        });
      }
      await _updateNotification();
      await _sendPresenceHeartbeat();
      await _refreshPttData();
    } catch (_) {
      await _backend.stopPttTransmit(
        channelId: talkChannelId,
        officerId: session.nrp,
        durationSeconds: 0,
      );
    }
  }

  Future<void> _stopNativePtt() async {
    if (!_isTalking) return;
    final session = _session;
    final talkChannelId = _pttTalkingChannelId ?? _selectedPttChannelId;
    final startedAt = _pttStartedAt;
    final durationSeconds = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds;

    try {
      await _pttWebRtcService.stopTalking();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isTalking = false;
        _pttTalkingChannelId = null;
        _pttStartedAt = null;
      });
    }

    await _updateNotification();

    if (session != null) {
      await _backend.stopPttTransmit(
        channelId: talkChannelId,
        officerId: session.nrp,
        durationSeconds: durationSeconds,
      );
      await _sendPresenceHeartbeat();
      await _refreshPttData();
    }
  }

  Future<void> _refreshPttData() async {
    final activeChannelId = _pttTalkingChannelId ?? _selectedPttChannelId;
    final presence = await _backend.loadPresence(
      channelId: _currentTab == BodyWornTab.ptt ? activeChannelId : null,
    );
    final feed = await _backend.loadPttFeed(channelId: activeChannelId);
    if (!mounted) return;
    setState(() {
      _presenceEntries = presence;
      _pttFeed = feed;
    });
  }

  Future<void> _refreshSosAlerts({bool notifyIncoming = false}) async {
    final alerts = await _backend.loadSosAlerts();
    if (!mounted) return;
    final session = _session;
    final incoming = notifyIncoming && session != null
        ? alerts
              .where(
                (alert) =>
                    !_seenSosAlertIds.contains(alert.id) &&
                    alert.officerId != session.nrp,
              )
              .toList()
        : const <SosAlert>[];
    setState(() {
      _sosAlerts = alerts;
    });
    _seenSosAlertIds.addAll(alerts.map((item) => item.id));
    for (final alert in incoming.reversed) {
      _announceIncomingSos(alert);
    }
  }

  Future<void> _refreshLiveSessions() async {
    final sessions = await _backend.loadLiveSessions();
    if (!mounted) return;
    final activeSession = _activeLiveSessionId == null
        ? null
        : sessions
              .where((item) => item.sessionId == _activeLiveSessionId)
              .firstOrNull;
    setState(() {
      if (activeSession != null) {
        _liveFrameCount = activeSession.frameCount;
        _liveTransportMode = activeSession.transport;
        if (activeSession.signalingState.isNotEmpty &&
            activeSession.signalingState != 'idle') {
          _liveSignalingStatus = 'Signaling ${activeSession.signalingState}';
        }
        if (activeSession.transport == 'webrtc') {
          _liveFrameStatus = 'Live kamera + mikrofon aktif via WebRTC.';
        } else {
          _liveFrameStatus = activeSession.frameCount == 0
              ? 'Menunggu frame live...'
              : 'Frame ${activeSession.frameCount} · ${_compactTimeFormat.format(DateTime.tryParse(activeSession.lastFrameAtIso)?.toLocal() ?? DateTime.now())}';
        }
      }
    });
  }

  Future<bool> _connectLiveSignaling(LiveStreamSession liveSession) async {
    await _disconnectLiveSignaling();
    if (!mounted) return false;
    if (liveSession.transport == 'webrtc') {
      final connected = await _liveWebRtcService.connect(
        url: liveSession.signalingUrl.isEmpty
            ? _config.liveSignalingWebSocketUrl
            : liveSession.signalingUrl,
        username: _session?.nrp ?? liveSession.officerId,
        sessionId: liveSession.sessionId,
        deviceId: liveSession.deviceId,
      );
      if (!mounted) return connected;
      setState(() {
        _liveTransportMode = liveSession.transport;
        _liveSignalingStatus = connected
            ? 'Signaling Live Cam tersambung.'
            : 'Signaling Live Cam gagal.';
        _liveFrameStatus = connected
            ? 'Streaming kamera + mikrofon ke dashboard.'
            : 'Live Cam WebRTC gagal tersambung.';
      });
      return connected;
    }
    setState(() {
      _liveTransportMode = liveSession.transport;
      _liveSignalingStatus = 'Fallback snapshot aktif.';
    });
    return true;
  }

  Future<void> _disconnectLiveSignaling() async {
    await _liveWebRtcService.disconnect();
    if (!mounted) return;
    setState(() {
      _liveSignalingStatus = 'Signaling belum aktif';
    });
  }

  Future<void> _startLiveImageStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isLiveImageStreamActive) return;
    _lastLiveFrameSentAt = null;
    await controller.startImageStream((image) {
      if (!_isRecording) return;
      if (_isSendingLiveFrame) return;
      final lastSent = _lastLiveFrameSentAt;
      final now = DateTime.now();
      if (lastSent != null && now.difference(lastSent) < _liveFrameInterval) {
        return;
      }
      _lastLiveFrameSentAt = now;
      unawaited(_pushLiveCameraImage(image));
    });
    _isLiveImageStreamActive = true;
  }

  Future<void> _stopLiveImageStream() async {
    final controller = _cameraController;
    if (controller == null) {
      _isLiveImageStreamActive = false;
      return;
    }
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
    _isLiveImageStreamActive = false;
    _lastLiveFrameSentAt = null;
  }

  Future<void> _pushLiveCameraImage(CameraImage image) async {
    final session = _session;
    final liveSessionId = _activeLiveSessionId;
    if (!_isRecording ||
        _isSendingLiveFrame ||
        session == null ||
        liveSessionId == null) {
      return;
    }

    _isSendingLiveFrame = true;
    try {
      if (mounted) {
        setState(() {
          _liveFrameStatus = _liveFrameCount == 0
              ? 'Mengambil frame pertama mode stream...'
              : 'Mengirim frame ${_liveFrameCount + 1} mode stream...';
        });
      }
      final encoded = encodeLiveCameraImage(image, jpegQuality: 48);
      if (encoded == null || encoded.isEmpty) {
        throw Exception('Frame stream tidak dapat diencode');
      }
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(encoded)}';
      debugPrint(
        '[live-frame-send] session=$liveSessionId next=${_liveFrameCount + 1} bytes=${encoded.length} loc=${_currentLat?.toStringAsFixed(4) ?? '-'},${_currentLng?.toStringAsFixed(4) ?? '-'}',
      );
      await _backend.pushLiveFrame(
        sessionId: liveSessionId,
        officerId: session.nrp,
        frameDataUrl: dataUrl,
        latitude: _currentLat,
        longitude: _currentLng,
        locationLabel: _currentLat == null
            ? 'Lokasi belum tersedia'
            : 'Lat ${_currentLat!.toStringAsFixed(4)}, Lng ${_currentLng!.toStringAsFixed(4)}',
      );
      if (mounted) {
        setState(() {
          _liveFrameCount += 1;
          _liveFrameStatus =
              'Frame $_liveFrameCount terkirim � stream ${_liveFrameInterval.inSeconds}dt � ${_compactTimeFormat.format(DateTime.now())}';
        });
      }
      if (_liveFrameCount <= 1) {
        await _refreshLiveSessions();
      }
    } catch (error) {
      debugPrint('[live-frame-error] session=$liveSessionId error=$error');
      if (mounted) {
        setState(() {
          _liveFrameStatus = 'Frame stream gagal: $error';
        });
      }
    } finally {
      _isSendingLiveFrame = false;
    }
  }

  void _startSosPolling() {
    _sosPollTimer?.cancel();
    _sosPollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshSosAlerts(notifyIncoming: true)),
    );
  }

  void _announceIncomingSos(SosAlert alert) {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    HapticFeedback.vibrate();
    if (!mounted || _activeSosDialogId == alert.id) {
      return;
    }
    _activeSosDialogId = alert.id;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('SOS Masuk'),
            content: Text(
              '${alert.officerName.isEmpty ? alert.officerId : alert.officerName}\n'
              'Channel: ${alert.channelId.isEmpty ? '-' : alert.channelId.toUpperCase()}\n'
              'Lokasi: ${alert.locationLabel}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      ).whenComplete(() {
        _activeSosDialogId = null;
      }),
    );
  }

  void _startPttRefreshLoop() {
    _pttRefreshTimer?.cancel();
    _pttRefreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshPttData()),
    );
  }

  void _startLiveRefreshLoop() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshLiveSessions()),
    );
  }

  String _pttTalkTimeLabel() {
    if (!_isTalking || _pttStartedAt == null) {
      return '00:00';
    }
    final elapsed = DateTime.now().difference(_pttStartedAt!);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _handleRecordScreenPtt() async {
    if (_isTalking) {
      await _stopNativePtt();
      return;
    }
    await _startNativePtt();
  }

  Future<void> _selectPttChannel(String id) async {
    if (_isTalking) {
      _showMessage('Channel tidak bisa diganti saat sedang transmit.');
      return;
    }
    setState(() => _selectedPttChannelId = id);
    try {
      await _pttWebRtcService.updateChannel(id);
    } catch (_) {}
    await _updateNotification();
    await _sendPresenceHeartbeat();
    await _refreshPttData();
  }

  Future<void> _connectNativePtt(OfficerSession session) async {
    try {
      final config = _config;
      if (!config.enableNativePttAudio) {
        if (mounted) setState(() => _isPttConnected = false);
        return;
      }
      await _pttWebRtcService.connect(
        url: config.pttSignalingWebSocketUrl,
        username: session.nrp,
        channelId: _selectedPttChannelId,
        deviceId: 'android_${session.nrp}',
      );
      await _kDeviceChannel.invokeMethod('startPersistentMode');
      await _updateNotification();
      await _refreshPttData();
    } catch (_) {}
  }

  Future<void> _disconnectNativePtt() async {
    if (_isTalking) {
      await _stopNativePtt();
    }
    try {
      await _pttWebRtcService.disconnect();
      await _kDeviceChannel.invokeMethod('stopPersistentMode');
    } catch (_) {}
    if (mounted) setState(() => _isPttConnected = false);
  }

  Future<void> _toggleAudioMute() async {
    final nextMuted = !_isMuted;
    if (_isTalking && nextMuted) {
      await _stopNativePtt();
    }
    if (!mounted) return;
    setState(() {
      _isMuted = nextMuted;
    });
    await _updateNotification();
    _showMessage(
      nextMuted
          ? 'Audio PTT dimatikan. Tombol bicara tidak akan transmit.'
          : 'Audio PTT diaktifkan kembali.',
    );
  }

  Future<void> _applyFlashMode() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isFlashOn = false;
      });
      _showMessage('Torch kamera tidak tersedia: $error');
    }
  }

  Future<void> _toggleFlash() async {
    await _ensureCameraReady();
    if (_cameraController?.value.isInitialized != true) {
      _showMessage('Kamera belum siap untuk mengaktifkan flash.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
    await _applyFlashMode();
    _showMessage(
      _isFlashOn ? 'Flash bodyworn aktif.' : 'Flash bodyworn dimatikan.',
    );
  }

  Future<void> _captureSnapshot() async {
    if (_session == null) return;
    await _ensureCameraReady();
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _showMessage('Kamera belum siap untuk mengambil foto.');
      return;
    }
    if (controller.value.isTakingPicture) {
      _showMessage('Snapshot sedang diproses.');
      return;
    }

    final shouldResumeStream =
        _isRecording && controller.value.isStreamingImages;
    if (shouldResumeStream) {
      unawaited(_stopLiveImageStream());
    }
    try {
      final captured = await controller.takePicture();
      final storedPath = await _storage.persistPhoto(captured);
      _showMessage('Snapshot tersimpan di $storedPath');
    } catch (error) {
      _showMessage('Gagal mengambil snapshot: $error');
    } finally {
      if (shouldResumeStream && _isRecording) {
        await _startLiveImageStream();
      }
    }
  }

  Future<void> _updateNotification() async {
    final activeChannelId = _pttTalkingChannelId ?? _selectedPttChannelId;
    final channelLabel =
        _pttChannels
            .where((c) => c.id == activeChannelId)
            .map((c) => c.label)
            .firstOrNull ??
        activeChannelId.toUpperCase();
    try {
      await _kDeviceChannel.invokeMethod('updatePersistentNotification', {
        'status': _isTalking ? 'TRANSMITTING' : 'Standby',
        'channel': channelLabel,
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    final session = _session;
    final liveSessionId = _activeLiveSessionId;
    _kDeviceChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _presenceTimer?.cancel();
    _pttRefreshTimer?.cancel();
    _liveRefreshTimer?.cancel();
    _sosPollTimer?.cancel();
    unawaited(_stopLiveImageStream());
    if (session != null && liveSessionId != null) {
      unawaited(
        _backend.stopLiveStream(
          sessionId: liveSessionId,
          officerId: session.nrp,
        ),
      );
    }
    unawaited(_disconnectNativePtt());
    unawaited(_disconnectLiveSignaling());
    _cameraController?.dispose();
    _nrpController.dispose();
    _passwordController.dispose();
    _descriptionController.dispose();
    _witnessController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (state == AppLifecycleState.inactive) {
      if (!_isRecording &&
          controller != null &&
          _currentTab == BodyWornTab.record) {
        controller.dispose();
        _cameraController = null;
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_session != null) {
        unawaited(_connectNativePtt(_session!));
        unawaited(_refreshPttData());
      }
      if (_isRecording && _session != null && _activeLiveSessionId != null) {
        final liveSession = LiveStreamSession(
          sessionId: _activeLiveSessionId!,
          officerId: _session!.nrp,
          officerName: _session!.fullName,
          deviceId: 'android_${_session!.nrp}',
          status: 'live',
          startedAtIso: DateTime.now().toIso8601String(),
          locationLabel: _currentLat == null
              ? 'Lokasi belum tersedia'
              : 'Lat ${_currentLat!.toStringAsFixed(4)}, Lng ${_currentLng!.toStringAsFixed(4)}',
          channelId: _selectedPttChannelId,
          transport: 'webrtc',
          signalingUrl: _config.liveSignalingWebSocketUrl,
        );
        unawaited(_connectLiveSignaling(liveSession));
      }
      if (_currentTab == BodyWornTab.record) {
        unawaited(_ensureCameraReady());
      }
      _syncBlackoutState();
    }
  }

  static const _sessionPrefsKey = 'officer_session_v1';

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionRaw = prefs.getString(_sessionPrefsKey);
    OfficerSession? restoredSession;
    if (sessionRaw != null) {
      try {
        final data = jsonDecode(sessionRaw) as Map<String, dynamic>;
        restoredSession = OfficerSession(
          nrp: data['nrp'] as String,
          officerName: data['officerName'] as String,
          rankLabel: data['rankLabel'] as String? ?? '',
          unitName: data['unitName'] as String? ?? '',
          shiftLabel: data['shiftLabel'] as String? ?? '',
          shiftWindow: data['shiftWindow'] as String? ?? '',
        );
      } catch (_) {}
    }

    final results = await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
    ].request();

    final stored = await _storage.loadRecordings();
    final combined = [...stored];
    combined.sort(
      (a, b) => DateTime.parse(
        b.recordedAtIso,
      ).compareTo(DateTime.parse(a.recordedAtIso)),
    );

    int batteryLevel = 100;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _session = restoredSession;
      _permissions = PermissionSummary.fromStatuses(results);
      _recordings = combined;
      _selectedRecordingId = combined.isNotEmpty ? combined.first.id : null;
      _batteryPercent = batteryLevel;
      _isInitializing = false;
    });

    if (restoredSession != null) {
      unawaited(_connectNativePtt(restoredSession));
      unawaited(_sendPresenceHeartbeat());
      unawaited(_refreshSosAlerts());
      unawaited(_refreshLiveSessions());
      _startPttRefreshLoop();
      _startSosPolling();
      _startLiveRefreshLoop();
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(_sendPresenceHeartbeat()),
      );
    }
  }

  Future<void> _ensureCameraReady() async {
    if (_cameraController?.value.isInitialized == true ||
        _isCameraInitializing) {
      return;
    }
    setState(() {
      _isCameraInitializing = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      _rearCamera =
          cameras
              .where(
                (camera) => camera.lensDirection == CameraLensDirection.back,
              )
              .firstOrNull ??
          cameras.firstOrNull;
      if (_rearCamera == null) {
        throw Exception('Kamera belakang tidak ditemukan');
      }

      final controller = CameraController(
        _rearCamera!,
        ResolutionPreset.low,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _cameraController?.dispose();
      setState(() {
        _cameraController = controller;
      });
      _syncBlackoutState();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
        });
      }
    }
  }

  // Kredensial fallback untuk digunakan saat server tidak tersedia.
  static const _localUsers = {
    'test1': (
      name: 'Test Satu',
      rank: '',
      unit: 'Satuan Alpha',
      shift: 'Shift Pagi Aktif',
      window: '07:00–15:00',
      pass: 'test1',
    ),
    'test2': (
      name: 'Test Dua',
      rank: '',
      unit: 'Satuan Bravo',
      shift: 'Shift Siang Aktif',
      window: '15:00–23:00',
      pass: 'test2',
    ),
    'test3': (
      name: 'Test Tiga',
      rank: '',
      unit: 'Satuan Charlie',
      shift: 'Shift Malam Aktif',
      window: '23:00–07:00',
      pass: 'test3',
    ),
    'test4': (
      name: 'Test Empat',
      rank: '',
      unit: 'Satuan Delta',
      shift: 'Shift Pagi Aktif',
      window: '07:00–15:00',
      pass: 'test4',
    ),
    'test5': (
      name: 'Test Lima',
      rank: '',
      unit: 'Satuan Echo',
      shift: 'Shift Siang Aktif',
      window: '15:00–23:00',
      pass: 'test5',
    ),
    'test6': (
      name: 'Test Enam',
      rank: '',
      unit: 'Satuan Foxtrot',
      shift: 'Shift Malam Aktif',
      window: '23:00–07:00',
      pass: 'test6',
    ),
    'test7': (
      name: 'Test Tujuh',
      rank: '',
      unit: 'Satuan Golf',
      shift: 'Shift Pagi Aktif',
      window: '07:00–15:00',
      pass: 'test7',
    ),
    'test8': (
      name: 'Test Delapan',
      rank: '',
      unit: 'Satuan Hotel',
      shift: 'Shift Siang Aktif',
      window: '15:00–23:00',
      pass: 'test8',
    ),
    'test9': (
      name: 'Test Sembilan',
      rank: '',
      unit: 'Satuan India',
      shift: 'Shift Malam Aktif',
      window: '23:00–07:00',
      pass: 'test9',
    ),
    'test10': (
      name: 'Test Sepuluh',
      rank: '',
      unit: 'Satuan Juliet',
      shift: 'Shift Pagi Aktif',
      window: '07:00–15:00',
      pass: 'test10',
    ),
  };

  Future<void> _activateSession() async {
    final username = _nrpController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      _showMessage('Username dan sandi wajib diisi.');
      return;
    }

    final config = _config;
    OfficerSession? session;
    var serverReachable = false;

    // Coba autentikasi ke server lokal.
    try {
      final client = ApiClient(
        baseUrl: config.rootUrl,
        timeout: Duration(seconds: config.connectTimeoutSeconds),
      );
      final result = await client.postJsonWithStatus('/auth/login', {
        'username': username,
        'password': password,
      });
      serverReachable = true;
      if (result.statusCode == 200) {
        final body = result.body as Map<String, dynamic>;
        session = OfficerSession(
          officerName: body['officerName'] as String? ?? username,
          rankLabel: body['rankLabel'] as String? ?? '',
          unitName: body['unitName'] as String? ?? '',
          shiftLabel: body['shiftLabel'] as String? ?? '',
          shiftWindow: body['shiftWindow'] as String? ?? '',
          nrp: body['nrp'] as String? ?? username,
        );
      } else if (result.statusCode == 401) {
        _showMessage('Username atau password salah.');
        return;
      }
    } catch (_) {
      // Server tidak tersedia — gunakan fallback lokal.
    }

    if (!config.useMockBackend && session == null) {
      if (serverReachable) {
        _showMessage(
          'Login ke server gagal. Periksa kredensial atau respons server.',
        );
      } else {
        _showMessage(
          'Tidak dapat terhubung ke server operasional. Pastikan internet dan endpoint aktif.',
        );
      }
      return;
    }

    // Fallback: validasi terhadap kredensial lokal.
    if (session == null) {
      final local = _localUsers[username];
      if (local == null || local.pass != password) {
        _showMessage('Username atau password salah.');
        return;
      }
      session = OfficerSession(
        officerName: local.name,
        rankLabel: local.rank,
        unitName: local.unit,
        shiftLabel: local.shift,
        shiftWindow: local.window,
        nrp: username,
      );
    }

    // Simpan sesi ke persistent storage agar tidak logout saat hp dikunci.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionPrefsKey,
      jsonEncode({
        'nrp': session.nrp,
        'officerName': session.officerName,
        'rankLabel': session.rankLabel,
        'unitName': session.unitName,
        'shiftLabel': session.shiftLabel,
        'shiftWindow': session.shiftWindow,
      }),
    );

    setState(() {
      _session = session;
      _currentTab = BodyWornTab.home;
    });
    _showMessage('Login berhasil. Perangkat siap bertugas.');
    unawaited(_connectNativePtt(session));
    unawaited(_sendPresenceHeartbeat());
    unawaited(_refreshSosAlerts());
    unawaited(_refreshLiveSessions());
    _startPttRefreshLoop();
    _startSosPolling();
    _startLiveRefreshLoop();
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_sendPresenceHeartbeat()),
    );
  }

  Future<void> _sendPresenceHeartbeat() async {
    final session = _session;
    if (session == null) return;

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {}

    int? freshBattery;
    try {
      freshBattery = await _battery.batteryLevel;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _currentLat = position?.latitude;
        _currentLng = position?.longitude;
        if (freshBattery != null) _batteryPercent = freshBattery;
      });
    }

    await _backend.updatePresence(
      username: session.nrp,
      deviceId: 'android_${session.nrp}',
      status: _isTalking
          ? 'ptt'
          : _isRecording
          ? 'live'
          : 'online',
      activeChannelId: _pttTalkingChannelId ?? _selectedPttChannelId,
      latitude: position?.latitude,
      longitude: position?.longitude,
    );
    await _refreshPttData();
  }

  void _logout() {
    final session = _session;
    final liveSessionId = _activeLiveSessionId;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.remove(_sessionPrefsKey),
    );
    _pttRefreshTimer?.cancel();
    _liveRefreshTimer?.cancel();
    _sosPollTimer?.cancel();
    if (session != null) {
      if (liveSessionId != null) {
        unawaited(
          _backend.stopLiveStream(
            sessionId: liveSessionId,
            officerId: session.nrp,
          ),
        );
      }
      unawaited(
        _backend.updatePresence(
          username: session.nrp,
          deviceId: 'android_${session.nrp}',
          status: 'offline',
          activeChannelId: _pttTalkingChannelId ?? _selectedPttChannelId,
          latitude: _currentLat,
          longitude: _currentLng,
        ),
      );
    }
    unawaited(_disconnectNativePtt());
    unawaited(_disconnectLiveSignaling());
    _ticker?.cancel();
    _presenceTimer?.cancel();
    unawaited(_stopLiveImageStream());
    _cameraController?.dispose();
    setState(() {
      _session = null;
      _currentTab = BodyWornTab.home;
      _isRecording = false;
      _recordingStartedAt = null;
      _isMuted = false;
      _cameraController = null;
      _cameraError = null;
      _presenceEntries = const [];
      _pttFeed = const [];
      _sosAlerts = const [];
      _pttTalkingChannelId = null;
      _pttStartedAt = null;
      _isTalking = false;
      _isPttConnected = false;
      _isBlackoutActive = false;
      _isProximityNear = false;
      _activeLiveSessionId = null;
      _isSendingLiveFrame = false;
      _isLiveImageStreamActive = false;
      _lastLiveFrameSentAt = null;
      _liveFrameCount = 0;
      _liveTransportMode = 'snapshot';
      _liveSignalingStatus = 'Signaling belum aktif';
      _liveFrameStatus = 'Belum ada frame live';
      _currentLat = null;
      _currentLng = null;
    });
    _seenSosAlertIds.clear();
    _activeSosDialogId = null;
  }

  Future<void> _startRecordingMode() async {
    if (_session == null) return;
    const prefersWebRtcLive = true;

    final results = await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
    ].request();
    setState(() {
      _permissions = PermissionSummary.fromStatuses(results);
      _currentTab = BodyWornTab.record;
    });
    _syncBlackoutState();

    if (!results[Permission.camera]!.isGranted ||
        !results[Permission.microphone]!.isGranted) {
      _showMessage('Izin kamera dan mikrofon wajib aktif.');
      return;
    }

    if (!prefersWebRtcLive) {
      await _ensureCameraReady();
      final controller = _cameraController;
      if (controller == null || !controller.value.isInitialized) {
        _showMessage(
          'Kamera belum siap: ${_cameraError ?? 'inisialisasi gagal'}',
        );
        return;
      }
    }
    if (_isRecording) {
      return;
    }
    final session = _session!;
    final location = await _resolveLocation();
    debugPrint(
      '[live-start-request] officer=${session.nrp} channel=$_selectedPttChannelId tag=$_selectedTag ws=${_config.liveSignalingWebSocketUrl} loc=${location?.latitude.toStringAsFixed(4) ?? '-'},${location?.longitude.toStringAsFixed(4) ?? '-'}',
    );
    final liveSession = await _backend.startLiveStream(
      officerId: session.nrp,
      officerName: session.fullName,
      deviceId: 'android_${session.nrp}',
      channelId: _selectedPttChannelId,
      tagLabel: _selectedTag,
      preferredTransport: prefersWebRtcLive ? 'webrtc' : 'snapshot',
      fallbackTransport: 'snapshot',
      signalingUrl: _config.liveSignalingWebSocketUrl,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationLabel: location == null
          ? 'Lokasi belum tersedia'
          : 'Lat ${location.latitude.toStringAsFixed(4)}, Lng ${location.longitude.toStringAsFixed(4)}',
    );
    debugPrint(
      '[live-start-response] officer=${session.nrp} ok=${liveSession != null} session=${liveSession?.sessionId ?? '-'} transport=${liveSession?.transport ?? '-'} signaling=${liveSession?.signalingUrl ?? '-'}',
    );
    if (liveSession == null) {
      _showMessage('Gagal membuka sesi live ke server.');
      return;
    }

    if (liveSession.transport != 'webrtc') {
      await _ensureCameraReady();
      final controller = _cameraController;
      if (controller == null || !controller.value.isInitialized) {
        await _backend.stopLiveStream(
          sessionId: liveSession.sessionId,
          officerId: session.nrp,
        );
        _showMessage(
          'Kamera fallback belum siap: ${_cameraError ?? 'inisialisasi gagal'}',
        );
        return;
      }
    }

    _ticker?.cancel();
    setState(() {
      _isRecording = true;
      _isMuted = false;
      _recordingStartedAt = DateTime.now();
      _activeLiveSessionId = liveSession.sessionId;
      _liveFrameCount = 0;
      _liveTransportMode = liveSession.transport;
      _liveSignalingStatus = 'Menyiapkan signaling WSS...';
      _liveFrameStatus = 'Menghubungkan Live Cam mode cepat...';
    });
    _syncBlackoutState();
    if (liveSession.transport == 'webrtc') {
      try {
        await _cameraController?.dispose();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _cameraController = null;
          _cameraError = null;
        });
      }
    }
    final connected = await _connectLiveSignaling(liveSession);
    debugPrint(
      '[live-signaling-connect] officer=${session.nrp} session=${liveSession.sessionId} connected=$connected transport=${liveSession.transport}',
    );
    if (!connected) {
      await _backend.stopLiveStream(
        sessionId: liveSession.sessionId,
        officerId: session.nrp,
      );
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingStartedAt = null;
        _activeLiveSessionId = null;
        _liveTransportMode = liveSession.transport;
        _liveSignalingStatus = 'Signaling Live Cam gagal.';
        _liveFrameStatus = 'Live Cam dibatalkan.';
      });
      await _ensureCameraReady();
      _showMessage('Live Cam WebRTC gagal tersambung ke dashboard.');
      return;
    }
    await _sendPresenceHeartbeat();
    await _refreshLiveSessions();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (liveSession.transport == 'webrtc') {
      _showMessage('Live Cam aktif. Video + suara berjalan ke dashboard.');
    } else {
      await Future<void>.delayed(
        const Duration(milliseconds: _liveFrameWarmupMs),
      );
      await _startLiveImageStream();
      _showMessage('Live Cam aktif. Stream frame berjalan ke server.');
    }
  }

  Future<void> _finishRecordingMode() async {
    if (!_isRecording) return;
    _ticker?.cancel();
    if (_liveTransportMode != 'webrtc') {
      await _stopLiveImageStream();
    }
    await _disconnectLiveSignaling();
    try {
      final session = _session;
      final liveSessionId = _activeLiveSessionId;
      if (session != null && liveSessionId != null) {
        await _backend.stopLiveStream(
          sessionId: liveSessionId,
          officerId: session.nrp,
        );
      }

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingStartedAt = null;
        _activeLiveSessionId = null;
        _liveSignalingStatus = 'Signaling selesai';
        _liveFrameStatus = 'Live Cam selesai';
      });
      await _sendPresenceHeartbeat();
      await _refreshLiveSessions();
      if (_liveTransportMode == 'webrtc') {
        await _ensureCameraReady();
      }
      _syncBlackoutState();
      _showMessage('Live Cam dihentikan. Monitoring server selesai.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingStartedAt = null;
        _activeLiveSessionId = null;
        _liveSignalingStatus = 'Signaling berhenti paksa';
        _liveFrameStatus = 'Live Cam gagal dihentikan';
      });
      await _refreshLiveSessions();
      if (_liveTransportMode == 'webrtc') {
        await _ensureCameraReady();
      }
      _syncBlackoutState();
      _showMessage('Gagal menghentikan live stream: $error');
    }
  }

  Future<Position?> _resolveLocation() async {
    final granted = await Geolocator.checkPermission();
    if (granted == LocationPermission.denied ||
        granted == LocationPermission.deniedForever) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  void _submitIncidentReport() {
    if (_descriptionController.text.trim().isEmpty) {
      _showMessage('Deskripsi singkat wajib diisi sebelum laporan dikirim.');
      return;
    }
    final report = IncidentReport(
      id: 'RPT_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      type: _selectedReportType,
      description: _descriptionController.text.trim(),
      witness: _witnessController.text.trim(),
      recordingId: _activeLiveSessionId ?? _selectedRecordingId ?? '',
      recordedAtIso: DateTime.now().toIso8601String(),
      locationLabel:
          _selectedRecording?.locationLabel ?? 'Lokasi tidak tersedia',
    );
    _showMessage(
      'Laporan insiden terkirim. GPS dan timestamp telah dilampirkan.',
    );
    setState(() {
      _incidentReports = [report, ..._incidentReports];
      _descriptionController.clear();
      _witnessController.clear();
    });
  }

  Future<void> _triggerSos({
    required String source,
    String targetOfficerId = '',
    String notes = '',
  }) async {
    final session = _session;
    if (session == null) return;
    final recordingId = _isRecording ? (_selectedRecordingId ?? '') : '';
    final alert = await _backend.triggerSos(
      officerId: session.nrp,
      officerName: session.fullName.trim(),
      deviceId: 'android_${session.nrp}',
      channelId: _pttTalkingChannelId ?? _selectedPttChannelId,
      source: source,
      recordingId: recordingId,
      targetOfficerId: targetOfficerId,
      latitude: _currentLat,
      longitude: _currentLng,
      locationLabel: _currentLat != null && _currentLng != null
          ? 'Lat ${_currentLat!.toStringAsFixed(5)}, Lng ${_currentLng!.toStringAsFixed(5)}'
          : 'Lokasi belum tersedia',
      notes: notes,
    );
    await _refreshSosAlerts();
    if (alert == null) {
      _showMessage('SOS gagal dikirim.');
      return;
    }
    _showMessage(
      'SOS ${alert.id} dikirim ke server${targetOfficerId.isEmpty ? '' : ' untuk $targetOfficerId'}. Total alert: ${_sosAlerts.length}.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(String iso) =>
      _fullDateFormat.format(DateTime.parse(iso).toLocal());

  String _formatTimeOnly(String iso) =>
      _compactTimeFormat.format(DateTime.parse(iso).toLocal());

  String _recordingClock() {
    if (_recordingStartedAt == null) return '00:00:00';
    final elapsed = DateTime.now().difference(_recordingStartedAt!);
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  List<RecordingEntry> get _filteredRecordings {
    final query = _searchController.text.trim().toLowerCase();
    return _recordings.where((item) {
      final filterMatch = switch (_selectedGalleryFilter) {
        'Uploaded' => item.status == RecordingUploadStatus.uploaded,
        'Pending' => item.status == RecordingUploadStatus.pending,
        _ => true,
      };
      final haystack = '${item.id} ${item.locationLabel} ${item.notes}'
          .toLowerCase();
      return filterMatch && (query.isEmpty || haystack.contains(query));
    }).toList();
  }

  int get _todayRecordingCount {
    final now = DateTime.now();
    return _recordings.where((item) {
      final date = DateTime.parse(item.recordedAtIso).toLocal();
      return date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }).length;
  }

  int get _uploadedCount => _recordings
      .where((item) => item.status == RecordingUploadStatus.uploaded)
      .length;

  int get _pendingCount => _recordings
      .where((item) => item.status == RecordingUploadStatus.pending)
      .length;

  int get _localSizeBytes =>
      _recordings.fold(0, (sum, item) => sum + item.sizeBytes);

  String get _syncStatusLabel {
    if (_isRecording || _activeLiveSessionId != null) {
      return _liveSignalingStatus.isEmpty
          ? _liveFrameStatus
          : '$_liveFrameStatus � $_liveSignalingStatus';
    }
    final pending = _pendingCount;
    return pending == 0
        ? 'Semua rekaman tersinkron'
        : '$pending rekaman menunggu upload';
  }

  RecordingEntry? get _selectedRecording {
    if (_selectedRecordingId == null) return null;
    return _recordings
        .where((item) => item.id == _selectedRecordingId)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_session == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        body: SafeArea(
          child: LoginScreen(
            nrpController: _nrpController,
            passwordController: _passwordController,
            permissions: _permissions,
            onLogin: _activateSession,
          ),
        ),
      );
    }

    final scaffold = Scaffold(
      backgroundColor: _currentTab == BodyWornTab.record
          ? const Color(0xFF11141B)
          : const Color(0xFFF4F6FA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildTabBody()),
            BottomBar(
              currentTab: _currentTab,
              onSelected: (tab) {
                unawaited(_handleTabSelected(tab));
              },
            ),
          ],
        ),
      ),
    );

    if (!_isBlackoutActive) return scaffold;

    return Stack(
      children: [
        scaffold,
        Positioned.fill(
          child: AbsorbPointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black),
              child: Center(
                child: Text(
                  'Layar terkunci — jauhkan dari sensor',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.18),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody() {
    switch (_currentTab) {
      case BodyWornTab.home:
        return HomeTab(
          session: _session!,
          recordings: _recordings.take(2).toList(),
          todayCount: _todayRecordingCount,
          uploadedCount: _uploadedCount,
          pendingCount: _pendingCount,
          batteryPercent: _batteryPercent,
          syncStatusLabel: _syncStatusLabel,
          localSizeLabel: formatStorage(_localSizeBytes),
          onStartRecording: _startRecordingMode,
          onLogout: _logout,
          formatDate: _formatDate,
        );
      case BodyWornTab.record:
        final livePreviewReady =
            _isRecording &&
            _liveTransportMode == 'webrtc' &&
            _liveWebRtcService.localRenderer != null;
        return RecordTab(
          isRecording: _isRecording,
          isMuted: _isMuted,
          isFlashOn: _isFlashOn,
          isBlackoutActive: _isBlackoutActive,
          preview: _buildCameraPreview(),
          previewAspectRatio: _cameraController?.value.aspectRatio ?? (9 / 16),
          cameraReady:
              livePreviewReady || _cameraController?.value.isInitialized == true,
          cameraStatusText: _cameraStatusText(),
          permissions: _permissions,
          recordingClock: _recordingClock(),
          recordingDateLabel: DateFormat(
            'dd MMM yyyy',
          ).format(_recordingStartedAt ?? DateTime.now()),
          recordingBytes: _localSizeBytes,
          locationLabel: _currentLat != null
              ? 'Lat ${_currentLat!.toStringAsFixed(4)}, Lng ${_currentLng!.toStringAsFixed(4)}'
              : 'Menunggu GPS...',
          locationCoords: _currentLat != null
              ? '${_currentLat!.toStringAsFixed(6)}, ${_currentLng!.toStringAsFixed(6)} · GPS aktif'
              : 'Menunggu sinyal GPS...',
          syncStatusLabel: _syncStatusLabel,
          pttLabel: _selectedPttChannelId.toUpperCase(),
          selectedTag: _selectedTag,
          tags: _recordingTags,
          onStart: _startRecordingMode,
          onStop: _finishRecordingMode,
          onToggleMute: () => unawaited(_toggleAudioMute()),
          onToggleFlash: () => unawaited(_toggleFlash()),
          onTakePhoto: () => unawaited(_captureSnapshot()),
          onOpenPtt: () => unawaited(_handleRecordScreenPtt()),
          onSelectTag: (tag) => setState(() => _selectedTag = tag),
          onSos: () => unawaited(
            _triggerSos(source: 'bodyworn', notes: 'SOS dari layar bodyworn'),
          ),
        );
      case BodyWornTab.map:
        return MapTab(
          team: _patrolTeam,
          onlineOfficers: _presenceEntries,
          currentLat: _currentLat,
          currentLng: _currentLng,
          coordinateLabel: _currentLat != null
              ? 'Lat ${_currentLat!.toStringAsFixed(4)}, Lng ${_currentLng!.toStringAsFixed(4)} · GPS aktif'
              : 'Menunggu sinyal GPS...',
          onChat: (personnel) =>
              _showMessage('Chat ke ${personnel.name} dibuka.'),
          onSos: (personnel) => unawaited(
            _triggerSos(
              source: 'map',
              targetOfficerId: personnel.name,
              notes: 'SOS dikirim dari tab peta',
            ),
          ),
        );
      case BodyWornTab.ptt:
        final channelUsers = _presenceEntries
            .where((e) => e.activeChannelId == _selectedPttChannelId)
            .toList();
        return PttTab(
          channels: _pttChannels,
          selectedChannelId: _selectedPttChannelId,
          transmissions: _pttFeed,
          onlineUsers: channelUsers,
          channelStatusLabel: _isPttConnected
              ? 'Terhubung · ${_pttChannels.where((c) => c.id == _selectedPttChannelId).map((c) => c.label).firstOrNull ?? _selectedPttChannelId.toUpperCase()}'
              : 'Menghubungkan ke relay...',
          signalWeak: !_isPttConnected,
          talkTimeLabel: _pttTalkTimeLabel(),
          isTalking: _isTalking,
          isConnected: _isPttConnected,
          onSelectChannel: (id) => unawaited(_selectPttChannel(id)),
          onPttPress: _startNativePtt,
          onPttRelease: _stopNativePtt,
        );
      case BodyWornTab.gallery:
        return GalleryTab(
          searchController: _searchController,
          selectedFilter: _selectedGalleryFilter,
          recordings: _filteredRecordings,
          recordingCountLabel: '${_filteredRecordings.length} rekaman',
          onFilterChanged: (value) =>
              setState(() => _selectedGalleryFilter = value),
          onSearchChanged: (_) => setState(() {}),
          onSelectRecording: (entry) {
            setState(() {
              _selectedRecordingId = entry.id;
              _currentTab = BodyWornTab.report;
            });
          },
          formatTime: _formatTimeOnly,
        );
      case BodyWornTab.report:
        return ReportTab(
          selectedType: _selectedReportType,
          selectedRecording: _selectedRecording,
          reports: _incidentReports,
          descriptionController: _descriptionController,
          witnessController: _witnessController,
          onTypeChanged: (value) => setState(() => _selectedReportType = value),
          onPickRecording: () {
            setState(() => _currentTab = BodyWornTab.gallery);
            _showMessage(
              'Pilih rekaman dari tab Rekaman untuk mengganti bukti terkait.',
            );
          },
          onSubmit: _submitIncidentReport,
        );
    }
  }

  Widget? _buildCameraPreview() {
    final liveRenderer = _liveWebRtcService.localRenderer;
    if (_isRecording &&
        _liveTransportMode == 'webrtc' &&
        liveRenderer != null) {
      return RTCVideoView(
        liveRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: false,
      );
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }
    return CameraPreview(controller);
  }

  String _cameraStatusText() {
    if (_isRecording) {
      return _liveSignalingStatus.isEmpty
          ? _liveFrameStatus
          : '$_liveFrameStatus · $_liveSignalingStatus';
    }
    if (_cameraError != null) {
      return 'Kamera gagal: $_cameraError';
    }
    if (_isCameraInitializing) {
      return 'Menyiapkan kamera...';
    }
    if (_cameraController?.value.isInitialized == true) {
      return 'SIAP LIVE CAM';
    }
    return 'Preview kamera';
  }

  Future<void> _handleTabSelected(BodyWornTab tab) async {
    setState(() {
      _currentTab = tab;
    });
    if (tab == BodyWornTab.record &&
        !(_isRecording && _liveTransportMode == 'webrtc')) {
      await _ensureCameraReady();
    }
    if (tab == BodyWornTab.ptt) {
      await _refreshPttData();
    }
    _syncBlackoutState();
  }
}
