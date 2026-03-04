import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/dashboard_provider.dart';
import '../../../../core/local/local_database_service.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/services/llm_service.dart';
import '../../../../core/widgets/eva_charts.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<LocalAnomalyAlert> _anomalies = [];
  String? _phaseTip;
  bool _tipLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ensure we have a valid auth token before loading the dashboard.
      // This handles the case where the backend was slow to start at app launch.
      await context.read<AuthProvider>().ensureToken();
      if (mounted) {
        context.read<DashboardProvider>().loadDashboard().then((_) => _loadPhaseTip());
        _loadAnomalies();
      }
    });
  }

  Future<void> _loadPhaseTip({bool forceRefresh = false}) async {
    if (!mounted) return;
    final dashboard = context.read<DashboardProvider>().dashboard;
    if (dashboard == null) return;

    // ── FIX #6: Cache daily tip so it doesn't regenerate on every rebuild ──
    final today     = DateTime.now();
    final cacheKey  = "phase_tip_${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}_${dashboard.currentPhase}";
    final prefs     = await SharedPreferences.getInstance();
    final cached    = prefs.getString(cacheKey);

    // Return cached tip unless force-refreshed via the ↻ button
    if (!forceRefresh && cached != null && cached.isNotEmpty) {
      if (mounted) setState(() => _phaseTip = cached);
      return;
    }

    const tips = {
      'menstrual':  'Rest is productive today. Your body is doing important work — honour it with warmth and gentle movement.',
      'follicular': 'Your energy is rising. Great day to start something new, exercise harder, or have a big conversation.',
      'ovulation':  "You're at peak energy and communication. Lean into social plans, creative work, and collaboration.",
      'luteal':     'Wind down gradually. Magnesium-rich foods like dark chocolate and nuts can ease tension today.',
    };

    final llm = getIt<LlmService>();
    if (!llm.isReady) {
      final tip = tips[dashboard.currentPhase] ?? tips['follicular']!;
      await prefs.setString(cacheKey, tip);
      if (mounted) setState(() => _phaseTip = tip);
      return;
    }
    if (mounted) setState(() => _tipLoading = true);
    try {
      final tip = await llm.generate(
        LlmService.buildDailyInsightPrompt(
          cyclePhase: dashboard.currentPhase,
          cycleDay: dashboard.currentCycleDay,
          avgSleepHours: 7.0,
          avgStress: 5.0,
          username: '',
        ),
        maxTokens: 60,
        temperature: 0.8,
      );
      final trimmed = tip.trim();
      if (trimmed.isNotEmpty) {
        await prefs.setString(cacheKey, trimmed);
        if (mounted) setState(() => _phaseTip = trimmed);
      } else {
        final fallback = tips[dashboard.currentPhase] ?? tips['follicular']!;
        await prefs.setString(cacheKey, fallback);
        if (mounted) setState(() => _phaseTip = fallback);
      }
    } catch (_) {
      final fallback = tips[dashboard.currentPhase] ?? tips['follicular']!;
      if (mounted) setState(() => _phaseTip = fallback);
    }
    if (mounted) setState(() => _tipLoading = false);
  }

  Future<void> _loadAnomalies() async {
    try {
      final alerts = await getIt<LocalDatabaseService>().getCycleAnomalies();
      if (mounted) setState(() => _anomalies = alerts);
    } catch (_) {}
  }

  Color _phaseColor(String phase) {
    switch (phase) {
      case 'menstrual':  return AppTheme.menstrualRed;
      case 'follicular': return AppTheme.follicularGreen;
      case 'ovulation':  return AppTheme.ovulationOrange;
      case 'luteal':     return AppTheme.lutealPurple;
      default:           return AppTheme.primaryPurple;
    }
  }

  // ignore: unused_element
  IconData _phaseIcon(String phase) {
    switch (phase) {
      case 'menstrual':  return Icons.water_drop_rounded;
      case 'follicular': return Icons.eco_rounded;
      case 'ovulation':  return Icons.wb_sunny_rounded;
      case 'luteal':     return Icons.nightlight_round;
      default:           return Icons.circle;
    }
  }

  IconData _phaseIcon2(String phase) {
    switch (phase) {
      case 'menstrual':  return Icons.water_drop_rounded;
      case 'follicular': return Icons.eco_rounded;
      case 'ovulation':  return Icons.wb_sunny_rounded;
      case 'luteal':     return Icons.nightlight_round;
      default:           return Icons.favorite_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final d = provider.dashboard;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F0FF),
          floatingActionButton: d != null && d.hasData
              ? FloatingActionButton.extended(
                  onPressed: () => _showQuickLogSheet(context, d.currentPhase),
                  backgroundColor: AppTheme.primaryPurple,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: Text('Quick Log',
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                )
              : null,
          body: CustomScrollView(
            slivers: [
              // ── Beautiful header ─────────────────────────────────────────
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                backgroundColor: const Color(0xFF7C3AED),
                elevation: 0,
                actions: [
                  // Calendar button — moved here from nav bar
                  IconButton(
                    icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
                    tooltip: 'Calendar',
                    onPressed: () => context.go('/calendar'),
                  ),
                  if (provider.isRefreshing)
                    const Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: Center(child: SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      onPressed: () async {
                        await context.read<AuthProvider>().ensureToken();
                        if (context.mounted) {
                          context.read<DashboardProvider>().loadDashboard();
                        }
                      },
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  // NO title here — title is set on SliverAppBar directly above
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF7C3AED), Color(0xFF9333EA), Color(0xFFEC4899)],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 72, 0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          Text('EVA',
                              style: GoogleFonts.inter(
                                  color: Colors.white, fontWeight: FontWeight.w800,
                                  fontSize: 30, letterSpacing: -0.5)),
                          Text('Your Wellness Assistant',
                              style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Body ────────────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                sliver: Builder(builder: (context) {
                  if (provider.isLoading) {
                    return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (provider.error != null && d == null) {
                    return SliverFillRemaining(
                      child: _ErrorState(
                          error: provider.error!,
                          onRetry: () async {
                            // Re-authenticate first (handles "Not authenticated" errors
                            // caused by backend being slow to start at app launch)
                            await context.read<AuthProvider>().ensureToken();
                            if (context.mounted) {
                              context.read<DashboardProvider>().loadDashboard();
                            }
                          }),
                    );
                  }
                  if (d == null || !d.hasData) {
                    return SliverFillRemaining(
                      child: _NoDataState(
                          message: d?.message ??
                              'Log your first cycle to unlock AI predictions!'),
                    );
                  }

                  final phaseColor = _phaseColor(d.currentPhase);
                  final phaseIcon2 = _phaseIcon2(d.currentPhase);

                  return SliverList(
                    delegate: SliverChildListDelegate([
                      // Anomaly alerts (if any)
                      if (_anomalies.isNotEmpty) ...[
                        ..._anomalies.map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AnomalyCard(alert: a),
                        )),
                      ],
                      _buildPhaseHero(context, d, phaseColor, phaseIcon2),
                      const SizedBox(height: 16),
                      // ── Chart 2: Cycle Phase Donut ──────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: CyclePhaseDonut(
                          cycleDay    : d.currentCycleDay,
                          cycleLength : d.cycleLengthPrediction ?? 28,
                          currentPhase: d.currentPhase,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildHealthRow(context, d),
                      const SizedBox(height: 16),
                      // ── Chart 5: Health Radar ───────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: HealthRadarChart(
                          sleepScore      : ((d.avgSleepFromDash ?? 7.0) / 9.0).clamp(0.0, 1.0),
                          moodScore       : (d.lastJournalSentiment * 0.5 + 0.5).clamp(0.0, 1.0),
                          cycleRegularity : d.confidenceScore.clamp(0.0, 1.0),
                          stressScore     : (1.0 - ((d.avgStressFromDash ?? 5.0) / 10.0)).clamp(0.0, 1.0),
                          activityScore   : 0.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildWeeklyMoodChart(context),
                      const SizedBox(height: 16),
                      _buildInsightCard(context, d),
                      const SizedBox(height: 16),
                      _buildDailyTipCard(context, d),
                      const SizedBox(height: 16),
                      _buildQuickActions(context),
                      const SizedBox(height: 16),
                      _buildModelBadge(d),
                      const SizedBox(height: 80), // space for FAB
                    ]),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Anomaly + weekly chart helpers ─────────────────────────────────────────
  Widget _buildWeeklyMoodChart(BuildContext context) {
    // Placeholder — in production this would read from moods endpoint

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.infoBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.show_chart_rounded, color: AppTheme.infoBlue, size: 18),
          ),
          const SizedBox(width: 12),
          Text('Weekly Mood & Energy',
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E))),
        ]),
        const SizedBox(height: 4),
        Text('Log mood daily to see your trend chart here',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9CA3AF))),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => context.go('/insights'),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text('View emotion timeline',
                style: GoogleFonts.inter(
                    color: AppTheme.primaryPurple,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
                overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_rounded,
                color: AppTheme.primaryPurple, size: 14),
          ]),
        ),
      ]),
    );
  }

  void _showQuickLogSheet(BuildContext context, String phase) {
    final provider = context.read<DashboardProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickLogSheet(
        phase: phase,
        onSaved: () {
          provider.invalidateCache();
          provider.loadDashboard();
        },
      ),
    );
  }

  // ── Phase hero card ─────────────────────────────────────────────────────────
  Widget _buildPhaseHero(BuildContext context, LocalDashboardData d, Color color, IconData phaseIcon2) {

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(phaseIcon2, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${d.currentPhase.substring(0, 1).toUpperCase()}${d.currentPhase.substring(1)} Phase',
                  style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E)),
                ),
                Text('Day ${d.currentCycleDay} of cycle',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: const Color(0xFF6B7280))),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${(d.confidenceScore * 100).round()}%',
                style: GoogleFonts.inter(
                    fontSize: 12, color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ]),

          const SizedBox(height: 16),
          Container(
            height: 1,
            color: color.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),

          // Stats row — scrollable so pills never clip on small screens
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _StatPill(
                icon: Icons.calendar_today_rounded,
                label: 'Period in',
                value: '${d.daysUntilPeriod}d',
                color: color,
              ),
              const SizedBox(width: 10),
              if (d.ovulationDate != null)
                _OvulationPills(ovulationDate: d.ovulationDate!),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Health + mood row ───────────────────────────────────────────────────────
  Widget _buildHealthRow(BuildContext context, LocalDashboardData d) {
    final score = (d.healthScore * 100).round();
    final scoreColor = score > 70
        ? AppTheme.successGreen
        : score > 40
            ? AppTheme.warningOrange
            : AppTheme.errorRed;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Health score
      Expanded(
        child: _Card(
          child: Column(children: [
            Row(children: [
              Icon(Icons.favorite_rounded, color: scoreColor, size: 18),
              const SizedBox(width: 8),
              Text('Daily Wellness',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: const Color(0xFF374151))),
            ]),
            const SizedBox(height: 16),
            Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: d.healthScore,
                  strokeWidth: 8,
                  backgroundColor: const Color(0xFFF3F4F6),
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$score',
                    style: GoogleFonts.inter(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        color: scoreColor)),
                Text('/100',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: const Color(0xFF9CA3AF))),
              ]),
            ]),
            const SizedBox(height: 10),
            Text('Sleep · Stress · Journal',
                style: GoogleFonts.inter(
                    fontSize: 10, color: const Color(0xFF9CA3AF)),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
      const SizedBox(width: 12),

      // Today's mood & journal sentiment
      Expanded(
        child: _Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.sentiment_satisfied_alt_rounded,
                  color: AppTheme.warningOrange, size: 18),
              const SizedBox(width: 8),
              Text('Today',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: const Color(0xFF374151))),
            ]),
            const SizedBox(height: 12),
            // Mood (from log or inferred from journal)
            if (d.moodToday != null) ...[
              _MoodChip(mood: d.moodToday!),
              const SizedBox(height: 8),
            ],
            // Journal sentiment indicator
            if (d.lastJournalSentiment != 0.0) ...[
              _JournalSentimentRow(sentiment: d.lastJournalSentiment),
              const SizedBox(height: 6),
            ],
            if (d.moodToday == null && d.lastJournalSentiment == 0.0)
              Text('Write a journal entry or log your mood',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: const Color(0xFFD1D5DB))),
            if (d.symptomsToday.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 4,
                children: d.symptomsToday.take(3).map<Widget>((s) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(s,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: const Color(0xFF6B7280))),
                )).toList(),
              ),
            ],
          ]),
        ),
      ),
    ]);
  }

  // ── AI Insight card ─────────────────────────────────────────────────────────
  // ── Daily phase tip card ──────────────────────────────────────────────────────
  Widget _buildDailyTipCard(BuildContext context, LocalDashboardData d) {
    final phaseColors = {
      'menstrual':  AppTheme.menstrualRed,
      'follicular': AppTheme.follicularGreen,
      'ovulation':  AppTheme.ovulationOrange,
      'luteal':     AppTheme.lutealPurple,
    };
    final phaseIcons = {
      'menstrual':  Icons.water_drop_rounded,
      'follicular': Icons.eco_rounded,
      'ovulation':  Icons.wb_sunny_rounded,
      'luteal':     Icons.nightlight_round,
    };
    final color = phaseColors[d.currentPhase] ?? AppTheme.primaryPurple;
    final icon  = phaseIcons[d.currentPhase]  ?? Icons.favorite_rounded;
    final phaseName = '${d.currentPhase[0].toUpperCase()}${d.currentPhase.substring(1)}';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Text('$phaseName Phase Tip',
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          const Spacer(),
          GestureDetector(
            onTap: _loadPhaseTip,
            child: Icon(Icons.refresh_rounded, size: 16, color: color.withValues(alpha: 0.6)),
          ),
        ]),
        const SizedBox(height: 10),
        if (_tipLoading)
          Row(children: [
            SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color)),
            const SizedBox(width: 8),
            Text('Generating insight…',
                style: GoogleFonts.inter(fontSize: 13, color: color.withValues(alpha: 0.7))),
          ])
        else if (_phaseTip != null)
          Text(_phaseTip!,
              style: GoogleFonts.inter(
                  fontSize: 14, color: const Color(0xFF374151), height: 1.5))
        else
          Text('Tap ↻ to get a personalised tip for today.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: const Color(0xFF9CA3AF))),
      ]),
    );
  }

  Widget _buildInsightCard(BuildContext context, LocalDashboardData d) {
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.warningOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lightbulb_rounded,
                color: AppTheme.warningOrange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(d.aiInsightTitle,
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E))),
          ),
          if (d.ollamaAvailable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('On-Device AI',
                  style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: AppTheme.primaryPurple)),
            ),
        ]),
        const SizedBox(height: 12),
        Text(d.aiInsightMessage,
            style: GoogleFonts.inter(
                fontSize: 14, color: const Color(0xFF6B7280), height: 1.6)),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => context.go('/insights'),
          child: Row(children: [
            Text('View all insights',
                style: GoogleFonts.inter(
                    color: AppTheme.primaryPurple,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_rounded,
                color: AppTheme.primaryPurple, size: 14),
          ]),
        ),
      ]),
    );
  }

  // ── Quick actions ───────────────────────────────────────────────────────────
  Widget _buildQuickActions(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(child: _ActionTile(
          icon: Icons.add_circle_outline_rounded,
          label: 'Log Mood',
          color: AppTheme.primaryPurple,
          onTap: () => context.go('/journal'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _ActionTile(
          icon: Icons.calendar_month_rounded,
          label: 'Log Cycle',
          color: AppTheme.menstrualRed,
          onTap: () => context.go('/log-cycle'),
        )),
        const SizedBox(width: 12),
        Expanded(child: _ActionTile(
          icon: Icons.chat_bubble_rounded,
          label: 'Ask EVA',
          color: AppTheme.follicularGreen,
          onTap: () => context.go('/chat'),
        )),
      ]),
      const SizedBox(height: 12),
      _Card(
        onTap: () => context.go('/cycles'),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.history_rounded, color: AppTheme.primaryPurple, size: 20),
          const SizedBox(width: 10),
          Text('View Cycle History',
              style: GoogleFonts.inter(
                  color: AppTheme.primaryPurple,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              color: AppTheme.primaryPurple, size: 18),
        ]),
      ),
    ]);
  }

  Widget _buildModelBadge(LocalDashboardData d) {
    return Builder(builder: (context) {

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(children: [
        const Icon(Icons.psychology_outlined, size: 14, color: Color(0xFF9CA3AF)),
        const SizedBox(width: 8),
        Expanded(child: Text(
          ['xgboost_only', 'xgboost_dominant', 'xgboost_kalman_mix', 'kalman_dominant', 'random_forest'].contains(d.predictionMethod)
              ? 'XGBoost + Kalman active ✓'
              : 'Log more cycles to activate XGBoost + Kalman predictions',
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF)),
        )),
      ]),
    );
    }); // Builder
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Card({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    const cardColor = Colors.white;
    final shadowColor = Colors.black.withValues(alpha: 0.05);
    final inner = Padding(padding: const EdgeInsets.all(16), child: child);
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: null,
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: onTap != null
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: inner,
              ),
            )
          : inner,
    );
  }
}

