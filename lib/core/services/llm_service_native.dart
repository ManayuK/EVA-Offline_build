
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';

// ── Model registry ────────────────────────────────────────────────────────────
const _kModelId     = 'llama3.2-3b-instruct-q4_k_m';
const _kModelName   = 'Llama 3.2 3B';
const _kModelUrl    =
    'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf';
const _kModelMemory = 2200000000; // ~2.2 GB RAM at runtime (safe on 8 GB device)

// ── LlmModelState ─────────────────────────────────────────────────────────────
enum LlmModelState {
  notDownloaded,
  downloading,
  downloaded,
  loading,
  ready,
  error,
  webUnsupported, // unused on native; kept so both files share the same enum
}

// ── LlmService ────────────────────────────────────────────────────────────────
class LlmService extends ChangeNotifier {
  LlmModelState _state           = LlmModelState.notDownloaded;
  double        _downloadProgress = 0.0;
  String        _errorMessage    = '';

  LlmModelState get state            => _state;
  double        get downloadProgress => _downloadProgress;
  String        get errorMessage     => _errorMessage;
  bool          get isReady          => _state == LlmModelState.ready;
  String        get modelName        => _kModelName;

  // ── One-time SDK + model registration ────────────────────────────────────
  static Future<void> initBackend() async {
    await RunAnywhere.initialize();
    await LlamaCpp.register(priority: 100);
    LlamaCpp.addModel(
      id               : _kModelId,
      name             : _kModelName,
      url              : _kModelUrl,
      memoryRequirement: _kModelMemory,
      supportsThinking : false,
    );
  }

  // ── Check if model already cached ────────────────────────────────────────
  Future<bool> isModelCached() async {
    try {
      final models = await RunAnywhere.availableModels();
      return models.any((m) => m.id == _kModelId && m.isDownloaded);
    } catch (_) {
      return false;
    }
  }

