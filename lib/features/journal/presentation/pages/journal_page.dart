import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/local/local_database_service.dart';
import '../../../../core/services/llm_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/providers/dashboard_provider.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});
  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  late final LocalDatabaseService _localDb;
  final _entryCtrl = TextEditingController();
  LocalEmotionResult? _analysis;
  bool _isAnalyzing  = false;
  bool _isLoadingHistory = false;
  List<LocalJournalEntry> _entries = [];
  String? _error;

  // ── Mood / daily log sliders ────────────────────────────────────────────
  String  _selectedMood  = 'neutral';
  double  _sleepHours    = 7.0;
  double  _stressLevel   = 5.0;
  double  _energyLevel   = 5.0;
  bool    _exercised     = false;
  bool    _showSliders   = true;   // shown by default — log daily vitals without writing
  bool    _sleepSynced   = false;  // true when slider is pre-filled from sleep log

  static const _moods = [
    ('happy',    Icons.sentiment_very_satisfied,  Color(0xFFFBBF24)),
    ('calm',     Icons.sentiment_satisfied,         Color(0xFF34D399)),
    ('neutral',  Icons.sentiment_neutral,           Color(0xFF94A3B8)),
    ('tired',    Icons.bedtime_outlined,            Color(0xFF818CF8)),
    ('anxious',  Icons.sentiment_dissatisfied,      Color(0xFFF59E0B)),
    ('irritable',Icons.sentiment_very_dissatisfied, Color(0xFFF97316)),
    ('sad',      Icons.sentiment_dissatisfied,      Color(0xFF60A5FA)),
    ('stressed', Icons.sentiment_dissatisfied,      Color(0xFFEF4444)),
  ];

  @override
  void initState() {
    super.initState();
    _localDb = getIt<LocalDatabaseService>();
    _loadHistory();
    _loadTodaySleep();
  }

  @override
  void dispose() { _entryCtrl.dispose(); super.dispose(); }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => _isLoadingHistory = true);
    try {
      final entries = await _localDb.getJournalEntries();
      if (mounted) setState(() { _entries = entries; _isLoadingHistory = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _loadTodaySleep() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logs = await _localDb.getSleepLogs(limit: 5);
      final todayLog = logs.where((l) => l.date == today).firstOrNull;
      if (todayLog != null && todayLog.hoursSlept != null) {
        final clamped = todayLog.hoursSlept!.clamp(2.0, 12.0);
        if (mounted) setState(() { _sleepHours = clamped; _sleepSynced = true; });
      }
    } catch (_) {}
  }

  Future<void> _analyzeAndSave() async {
    final text = _entryCtrl.text.trim();
    final hasSlidersData = _showSliders;
    if (text.isEmpty && !hasSlidersData) return;

    setState(() { _isAnalyzing = true; _error = null; });
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Always log mood/vitals to moods endpoint
      await _localDb.logMood(
        date        : today,
        mood        : _selectedMood,
        intensity   : _stressLevel / 10.0,
        sleepHours  : _sleepHours,
        energyLevel : _energyLevel.round(),
        exercise    : _exercised,
      );

      // Build the journal text — use written text if provided, otherwise
      // auto-generate a concise vitals summary so it appears in Past Entries
      final moodLabel = _selectedMood[0].toUpperCase() + _selectedMood.substring(1);
      final journalText = text.isNotEmpty
          ? text
          : 'Daily log — Mood: $moodLabel · Sleep: ${_sleepHours.toStringAsFixed(1)}h '
            '· Stress: ${_stressLevel.round()}/10 · Energy: ${_energyLevel.round()}/10'
            '${_exercised ? ' · Exercised' : ''}';

      final result = await _localDb.analyzeJournalEntry(journalText, today);

      // Generate empathetic AI response via RunAnywhere (on-device) or backend (web).
      // If backend offline, skip gracefully — BERT analysis still works.
      String localAiResponse = result.aiResponse;
      final llm = getIt<LlmService>();
      if (llm.isReady && text.isNotEmpty) {
        try {
          // Truncate to ~200 words for the LLM prompt to avoid OOM crashes
          final promptText = text.trim().split(RegExp(r'\s+')).take(200).join(' ');
          localAiResponse = await llm.generate(
            'Write a 2-3 sentence warm, empathetic response to this journal entry. '
            'Acknowledge the emotion and offer one gentle suggestion. '
            'Entry: "$promptText"',
            maxTokens   : 120,
            temperature : 0.7,
          );
        } catch (_) {  }
      }
      // Build final result — merge LLM response if available
      final finalResult = LocalEmotionResult(
        sentiment      : result.sentiment,
        primaryEmotion : result.primaryEmotion,
        emotionScores  : result.emotionScores,
        aiResponse     : localAiResponse.isNotEmpty ? localAiResponse : result.aiResponse,
        keywords       : result.keywords,
      );
      setState(() { _analysis = finalResult; });

      if (text.isEmpty) {
        // Sliders-only — show confirmation snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Daily log saved!',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              backgroundColor: const Color(0xFF34D399),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }

      setState(() { _isAnalyzing = false; });
      await _loadHistory();
      // Refresh home dashboard so health score and mood update immediately
      if (mounted) context.read<DashboardProvider>().loadDashboard();
    } catch (e) {
      setState(() { _error = e.toString(); _isAnalyzing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        title: Text('Emotion Journal',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: AppTheme.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              // ── Entry card ─────────────────────────────────────────────
              _buildEntryCard(),

              // ── Error ──────────────────────────────────────────────────
              if (_error != null) _buildError(),

              // ── Analysis result ────────────────────────────────────────
              if (_analysis != null) ...[
                const SizedBox(height: 8),
                _EmotionResultCard(result: _analysis!),
              ],

              // ── Past entries header ────────────────────────────────────
              if (_entries.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Past Entries',
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: const Color(0xFF6B7280))),
                ),
                ..._entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: e.entryText.startsWith('Daily log —')
                      ? _QuickLogCard(entry: e)
                      : e.entryText.contains('logged via Quick Log')
                          ? _QuickLogSymptomCard(entry: e)
                          : e.entryText.startsWith('[chat]')
                              ? _ChatExtractCard(entry: e)
                              : _EntryCard(
                      entry: e,
                      onDelete: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text('Delete entry?',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                            content: Text('This cannot be undone.',
                                style: GoogleFonts.inter(fontSize: 14)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false),
                                  child: Text('Cancel', style: GoogleFonts.inter())),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text('Delete',
                                    style: GoogleFonts.inter(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _localDb.deleteJournalEntry(e.id);
                          await _loadHistory();
                        }
                      },
                      onEdit: (newText) async {
                        await _localDb.updateJournalEntry(e.id, newText, e.date);
                        await _loadHistory();
                      },
                    ),
                )),
              ] else if (!_isLoadingHistory)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Center(
                    child: Column(children: [
                      const Icon(Icons.book_outlined, size: 48, color: Color(0xFFD1D5DB)),
                      const SizedBox(height: 12),
                      Text('No entries yet — write your first one!',
                          style: GoogleFonts.inter(color: const Color(0xFF9CA3AF))),
                    ]),
                  ),
                ),

              if (_isLoadingHistory)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildEntryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Flexible(child: Text(DateFormat('EEEE, MMMM d').format(DateTime.now()),
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF374151)),
                overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _showSliders = !_showSliders),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _showSliders ? AppTheme.primaryPurple.withValues(alpha: 0.1) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.tune_rounded,
                      size: 14,
                      color: _showSliders ? AppTheme.primaryPurple : const Color(0xFF6B7280)),
                  const SizedBox(width: 4),
                  Text('Daily Log',
                      style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: _showSliders ? AppTheme.primaryPurple : const Color(0xFF6B7280))),
                ]),
              ),
            ),
          ]),
        ),

        // Text area
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _entryCtrl,
            maxLines: null,      // unlimited lines — scrolls within the card
            minLines: 4,
            maxLength: 3000,     // ~500 words; warn user, never crash
            decoration: InputDecoration(
              hintText: 'How are you feeling today? Write freely...',
              hintStyle: GoogleFonts.inter(color: const Color(0xFFD1D5DB), fontSize: 14),
              border: InputBorder.none,
              counterStyle: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFD1D5DB)),
            ),
            style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1A1A2E), height: 1.5),
            onChanged: (_) => setState(() => _analysis = null),
          ),
        ),

        // ── Sliders panel (collapsible) ──────────────────────────────────
        if (_showSliders) ...[
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Mood selector
              Text('How are you feeling?',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF374151))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: _moods.map((m) {
                final selected = _selectedMood == m.$1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedMood = m.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? m.$3.withValues(alpha: 0.18) : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? m.$3 : const Color(0xFFE5E7EB),
                        width: selected ? 1.8 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(m.$2, size: 18, color: m.$3.withValues(alpha: 0.8)),
                      const SizedBox(width: 5),
                      Text(m.$1.substring(0, 1).toUpperCase() + m.$1.substring(1),
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? m.$3 : const Color(0xFF6B7280))),
                    ]),
                  ),
                );
              }).toList()),

              const SizedBox(height: 16),

              // Sleep slider — pre-filled from today's Sleep Log if available
              _SliderRow(
                icon: Icons.bedtime_rounded,
                iconColor: const Color(0xFF818CF8),
                label: 'Sleep',
                value: _sleepHours,
                min: 2, max: 12, divisions: 20,
                displayValue: '${_sleepHours.toStringAsFixed(1)}h',
                synced: _sleepSynced,
                onChanged: (v) => setState(() {
                  _sleepHours = v;
                  _sleepSynced = false; // user manually adjusted — clear badge
                }),
              ),
              const SizedBox(height: 10),

              // Stress slider
              _SliderRow(
                icon: Icons.psychology_rounded,
                iconColor: const Color(0xFFEF4444),
                label: 'Stress',
                value: _stressLevel,
                min: 1, max: 10, divisions: 9,
                displayValue: '${_stressLevel.round()}/10',
                onChanged: (v) => setState(() => _stressLevel = v),
              ),
              const SizedBox(height: 10),

              // Energy slider
              _SliderRow(
                icon: Icons.bolt_rounded,
                iconColor: const Color(0xFFFBBF24),
                label: 'Energy',
                value: _energyLevel,
                min: 1, max: 10, divisions: 9,
                displayValue: '${_energyLevel.round()}/10',
                onChanged: (v) => setState(() => _energyLevel = v),
              ),
              const SizedBox(height: 12),

              // Exercised toggle
              Row(children: [
                const Icon(Icons.directions_run_rounded,
                    size: 18, color: Color(0xFF34D399)),
                const SizedBox(width: 8),
                Text('Exercised today',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF374151))),
                const Spacer(),
                Switch.adaptive(
                  value: _exercised,
                  onChanged: (v) => setState(() => _exercised = v),
                  activeThumbColor: AppTheme.primaryPurple,
                ),
              ]),
              const SizedBox(height: 4),
            ]),
          ),
        ],

            const Divider(height: 1, color: Color(0xFFF3F4F6)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Model badge row
              Text('DistilRoBERTa · RunAnywhere',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
              const SizedBox(height: 10),
              // Action buttons row — always has enough space now
              Row(children: [
                if (_entryCtrl.text.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() { _entryCtrl.clear(); _analysis = null; }),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Clear',
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9CA3AF))),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: _entryCtrl.text.isNotEmpty ? 2 : 1,
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzing ? null : _analyzeAndSave,
                    icon: _isAnalyzing
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_entryCtrl.text.isEmpty ? Icons.save_outlined : Icons.psychology_outlined, size: 16),
                    label: Text(_isAnalyzing
                        ? 'Saving...'
                        : (_entryCtrl.text.isEmpty ? 'Save Log' : 'Analyze & Save'),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryPurple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEF4444)))),
      ]),
    );
  }
}

