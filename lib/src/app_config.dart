class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.apiVersion,
    required this.useMockBackend,
    required this.connectTimeoutSeconds,
    required this.pttAudioPort,
  });

  final String apiBaseUrl;
  final String apiVersion;
  final bool useMockBackend;
  final int connectTimeoutSeconds;
  final int pttAudioPort;

  factory AppConfig.fromEnvironment() {
    return AppConfig(
      apiBaseUrl: const String.fromEnvironment(
        'POLRI_BWC_API_BASE_URL',
        defaultValue: 'http://192.168.1.26:8787',
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
  String get chatsEndpoint => '$rootUrl/chats';
  String get reportsEndpoint => '$rootUrl/reports';
  String get recordingsEndpoint => '$rootUrl/recordings';
  String get presenceEndpoint => '$rootUrl/presence';
  String get healthEndpoint => '$rootUrl/health';
  String get pttChannelsEndpoint => '$rootUrl/ptt/channels';
  String get pttFeedEndpoint => '$rootUrl/ptt/feed';
  String get pttTransmitStartEndpoint => '$rootUrl/ptt/transmit/start';
  String get pttTransmitStopEndpoint => '$rootUrl/ptt/transmit/stop';
}
