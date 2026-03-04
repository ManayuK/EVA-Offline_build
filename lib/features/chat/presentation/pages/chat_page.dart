import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/local/local_database_service.dart';
import '../../../../core/services/llm_service.dart';
import '../../../../core/services/tts_service.dart';                  // ← NEW
import '../../../../core/services/chat_local_repository.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// ── Domain model ──────────────────────────────────────────────────────────────

class _ChatMsg {
  final String role;
  final String content;
  final bool   isLoading;

  const _ChatMsg({required this.role, required this.content, this.isLoading = false});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  LocalChatMessage toLocal(String userKey, String session) => LocalChatMessage(
        userKey: userKey,
        session: session,
        role   : role,
        content: content,
        ts     : DateTime.now(),
      );
}

// ── Page ─────────────────────────────────────────────────────────────────────

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _controller  = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final List<_ChatMsg> _messages = [];

  bool   _isLoading    = false;
  bool   _sendLock     = false;   // synchronous guard against double-tap
  bool   _initDone     = false;
  bool   _showHistory  = false;
  // Streaming token buffer for the current assistant message
  final StringBuffer _streamBuffer = StringBuffer();
  bool _disposed = false;

  String _cyclePhase   = '';
  int    _cycleDay     = 0;
  int    _journalCount = 0;
  String _userMood     = 'neutral';
  String _username     = '';
  List<String> _recentTopics = [];

  // ── Silent background analysis state ─────────────────────────────────────
  // Accumulates the user's messages across the session for a single daily
  // emotion analysis call. We batch them to avoid calling analyzeJournalEntry
  // on every single message (which would thrash the Kalman state).
  final List<String> _userMessageBuffer = [];
  String? _lastSilentAnalysisDate;   // 'yyyy-MM-dd' — only one pass per day

  late final ChatLocalRepository _localRepo;
  late String _userKey;
  late String _currentSession;
  List<ChatSession> _pastSessions = [];

  @override
  void initState() {
    super.initState();
    _localRepo      = getIt<ChatLocalRepository>();
    _currentSession = ChatLocalRepository.todaySession();
    _userKey = 'local_user';
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    // Re-run init when model finishes downloading/loading so the chat
    // context chip and intro message appear without needing an app restart.
    getIt<LlmService>().addListener(_onLlmStateChange);
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _scrollCtrl.dispose();
    // Stop any speech when leaving the chat screen
    getIt<TtsService>().stop();
    getIt<LlmService>().removeListener(_onLlmStateChange);
    super.dispose();
  }

  LlmService get _llm  => getIt<LlmService>();
  TtsService get _tts  => getIt<TtsService>();

  // Called when LLM model finishes downloading / loading.
  // Re-runs _init so the context chip fills in and a proper greeting is shown.
  void _onLlmStateChange() {
    if (_llm.isReady && _messages.isEmpty && !_initDone) {
      _init();
    }
  }              // ← NEW

  Future<void> _init() async {
    // Load auth context for username
    final auth = context.read<AuthProvider>();
    _username = auth.currentUser?.name ?? '';

    final saved = await _localRepo.getMessages(_userKey, _currentSession);
    if (saved.isNotEmpty) {
      setState(() {
        for (final m in saved) {
          _messages.add(_ChatMsg(role: m.role, content: m.content));
        }
        _initDone = true;
      });
      _scrollToBottom();

      // Pre-fill the silent analysis buffer with today's user messages so
      // word-count thresholds work correctly if the user re-opens chat.
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final m in saved) {
        if (m.role == 'user') _userMessageBuffer.add(m.content);
      }
      // Mark today as already analyzed if there are pre-existing messages —
      // we don't re-analyze on every app open, only on new messages.
      if (_userMessageBuffer.isNotEmpty) _lastSilentAnalysisDate = today;
    }
    await _refreshSessionsList();

    // Load cycle/journal context from local DB — no network call
    try {
      final localDb = getIt<LocalDatabaseService>();
      final dash    = await localDb.getDashboard();
      final memory  = await localDb.getChatMemory();
      setState(() {
        _cyclePhase   = dash.currentPhase;
        _cycleDay     = dash.currentCycleDay;
        _journalCount = memory.totalJournalEntries;
        _recentTopics = memory.summaries.take(3).toList();
        _userMood     = dash.moodToday ?? memory.topMood;
      });
    } catch (_) {}

    if (_messages.isEmpty) {
      const intro = "Hi! I'm EVA, your on-device wellness companion. What's on your mind today?";
      setState(() {
        _messages.add(const _ChatMsg(role: 'assistant', content: intro));
        _initDone = true;
      });
      await _localRepo.saveMessage(
        const _ChatMsg(role: 'assistant', content: intro).toLocal(_userKey, _currentSession));
    } else if (!_initDone) {
      setState(() => _initDone = true);
    }
  }

  Future<void> _refreshSessionsList() async {
    final sessions = await _localRepo.getSessions(_userKey);
    if (mounted) setState(() => _pastSessions = sessions);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading || _sendLock) return;
    _sendLock = true; // synchronous — prevents double-tap before first setState
    _controller.clear();

    // Stop any current TTS before the user's new message arrives
    if (_tts.isSpeaking) await _tts.stop();

    // Check model is downloaded and loaded
    if (!_llm.isReady) {
      setState(() {
        _messages.add(_ChatMsg(
          role: 'assistant',
          content: _llm.state == LlmModelState.downloading
              ? 'AI model is downloading… ${(_llm.downloadProgress * 100).toStringAsFixed(0)}% done.'
              : _llm.state == LlmModelState.loading
                  ? 'Loading AI model into memory, almost ready…'
                  : 'AI model not loaded yet. Tap the Download button in the Chat tab.',
        ));
      });
      return;
    }

    final userMsg = _ChatMsg(role: 'user', content: text);
    setState(() {
      _messages.add(userMsg);
      _messages.add(const _ChatMsg(role: 'assistant', content: '', isLoading: true));
      _isLoading = true;
    });
    _scrollToBottom();
    await _localRepo.saveMessage(userMsg.toLocal(_userKey, _currentSession));

    // ── Option A: silent background emotion extraction ──────────────────────
    // Accumulate user message and run analysis in the background.
    // We don't await — it must never block the UI or the LLM response.
    _bufferAndAnalyzeSilently(text);

    try {
      // Build conversation history (all real messages except the loading placeholder)
      final allReal = _messages.where((m) => !m.isLoading).toList();
      final history = allReal
          .map((m) => <String, String>{'role': m.role, 'content': m.content})
          .toList();

      final systemPrompt = LlmService.buildEvaSystemPrompt(
        cyclePhase   : _cyclePhase,
        cycleDay     : _cycleDay,
        journalCount : _journalCount,
        mood         : _userMood,
        username     : _username,
        recentTopics : _recentTopics,
      );

      // Stream tokens into the loading bubble
      _streamBuffer.clear();
      await for (final token in _llm.chatStream(
        systemPrompt: systemPrompt,
        history     : history,
        maxTokens   : 400,
        temperature : 0.75,
      )) {
        _streamBuffer.write(token);
        if (!_disposed && mounted) {
          setState(() {
          _messages[_messages.length - 1] =
              _ChatMsg(role: 'assistant', content: _streamBuffer.toString(), isLoading: false);
        });
        }
      }

      final finalReply = _streamBuffer.toString().trim();
      final aMsg = _ChatMsg(role: 'assistant', content: finalReply.isEmpty
          ? "I wasn't able to generate a response. Please check that the backend is running and try again. 💜"
          : finalReply);

      if (!_disposed && mounted) {
        setState(() {
        _messages[_messages.length - 1] = aMsg;
        _isLoading = false;
        _sendLock  = false;
      });
      }
      await _localRepo.saveMessage(aMsg.toLocal(_userKey, _currentSession));
      if (!_disposed) await _refreshSessionsList();

      // ── Auto-speak: read EVA's reply if the toggle is on ─────────────────
      if (_tts.autoSpeak && aMsg.content.isNotEmpty) {
        final msgId = '${_currentSession}_${_messages.length - 1}';
        await _tts.speak(aMsg.content, msgId: msgId);
      }
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(_ChatMsg(
          role   : 'assistant',
          content: 'Something went wrong with the local AI. Error: $e',
        ));
        _isLoading = false;
        _sendLock  = false;
      });
    }
    _scrollToBottom();
  }

  // ── Silent background emotion extraction (Option A) ──────────────────────
  //
  // Called every time the user sends a message. Accumulates text across the
  // session and runs analyzeJournalEntry in the background — never blocks UI.
  //
  // Rules:
  //  • Minimum 20 words before a full analysis (filters "ok", "thanks" etc.)
  //  • At most ONE full journal write per calendar day (avoids Kalman thrash)
  //  • Extra emotionally-loaded messages after the daily write still nudge the
  //    Kalman variance via a lightweight updateKalmanSentimentOnly path
  //  • Completely invisible — no snackbars, no buttons, no user action needed
  void _bufferAndAnalyzeSilently(String userText) {
    _userMessageBuffer.add(userText);

    // Fire-and-forget — never block _send()
    () async {
      try {
        final today   = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final localDb = getIt<LocalDatabaseService>();

        // ── Full daily analysis (once per day) ────────────────────────────
        if (_lastSilentAnalysisDate != today) {
          final combined  = _userMessageBuffer.join(' ');
          final wordCount = combined.trim().split(RegExp(r'\s+')).length;

          if (wordCount >= 20) {
            // analyzeJournalEntry runs EmotionDetector, nudges Kalman variance,
            // logs mood, and upserts a journal_entries row tagged with
            // model_version = 'chat_silent' so it is distinguishable from
            // manually written entries in the Insights journal view.
            await localDb.analyzeJournalEntry(
              '[chat]\n$combined',
              today,
            );
            _lastSilentAnalysisDate = today;

            // Keep the context chip counter accurate after background write
            if (mounted) setState(() => _journalCount++);
          }
        } else {
          // ── Lightweight intra-day nudge ────────────────────────────────
          // After the daily write, still push strongly emotional single
          // messages into the Kalman sentiment path.
          final wordCount = userText.trim().split(RegExp(r'\s+')).length;
          if (wordCount >= 8) {
            final lower = userText.toLowerCase();
            const emotionWords = [
              'anxious','stressed','sad','angry','frustrated','scared',
              'worried','happy','excited','grateful','exhausted','tired',
              'depressed','hopeless','overwhelmed','calm','peaceful',
              'irritated','nervous','miserable','joyful','awful',
            ];
            if (emotionWords.any((w) => lower.contains(w))) {
              await localDb.updateKalmanSentimentOnly(userText);
            }
          }
        }
      } catch (_) {
        // Swallow silently — background work must never surface errors to user
      }
    }();
  }

  Future<void> _loadSession(String session) async {
    await _tts.stop();
    final saved = await _localRepo.getMessages(_userKey, session);
    setState(() {
      _currentSession = session;
      _messages.clear();
      for (final m in saved) {
        _messages.add(_ChatMsg(role: m.role, content: m.content));
      }
      _showHistory = false;
    });
    _scrollToBottom();
  }

  Future<void> _startNewSession() async {
    await _tts.stop();
    // Use a timestamp-based key so same-day sessions don't collide
    final ts = DateTime.now();
    final newSession = [
      ts.year.toString().padLeft(4, '0'),
      '-',
      ts.month.toString().padLeft(2, '0'),
      '-',
      ts.day.toString().padLeft(2, '0'),
      '_',
      ts.hour.toString().padLeft(2, '0'),
      '-',
      ts.minute.toString().padLeft(2, '0'),
      '-',
      ts.second.toString().padLeft(2, '0'),
    ].join();
    setState(() {
      _currentSession = newSession;
      _messages.clear();
      _showHistory    = false;
      _initDone       = false;
    });
    await _init();
  }

  Future<void> _deleteSession(String session) async {
    await _localRepo.deleteSession(_userKey, session);
    await _refreshSessionsList();
    if (_currentSession == session) await _startNewSession();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve   : Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: _buildAppBar(),
      body: ListenableBuilder(
        listenable: getIt<LlmService>(),
        builder: (context, _) {
          final llm = getIt<LlmService>();
          if (!llm.isReady) {
            return _ModelDownloadPanel(llm: llm);
          }
          return _buildChatBody();
        },
      ),
    );
  }

  Widget _buildChatBody() {
    return GestureDetector(
      // Tapping the chat area while sidebar is open closes the sidebar
      onTap: _showHistory ? () => setState(() => _showHistory = false) : null,
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          width: _showHistory ? 270 : 0,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 270,
              maxWidth: 270,
              child: _HistorySidebar(
                sessions       : _pastSessions,
                currentSession : _currentSession,
                onSelectSession: _loadSession,
                onDeleteSession: _deleteSession,
                onNewSession   : _startNewSession,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(children: [
            if (_cyclePhase.isNotEmpty) _buildContextChip(),
            Expanded(child: _buildMessageList()),
            _buildInputBar(),
          ]),
        ),
      ]),
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: AppTheme.primaryPurple,
    foregroundColor: Colors.white,
    leading: IconButton(
      icon   : Icon(_showHistory ? Icons.menu_open : Icons.menu_rounded),
      tooltip: _showHistory ? 'Hide history' : 'Chat history',
      onPressed: () => setState(() => _showHistory = !_showHistory),
    ),
    title: Row(children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('E', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('EVA Chat',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ListenableBuilder(
            listenable: getIt<LlmService>(),
            builder: (_, __) {
              final llm = getIt<LlmService>();
              final label = llm.isReady
                  ? '🤖 ${llm.modelName} · on-device'
                  : llm.state == LlmModelState.downloading
                      ? '⬇️ Downloading… ${(llm.downloadProgress * 100).toStringAsFixed(0)}%'
                      : llm.state == LlmModelState.loading
                          ? '⏳ Loading model…'
                          : 'Connecting…';
              return Text(label,
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.white70));
            },
          ),
        ]),
      ),
    ]),
    actions: [
      // ── Auto-speak toggle ─────────────────────────────────────────────────
      ListenableBuilder(
        listenable: _tts,
        builder: (_, __) => IconButton(
          icon: Icon(
            _tts.autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: _tts.autoSpeak ? Colors.white : Colors.white54,
          ),
          tooltip: _tts.autoSpeak
              ? 'Auto-speak ON — tap to turn off'
              : 'Auto-speak OFF — tap to turn on',
          onPressed: () => _tts.toggleAutoSpeak(),
        ),
      ),
      IconButton(
        icon   : const Icon(Icons.add_comment_outlined),
        tooltip: 'New conversation',
        onPressed: _startNewSession,
      ),
    ],
  );

  Widget _buildContextChip() {
    return Container(
      color  : AppTheme.primaryPurple.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        const Icon(Icons.auto_awesome, size: 13, color: AppTheme.primaryPurple),
        const SizedBox(width: 6),
        Expanded(child: Text(
          'Phase: $_cyclePhase · Day $_cycleDay · $_journalCount entries · on-device AI',
          style   : GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryPurple),
          overflow: TextOverflow.ellipsis,
        )),
      ]),
    );
  }

  Widget _buildMessageList() => ListView.builder(
    controller : _scrollCtrl,
    padding    : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    itemCount  : _messages.length,
    itemBuilder: (_, i) => _MessageBubble(
      msg    : _messages[i],
      msgId  : '${_currentSession}_$i',       // ← NEW: unique id per bubble
    ),
  );

  Widget _buildInputBar() => Container(
    padding: EdgeInsets.only(
      left  : 12, right: 8, top: 10,
      bottom: MediaQuery.of(context).viewInsets.bottom + 12,
    ),
    decoration: BoxDecoration(
      color    : Colors.white,
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
    ),
    child: Row(children: [
      Expanded(
        child: TextField(
          controller        : _controller,
          enabled           : !_showHistory,
          minLines          : 1,
          maxLines          : 4,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted       : (_) => _send(),
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1A1A2E)),
          decoration: InputDecoration(
            hintText     : 'Ask EVA anything…',
            hintStyle    : GoogleFonts.inter(color: const Color(0xFFADB5BD), fontSize: 14),
            filled       : true,
            fillColor    : const Color(0xFFF5F0FF),
            border       : OutlineInputBorder(
                borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _send,
        child: AnimatedContainer(
          duration : const Duration(milliseconds: 200),
          width: 44, height: 44,
          decoration: BoxDecoration(
              color: _isLoading ? Colors.grey[300] : AppTheme.primaryPurple,
              shape: BoxShape.circle),
          child: _isLoading
              ? const Padding(padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    ]),
  );
}

// ── History sidebar ───────────────────────────────────────────────────────────

class _HistorySidebar extends StatelessWidget {
  final List<ChatSession> sessions;
  final String currentSession;
  final ValueChanged<String> onSelectSession;
  final ValueChanged<String> onDeleteSession;
  final VoidCallback onNewSession;

  const _HistorySidebar({
    required this.sessions,
    required this.currentSession,
    required this.onSelectSession,
    required this.onDeleteSession,
    required this.onNewSession,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color    : Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          color  : AppTheme.primaryPurple,
          width  : double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child  : Row(children: [
            Text('History',
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
            IconButton(
              icon   : const Icon(Icons.add_rounded, color: Colors.white),
              tooltip: 'New conversation',
              onPressed: onNewSession,
            ),
          ]),
        ),
        Expanded(
          child: sessions.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 10),
                  Text('No past conversations',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF))),
                ]))
              : ListView.separated(
                  padding    : const EdgeInsets.symmetric(vertical: 8),
                  itemCount  : sessions.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  itemBuilder: (_, i) {
                    final s = sessions[i];
                    return _SessionTile(
                      session    : s,
                      isSelected : s.session == currentSession,
                      onTap      : () => onSelectSession(s.session),
                      onDelete   : () => onDeleteSession(s.session),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final ChatSession session;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppTheme.primaryPurple.withValues(alpha: 0.08) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(session.label,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppTheme.primaryPurple : const Color(0xFF374151))),
              const SizedBox(height: 3),
              Text(session.preview.isEmpty ? '(empty)' : session.preview,
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF)),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('${session.messageCount} messages',
                  style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFD1D5DB))),
            ])),
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: Icon(Icons.delete_outline_rounded,
                    size : 16,
                    color: isSelected
                        ? AppTheme.primaryPurple.withValues(alpha: 0.4)
                        : const Color(0xFFD1D5DB)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatefulWidget {
  final _ChatMsg   msg;
  final String     msgId;

  const _MessageBubble({
    required this.msg,
    required this.msgId,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _saving = false;
  bool _saved  = false;

  bool get _isUser => widget.msg.role == 'user';

  TtsService get _tts => getIt<TtsService>();

  Future<void> _saveToJournal() async {
    if (_saving || _saved || widget.msg.isLoading || widget.msg.content.isEmpty) return;
    setState(() => _saving = true);
    try {
      final localDb = getIt<LocalDatabaseService>();
      final today   = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final result  = await localDb.analyzeJournalEntry(widget.msg.content, today);
      final label   = result.sentiment > 0.15 ? 'positive'
                    : result.sentiment < -0.15 ? 'negative' : 'neutral';
      final emotion = result.primaryEmotion;
      setState(() { _saving = false; _saved = true; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.book_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('Saved to Journal · $label${emotion.isNotEmpty ? " · $emotion" : ""}',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
          backgroundColor: const Color(0xFF7C3AED),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save to journal')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment : _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_isUser) _eva(),
          const SizedBox(width: 8),
          Flexible(child: _bubbleWithActions()),
          const SizedBox(width: 8),
          if (_isUser) _user(),
        ],
      ),
    );
  }

  Widget _eva() => Container(
    width: 32, height: 32,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [AppTheme.primaryPurple, AppTheme.secondaryPurple]),
      shape   : BoxShape.circle,
    ),
    child: const Center(
        child: Text('E', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
  );

  Widget _user() => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
    child: const Icon(Icons.person, size: 18, color: Colors.grey),
  );

  Widget _bubbleWithActions() {
    if (widget.msg.isLoading) {
      return Container(
        padding   : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color       : Colors.white,
          borderRadius: BorderRadius.circular(18).copyWith(bottomLeft: Radius.zero),
          boxShadow   : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)],
        ),
        child: const _TypingIndicator(),
      );
    }

    return Column(
      crossAxisAlignment: _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: widget.msg.content.isNotEmpty ? _saveToJournal : null,
          child: Container(
            padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _isUser ? AppTheme.primaryPurple : Colors.white,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: _isUser ? Radius.zero : const Radius.circular(18),
                bottomLeft : _isUser ? const Radius.circular(18) : Radius.zero,
              ),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Text(widget.msg.content,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    color   : _isUser ? Colors.white : const Color(0xFF1A1A2E),
                    height  : 1.45)),
          ),
        ),

        // ── Action row below EVA's bubble ───────────────────────────────────
        if (!_isUser && widget.msg.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🔊 Speak / stop button
                ListenableBuilder(
                  listenable: _tts,
                  builder: (_, __) {
                    final isThisSpeaking =
                        _tts.isSpeaking && _tts.speakingMsgId == widget.msgId;
                    return GestureDetector(
                      onTap: () => _tts.speak(
                        widget.msg.content,
                        msgId: widget.msgId,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isThisSpeaking
                              ? AppTheme.primaryPurple.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            isThisSpeaking
                                ? Icons.stop_circle_outlined
                                : Icons.volume_up_rounded,
                            size : 14,
                            color: isThisSpeaking
                                ? AppTheme.primaryPurple
                                : const Color(0xFFADB5BD),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isThisSpeaking ? 'Stop' : 'Read aloud',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: isThisSpeaking
                                  ? AppTheme.primaryPurple
                                  : const Color(0xFFADB5BD),
                              fontWeight: isThisSpeaking
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),

                // ── Save to Journal button (always visible for EVA messages) ──
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _saved ? null : _saveToJournal,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _saved
                          ? const Color(0xFF7C3AED).withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _saving
                        ? const SizedBox(width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF7C3AED)))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              _saved ? Icons.check_circle_rounded : Icons.bookmark_add_outlined,
                              size: 14,
                              color: _saved
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFFADB5BD),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _saved ? 'Saved' : 'Save to Journal',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: _saved
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFFADB5BD),
                                fontWeight: _saved ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ]),
                  ),
                ),
              ],
            ),
            ),
          )
        // For user bubbles, keep the old save indicator behaviour
        else if (_isUser && (_saving || _saved))
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
            child: _saving
                ? const SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF7C3AED)))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.book_rounded, size: 12, color: Color(0xFF7C3AED)),
                    const SizedBox(width: 3),
                    Text('Saved to Journal',
                        style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF7C3AED),
                            fontWeight: FontWeight.w600)),
                  ]),
          ),
      ],
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with TickerProviderStateMixin {
  late final List<AnimationController> _ctrl;
  late final List<Animation<double>>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = List.generate(3, (i) => AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..repeat(reverse: true, period: Duration(milliseconds: 800 + i * 200)));
    _anim = _ctrl.map((c) => Tween(begin: 0.3, end: 1.0).animate(c)).toList();
  }

  @override
  void dispose() { for (final c in _ctrl) {
    c.dispose();
  } super.dispose(); }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child  : FadeTransition(opacity: _anim[i],
          child: Container(width: 7, height: 7,
              decoration: const BoxDecoration(color: AppTheme.primaryPurple, shape: BoxShape.circle))),
    )),
  );
}