// ── Slider row ────────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final double value;
  final double min, max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final bool synced;

  const _SliderRow({
    required this.icon, required this.iconColor, required this.label,
    required this.value, required this.min, required this.max,
    required this.divisions, required this.displayValue, required this.onChanged,
    this.synced = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        SizedBox(width: 46,
            child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF374151)))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.primaryPurple,
              thumbColor: AppTheme.primaryPurple,
              inactiveTrackColor: const Color(0xFFE5E7EB),
              overlayColor: AppTheme.primaryPurple.withValues(alpha: 0.1),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
          ),
        ),
        SizedBox(width: 36,
            child: Text(displayValue,
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF374151)))),
      ]),
      if (synced)
        Padding(
          padding: const EdgeInsets.only(left: 26, bottom: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.sync_rounded, size: 11, color: Color(0xFF818CF8)),
            const SizedBox(width: 3),
            Text('from Sleep Log',
                style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF818CF8))),
          ]),
        ),
    ]);
  }
}

// ── Emotion result card ───────────────────────────────────────────────────────

class _EmotionResultCard extends StatelessWidget {
  final LocalEmotionResult result;
  const _EmotionResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    final topEmotions = (r.emotionScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))).take(4).toList();
    final sentimentColor = r.sentiment > 0.25
        ? const Color(0xFF22C55E)
        : r.sentiment < -0.25 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sentimentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                r.sentiment > 0.25 ? 'Positive' : r.sentiment < -0.25 ? 'Negative' : 'Neutral',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: sentimentColor),
              ),
            ),
            const Spacer(),
            if (r.aiResponse.isNotEmpty)
              const Icon(Icons.smart_toy_outlined, size: 14, color: Color(0xFF9CA3AF)),
          ]),
          if (r.aiResponse.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(r.aiResponse,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151), height: 1.5)),
          ],
          if (topEmotions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 10),
            ...topEmotions.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(width: 80,
                    child: Text(e.key.substring(0, 1).toUpperCase() + e.key.substring(1),
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF6B7280)))),
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: e.value,
                    backgroundColor: const Color(0xFFF3F4F6),
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryPurple.withValues(alpha: 0.7)),
                    minHeight: 5,
                  ),
                )),
                const SizedBox(width: 8),
                Text('${(e.value * 100).round()}%',
                    style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF9CA3AF))),
              ]),
            )),
          ],
          if (r.keywords.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: r.keywords.take(5).map<Widget>((k) =>
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F0FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(k, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primaryPurple)),
              )
            ).toList()),
          ],
        ]),
      ),
    );
  }
}

