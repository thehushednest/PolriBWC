import 'package:flutter/material.dart';

import 'models.dart';
import 'ui_components.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    required this.nrpController,
    required this.passwordController,
    required this.permissions,
    required this.onLogin,
  });

  final TextEditingController nrpController;
  final TextEditingController passwordController;
  final PermissionSummary permissions;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final outerPadding = screenSize.width < 360 ? 18.0 : 24.0;
    final compact = screenSize.height < 760;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            outerPadding,
            compact ? 18 : 22,
            outerPadding,
            20,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 12),
            child: IntrinsicHeight(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(compact ? 30 : 36),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFFFF), Color(0xFFF4F7FC)],
                  ),
                  border: Border.all(color: const Color(0xFFDCE4F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D15345D),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  compact ? 18 : 22,
                  compact ? 20 : 24,
                  compact ? 18 : 22,
                  compact ? 18 : 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: compact ? 8 : 16),
                    Align(
                      child: Container(
                        width: compact ? 62 : 72,
                        height: compact ? 62 : 72,
                        decoration: BoxDecoration(
                          color: kBluePrimary,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: kBluePrimary.withValues(alpha: 0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.video_camera_back_outlined,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 18 : 22),
                    const Text(
                      'Polri BWC',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: kTextMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sistem Body Worn Camera',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kTextMuted, fontSize: 13.5),
                    ),
                    SizedBox(height: compact ? 18 : 22),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECF3FF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFD9E5FB)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              color: kBluePrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mode dinas siap digunakan',
                                  style: TextStyle(
                                    color: kTextMain,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Masuk dengan akun yang terdaftar pada perangkat operasional.',
                                  style: TextStyle(
                                    color: kTextMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 18 : 22),
                    _LoginField(
                      controller: nrpController,
                      hint: 'NRP / Username',
                      obscure: false,
                      prefixIcon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 10),
                    _LoginField(
                      controller: passwordController,
                      hint: 'Kata sandi',
                      obscure: true,
                      prefixIcon: Icons.lock_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onLogin,
                        style: FilledButton.styleFrom(
                          backgroundColor: kBluePrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login_rounded, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Masuk',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFD8E0ED)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF8AB1E9),
                              ),
                            ),
                            child: const Icon(
                              Icons.fingerprint,
                              color: kBluePrimary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Masuk cepat dengan sidik jari',
                                  style: TextStyle(
                                    color: kTextMain,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Gunakan autentikasi biometrik bila perangkat mendukung.',
                                  style: TextStyle(
                                    color: kTextMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 18),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        PermissionPill(
                          label: 'Kamera',
                          enabled: permissions.cameraGranted,
                        ),
                        PermissionPill(
                          label: 'Mic',
                          enabled: permissions.microphoneGranted,
                        ),
                        PermissionPill(
                          label: 'GPS',
                          enabled: permissions.locationGranted,
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(height: compact ? 14 : 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF4FB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD7E0EE)),
                      ),
                      child: const Center(
                        child: Text(
                          'Hanya perangkat terdaftar MDM',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF6E7A8A),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({
    super.key,
    required this.session,
    required this.recordings,
    required this.todayCount,
    required this.uploadedCount,
    required this.pendingCount,
    required this.localSizeLabel,
    required this.batteryPercent,
    required this.syncStatusLabel,
    required this.onStartRecording,
    required this.onLogout,
    required this.formatDate,
  });

  final OfficerSession session;
  final List<RecordingEntry> recordings;
  final int todayCount;
  final int uploadedCount;
  final int pendingCount;
  final String localSizeLabel;
  final int batteryPercent;
  final String syncStatusLabel;
  final VoidCallback onStartRecording;
  final VoidCallback onLogout;
  final String Function(String iso) formatDate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      children: [
        Container(
          decoration: BoxDecoration(
            color: kBluePrimary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Selamat datang',
                        style: TextStyle(
                          color: Color(0xFFC7D6F4),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7EA5DD),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          session.officerName
                              .replaceAll(RegExp(r'[^A-Za-z ]'), '')
                              .trim()
                              .split(' ')
                              .where((p) => p.isNotEmpty)
                              .take(2)
                              .map((p) => p[0].toUpperCase())
                              .join(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  session.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.unitName,
                  style: const TextStyle(color: Color(0xFFC7D6F4)),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3C73B8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 9,
                                  color: Color(0xFF34D973),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  session.shiftLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              session.shiftWindow,
                              style: const TextStyle(
                                color: Color(0xFFD6E5FA),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: onLogout,
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF7EA5DD),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Akhiri'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF3FC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD7E3F8)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9E7FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_outlined, color: kBluePrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Backend operasional aktif',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: kTextMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      syncStatusLabel,
                      style: const TextStyle(color: kTextMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const StatusChip(
                label: 'Live',
                state: RecordingUploadStatus.syncing,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _HomeQuickActionCard(
                icon: Icons.videocam_rounded,
                title: 'Rekam cepat',
                subtitle: 'Mulai body cam',
                tint: kBluePrimary,
                onTap: onStartRecording,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HomeQuickActionCard(
                icon: Icons.router_outlined,
                title: 'Koneksi',
                subtitle: pendingCount == 0
                    ? 'Jaringan stabil'
                    : '$pendingCount antrean',
                tint: pendingCount == 0
                    ? const Color(0xFF149C60)
                    : const Color(0xFFAF7A17),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisExtent: 132,
          children: [
            MetricCard(
              value: '$todayCount',
              label: 'Rekaman hari ini',
              leadingIcon: Icons.videocam_outlined,
              footerLabel: pendingCount == 0
                  ? 'Semua aman'
                  : '$pendingCount antrean',
            ),
            MetricCard(
              value: localSizeLabel,
              label: 'Storage lokal',
              leadingIcon: Icons.sd_storage_outlined,
              footerLabel: 'Tersandi perangkat',
            ),
            MetricCard(
              value: pendingCount == 0 ? 'Sync' : '$uploadedCount',
              label: 'Status upload',
              accentColor: pendingCount > 0
                  ? kBluePrimary
                  : const Color(0xFF1BB56E),
              compactValue: true,
              leadingIcon: Icons.cloud_done_outlined,
              footerLabel: pendingCount > 0
                  ? '$pendingCount menunggu upload'
                  : 'Semua tersinkron',
            ),
            MetricCard(
              value: '$batteryPercent%',
              label: 'Baterai',
              accentColor: batteryPercent < 35
                  ? const Color(0xFFAF7A17)
                  : const Color(0xFF1BB56E),
              leadingIcon: Icons.battery_full,
              footerLabel: batteryPercent < 35
                  ? 'Perlu isi ulang'
                  : 'Daya aman',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: AppSectionTitle('Aktivitas terakhir')),
            TextButton.icon(
              onPressed: onStartRecording,
              icon: const Icon(Icons.videocam, size: 18),
              label: const Text('Mulai baru'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...recordings.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RecentRecordingCard(entry: entry, formatDate: formatDate),
          ),
        ),
      ],
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.hint,
    required this.obscure,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15, color: kTextMain),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kTextSubtle, fontSize: 14.5),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: kBlueSoft, size: 20)
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kBluePrimary, width: 1.5),
        ),
      ),
    );
  }
}

class _HomeQuickActionCard extends StatelessWidget {
  const _HomeQuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: kTextMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: kTextMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
