import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'navigation.dart';
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
            borderSide: const BorderSide(
              color: Color(0xFF2B61AE),
              width: 1.5,
            ),
          ),
          hintStyle: const TextStyle(
            color: Color(0xFF9AA6B6),
            fontSize: 14,
          ),
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
  final RecordingStorage _storage = RecordingStorage();
  final DateFormat _fullDateFormat = DateFormat('dd MMM yyyy HH:mm');
  final DateFormat _compactTimeFormat = DateFormat('HH:mm');
  final TextEditingController _nrpController = TextEditingController(
    text: '88122344',
  );
  final TextEditingController _passwordController = TextEditingController(
    text: '12345678',
  );
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _witnessController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  OfficerSession? _session;
  PermissionSummary _permissions = const PermissionSummary();
  List<RecordingEntry> _recordings = const [];
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isMuted = false;
  bool _isCameraInitializing = false;
  BodyWornTab _currentTab = BodyWornTab.home;
  DateTime? _recordingStartedAt;
  Timer? _ticker;
  String _selectedGalleryFilter = 'Semua';
  String _selectedReportType = 'Penangkapan';
  String? _selectedRecordingId;
  String? _cameraError;
  CameraController? _cameraController;
  CameraDescription? _rearCamera;
  bool _isFlashOn = false;
  final bool _isBlackoutActive = false;
  String _selectedTag = 'Penangkapan';
  bool _isTalking = false;
  String _selectedPttChannelId = 'ch1';
  final int _batteryPercent = 87;
  List<IncidentReport> _incidentReports = const [];

  final List<PttChannel> _pttChannels = const [
    PttChannel(id: 'ch1', label: 'CH-1 Patroli', subtitle: 'Kanal utama'),
    PttChannel(id: 'ch2', label: 'CH-2 Komando', subtitle: 'Pimpinan'),
    PttChannel(id: 'ch3', label: 'CH-3 Darurat', subtitle: 'Prioritas SOS'),
  ];

  final List<String> _recordingTags = const [
    'Penangkapan',
    'Razia',
    'Patroli',
    'Lainnya',
  ];

  final List<PersonnelStatus> _patrolTeam = const [
    PersonnelStatus(
      initials: 'AS',
      name: 'Bripda A. Susilo',
      detail: 'Jl. Thamrin - Rekam aktif',
      status: 'Rec',
      statusColor: Color(0xFF19A66A),
      dotColor: Color(0xFF1BA467),
    ),
    PersonnelStatus(
      initials: 'BW',
      name: 'Briptu B. Wahyu',
      detail: 'Pasar Baru - Patroli',
      status: 'Standby',
      statusColor: Color(0xFF4A88E6),
      dotColor: Color(0xFF19A66A),
    ),
    PersonnelStatus(
      initials: 'DK',
      name: 'Ipda D. Kurniawan',
      detail: 'Gambir - Sinyal lemah',
      status: 'Weak',
      statusColor: Color(0xFFE5A126),
      dotColor: Color(0xFFE89A1B),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
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
    if (controller == null || _currentTab != BodyWornTab.record) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_ensureCameraReady());
    }
  }

  Future<void> _initialize() async {
    final results = await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
    ].request();

    final stored = await _storage.loadRecordings();
    final combined = [...stored];
    for (final entry in _seedRecordings()) {
      if (!combined.any((item) => item.id == entry.id)) {
        combined.add(entry);
      }
    }
    combined.sort(
      (a, b) => DateTime.parse(
        b.recordedAtIso,
      ).compareTo(DateTime.parse(a.recordedAtIso)),
    );

    if (!mounted) return;
    setState(() {
      _permissions = PermissionSummary.fromStatuses(results);
      _recordings = combined;
      _selectedRecordingId = combined.isNotEmpty ? combined.first.id : null;
      _isInitializing = false;
    });
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
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _cameraController?.dispose();
      setState(() {
        _cameraController = controller;
      });
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

  Future<void> _activateSession() async {
    if (_nrpController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showMessage('NRP dan sandi wajib diisi.');
      return;
    }
    setState(() {
      _session = OfficerSession(
        officerName: 'R. Santoso',
        rankLabel: 'Bripda',
        unitName: 'Polda Metro Jaya',
        shiftLabel: 'Shift Pagi Aktif',
        shiftWindow: '07:00-15:00 - j-22m',
        nrp: _nrpController.text.trim(),
      );
      _currentTab = BodyWornTab.home;
    });
    _showMessage('Login berhasil. Perangkat terdaftar MDM siap bertugas.');
  }

  void _logout() {
    _ticker?.cancel();
    _cameraController?.dispose();
    setState(() {
      _session = null;
      _currentTab = BodyWornTab.home;
      _isRecording = false;
      _recordingStartedAt = null;
      _isMuted = false;
      _cameraController = null;
      _cameraError = null;
    });
  }

  Future<void> _startRecordingMode() async {
    if (_session == null) return;

    final results = await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
    ].request();
    setState(() {
      _permissions = PermissionSummary.fromStatuses(results);
      _currentTab = BodyWornTab.record;
    });

    if (!results[Permission.camera]!.isGranted ||
        !results[Permission.microphone]!.isGranted) {
      _showMessage('Izin kamera dan mikrofon wajib aktif.');
      return;
    }

    await _ensureCameraReady();
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _showMessage(
        'Kamera belum siap: ${_cameraError ?? 'inisialisasi gagal'}',
      );
      return;
    }
    if (controller.value.isRecordingVideo) {
      return;
    }

    try {
      await controller.prepareForVideoRecording();
    } catch (_) {}

    try {
      await controller.startVideoRecording();
    } catch (error) {
      _showMessage('Gagal memulai rekaman: $error');
      return;
    }

    _ticker?.cancel();
    setState(() {
      _isRecording = true;
      _isMuted = false;
      _recordingStartedAt = DateTime.now();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _finishRecordingMode() async {
    if (!_isRecording) return;
    _ticker?.cancel();
    try {
      final controller = _cameraController;
      if (controller == null ||
          !controller.value.isInitialized ||
          !controller.value.isRecordingVideo) {
        throw Exception('Rekaman tidak aktif pada kamera');
      }

      final captured = await controller.stopVideoRecording();
      final storedPath = await _storage.persistVideo(captured);
      final position = await _resolveLocation();
      final file = File(storedPath);
      final now = DateTime.now();
      final duration = _recordingStartedAt == null
          ? 0
          : now.difference(_recordingStartedAt!).inSeconds;

      final entry = RecordingEntry(
        id: 'REC_${DateFormat('yyyyMMdd_HHmmss').format(now)}',
        officerName: _session!.fullName,
        unitName: _session!.unitName,
        recordedAtIso: now.toIso8601String(),
        filePath: storedPath,
        latitude: position?.latitude,
        longitude: position?.longitude,
        source: 'LIVE_RECORD_CAPTURE',
        notes: '${_recordingTags.first} - ${_humanDuration(duration)}',
        status: RecordingUploadStatus.pending,
        durationSeconds: duration,
        sizeBytes: await file.length(),
        locationLabel: position == null
            ? 'Lokasi belum tersedia'
            : 'Lat ${position.latitude.toStringAsFixed(4)}, Lng ${position.longitude.toStringAsFixed(4)}',
        tagLabel: _recordingTags.first,
        isSeeded: false,
      );

      final updated = [entry, ..._recordings];
      await _storage.saveRecordings(
        updated.where((item) => !item.isSeeded).toList(),
      );

      if (!mounted) return;
      setState(() {
        _recordings = updated;
        _selectedRecordingId = entry.id;
        _isRecording = false;
        _recordingStartedAt = null;
        _currentTab = BodyWornTab.gallery;
      });
      _showMessage('Rekaman berhasil disimpan dan masuk galeri.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingStartedAt = null;
      });
      _showMessage('Gagal menyimpan rekaman: $error');
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
      recordingId: _selectedRecordingId ?? '',
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

  String _humanDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return minutes == 0 ? '${remaining}dt' : '${minutes}m ${remaining}dt';
  }

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

    return Scaffold(
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
        return RecordTab(
          isRecording: _isRecording,
          isMuted: _isMuted,
          isFlashOn: _isFlashOn,
          isBlackoutActive: _isBlackoutActive,
          preview: _buildCameraPreview(),
          previewAspectRatio: _cameraController?.value.aspectRatio ?? (9 / 16),
          cameraReady: _cameraController?.value.isInitialized == true,
          cameraStatusText: _cameraStatusText(),
          permissions: _permissions,
          recordingClock: _recordingClock(),
          recordingDateLabel: DateFormat('dd MMM yyyy').format(
            _recordingStartedAt ?? DateTime.now(),
          ),
          recordingBytes: _recordings.isEmpty
              ? 142 * 1024 * 1024
              : (_recordings.first.sizeBytes + 8 * 1024 * 1024),
          locationLabel:
              _selectedRecording?.locationLabel ?? 'Jl. Jend. Sudirman, Jakpus',
          locationCoords: _selectedRecording == null
              ? '-6.2088, 106.8456 - +/-4m'
              : '${(_selectedRecording!.latitude ?? -6.2088).toStringAsFixed(4)}, '
                    '${(_selectedRecording!.longitude ?? 106.8456).toStringAsFixed(4)} - +/-4m',
          syncStatusLabel: _syncStatusLabel,
          pttLabel: _selectedPttChannelId.toUpperCase(),
          selectedTag: _selectedTag,
          tags: _recordingTags,
          onStart: _startRecordingMode,
          onStop: _finishRecordingMode,
          onToggleMute: () => setState(() => _isMuted = !_isMuted),
          onToggleFlash: () => setState(() => _isFlashOn = !_isFlashOn),
          onTakePhoto: () => _showMessage('Snapshot foto diambil.'),
          onOpenPtt: () => setState(() => _currentTab = BodyWornTab.ptt),
          onSelectTag: (tag) => setState(() => _selectedTag = tag),
          onSos: () =>
              _showMessage('Panic/SOS dikirim ke command center mock.'),
        );
      case BodyWornTab.map:
        return MapTab(
          team: _patrolTeam,
          coordinateLabel:
              'Lat -6.2088, Lng 106.8456 - GPS aktif (+/-4m)',
          onChat: (personnel) =>
              _showMessage('Chat ke ${personnel.name} dibuka.'),
          onSos: (personnel) =>
              _showMessage('SOS dikirim ke ${personnel.name}.'),
        );
      case BodyWornTab.ptt:
        return PttTab(
          channels: _pttChannels,
          selectedChannelId: _selectedPttChannelId,
          transmissions: const [],
          onlineUsers: const [],
          channelStatusLabel: 'Terhubung ke ${_selectedPttChannelId.toUpperCase()}',
          signalWeak: false,
          talkTimeLabel: '00:00',
          isTalking: _isTalking,
          onSelectChannel: (id) =>
              setState(() => _selectedPttChannelId = id),
          onToggleTalk: () => setState(() => _isTalking = !_isTalking),
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
          onTypeChanged: (value) =>
              setState(() => _selectedReportType = value),
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

  List<RecordingEntry> _seedRecordings() {
    final now = DateTime.now();
    return [
      RecordingEntry(
        id: 'REC_20260402_091233',
        officerName: 'Bripda R. Santoso',
        unitName: 'Polda Metro Jaya',
        recordedAtIso: now
            .subtract(const Duration(minutes: 29))
            .toIso8601String(),
        filePath: 'mock/REC_20260402_091233.mp4',
        latitude: -6.2088,
        longitude: 106.8456,
        source: 'DEVICE_CAMERA_INTENT',
        notes: 'Jl. Jend. Sudirman - 31 detik',
        status: RecordingUploadStatus.uploaded,
        durationSeconds: 31,
        sizeBytes: 4 * 1024 * 1024,
        locationLabel: 'Jl. Jend. Sudirman, Jakpus',
        tagLabel: 'Penangkapan',
      ),
      RecordingEntry(
        id: 'REC_20260402_082847',
        officerName: 'Bripda R. Santoso',
        unitName: 'Polda Metro Jaya',
        recordedAtIso: now
            .subtract(const Duration(hours: 1, minutes: 13))
            .toIso8601String(),
        filePath: 'mock/REC_20260402_082847.mp4',
        latitude: -6.1700,
        longitude: 106.8350,
        source: 'DEVICE_CAMERA_INTENT',
        notes: 'Pasar Baru - 2 menit 10 detik',
        status: RecordingUploadStatus.pending,
        durationSeconds: 130,
        sizeBytes: 41 * 1024 * 1024,
        locationLabel: 'Pasar Baru',
        tagLabel: 'Razia',
      ),
      RecordingEntry(
        id: 'REC_20260401_153012',
        officerName: 'Bripda R. Santoso',
        unitName: 'Polda Metro Jaya',
        recordedAtIso: now
            .subtract(const Duration(days: 1, hours: 2))
            .toIso8601String(),
        filePath: 'mock/REC_20260401_153012.mp4',
        latitude: -6.1754,
        longitude: 106.8272,
        source: 'DEVICE_CAMERA_INTENT',
        notes: 'Monas - 8 menit 47 detik',
        status: RecordingUploadStatus.uploaded,
        durationSeconds: 527,
        sizeBytes: 203 * 1024 * 1024,
        locationLabel: 'Monas',
        tagLabel: 'Patroli',
      ),
    ];
  }

  Widget? _buildCameraPreview() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }
    return CameraPreview(controller);
  }

  String _cameraStatusText() {
    if (_cameraError != null) {
      return 'Kamera gagal: $_cameraError';
    }
    if (_isCameraInitializing) {
      return 'Menyiapkan kamera...';
    }
    if (_cameraController?.value.isInitialized == true) {
      return 'Preview kamera aktif';
    }
    return 'Preview kamera';
  }

  Future<void> _handleTabSelected(BodyWornTab tab) async {
    setState(() {
      _currentTab = tab;
    });
    if (tab == BodyWornTab.record) {
      await _ensureCameraReady();
    }
  }
}