// ── Quick log card (slider-only daily check-ins) ─────────────────────────────

// ── Quick Log symptom card (auto-created from Quick Log button) ───────────────

class _QuickLogSymptomCard extends StatelessWidget {
  final LocalJournalEntry entry;
  const _QuickLogSymptomCard({required this.entry});

  List<String> _extractSymptoms() {
    final text = entry.entryText;
    // Parse "I experienced cramps, fatigue and mood swings."
    final match = RegExp(r'I experienced (.+?)\.').firstMatch(text);
    if (match == null) return [];
    final raw = match.group(1) ?? '';
    return raw
        .replaceAll(' and ', ', ')
        .split(', ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String? _extractFlow() {
    final match = RegExp(r'I had (light|moderate|heavy) flow').firstMatch(entry.entryText);
    return match?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    final symptoms = _extractSymptoms();
    final flow     = _extractFlow();
    const purple   = Color(0xFF7C3AED);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: purple.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: Text(entry.date,
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF)),
              overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Quick Log',
                style: GoogleFonts.inter(
                    fontSize: 9, fontWeight: FontWeight.w700, color: purple)),
          ),
        ]),
        const SizedBox(height: 10),
        if (flow != null) ...[
          Row(children: [
            const Icon(Icons.water_drop_rounded, size: 13, color: Color(0xFFFF6B6B)),
            const SizedBox(width: 6),
            Text('Flow: $flow',
                style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151))),
          ]),
          const SizedBox(height: 8),
        ],
        if (symptoms.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6,
            children: symptoms.map((s) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: purple.withValues(alpha: 0.2)),
              ),
              child: Text(s,
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w500, color: purple)),
            )).toList(),
          ),
      ]),
    );
  }
}

