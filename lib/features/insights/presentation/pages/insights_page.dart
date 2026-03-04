import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/dashboard_provider.dart';
import '../../../../core/local/local_database_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/eva_charts.dart';

class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  LocalChatMemorySummary? _chatMemory;
  Map<String, dynamic>? _emotionTimeline;
  List<PhaseTask> _phaseTasks = [];
  List<LocalSymptomRecord> _symptoms = [];
  List<LocalSleepLogData> _sleepLogs = [];
  List<MoodHeatmapEntry> _moodHeatmap = [];    // ← NEW for chart 3
  Map<String, double> _moodScoreMap = {};      // ← NEW for chart 4
  bool _loadingExtras = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<DashboardProvider>();
      p.loadSuggestions();
      p.loadHealthRisks();
      if (p.dashboard == null) p.loadDashboard();
      _loadExtras();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExtras() async {
    setState(() => _loadingExtras = true);
    try {
      final ai = getIt<LocalDatabaseService>();
      final results = await Future.wait([
        ai.getChatMemory().catchError((_) => const LocalChatMemorySummary(totalJournalEntries: 0, topMood: 'neutral', topKeywords: {}, phaseAvgSentiment: {}, summaries: [])),
        ai.getEmotionTimeline(days: 30).catchError((_) => <String, dynamic>{}),
        ai.getPhaseTasks().catchError((_) => <String, dynamic>{}),
        ai.getSymptoms(limit: 100).catchError((_) => <LocalSymptomRecord>[]),
        ai.getSleepLogs(limit: 90).catchError((_) => <LocalSleepLogData>[])
      ]);
      if (mounted) {
        final sleepLogs = results[4] as List<LocalSleepLogData>;

        // Build mood heatmap from emotion timeline
        final timeline = results[1] as Map<String, dynamic>;
        final points = (timeline['timeline'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        final heatmapEntries = <MoodHeatmapEntry>[];
        final scoreMap = <String, double>{};
        for (final p in points) {
          final dateStr = p['date'] as String?;
          final sentiment = (p['sentiment'] as num?)?.toDouble();
          if (dateStr != null && sentiment != null) {
            final date = DateTime.tryParse(dateStr);
            if (date != null) {
              final score = (sentiment + 1.0) / 2.0; // −1..1 → 0..1
              heatmapEntries.add(MoodHeatmapEntry(date: date, score: score));
              scoreMap[dateStr] = score;
            }
          }
        }

        setState(() {
          _chatMemory = results[0] as LocalChatMemorySummary;
          _emotionTimeline = timeline;
          final taskData = results[2] as Map<String, dynamic>;
          _phaseTasks = (taskData['tasks'] as List? ?? [])
              .map((t) => PhaseTask.fromJson(t as Map<String, dynamic>))
              .toList();
          _symptoms     = results[3] as List<LocalSymptomRecord>;
          _sleepLogs    = sleepLogs;
          _moodHeatmap  = heatmapEntries;
          _moodScoreMap = scoreMap;
        });
      }
    } catch (_) {}
    setState(() => _loadingExtras = false);
  }

  @override
  Widget build(BuildContext context) {

    const bgColor = AppTheme.backgroundLight;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('AI Insights',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.primaryPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final p = context.read<DashboardProvider>();
              p.loadSuggestions();
              p.loadHealthRisks();
              _loadExtras();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: const [
            Tab(text: 'Insights'),
            Tab(text: 'Timeline'),
            Tab(text: 'Tasks'),
            Tab(text: 'Symptoms'),
            Tab(text: 'Heatmap'),
            Tab(text: 'Correlations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildInsightsTab(),
          _buildTimelineTab(),
          _buildTasksTab(),
          _buildSymptomsTab(),
          _buildHeatmapTab(),
          _buildCorrelationsTab(),
        ],
      ),
    );
  }

  // ── Tab 1: Suggestions + Health Risks + Chat Memory ──────────────────────

  Widget _buildInsightsTab() {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final dashboard = provider.dashboard;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Phase banner
            if (dashboard != null && dashboard.hasData)
              _PhaseBanner(
                phase: dashboard.currentPhase,
                cycleDay: dashboard.currentCycleDay,
                daysUntilPeriod: dashboard.daysUntilPeriod,
                confidenceScore: dashboard.confidenceScore,
                predictionMethod: dashboard.predictionMethod,
              )
            else
              _PlaceholderBanner(),

            const SizedBox(height: 16),

            // Chat memory summary
            if (_chatMemory != null && _chatMemory!.summaries.isNotEmpty)
              _ChatMemoryCard(memory: _chatMemory!),

            if (_chatMemory != null && _chatMemory!.summaries.isNotEmpty)
              const SizedBox(height: 16),

            // Ollama + rule-based suggestions
            Row(children: [
              Text('Personalised Suggestions',
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              if (provider.isSuggestionsLoading)
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 12),

            if (provider.suggestions.isEmpty && !provider.isSuggestionsLoading)
              const _EmptyState(
                icon: Icons.lightbulb_outline,
                message: 'Log a cycle to get personalised suggestions',
              )
            else
              ...provider.suggestions.take(6).map(
                  (s) => _SuggestionCard(suggestion: s)),

            const SizedBox(height: 16),

            // Health risk indicators
            Row(children: [
              Text('Health Risk Indicators',
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              if (provider.isRisksLoading)
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 12),

            if (provider.healthRisks.isEmpty && !provider.isRisksLoading)
              const _EmptyState(
                icon: Icons.health_and_safety_outlined,
                message: 'Log more cycles to see health risk analysis',
              )
            else
              ...provider.healthRisks.map((r) => _HealthRiskCard(risk: r)),

            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  // ── Tab 2: Emotion Timeline ───────────────────────────────────────────────

  Widget _buildTimelineTab() {
    const textPrimary = Color(0xFF1A1A2E);

    if (_loadingExtras) {
      return const Center(child: CircularProgressIndicator());
    }

    final timeline = _emotionTimeline;
    if (timeline == null || (timeline['entry_count'] as int? ?? 0) == 0) {
      return const _EmptyState(
        icon: Icons.timeline_outlined,
        message: 'Write journal entries to see your emotion timeline',
      );
    }

    final points = (timeline['timeline'] as List? ?? [])
        .map((e) => EmotionTimelinePoint.fromJson(e as Map<String, dynamic>))
        .where((p) => p.sentiment != null)
        .toList();

    final topEmotions = timeline['top_emotions'] as Map<String, dynamic>? ?? {};
    final avgSentiment = (timeline['avg_sentiment'] as num?)?.toDouble() ?? 0;

    final sentimentSpots = points.asMap().entries.map((e) =>
        FlSpot(e.key.toDouble(), e.value.sentiment!)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Avg sentiment banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: avgSentiment >= 0
                  ? [const Color(0xFF10B981), const Color(0xFF059669)]
                  : [const Color(0xFFEF4444), const Color(0xFFDC2626)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                avgSentiment >= 0.2
                    ? Icons.mood_rounded
                    : avgSentiment <= -0.2
                        ? Icons.mood_bad_rounded
                        : Icons.sentiment_satisfied_alt_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('30-day Mood Average',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
              Text(avgSentiment >= 0.2 ? 'Mostly Positive' :
                   avgSentiment <= -0.2 ? 'Mostly Difficult' : 'Balanced',
                  style: GoogleFonts.inter(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 18)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // Sentiment chart
        if (sentimentSpots.length >= 3)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sentiment Over Time',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: LineChart(LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.1),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: -1,
                  maxY: 1,
                  lineBarsData: [
                    LineChartBarData(
                      spots: sentimentSpots,
                      isCurved: true,
                      color: avgSentiment >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: (avgSentiment >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                            .withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                )),
              ),
            ]),
          ),

        const SizedBox(height: 16),

        // Top emotions
        if (topEmotions.isNotEmpty) ...[
          Text('Top Emotions (30 days)',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: topEmotions.entries.map((e) {
            final emotionChipIcons = <String, IconData>{
              'happy'    : Icons.mood_rounded,
              'joy'      : Icons.mood_rounded,
              'calm'     : Icons.spa_outlined,
              'neutral'  : Icons.sentiment_satisfied_alt_rounded,
              'sad'      : Icons.mood_bad_rounded,
              'sadness'  : Icons.mood_bad_rounded,
              'anxious'  : Icons.psychology_outlined,
              'anxiety'  : Icons.psychology_outlined,
              'stressed' : Icons.crisis_alert_rounded,
              'irritable': Icons.mood_bad_rounded,
              'energetic': Icons.bolt_rounded,
              'depressed': Icons.mood_bad_rounded,
              'fear'     : Icons.visibility_off_outlined,
              'anger'    : Icons.local_fire_department_outlined,
              'surprise' : Icons.auto_awesome_rounded,
              'tired'    : Icons.bedtime_outlined,
            };
            final chipIcon = emotionChipIcons[e.key.toLowerCase()] ?? Icons.radio_button_unchecked_rounded;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(chipIcon, size: 14, color: AppTheme.primaryPurple),
                const SizedBox(width: 5),
                Text('${e.key}  ×${e.value}',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppTheme.primaryPurple)),
              ]),
            );
          }).toList()),
        ],

        // Individual entries
        const SizedBox(height: 16),
        Text('Recent Journal Emotions',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
        const SizedBox(height: 12),
        ...(timeline['timeline'] as List? ?? [])
            .reversed
            .take(10)
            .map((e) {
              final p = EmotionTimelinePoint.fromJson(e as Map<String, dynamic>);
              final emotionIconMap = <String, IconData>{
                'happy'    : Icons.mood_rounded,
                'joy'      : Icons.mood_rounded,
                'calm'     : Icons.spa_outlined,
                'neutral'  : Icons.sentiment_satisfied_alt_rounded,
                'sad'      : Icons.mood_bad_rounded,
                'sadness'  : Icons.mood_bad_rounded,
                'anxious'  : Icons.psychology_outlined,
                'anxiety'  : Icons.psychology_outlined,
                'stressed' : Icons.crisis_alert_rounded,
                'anger'    : Icons.local_fire_department_outlined,
                'irritable': Icons.mood_bad_rounded,
                'tired'    : Icons.bedtime_outlined,
                'fear'     : Icons.visibility_off_outlined,
                'disgust'  : Icons.do_not_disturb_on_outlined,
                'surprise' : Icons.auto_awesome_rounded,
              };
              final emotionIcon = emotionIconMap[p.emotion?.toLowerCase()] ?? Icons.radio_button_unchecked_rounded;
              final sentColor = p.sentiment != null
                  ? (p.sentiment! > 0.1 ? const Color(0xFF10B981) : p.sentiment! < -0.1 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B))
                  : Colors.grey;
              final emotionColor = sentColor;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(children: [
                  Icon(emotionIcon, size: 22, color: emotionColor),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.date,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                    if (p.emotion != null)
                      Text(p.emotion!,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: textPrimary)),
                  ])),
                  if (p.sentiment != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: sentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        p.sentiment! > 0 ? '+${p.sentiment!.toStringAsFixed(2)}' : p.sentiment!.toStringAsFixed(2),
                        style: GoogleFonts.inter(fontSize: 11, color: sentColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                ]),
              );
            }),

        const SizedBox(height: 32),
      ],
    );
  }

  // ── Tab 3: Phase-Based Tasks ──────────────────────────────────────────────

  Widget _buildTasksTab() {
    const textPrimary = Color(0xFF1A1A2E);

    if (_loadingExtras) return const Center(child: CircularProgressIndicator());

    final phaseColors = {
      'menstrual': AppTheme.menstrualRed,
      'follicular': AppTheme.follicularGreen,
      'ovulation': AppTheme.ovulationOrange,
      'luteal': AppTheme.lutealPurple,
    };

    final phaseIcons = {
      'menstrual': Icons.water_drop_rounded,
      'follicular': Icons.eco_rounded,
      'ovulation': Icons.wb_sunny_rounded,
      'luteal': Icons.nightlight_round,
    };

    return Consumer<DashboardProvider>(builder: (context, provider, _) {
      final phase = provider.dashboard?.currentPhase ?? 'follicular';
      final phaseColor = phaseColors[phase] ?? AppTheme.primaryPurple;
      final phaseIconData = phaseIcons[phase] ?? Icons.favorite_rounded;

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Phase header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                phaseColor.withValues(alpha: 0.2), phaseColor.withValues(alpha: 0.05)
              ]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: phaseColor.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(phaseIconData, size: 32, color: phaseColor),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${phase[0].toUpperCase()}${phase.substring(1)} Phase',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: phaseColor)),
                Text('Your personalised task list for today',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
              ])),
            ]),
          ),

          const SizedBox(height: 16),

          if (_phaseTasks.isEmpty)
            const _EmptyState(icon: Icons.task_alt, message: 'Log a cycle to see phase tasks')
          else
            ..._phaseTasks.map((task) {
              final prioColors = {
                'high': const Color(0xFFEF4444),
                'medium': const Color(0xFFF59E0B),
                'low': const Color(0xFF10B981),
              };
              final prioColor = prioColors[task.priority] ?? Colors.grey;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
                ),
                child: Row(children: [
                  _TaskIcon(taskText: task.task, iconStr: task.icon),
                  const SizedBox(width: 12),
                  Expanded(child: Text(task.task,
                      style: GoogleFonts.inter(fontSize: 14, color: textPrimary, height: 1.4))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: prioColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(task.priority,
                        style: GoogleFonts.inter(fontSize: 10, color: prioColor, fontWeight: FontWeight.w700)),
                  ),
                ]),
              );
            }),

          const SizedBox(height: 32),
        ],
      );
    });
  }

  // ── Tab 4: Symptom Pattern Chart ──────────────────────────────────────────
  Widget _buildSymptomsTab() {
    if (_loadingExtras) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_symptoms.isEmpty) {
      return const _EmptyState(
        icon: Icons.monitor_heart_outlined,
        message: 'Log symptoms via Quick Log to see your patterns here',
      );
    }

    // Count frequency per symptom
    final freqMap = <String, int>{};
    final severityMap = <String, List<int>>{};
    for (final s in _symptoms) {
      freqMap[s.symptomType] = (freqMap[s.symptomType] ?? 0) + 1;
      severityMap.putIfAbsent(s.symptomType, () => []).add(s.severity);
    }

    // Sort by frequency descending, take top 8
    final sorted = freqMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(8).toList();

    // Phase breakdown — count symptom occurrences per cycle phase
    // Approximate phase from day-of-month using logged dates
    final phaseCount = <String, Map<String, int>>{
      'menstrual':  {},
      'follicular': {},
      'ovulation':  {},
      'luteal':     {},
    };

    for (final s in _symptoms) {
      if (s.date.isEmpty) continue;
      try {
        final d = DateTime.parse(s.date);
        // Simple heuristic: day 1-5 = menstrual, 6-13 = follicular,
        // 14-16 = ovulation, 17-28 = luteal (based on 28-day cycle)
        final dayOfMonth = d.day;
        String phase;
        if (dayOfMonth <= 5) {
          phase = 'menstrual';
        } else if (dayOfMonth <= 13) phase = 'follicular';
        else if (dayOfMonth <= 16) phase = 'ovulation';
        else                       phase = 'luteal';
        phaseCount[phase]![s.symptomType] =
            (phaseCount[phase]![s.symptomType] ?? 0) + 1;
      } catch (_) {}
    }

    const phaseColors = {
      'menstrual':  Color(0xFFFF6B6B),
      'follicular': Color(0xFF34D399),
      'ovulation':  Color(0xFFF59E0B),
      'luteal':     Color(0xFF818CF8),
    };

    final symptomLabels = {
      'cramps':            'Cramps',
      'bloating':          'Bloating',
      'headache':          'Headache',
      'breast_tenderness': 'Breast Tenderness',
      'acne':              'Acne',
      'fatigue':           'Fatigue',
      'back_pain':         'Back Pain',
      'nausea':            'Nausea',
      'diarrhea':          'Diarrhea',
      'constipation':      'Constipation',
      'food_cravings':     'Cravings',
      'insomnia':          'Insomnia',
      'hot_flashes':       'Hot Flashes',
      'mood_swings':       'Mood Swings',
      'anxiety':           'Anxiety',
      'depression':        'Depression',
    };

    final maxVal = top.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── Summary banner ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bar_chart_rounded, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_symptoms.length} symptoms logged',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
              Text('${freqMap.length} unique types tracked',
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
            ])),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Frequency bar chart ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Most Frequent Symptoms',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, fontSize: 14,
                    color: const Color(0xFF1A1A2E))),
            Text('Based on all logged data',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),

            LayoutBuilder(builder: (_, bc) => SizedBox(
              height: 220,
              width: bc.maxWidth,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal + 1,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, gi, rod, ri) {
                        final name = symptomLabels[top[gi].key] ?? top[gi].key;
                        return BarTooltipItem(
                          '${name.replaceAll("\\n", " ")}\n${rod.toY.round()}×',
                          GoogleFonts.inter(color: Colors.white, fontSize: 11,
                              fontWeight: FontWeight.w600),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, _) => Text(
                          v.round().toString(),
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.grey),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        getTitlesWidget: (v, meta) {
                          final idx = v.round();
                          if (idx < 0 || idx >= top.length) return const SizedBox();
                          final label = symptomLabels[top[idx].key] ?? top[idx].key;
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            space: 4,
                            angle: -0.785,
                            child: Text(
                              label,
                              style: GoogleFonts.inter(
                                  fontSize: 10, color: const Color(0xFF374151)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.grey.withValues(alpha: 0.1), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: top.asMap().entries.map((entry) {
                    final color = const [
                      Color(0xFF7C3AED), Color(0xFFDB2777), Color(0xFF3B82F6),
                      Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444),
                      Color(0xFF8B5CF6), Color(0xFF06B6D4),
                    ][entry.key % 8];
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.value.toDouble(),
                          color: color,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            )
            ),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Phase breakdown ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Symptoms by Cycle Phase',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, fontSize: 14,
                    color: const Color(0xFF1A1A2E))),
            Text('Which phase causes most symptoms',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),
            ...phaseCount.entries.map((phaseEntry) {
              final phase = phaseEntry.key;
              final symptoms = phaseEntry.value;
              final total = symptoms.values.fold(0, (a, b) => a + b);
              final color = phaseColors[phase] ?? AppTheme.primaryPurple;
              final phaseName =
                  '${phase[0].toUpperCase()}${phase.substring(1)}';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(phaseName,
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: const Color(0xFF374151))),
                    const Spacer(),
                    Text('$total occurrences',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxVal > 0 ? (total / (maxVal * 2)).clamp(0.0, 1.0) : 0,
                      backgroundColor: Colors.grey.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 8,
                    ),
                  ),
                  if (symptoms.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: (symptoms.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value)))
                          .take(3)
                          .map((e) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${symptomLabels[e.key] ?? e.key} (${e.value}×)',
                              style: GoogleFonts.inter(
                                  fontSize: 10, color: color,
                                  fontWeight: FontWeight.w500),
                            ),
                          ))
                          .toList(),
                    ),
                  ],
                ]),
              );
            }),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Average severity per symptom ────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Average Severity',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, fontSize: 14,
                    color: const Color(0xFF1A1A2E))),
            Text('How intense each symptom typically is (1–10)',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 14),
            ...top.map((entry) {
              final avgSev = severityMap[entry.key]!.reduce((a, b) => a + b) /
                  severityMap[entry.key]!.length;
              final sevColor = avgSev >= 7
                  ? const Color(0xFFEF4444)
                  : avgSev >= 4
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF10B981);
              final label = symptomLabels[entry.key] ?? entry.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      label.replaceAll('\n', ' '),
                      style: GoogleFonts.inter(
                          fontSize: 11, color: const Color(0xFF374151)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: avgSev / 10,
                        backgroundColor: Colors.grey.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(sevColor),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${avgSev.toStringAsFixed(1)}/10',
                      style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: sevColor)),
                ]),
              );
            }),
          ]),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ── Tab 5: Mood Heatmap ───────────────────────────────────────────────────
  Widget _buildHeatmapTab() {
    if (_loadingExtras) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_moodHeatmap.isEmpty)
          const _EmptyState(
            icon: Icons.grid_view_rounded,
            message: 'Write journal entries to see your 90-day mood heatmap here',
          )
        else
          MoodHeatmapGrid(entries: _moodHeatmap),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Tab 6: Sleep × Mood Correlations ─────────────────────────────────────
  Widget _buildCorrelationsTab() {
    if (_loadingExtras) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SleepMoodScatter(
          sleepLogs : _sleepLogs,
          moodScores: _moodScoreMap,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, color: AppTheme.textTertiary, size: 32),
        const SizedBox(width: 16),
        Expanded(
          child: Text(message,
              style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        ),
      ]),
    );
  }
}