// ── Ovulation pills: date + countdown ────────────────────────────────────────
class _OvulationPills extends StatelessWidget {
  final String ovulationDate;
  const _OvulationPills({required this.ovulationDate});

  @override
  Widget build(BuildContext context) {
    final ovDate     = DateTime.tryParse(ovulationDate);
    final daysUntil  = ovDate?.difference(DateTime.now()).inDays;
    final dateLabel  = ovDate != null
        ? DateFormat('MMM d').format(ovDate)
        : ovulationDate.substring(5);
    const color = AppTheme.ovulationOrange;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      _StatPill(
        icon: Icons.wb_sunny_rounded,
        label: 'Ovulation',
        value: dateLabel,
        color: color,
      ),
      if (daysUntil != null && daysUntil >= 0) ...[
        const SizedBox(width: 10),
        _StatPill(
          icon: Icons.timer_outlined,
          label: 'In',
          value: '${daysUntil}d',
          color: color,
        ),
      ],
    ]);
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatPill({
    required this.icon, required this.label,
    required this.value, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 10, color: color.withValues(alpha: 0.7)),
              overflow: TextOverflow.ellipsis),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color),
              overflow: TextOverflow.ellipsis),
        ]),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const cardColor = Colors.white;
    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8, offset: const Offset(0, 2),
              ),
            ],
            color: cardColor,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: const Color(0xFF374151))),
          ]),
        ),
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  final String mood;
  const _MoodChip({required this.mood});

  static const _colors = {
    'happy'   : Color(0xFFFBBF24), 'calm'    : Color(0xFF34D399),
    'neutral' : Color(0xFF94A3B8), 'tired'   : Color(0xFF818CF8),
    'anxious' : Color(0xFFF59E0B), 'irritable': Color(0xFFF97316),
    'sad'     : Color(0xFF60A5FA), 'stressed': Color(0xFFEF4444),
    'energetic': Color(0xFF10B981), 'depressed': Color(0xFF6366F1),
  };

  static const _icons = <String, IconData>{
    'happy':    Icons.sentiment_very_satisfied,
    'calm':     Icons.sentiment_satisfied,
    'neutral':  Icons.sentiment_neutral,
    'tired':    Icons.bedtime_outlined,
    'anxious':  Icons.sentiment_dissatisfied,
    'irritable':Icons.sentiment_very_dissatisfied,
    'sad':      Icons.sentiment_dissatisfied,
    'stressed': Icons.sentiment_dissatisfied,
    'energetic':Icons.bolt_rounded,
    'depressed':Icons.sentiment_very_dissatisfied,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[mood] ?? const Color(0xFF94A3B8);
    final icon  = _icons[mood]  ?? Icons.sentiment_neutral;
    final label = mood.substring(0, 1).toUpperCase() + mood.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _JournalSentimentRow extends StatelessWidget {
  final double sentiment;
  const _JournalSentimentRow({required this.sentiment});

  @override
  Widget build(BuildContext context) {
    final isPos = sentiment > 0.1;
    final isNeg = sentiment < -0.1;
    final label = isPos ? 'Journal: positive' : isNeg ? 'Journal: negative' : 'Journal: neutral';
    final color = isPos ? const Color(0xFF22C55E) : isNeg ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final icon  = isPos ? Icons.menu_book_rounded : isNeg ? Icons.menu_book_rounded : Icons.menu_book_outlined;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Text(label,
          style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    ]);
  }
}