class _QuickLogCard extends StatelessWidget {
  final LocalJournalEntry entry;
  const _QuickLogCard({required this.entry});

  Map<String, String> _parse() {
    final text = entry.entryText;
    final result = <String, String>{};
    final parts = text.replaceFirst('Daily log — ', '').split(' · ');
    for (final part in parts) {
      if (part.startsWith('Mood: ')) {
        result['mood'] = part.substring(6);
      } else if (part.startsWith('Sleep: ')) result['sleep'] = part.substring(7);
      else if (part.startsWith('Stress: ')) result['stress'] = part.substring(8);
      else if (part.startsWith('Energy: ')) result['energy'] = part.substring(8);
      else if (part.contains('Exercised')) result['exercised'] = 'done';
    }
    return result;
  }

  Color _moodColor(String? mood) {
    switch (mood?.toLowerCase()) {
      case 'happy':    return const Color(0xFFFBBF24);
      case 'calm':     return const Color(0xFF34D399);
      case 'neutral':  return const Color(0xFF94A3B8);
      case 'tired':    return const Color(0xFF818CF8);
      case 'anxious':  return const Color(0xFFF59E0B);
      case 'irritable':return const Color(0xFFF97316);
      case 'sad':      return const Color(0xFF60A5FA);
      case 'stressed': return const Color(0xFFEF4444);
      default:         return const Color(0xFF94A3B8);
    }
  }