  // ── Download + load ───────────────────────────────────────────────────────
  Future<void> downloadAndLoad() async {
    if (_state == LlmModelState.ready || _state == LlmModelState.downloading) return;

    if (await isModelCached()) {
      await _load();
      return;
    }

    _setState(LlmModelState.downloading);
    try {
      await for (final progress in RunAnywhere.downloadModel(_kModelId)) {
        _downloadProgress = progress.percentage; // Llama 3.2 fix — use .percentage
        notifyListeners();
      }
      _setState(LlmModelState.downloaded);
    } catch (e) {
      _errorMessage = 'Download failed: $e';
      _setState(LlmModelState.error);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    _setState(LlmModelState.loading);
    try {
      await RunAnywhere.loadModel(_kModelId);
      _setState(LlmModelState.ready);
    } catch (e) {
      _errorMessage = 'Failed to load model: $e';
      _setState(LlmModelState.error);
    }
  }

  // ── Chat (named params, non-streaming) ───────────────────────────────────
  Future<String> chat({
    required String systemPrompt,
    required List<Map<String, String>> history,
    int    maxTokens   = 400,
    double temperature = 0.75,
  }) async {
    _assertReady();
    final prompt = _buildPrompt(systemPrompt, history);
    final result = await RunAnywhere.generateStream(
      prompt,
      options: LLMGenerationOptions(maxTokens: maxTokens, temperature: temperature),
    );
    final buffer = StringBuffer();
    await for (final token in result.stream) {
      buffer.write(token);
    }
    return _clean(buffer.toString());
  }

  Stream<String> chatStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    int    maxTokens   = 400,
    double temperature = 0.75,
  }) async* {
    _assertReady();
    final prompt = _buildPrompt(systemPrompt, history);
    final result = await RunAnywhere.generateStream(
      prompt,
      options: LLMGenerationOptions(maxTokens: maxTokens, temperature: temperature),
    );
    await for (final token in result.stream) {
      yield token;
    }
  }

  Future<String> generate(
    String prompt, {
    int    maxTokens   = 280,
    double temperature = 0.7,
  }) async {
    _assertReady();
    final result = await RunAnywhere.generateStream(
      prompt,
      options: LLMGenerationOptions(maxTokens: maxTokens, temperature: temperature),
    );
    final buffer = StringBuffer();
    await for (final token in result.stream) {
      buffer.write(token);
    }
    return _clean(buffer.toString());
  }

  // ── Prompt builders (Llama 3.2 format) ───────────────────────────────────
  //
  // Llama 3.2 Instruct template:
  //
  //   <|begin_of_text|>
  //   <|start_header_id|>system<|end_header_id|>\n\n{system}<|eot_id|>
  //   <|start_header_id|>user<|end_header_id|>\n\n{message}<|eot_id|>
  //   <|start_header_id|>assistant<|end_header_id|>\n\n
  //
  // The double newline after each header is required by the tokenizer.
  // Do NOT use <|im_start|>/<|im_end|> — those are ChatML/Qwen tokens.

  static String buildEvaSystemPrompt({
    String       cyclePhase   = 'follicular',
    int          cycleDay     = 1,
    int          journalCount = 0,
    String       mood         = 'neutral',
    String       username     = 'there',
    List<String> recentTopics = const [],
  }) =>
      'You are EVA, a warm, empathetic wellness companion for menstrual health. '
      'You support ${username.isEmpty ? 'the user' : username} with compassion and evidence-based guidance.\n\n'
      'Current context:\n'
      '- Cycle phase: $cyclePhase (day $cycleDay)\n'
      '- Mood today: $mood\n'
      '- Journal entries: $journalCount\n'
      '${recentTopics.isNotEmpty ? '- Recent topics: ${recentTopics.join(', ')}\n' : ''}'
      '\nGuidelines:\n'
      '• Acknowledge feelings before giving advice.\n'
      '• Tailor suggestions to the $cyclePhase phase.\n'
      '• Be warm but concise — 80–120 words max unless the user asks for more.\n'
      '• Never diagnose. Suggest a doctor for severe or unusual symptoms.\n'
      '• Use "you" not "one". Be natural, never preachy.\n'
      '• End responses with a follow-up question or gentle prompt to keep the conversation going.';

  static String buildJournalResponsePrompt({
    required String journalText,
    required String primaryEmotion,
    required double sentimentScore,
    required String cyclePhase,
    required String username,
  }) {
    final sentiment = sentimentScore > 0.2 ? 'positive'
                    : sentimentScore < -0.2 ? 'negative' : 'neutral';
    final name = username.isEmpty ? 'the user' : username;
    return '<|begin_of_text|>'
        '<|start_header_id|>system<|end_header_id|>\n\n'
        'You are EVA, a compassionate wellness companion. Write a brief (2–3 sentence) '
        'warm, empathetic response to this journal entry. Acknowledge the emotion, '
        'validate feelings, and offer one gentle suggestion. '
        'Do not repeat the journal text back. Do not use bullet points.\n'
        '<|eot_id|>'
        '<|start_header_id|>user<|end_header_id|>\n\n'
        'Journal entry from $name:\n'
        '"$journalText"\n\n'
        'Context: ${primaryEmotion.isNotEmpty ? primaryEmotion : sentiment} mood, '
        'currently in $cyclePhase phase.\n'
        '<|eot_id|>'
        '<|start_header_id|>assistant<|end_header_id|>\n\n';
  }

  static String buildDailyInsightPrompt({
    required String cyclePhase,
    required int    cycleDay,
    required double avgSleepHours,
    required double avgStress,
    required String username,
  }) =>
      '<|begin_of_text|>'
      '<|start_header_id|>system<|end_header_id|>\n\n'
      'You are EVA. Write ONE short (max 40 words), uplifting, actionable daily '
      'wellness insight. Do not mention numbers or data values directly.\n'
      '<|eot_id|>'
      '<|start_header_id|>user<|end_header_id|>\n\n'
      'Give me today\'s wellness insight. I am in my $cyclePhase phase '
      '(day $cycleDay). My sleep has been ${avgSleepHours < 6 ? 'poor' : avgSleepHours < 7 ? 'okay' : 'good'} '
      'and my stress is ${avgStress > 7 ? 'high' : avgStress > 4 ? 'moderate' : 'low'}.\n'
      '<|eot_id|>'
      '<|start_header_id|>assistant<|end_header_id|>\n\n';

  // ── Internal prompt builder for multi-turn chat ───────────────────────────
  String _buildPrompt(String systemPrompt, List<Map<String, String>> history) {
    final buf = StringBuffer();

    // Opening BOS token
    buf.write('<|begin_of_text|>');

    // System turn
    if (systemPrompt.isNotEmpty) {
      buf.write('<|start_header_id|>system<|end_header_id|>\n\n');
      buf.write(systemPrompt);
      buf.write('<|eot_id|>');
    }

    // Conversation history
    for (final msg in history) {
      final role    = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      buf.write('<|start_header_id|>$role<|end_header_id|>\n\n');
      buf.write(content);
      buf.write('<|eot_id|>');
    }

    // Prime the assistant turn — model continues from here
    buf.write('<|start_header_id|>assistant<|end_header_id|>\n\n');

    return buf.toString();
  }

  // ── Strip Llama 3.2 special tokens from output ───────────────────────────
  String _clean(String raw) => raw
      .replaceAll('<|eot_id|>', '')
      .replaceAll('<|end_of_text|>', '')
      .replaceAll('<|start_header_id|>', '')
      .replaceAll('<|end_header_id|>', '')
      .replaceAll('<|begin_of_text|>', '')
      // Also strip any leftover ChatML tokens in case of model mixup
      .replaceAll('<|im_end|>', '')
      .replaceAll(RegExp(r'<\|[^|]+\|>'), '')
      .trim();

  void _assertReady() {
    if (!isReady) throw StateError('LLM not loaded. State: $_state');
  }

  void _setState(LlmModelState s) {
    _state = s;
    notifyListeners();
  }
}