class _PhaseBanner extends StatelessWidget {
  final String phase;
  final int cycleDay;
  final int daysUntilPeriod;
  final double confidenceScore;
  final String predictionMethod;

  const _PhaseBanner({
    required this.phase,
    required this.cycleDay,
    required this.daysUntilPeriod,
    required this.confidenceScore,
    required this.predictionMethod,
  });

  String get _phaseDescription {
    switch (phase) {
      case 'menstrual':
        return 'Your body is shedding the uterine lining. Prioritise rest and iron-rich foods.';
      case 'follicular':
        return 'Rising oestrogen boosts energy and cognitive performance. Great for new projects.';
      case 'ovulation':
        return 'Peak oestrogen and testosterone. You\'re at your most energised and confident.';
      case 'luteal':
        return 'Progesterone rises, shifting you toward introspection. Support your body with magnesium.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryPurple, AppTheme.secondaryPurple],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Current Phase',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(phase.toUpperCase(),
                style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ]),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Day $cycleDay',
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text('$daysUntilPeriod days to period',
                style: GoogleFonts.inter(
                    fontSize: 11, color: Colors.white70)),
          ]),
        ]),
        const SizedBox(height: 10),
        Text(_phaseDescription,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            ['xgboost_only', 'xgboost_dominant', 'xgboost_kalman_mix', 'kalman_dominant', 'random_forest'].contains(predictionMethod)
                ? 'XGBoost + Kalman · ${(confidenceScore * 100).round()}% confidence'
                : 'Statistical baseline · ${(confidenceScore * 100).round()}% confidence',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

class _PlaceholderBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Log a cycle to see your personalised phase banner',
        style: GoogleFonts.inter(color: AppTheme.textSecondary),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final LocalSuggestionData suggestion;

  const _SuggestionCard({required this.suggestion});

  IconData _icon() {
    switch (suggestion.category) {
      case 'diet':       return Icons.restaurant_menu;
      case 'exercise':   return Icons.fitness_center;
      case 'meditation': return Icons.self_improvement;
      case 'sleep':      return Icons.nightlight_round;
      case 'social':     return Icons.people_outline;
      case 'productivity': return Icons.lightbulb_outline;
      default:           return Icons.star_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: suggestion.isAI
                ? Colors.green.withValues(alpha: 0.1)
                : AppTheme.lightPurple,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_icon(),
              color: suggestion.isAI
                  ? Colors.green
                  : AppTheme.primaryPurple,
              size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(suggestion.category.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: suggestion.isAI
                          ? Colors.green
                          : AppTheme.primaryPurple,
                      letterSpacing: 0.5)),
              if (suggestion.isAI) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('AI',
                      style: GoogleFonts.inter(
                          fontSize: 9,
                          color: Colors.green,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            Text(suggestion.title,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(suggestion.description,
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppTheme.textSecondary)),
            if (suggestion.reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Why: ${suggestion.reason}',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                      fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _RiskCard extends StatelessWidget {
  final LocalHealthRisk risk;

  const _RiskCard({required this.risk});

  Color get _color {
    if (risk.score < 0.2) return AppTheme.successGreen;
    if (risk.score < 0.5) return AppTheme.warningOrange;
    return AppTheme.errorRed;
  }

  String get _label {
    if (risk.score < 0.2) return 'Low';
    if (risk.score < 0.5) return 'Moderate';
    return 'High';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(risk.name,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_label,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _color)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: risk.score,
            backgroundColor: Colors.grey[200],
            color: _color,
            minHeight: 6,
          ),
        ),
        if (risk.recommendations.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...risk.recommendations.take(2).map((r) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  const Icon(Icons.arrow_right, size: 14, color: AppTheme.textSecondary),
                  Expanded(
                    child: Text(r,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  ),
                ]),
              )),
        ],
      ]),
    );
  }
}

