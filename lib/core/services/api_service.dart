import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // ── Backend URL ─────────────────────────────────────────────────────────────
  // Default: localhost for web/desktop. Android physical devices cannot reach
  // the PC's localhost — use the PC's LAN IP (e.g. http://192.168.1.x:8000).
  // The URL can be changed at runtime via setBaseUrl() and is persisted to
  // SharedPreferences so it survives app restarts.
  static const String _defaultUrl = 'http://localhost:8000';

  // Runtime-mutable base URL (set once at startup from SharedPreferences)
  static String _baseUrl = _defaultUrl;

  static String get baseUrl => _baseUrl;

  static void setBaseUrl(String url) {
    final trimmed = url.trim().replaceAll(RegExp(r'/$'), ''); // strip trailing slash
    if (trimmed.isNotEmpty) _baseUrl = trimmed;
  }

  String? _authToken;

  // Static copy — lets the web LlmService stub read the token without
  // circular imports (stub imports api_service but not vice-versa).
  static String? _staticToken;
  static String? get staticToken => _staticToken;

  void setAuthToken(String token) {
    _authToken = token;
    _staticToken = token;
  }

  void clearAuthToken() {
    _authToken = null;
    _staticToken = null;
  }

  bool get hasToken => _authToken != null;

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  Map<String, String> get _formHeaders => {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  // ── Health check ────────────────────────────────────────────────────────────
  Future<bool> isBackendAlive() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── JSON POST ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl/api$endpoint');
      if (kDebugMode) debugPrint('POST $uri');
      final response = await http
          .post(uri, headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response, endpoint);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_friendlyNetworkError(e, endpoint));
    }
  }

  Future<Map<String, dynamic>> postLong(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl/api$endpoint');
      if (kDebugMode) debugPrint('POST (long) $uri');
      final response = await http
          .post(uri, headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));
      return _handleResponse(response, endpoint);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_friendlyNetworkError(e, endpoint));
    }
  }

  // ── Form POST (OAuth2 login) ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> postForm(
      String endpoint, Map<String, String> body) async {
    try {
      final uri = Uri.parse('$baseUrl/api$endpoint');
      if (kDebugMode) debugPrint('POST (form) $uri');
      final response = await http
          .post(uri, headers: _formHeaders, body: body)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response, endpoint);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_friendlyNetworkError(e, endpoint));
    }
  }

  // ── GET ──────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final uri = Uri.parse('$baseUrl/api$endpoint');
      if (kDebugMode) debugPrint('GET $uri');
      final response = await http
          .get(uri, headers: _jsonHeaders)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response, endpoint);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_friendlyNetworkError(e, endpoint));
    }
  }

  // ── PUT ──────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> put(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl/api$endpoint');
      final response = await http
          .put(uri, headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response, endpoint);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_friendlyNetworkError(e, endpoint));
    }
  }

  Future<Map<String, dynamic>> patch(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl/api$endpoint');
      final response = await http
          .patch(uri, headers: _jsonHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response, endpoint);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_friendlyNetworkError(e, endpoint));
    }
  }

  // ── Response handler ─────────────────────────────────────────────────────────
  Map<String, dynamic> _handleResponse(http.Response response, String endpoint) {
    if (kDebugMode) {
      debugPrint('Response ${response.statusCode} for $endpoint');
    }
    if (response.statusCode == 204) return {};

    final body = _parseBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is Map<String, dynamic>) return body;
      return {'data': body};
    }

    // Extract meaningful error message
    String detail = 'Server error (${response.statusCode})';
    if (body is Map) {
      detail = body['detail']?.toString() ?? body['message']?.toString() ?? detail;
    }
    throw ApiException(detail);
  }

  dynamic _parseBody(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  // ── Human-readable network errors ────────────────────────────────────────────
  String _friendlyNetworkError(dynamic error, String endpoint) {
    final msg = error.toString().toLowerCase();

    if (msg.contains('cors') || msg.contains('xmlhttprequest')) {
      return 'CORS error — restart the backend with:\n'
          'uvicorn main:app --port 8000 --reload';
    }
    if (msg.contains('connection refused') || msg.contains('failed host') ||
        msg.contains('network is unreachable') || msg.contains('no address associated')) {
      return 'Cannot reach backend at $baseUrl\n'
          'On a physical Android device, set your PC\'s LAN IP in Profile → Backend URL\n'
          'e.g. http://192.168.1.x:8000  (run \'ipconfig\' on Windows to find it)';
    }
    if (msg.contains('timeout')) {
      return 'Analysis is taking longer than expected. '
          'This can happen when the AI models are warming up — please try again.';
    }
    if (msg.contains('socket')) {
      return 'Network error. Make sure backend is on port 8000.';
    }
    return 'Connection failed: $error\n'
        'Backend URL: $baseUrl';
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