class _ErrorState extends StatefulWidget {
  final String error;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  State<_ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<_ErrorState> {
  bool _retrying = false;

  bool get _isConnectionError =>
      widget.error.toLowerCase().contains('fetch') ||
      widget.error.toLowerCase().contains('connection') ||
      widget.error.toLowerCase().contains('socket') ||
      widget.error.toLowerCase().contains('not authenticated') ||
      widget.error.toLowerCase().contains('backend not running');

  @override
  Widget build(BuildContext context) {

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.errorRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppTheme.errorRed),
          ),
          const SizedBox(height: 20),
          Text('Could not load dashboard',
              style: GoogleFonts.inter(
                  fontSize: 17, fontWeight: FontWeight.w700,
                  color: AppTheme.errorRed)),
          const SizedBox(height: 12),
          if (_isConnectionError) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.terminal_rounded, size: 14, color: AppTheme.primaryPurple),
                  const SizedBox(width: 8),
                  Text('Start the backend server:',
                      style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: const Color(0xFF374151))),
                ]),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('cd backend && uvicorn main:app --reload',
                      style: GoogleFonts.sourceCodePro(
                          fontSize: 11, color: const Color(0xFF34D399))),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Backend URL: http://localhost:8000',
                style: GoogleFonts.inter(
                    fontSize: 11, color: const Color(0xFF9CA3AF))),
          ] else
            Text(widget.error,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFF6B7280))),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _retrying ? null : () async {
              setState(() => _retrying = true);
              await widget.onRetry();
              if (mounted) setState(() => _retrying = false);
            },
            icon: _retrying
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(_retrying ? 'Connecting...' : 'Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          Text('Journal and Chat still work while offline',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF9CA3AF))),
        ]),
      ),
    );
  }
}

