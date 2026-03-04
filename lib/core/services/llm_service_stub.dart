
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

// ── LlmModelState — must match native exactly ──────────────────────────────────
enum LlmModelState {
  notDownloaded,
  downloading,
  downloaded,
  loading,
  ready,
  error,
  webUnsupported,
}

// ── LlmService stub ────────────────────────────────────────────────────────────
class LlmService extends ChangeNotifier {
  LlmModelState _state = LlmModelState.loading;

  LlmModelState get state            => _state;
  double        get downloadProgress => 0.0;
  String        get errorMessage     => '';
  // On web, "ready" = we have an auth token and the backend is reachable
  bool          get isReady          => ApiService.staticToken != null;
  String        get modelName        => 'EVA Backend (web)';

  // ── Init ───────────────────────────────────────────────────────────────────
  static Future<void> initBackend() async {
    // Nothing to initialise on web — backend handles everything
  }

  Future<bool> isModelCached() async => false;

  Future<void> downloadAndLoad() async {
    // On web there's no model to download — just check backend reachability
    _state = LlmModelState.loading;
    notifyListeners();
    try {
      final resp = await http
          .get(Uri.parse('${ApiService.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
      _state = resp.statusCode == 200
          ? LlmModelState.ready
          : LlmModelState.error;
    } catch (_) {
      _state = LlmModelState.error;
    }
    notifyListeners();
  }

  // ── Chat via backend ───────────────────────────────────────────────────────

  Future<String> chat({
    required String systemPrompt,
    required List<Map<String, String>> history,
    int    maxTokens   = 400,
    double temperature = 0.75,
  }) async {
    final token = ApiService.staticToken;
    if (token == null) return '';

    // Extract the last user message from history
    final userMessages = history.where((m) => m['role'] == 'user').toList();
    final lastMsg = userMessages.isNotEmpty
        ? userMessages.last['content'] ?? ''
        : '';
    final prevHistory = history.length > 1
        ? history.sublist(0, history.length - 1)
        : <Map<String, String>>[];

    try {
      final resp = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/chat/message'),
            headers: {
              'Content-Type' : 'application/json',
              'Accept'       : 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'message': lastMsg,
              'history': prevHistory,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['reply'] as String? ?? '';
      } else {
        // Surface server errors so Flutter shows them instead of silent empty
        final body = jsonDecode(resp.body);
        final detail = body['detail']?.toString() ?? 'Server error ${resp.statusCode}';
        throw Exception(detail);
      }
    } catch (e) {
      rethrow;
    }
  }

  Stream<String> chatStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    int    maxTokens   = 400,
    double temperature = 0.75,
  }) async* {
    final reply = await chat(
      systemPrompt: systemPrompt,
      history     : history,
      maxTokens   : maxTokens,
      temperature : temperature,
    );
    if (reply.isNotEmpty) yield reply;
  }

  Future<String> generate(
    String prompt, {
    int    maxTokens   = 280,
    double temperature = 0.7,
  }) async {
    // For journal responses — treat the prompt as a direct message
    final token = ApiService.staticToken;
    if (token == null) return '';
    try {
      final resp = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/chat/message'),
            headers: {
              'Content-Type' : 'application/json',
              'Accept'       : 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'message': prompt, 'history': []}),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['reply'] as String? ?? '';
      } else {
        // Surface server errors so Flutter shows them instead of silent empty
        final body = jsonDecode(resp.body);
        final detail = body['detail']?.toString() ?? 'Server error ${resp.statusCode}';
        throw Exception(detail);
      }
    } catch (e) {
      rethrow;
    }
  }

  // ── Static prompt builders — kept for call-site compatibility ──────────────

  static String buildEvaSystemPrompt({
    String       cyclePhase   = 'follicular',
    int          cycleDay     = 1,
    int          journalCount = 0,
    String       mood         = 'neutral',
    String       username     = 'there',
    List<String> recentTopics = const [],
  }) => ''; // backend builds prompt from DB

  static String buildJournalResponsePrompt({
    required String journalText,
    required String primaryEmotion,
    required double sentimentScore,
    required String cyclePhase,
    required String username,
  }) => journalText;

  static String buildDailyInsightPrompt({
    required String cyclePhase,
    required int    cycleDay,
    required double avgSleepHours,
    required double avgStress,
    required String username,
  }) => '';
}