  IconData _moodIcon(String? mood) {
    switch (mood?.toLowerCase()) {
      case 'happy':    return Icons.sentiment_very_satisfied;
      case 'calm':     return Icons.sentiment_satisfied;
      case 'neutral':  return Icons.sentiment_neutral;
      case 'tired':    return Icons.bedtime_outlined;
      case 'anxious':  return Icons.sentiment_dissatisfied;
      case 'irritable':return Icons.sentiment_very_dissatisfied;
      case 'sad':      return Icons.sentiment_dissatisfied;
      case 'stressed': return Icons.sentiment_dissatisfied;
      default:         return Icons.sentiment_neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _parse();
    final mood  = data['mood'];
    final mc    = _moodColor(mood);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mc.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Flexible(child: Text(entry.date,
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF)),
              overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: mc.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_moodIcon(mood), size: 20),
              const SizedBox(width: 4),
              Text(mood ?? 'Check-in',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: mc)),
            ]),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Check-in',
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFF16A34A))),
          ),
        ]),
        const SizedBox(height: 12),
        // Vitals grid — Wrap prevents overflow on narrow screens
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (data['sleep'] != null)
              _VitalChip(icon: Icons.bedtime_rounded, color: const Color(0xFF818CF8),
                  label: 'Sleep', value: data['sleep']!),
            if (data['stress'] != null)
              _VitalChip(icon: Icons.psychology_rounded, color: const Color(0xFFEF4444),
                  label: 'Stress', value: data['stress']!),
            if (data['energy'] != null)
              _VitalChip(icon: Icons.bolt_rounded, color: const Color(0xFFFBBF24),
                  label: 'Energy', value: data['energy']!),
            if (data['exercised'] != null)
              const _VitalChip(icon: Icons.directions_run_rounded, color: Color(0xFF34D399),
                  label: 'Exercise', value: 'done'),
          ],
        ),
      ]),
    );
  }
}

class _VitalChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _VitalChip({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.inter(fontSize: 9, color: color.withValues(alpha: 0.8))),
            Text(value, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ]),
        ]),
      ),
    );
  }
}

// ── Entry card ────────────────────────────────────────────────────────────────

class _EntryCard extends StatefulWidget {
  final LocalJournalEntry entry;
  final Future<void> Function()? onDelete;
  final Future<void> Function(String)? onEdit;