class _NoDataState extends StatelessWidget {
  final String message;

  const _NoDataState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.calendar_month_rounded,
                size: 48, color: AppTheme.primaryPurple),
          ),
          const SizedBox(height: 20),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Log First Cycle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => context.go('/log-cycle'),
          ),
        ]),
      ),
    );
  }
}

// ── Anomaly Alert Card ────────────────────────────────────────────────────────

class _AnomalyCard extends StatelessWidget {
  final LocalAnomalyAlert alert;

  const _AnomalyCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isHigh = alert.severity == 'high';
    final color = isHigh ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(alert.title,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          const SizedBox(height: 4),
          Text(alert.message,
              style: GoogleFonts.inter(
                  fontSize: 12, color: const Color(0xFF374151), height: 1.5)),
        ])),
      ]),
    );
  }
}

// ── Quick Log Bottom Sheet ────────────────────────────────────────────────────

class _QuickLogSheet extends StatefulWidget {
  final String phase;
  final VoidCallback? onSaved;

  const _QuickLogSheet({required this.phase, this.onSaved});

  @override
  State<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<_QuickLogSheet> {
  String? _flowIntensity;
  final Set<String> _symptoms = {};
  // Per-symptom severity (1–10). Defaults to 5 until the user moves the slider.
  final Map<String, int> _severity = {};
  bool _saving = false;

  static const _flows = ['light', 'medium', 'heavy'];
  static const _symptomOptions = [
    ('cramps',      Icons.waves_rounded),
    ('bloating',    Icons.air_rounded),
    ('headache',    Icons.psychology_outlined),
    ('fatigue',     Icons.bedtime_outlined),
    ('mood_swings', Icons.swap_horiz_rounded),
    ('nausea',      Icons.sick_outlined),
    ('back_pain',   Icons.accessibility_new_rounded),
    ('anxiety',     Icons.sentiment_dissatisfied),
  ];

  String _buildJournalText() {
    final parts = <String>[];

    if (_flowIntensity != null) {
      final flowLabel = {'light': 'light', 'medium': 'moderate', 'heavy': 'heavy'}[_flowIntensity]!;
      parts.add('I had $flowLabel flow today.');
    }

    if (_symptoms.isNotEmpty) {
      final labels = _symptoms.map((s) {
        final sev = _severity[s] ?? 5;
        final sevWord = sev >= 7 ? 'severe' : sev >= 4 ? 'moderate' : 'mild';
        return '$sevWord ${s.replaceAll('_', ' ')}';
      }).toList();
      if (labels.length == 1) {
        parts.add('I experienced ${labels.first}.');
      } else {
        final last = labels.removeLast();
        parts.add('I experienced ${labels.join(', ')} and $last.');
      }
    }

    // Add phase-aware context so sentiment analysis has more signal
    if (parts.isNotEmpty) {
      parts.add('This was logged via Quick Log during my ${widget.phase} phase.');
    }

    return parts.join(' ');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final localDb = getIt<LocalDatabaseService>();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. Save flow intensity to the active cycle
      if (_flowIntensity != null) {
        try {
          await localDb.updateCycleFlow(_flowIntensity!);
        } catch (_) {}
      }

      // 2. Save each symptom with its individual severity rating
      for (final sym in _symptoms) {
        try {
          await localDb.logSymptom(
            date       : today,
            symptomType: sym,
            severity   : _severity[sym] ?? 5,
          );
        } catch (_) {}
      }

      // 3. Create a journal entry from the quick log so:
      //    - It appears in the Journal tab history
      //    - The Today card shows accurate sentiment (not stale data)
      //    - Dashboard health score incorporates today's real feelings
      final journalText = _buildJournalText();
      if (journalText.isNotEmpty) {
        try {
          await localDb.analyzeJournalEntry(journalText, today);
        } catch (_) {}
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [

              Text('Logged successfully!',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ]),
            backgroundColor: AppTheme.primaryPurple,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {

    const sheetColor = Colors.white;

    return Container(
      decoration: const BoxDecoration(
        color: sheetColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),

        Text('Quick Log',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w800, fontSize: 20,
                color: const Color(0xFF1A1A2E))),
        Text('Log flow & symptoms in seconds',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9CA3AF))),

        const SizedBox(height: 20),

        // Flow intensity
        Align(alignment: Alignment.centerLeft, child: Text('Flow intensity',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13,
                color: const Color(0xFF374151)))),
        const SizedBox(height: 8),
        Row(children: _flows.map((f) {
          final selected = _flowIntensity == f;
          final colors = {'light': Colors.pink.shade200, 'medium': Colors.red.shade400, 'heavy': Colors.red.shade700};
          final c = colors[f]!;
          return Expanded(child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _flowIntensity = selected ? null : f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? c : c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? c : c.withValues(alpha: 0.3)),
                ),
                child: Center(child: Text(
                  f[0].toUpperCase() + f.substring(1),
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : c),
                )),
              ),
            ),
          ));
        }).toList()),

        const SizedBox(height: 16),

        // Symptoms
        Align(alignment: Alignment.centerLeft, child: Text('Top symptoms (pick up to 3)',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13,
                color: const Color(0xFF374151)))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: _symptomOptions.map((opt) {
          final key      = opt.$1;
          final iconData = opt.$2;
          final label    = key.replaceAll('_', ' ');
          final selected = _symptoms.contains(key);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _symptoms.remove(key);
                  _severity.remove(key);
                } else if (_symptoms.length < 3) {
                  _symptoms.add(key);
                  _severity[key] = 5; // default mid severity
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primaryPurple
                    : AppTheme.primaryPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected
                        ? AppTheme.primaryPurple
                        : AppTheme.primaryPurple.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(iconData, size: 14,
                    color: selected ? Colors.white : AppTheme.primaryPurple),
                const SizedBox(width: 5),
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : AppTheme.primaryPurple)),
              ]),
            ),
          );
        }).toList()),

        // ── Per-symptom severity sliders (shown only when symptoms selected) ─
        if (_symptoms.isNotEmpty) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Rate severity (1 = mild  ·  10 = severe)',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 13,
                    color: const Color(0xFF374151))),
          ),
          const SizedBox(height: 4),
          ..._symptoms.map((sym) {
            final label = sym.replaceAll('_', ' ');
            final sev   = _severity[sym] ?? 5;
            final sevColor = sev >= 7
                ? const Color(0xFFEF4444)
                : sev >= 4
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      label[0].toUpperCase() + label.substring(1),
                      style: GoogleFonts.inter(
                          fontSize: 12, color: const Color(0xFF374151)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: sevColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$sev / 10',
                        style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: sevColor),
                      ),
                    ),
                  ]),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor  : sevColor,
                      inactiveTrackColor: sevColor.withValues(alpha: 0.15),
                      thumbColor        : sevColor,
                      overlayColor      : sevColor.withValues(alpha: 0.15),
                      trackHeight       : 4,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: sev.toDouble(),
                      min: 1, max: 10, divisions: 9,
                      onChanged: (v) => setState(
                          () => _severity[sym] = v.round()),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_flowIntensity == null && _symptoms.isEmpty) || _saving
                ? null
                : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPurple,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Log It',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
          ),
        ),
      ]),
      ),
    );
  }
}
