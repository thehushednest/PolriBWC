import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.timeout,
  });

  final String baseUrl;
  final Duration timeout;
  final HttpClient _client = HttpClient();

  Future<dynamic> getJson(String endpoint) async {
    final uri = Uri.parse(_resolve(endpoint));
    final request = await _client.getUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    final response = await request.close().timeout(timeout);
    return _decode(response);
  }

  Future<dynamic> postJson(String endpoint, Map<String, dynamic> body) async {
    final result = await postJsonWithStatus(endpoint, body);
    return result.body;
  }

  Future<ApiResponse> postJsonWithStatus(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse(_resolve(endpoint));
    final request = await _client.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    return ApiResponse(
      statusCode: response.statusCode,
      body: await _decode(response),
    );
  }

  String _resolve(String endpoint) {
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return endpoint;
    }
    return '${baseUrl.replaceAll(RegExp(r'/$'), '')}/${endpoint.replaceAll(RegExp(r'^/'), '')}';
  }

  Future<dynamic> _decode(HttpClientResponse response) async {
    final raw = await utf8.decoder.bind(response).join();
    if (raw.isEmpty) {
      return null;
    }
    return jsonDecode(raw);
  }
}

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final dynamic body;
}