// ── _HealthRiskCard (new alias for _RiskCard using new type) ─────────────────

class _HealthRiskCard extends StatelessWidget {
  final LocalHealthRisk risk;

  const _HealthRiskCard({required this.risk});

  @override
  Widget build(BuildContext context) {
    return _RiskCard(risk: risk);
  }
}

// ── _ChatMemoryCard ──────────────────────────────────────────────────────────

class _ChatMemoryCard extends StatelessWidget {
  final LocalChatMemorySummary memory;
  const _ChatMemoryCard({required this.memory});

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFF1A1A2E);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryPurple.withValues(alpha: 0.12),
            AppTheme.accentPink.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.psychology_rounded,
                  color: AppTheme.primaryPurple, size: 18),
            ),
            const SizedBox(width: 10),
            Text('What EVA knows about you',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary)),
          ]),
          const SizedBox(height: 12),
          ...memory.summaries.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.favorite_rounded, size: 12, color: AppTheme.primaryPurple),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(s,
                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF374151), height: 1.4))),
            ]),
          )),
        ]),
      ),
    );
  }
}

// ── _TaskIcon ─────────────────────────────────────────────────────────────────
// Maps backend emoji string / task text keywords → a reliable Material IconData.

class _TaskIcon extends StatelessWidget {
  final String taskText;
  final String iconStr;