  const _EntryCard({
    required this.entry,
    this.onDelete,
    this.onEdit,
  });

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _expanded = false;
  bool _editing  = false;
  late final TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.entry.entryText);
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final score    = widget.entry.sentimentScore ?? 0;
    final emotion  = widget.entry.primaryEmotion?.toLowerCase() ?? '';
    const posEmotions = {'joy', 'happiness', 'calm', 'love', 'gratitude', 'relief', 'surprise'};
    const negEmotions = {'sadness', 'anger', 'fear', 'disgust', 'anxiety', 'stress', 'grief'};
    final bool isPos = score > 0.25 || (score > -0.05 && posEmotions.contains(emotion));
    final bool isNeg = !isPos && (score < -0.25 || (score < 0.05 && negEmotions.contains(emotion)));
    final label    = isPos ? 'Positive' : isNeg ? 'Negative' : 'Neutral';
    final sentIcon = isPos ? Icons.sentiment_very_satisfied
                   : isNeg ? Icons.sentiment_very_dissatisfied
                   : Icons.sentiment_neutral;
    final tagColor = isPos ? const Color(0xFF22C55E)
                   : isNeg ? const Color(0xFFEF4444)
                   : const Color(0xFFF59E0B);

    return GestureDetector(
      onTap: () => setState(() { _expanded = !_expanded; if (!_expanded) _editing = false; }),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(children: [
            Flexible(child: Text(widget.entry.date,
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF)),
                overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tagColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(sentIcon, size: 12, color: tagColor),
                const SizedBox(width: 4),
                Text(label,
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: tagColor)),
              ]),
            ),
            const Spacer(),
            // ── Edit / Delete actions (visible when expanded) ───────────
            if (_expanded) ...[
              GestureDetector(
                onTap: () => setState(() => _editing = !_editing),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _editing
                        ? AppTheme.primaryPurple.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _editing ? Icons.edit_off_rounded : Icons.edit_rounded,
                    size: 16,
                    color: _editing ? AppTheme.primaryPurple : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                ),
              ),
            ],
            Icon(
              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: const Color(0xFFD1D5DB),
            ),
          ]),

          const SizedBox(height: 8),

          // ── Entry text (collapsed: 3 lines; expanded: full or editable) ─
          if (_editing && _expanded) ...[
            TextField(
              controller: _editCtrl,
              maxLines: null,
              minLines: 4,
              maxLength: 3000,
              decoration: InputDecoration(
                hintText: 'Edit your entry...',
                filled: true,
                fillColor: const Color(0xFFF5F0FF),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.primaryPurple.withValues(alpha: 0.2))),
                contentPadding: const EdgeInsets.all(10),
                counterStyle: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFD1D5DB)),
              ),
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1A1A2E), height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => setState(() => _editing = false),
                child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF6B7280))),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  final newText = _editCtrl.text.trim();
                  if (newText.isEmpty) return;
                  await widget.onEdit?.call(newText);
                  if (mounted) setState(() => _editing = false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text('Save', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ]),
          ] else
            Text(
              widget.entry.entryText,
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF1A1A2E), height: 1.4),
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),

          // ── Keywords row (only when expanded) ───────────────────────────
          if (_expanded && widget.entry.keywords.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.entry.keywords.take(8).map((k) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryPurple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(k, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primaryPurple)),
              )).toList(),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Chat-extracted journal card ───────────────────────────────────────────────
class _ChatExtractCard extends StatelessWidget {
  final LocalJournalEntry entry;
  const _ChatExtractCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final sentiment = entry.sentimentScore ?? 0.0;
    final tagColor = sentiment > 0.15
        ? const Color(0xFF10B981)
        : sentiment < -0.15
            ? const Color(0xFFEF4444)
            : const Color(0xFF6B7280);

    final displayText = entry.entryText.startsWith('[chat]\n')
        ? entry.entryText.substring(8)
        : entry.entryText;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.chat_bubble_outline_rounded,
              size: 12, color: AppTheme.primaryPurple),
          const SizedBox(width: 6),
          Text('From Chat · ${entry.date}',
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryPurple)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tagColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(entry.primaryEmotion ?? 'neutral',
                style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w600, color: tagColor)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(displayText,
            style: GoogleFonts.inter(
                fontSize: 13, color: const Color(0xFF374151), height: 1.4),
            maxLines: 4,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text('Extracted silently from your chat session.',
            style: GoogleFonts.inter(
                fontSize: 10,
                color: const Color(0xFF9CA3AF),
                fontStyle: FontStyle.italic)),
      ]),
    );
  }
}
