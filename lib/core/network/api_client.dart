import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient(this._baseUrl, this._client);

  final Uri _baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> get(String path, {String? token}) =>
      _send('GET', path, token: token);

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    String? token,
  }) => _send('POST', path, body: body, token: token);

  Future<void> checkHealth() async {
    final response = await get('/health');
    if (response['status'] != 'ok') {
      throw const ApiException(
        statusCode: 0,
        code: 'backend_unhealthy',
        message: 'The backend health check failed.',
      );
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final request = http.Request(method, _baseUrl.resolve(path));
    request.headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (token != null) request.headers['authorization'] = 'Bearer $token';

    try {
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'] as Map<String, dynamic>?;
        throw ApiException(
          statusCode: response.statusCode,
          code: error?['code'] as String? ?? 'request_failed',
          message: error?['message'] as String? ?? 'Request failed.',
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on Object {
      throw const ApiException(
        statusCode: 0,
        code: 'network_error',
        message: 'Unable to connect. Check your network and try again.',
      );
    }
  }
}

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;
}