  const _TaskIcon({required this.taskText, required this.iconStr});

  static IconData _resolve(String task, String icon) {
    final t = task.toLowerCase();
    // Keyword-based matching so we're not relying on emoji rendering
    if (t.contains('sleep') || t.contains('rest') || t.contains('nap')) {
      return Icons.bedtime_rounded;
    }
    if (t.contains('caffeine') || t.contains('alcohol') || t.contains('drink')) {
      return Icons.no_drinks_outlined;
    }
    if (t.contains('meal') || t.contains('eat') || t.contains('food') ||
        t.contains('diet') || t.contains('appetite') || t.contains('crav')) {
      return Icons.restaurant_outlined;
    }
    if (t.contains('walk') || t.contains('swim') || t.contains('exercise') ||
        t.contains('hiit') || t.contains('workout') || t.contains('yoga')) {
      return Icons.directions_walk_rounded;
    }
    if (t.contains('meditat') || t.contains('breath') || t.contains('calm') ||
        t.contains('mindful')) {
      return Icons.self_improvement_rounded;
    }
    if (t.contains('social') || t.contains('alone') || t.contains('solo') ||
        t.contains('people') || t.contains('boundary') || t.contains('boundaries')) {
      return Icons.people_outline_rounded;
    }
    if (t.contains('work') || t.contains('commit') || t.contains('decision') ||
        t.contains('stress') || t.contains('focus')) {
      return Icons.work_outline_rounded;
    }
    if (t.contains('water') || t.contains('hydrat')) {
      return Icons.water_drop_outlined;
    }
    if (t.contains('vitamin') || t.contains('supplement') || t.contains('iron') ||
        t.contains('magnesium') || t.contains('omega')) {
      return Icons.medication_outlined;
    }
    if (t.contains('journal') || t.contains('write') || t.contains('track')) {
      return Icons.edit_note_rounded;
    }
    if (t.contains('avoid') || t.contains('limit') || t.contains('reduce') ||
        t.contains('pms') || t.contains('late luteal')) {
      return Icons.do_not_disturb_on_outlined;
    }
    if (t.contains('prioritis') || t.contains('prioritize')) {
      return Icons.star_outline_rounded;
    }
    if (t.contains('pain') || t.contains('cramp') || t.contains('heat')) {
      return Icons.local_hospital_outlined;
    }
    if (t.contains('creative') || t.contains('project') || t.contains('new idea')) {
      return Icons.lightbulb_outline_rounded;
    }
    if (t.contains('stretch') || t.contains('gentle')) {
      return Icons.accessibility_new_rounded;
    }
    return Icons.task_alt_rounded; // default
  }

  @override
  Widget build(BuildContext context) {
    final iconData = _resolve(taskText, iconStr);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primaryPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, size: 18, color: AppTheme.primaryPurple),
    );
  }
}
