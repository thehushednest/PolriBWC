class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.apiVersion,
    required this.useMockBackend,
    required this.enableNativePttAudio,
    required this.connectTimeoutSeconds,
    required this.pttAudioPort,
  });

  final String apiBaseUrl;
  final String apiVersion;
  final bool useMockBackend;
  final bool enableNativePttAudio;
  final int connectTimeoutSeconds;
  final int pttAudioPort;

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      apiBaseUrl: const String.fromEnvironment(
        'POLRI_BWC_API_BASE_URL',
        defaultValue: 'https://asksenopati.com/polribwc',
      ),
      apiVersion: const String.fromEnvironment(
        'POLRI_BWC_API_VERSION',
        defaultValue: 'v1',
      ),
      useMockBackend:
          const String.fromEnvironment(
            'POLRI_BWC_USE_MOCK',
            defaultValue: 'false',
          ) ==
          'true',
      enableNativePttAudio:
          const String.fromEnvironment(
            'POLRI_BWC_ENABLE_NATIVE_PTT_AUDIO',
            defaultValue: 'true',
          ) ==
          'true',
      connectTimeoutSeconds:
          int.tryParse(
            const String.fromEnvironment(
              'POLRI_BWC_TIMEOUT_SECONDS',
              defaultValue: '10',
            ),
          ) ??
          10,
      pttAudioPort:
          int.tryParse(
            const String.fromEnvironment(
              'POLRI_BWC_PTT_AUDIO_PORT',
              defaultValue: '8788',
            ),
          ) ??
          8788,
    );
  }

  String get rootUrl =>
      '${apiBaseUrl.replaceAll(RegExp(r'/$'), '')}/api/$apiVersion';
  String get apiHost => Uri.parse(apiBaseUrl).host;
  String get pttWebSocketUrl {
    final base = apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse(base);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final trimmedPath = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final wsPath =
        '${trimmedPath.isEmpty ? '' : trimmedPath}/api/$apiVersion/ptt/ws';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: wsPath,
    ).toString();
  }
  String get liveSignalingWebSocketUrl {
    final base = apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse(base);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final trimmedPath = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    final wsPath = '${trimmedPath.isEmpty ? '' : trimmedPath}/api/$apiVersion/live/ws';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: wsPath,
    ).toString();
  }
  String get chatsEndpoint => '$rootUrl/chats';
  String get reportsEndpoint => '$rootUrl/reports';
  String get recordingsEndpoint => '$rootUrl/recordings';
  String get presenceEndpoint => '$rootUrl/presence';
  String get sosEndpoint => '$rootUrl/sos';
  String get healthEndpoint => '$rootUrl/health';
  String get pttChannelsEndpoint => '$rootUrl/ptt/channels';
  String get pttFeedEndpoint => '$rootUrl/ptt/feed';
  String get pttTransmitStartEndpoint => '$rootUrl/ptt/transmit/start';
  String get pttTransmitStopEndpoint => '$rootUrl/ptt/transmit/stop';
  String get liveSessionsEndpoint => '$rootUrl/live/sessions';
}