// ── Model Download / Status Panel ────────────────────────────────────────────

class _ModelDownloadPanel extends StatelessWidget {
  final LlmService llm;
  const _ModelDownloadPanel({required this.llm});

  @override
  Widget build(BuildContext context) {
    final isDownloading    = llm.state == LlmModelState.downloading;
    final isLoading        = llm.state == LlmModelState.loading;
    final isError          = llm.state == LlmModelState.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isError
                      ? [const Color(0xFF6B7280), const Color(0xFF9CA3AF)]
                      : [AppTheme.primaryPurple, AppTheme.secondaryPurple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.memory_rounded, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              isError       ? 'Download Failed' :
              isDownloading ? 'Downloading AI Model…' :
              isLoading     ? 'Preparing EVA AI…' :
              'On-Device AI',
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              isError
                  ? llm.errorMessage
                  : isDownloading || isLoading
                      ? 'Downloaded once, cached forever on your device.'
                      : 'Private on-device AI via RunAnywhere + llama.cpp.\nModel: ${llm.modelName}',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF6B7280), height: 1.6),
              textAlign: TextAlign.center,
            ),

            if (isDownloading) ...[
              const SizedBox(height: 28),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: llm.downloadProgress,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryPurple),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(llm.downloadProgress * 100).toStringAsFixed(1)}%',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppTheme.primaryPurple),
              ),
            ],

            if (isLoading) ...[
              const SizedBox(height: 28),
              const CircularProgressIndicator(color: AppTheme.primaryPurple, strokeWidth: 3),
            ],

            if (!isDownloading && !isLoading) ...[
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(isError ? Icons.refresh_rounded : Icons.download_rounded,
                      color: Colors.white),
                  label: Text(
                    isError ? 'Retry Download' : 'Download & Start (~1 GB)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => llm.downloadAndLoad(),
                ),
              ),
              const SizedBox(height: 12),
              Text('Runs privately on your device — no cloud, no API key',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
            ],
          ],
        ),
      ),
    );
  }
}
