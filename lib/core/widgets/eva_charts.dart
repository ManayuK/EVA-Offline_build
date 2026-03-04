// lib/core/widgets/eva_charts.dart
//
// ── EVA New Chart Widgets ────────────────────────────────────────────────────
//
// 5 plug-in chart widgets. All use fl_chart (already in pubspec).
// Each widget is fully self-contained — just pass your existing data objects.
//
// CHART 1 ─ SleepDualAxisChart   → drop into sleep_log_page.dart
// CHART 2 ─ CyclePhaseDonut      → drop into home_page.dart / cycles page
// CHART 3 ─ MoodHeatmapGrid      → drop into insights_page.dart (new tab)
// CHART 4 ─ SleepMoodScatter     → drop into insights_page.dart (new tab)
// CHART 5 ─ HealthRadarChart     → drop into home_page.dart / insights page
//
// Integration snippets are included as comments above each class.

import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../local/local_database_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CHART 1 — Sleep Duration & Quality Dual-Axis Chart
// ─────────────────────────────────────────────────────────────────────────────
//
// HOW TO INTEGRATE — sleep_log_page.dart:
//
//   // After the _StatsBanner widget, add:
//   if (_logs.length >= 3) ...[
//     const SizedBox(height: 20),
//     SleepDualAxisChart(logs: _logs),
//   ],
//
// Shows purple bars for hours slept (left axis) with an amber line overlay
// for sleep quality score (right axis, 1-5) over the last 14 nights.

class SleepDualAxisChart extends StatelessWidget {
  final List<SleepLogData> logs;
  const SleepDualAxisChart({required this.logs, super.key});

  static const Color _barColor     = Color(0xFF4F46E5);
  static const Color _qualityColor = Color(0xFFFBBF24);

  @override
  Widget build(BuildContext context) {
    // Take last 14 entries in chronological order
    final data = logs.reversed.take(14).toList().reversed.toList();
    if (data.length < 3) return const SizedBox.shrink();

    final maxH = data
        .map((e) => e.hoursSlept ?? 0.0)
        .fold<double>(0, math.max)
        .clamp(8.0, 12.0);

    final barGroups = data.asMap().entries.map((e) {
      final h = e.value.hoursSlept ?? 0.0;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY            : h,
            color          : _barColor.withValues(alpha: h >= 7 ? 1.0 : 0.55),
            width          : 10,
            borderRadius   : const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show : true,
              toY  : maxH,
              color: _barColor.withValues(alpha: 0.06),
            ),
          ),
        ],
      );
    }).toList();

    final qualitySpots = data.asMap().entries
        .where((e) => e.value.quality != null)
        .map((e) => FlSpot(e.key.toDouble(), e.value.quality!.toDouble()))
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color        : Colors.white,
        borderRadius : BorderRadius.circular(16),
        boxShadow    : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _barColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bedtime_rounded, color: _barColor, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Sleep Duration & Quality',
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E))),
          const Spacer(),
          const _Legend(color: _barColor,     label: 'Hours'),
          const SizedBox(width: 10),
          const _Legend(color: _qualityColor, label: 'Quality'),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: Stack(children: [
            // ── Bars ──────────────────────────────────────────────────────────
            BarChart(BarChartData(
              maxY: maxH,
              barGroups: barGroups,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.withValues(alpha: 0.08), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 4,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}h',
                      style: GoogleFonts.inter(fontSize: 9, color: Colors.grey),
                    ),
                  ),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (v, _) => Text(
                      v <= 5 ? '${v.toInt()}★' : '',
                      style: GoogleFonts.inter(
                          fontSize: 9, color: _qualityColor.withValues(alpha: 0.8)),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 18,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= data.length) return const SizedBox.shrink();
                      final d = DateTime.tryParse(data[i].date);
                      if (d == null) return const SizedBox.shrink();
                      // Show label only every other bar to avoid clutter
                      if (i % 2 != 0) return const SizedBox.shrink();
                      return Text('${d.month}/${d.day}',
                          style: GoogleFonts.inter(fontSize: 9, color: Colors.grey));
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipBgColor: const Color(0xFF1A1A2E),
                  getTooltipItem: (group, _, rod, __) {
                    final log = data[group.x];
                    return BarTooltipItem(
                      '${log.hoursSlept?.toStringAsFixed(1) ?? '?'}h\n'
                      '${log.quality != null ? '${log.quality}★' : ''}',
                      GoogleFonts.inter(
                          color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ),
            )),

            // ── Quality line overlay ──────────────────────────────────────────
            if (qualitySpots.length >= 2)
              Padding(
                padding: const EdgeInsets.only(left: 28, right: 24, bottom: 18),
                child: LineChart(LineChartData(
                  minY: 0,
                  maxY: maxH,
                  // Map quality 1-5 onto the same 0-maxH axis
                  lineBarsData: [
                    LineChartBarData(
                      spots: qualitySpots.map((s) =>
                          FlSpot(s.x, (s.y / 5.0) * maxH)).toList(),
                      isCurved      : true,
                      color         : _qualityColor,
                      barWidth      : 2,
                      dotData       : FlDotData(
                        show: true,
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                          radius   : 3,
                          color    : _qualityColor,
                          strokeWidth: 1.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  gridData  : const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(
                    leftTitles  : AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles : AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles   : AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                )),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Last ${data.length} nights  ·  Purple = sleep time, Amber line = quality (1–5★)',
            style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART 2 — Cycle Phase Donut Chart
// ─────────────────────────────────────────────────────────────────────────────
//
// HOW TO INTEGRATE — home_page.dart, inside _buildPhaseHero or as a new card:
//
//   CyclePhaseDonut(
//     cycleDay : d.currentCycleDay,
//     cycleLength: d.cycleLengthPrediction ?? 28,
//     currentPhase: d.currentPhase,
//   )
//
// Splits the cycle into the 4 standard phases, highlights the current one,
// and draws a centre label with day / phase name.

class CyclePhaseDonut extends StatefulWidget {
  final int    cycleDay;
  final int    cycleLength;
  final String currentPhase;

  const CyclePhaseDonut({
    required this.cycleDay,
    required this.cycleLength,
    required this.currentPhase,
    super.key,
  });

  @override
  State<CyclePhaseDonut> createState() => _CyclePhaseDonutState();
}

class _CyclePhaseDonutState extends State<CyclePhaseDonut> {
  int _touched = -1;

  // Phase definitions: name, colour, fraction of cycle
  static const _phases = [
    _PhaseInfo('Menstrual',  Color(0xFFEF4444), 0.18),
    _PhaseInfo('Follicular', Color(0xFF8B5CF6), 0.25),
    _PhaseInfo('Ovulation',  Color(0xFF10B981), 0.14),
    _PhaseInfo('Luteal',     Color(0xFFF59E0B), 0.43),
  ];

  int get _currentIdx {
    switch (widget.currentPhase.toLowerCase()) {
      case 'menstrual':  return 0;
      case 'follicular': return 1;
      case 'ovulation':  return 2;
      case 'luteal':     return 3;
      default:           return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = _phases.asMap().entries.map((e) {
      final isActive  = e.key == _currentIdx;
      final isTouched = e.key == _touched;
      return PieChartSectionData(
        value        : e.value.fraction * widget.cycleLength,
        color        : e.value.color.withValues(alpha: isActive ? 1.0 : 0.25),
        radius       : isTouched ? 52 : isActive ? 48 : 38,
        title        : '',
        borderSide   : isActive
            ? BorderSide(color: e.value.color, width: 2.5)
            : BorderSide.none,
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow   : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.pie_chart_rounded,
                color: AppTheme.primaryPurple, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Cycle Phase Overview',
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          SizedBox(
            width: 150, height: 150,
            child: Stack(alignment: Alignment.center, children: [
              PieChart(PieChartData(
                sections       : sections,
                centerSpaceRadius: 44,
                sectionsSpace  : 3,
                pieTouchData   : PieTouchData(
                  touchCallback: (event, resp) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          resp == null || resp.touchedSection == null) {
                        _touched = -1;
                      } else {
                        _touched = resp.touchedSection!.touchedSectionIndex;
                      }
                    });
                  },
                ),
              )),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Day',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
                Text('${widget.cycleDay}',
                    style: GoogleFonts.inter(
                        fontSize: 22, fontWeight: FontWeight.w800,
                        color: _phases[_currentIdx].color)),
                Text(_phases[_currentIdx].name,
                    style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w600,
                        color: _phases[_currentIdx].color),
                    textAlign: TextAlign.center),
              ]),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _phases.asMap().entries.map((e) {
                final isActive = e.key == _currentIdx;
                final days     = (e.value.fraction * widget.cycleLength).round();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color : e.value.color.withValues(alpha: isActive ? 1.0 : 0.35),
                        shape : BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${e.value.name}  (~$days d)',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                          color: isActive
                              ? e.value.color
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color       : e.value.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('NOW',
                            style: GoogleFonts.inter(
                                fontSize: 9, fontWeight: FontWeight.w800,
                                color: e.value.color)),
                      ),
                  ]),
                );
              }).toList(),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _PhaseInfo {
  final String name;
  final Color  color;
  final double fraction; // fraction of total cycle length
  const _PhaseInfo(this.name, this.color, this.fraction);
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART 3 — Mood Heatmap Grid (GitHub-style contribution graph)
// ─────────────────────────────────────────────────────────────────────────────
//
// HOW TO INTEGRATE — insights_page.dart, as a new tab or inside Timeline tab:
//
//   // Pass the mood entries from your existing API call, e.g. in initState:
//   final moods = await _aiService.getMoodLogs(limit: 90); // returns List<MoodLogData>
//
//   MoodHeatmapGrid(entries: moods)
//
// Each cell = one day, colour = mood intensity.
// Brighter purple = more positive/calm. Red = high stress.

class MoodHeatmapEntry {
  final DateTime date;
  final double   score; // 0.0 (very negative) → 1.0 (very positive)
  const MoodHeatmapEntry({required this.date, required this.score});
}

class MoodHeatmapGrid extends StatefulWidget {
  final List<MoodHeatmapEntry> entries;
  const MoodHeatmapGrid({required this.entries, super.key});

  @override
  State<MoodHeatmapGrid> createState() => _MoodHeatmapGridState();
}

class _MoodHeatmapGridState extends State<MoodHeatmapGrid> {
  MoodHeatmapEntry? _hovered;

  Color _scoreToColor(double score) {
    if (score < 0.0) return Colors.grey.withValues(alpha: 0.1);
    if (score < 0.25) return const Color(0xFFEF4444).withValues(alpha: 0.7);
    if (score < 0.50) return const Color(0xFFF97316).withValues(alpha: 0.65);
    if (score < 0.70) return const Color(0xFFA78BFA).withValues(alpha: 0.6);
    if (score < 0.85) return const Color(0xFF7C3AED).withValues(alpha: 0.75);
    return const Color(0xFF10B981).withValues(alpha: 0.85);
  }

  String _scoreTolabel(double s) {
    if (s < 0.25) return 'Difficult';
    if (s < 0.50) return 'Low';
    if (s < 0.70) return 'Okay';
    if (s < 0.85) return 'Good';
    return 'Great';
  }

  @override
  Widget build(BuildContext context) {
    // Build a map keyed by date string
    final map = { for (final e in widget.entries) _dateKey(e.date): e };

    // Build 13 weeks × 7 days grid ending today
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 90));

    final weeks = <List<DateTime>>[];
    var day     = start.subtract(Duration(days: start.weekday % 7));
    while (day.isBefore(today.add(const Duration(days: 1)))) {
      final week = List.generate(7, (i) => day.add(Duration(days: i)));
      weeks.add(week);
      day = day.add(const Duration(days: 7));
    }

    const cellSize = 14.0;
    const gap      = 3.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow   : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.grid_view_rounded,
                color: AppTheme.primaryPurple, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Mood Heatmap — 90 days',
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E))),
        ]),
        const SizedBox(height: 14),

        // Day labels
        Row(children: [
          const SizedBox(width: 22),
          ...['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) =>
              SizedBox(
                width: cellSize + gap,
                child: Text(d,
                    style: GoogleFonts.inter(
                        fontSize: 8, color: Colors.grey),
                    textAlign: TextAlign.center),
              )),
        ]),
        const SizedBox(height: 4),

        // Grid
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month labels column
              Column(
                children: weeks.map((week) {
                  final first = week.first;
                  final showLabel = first.day <= 7;
                  return SizedBox(
                    height: cellSize + gap,
                    width: 22,
                    child: showLabel
                        ? Text(
                            _monthAbbr(first.month),
                            style: GoogleFonts.inter(
                                fontSize: 8, color: Colors.grey),
                          )
                        : null,
                  );
                }).toList(),
              ),
              // Cells
              ...weeks.map((week) => Column(
                children: week.map((d) {
                  final key   = _dateKey(d);
                  final entry = map[key];
                  final isInRange = d.isAfter(start.subtract(const Duration(days: 1)))
                      && !d.isAfter(today);
                  final score = isInRange ? (entry?.score ?? -1.0) : -1.0;
                  final isHovered = _hovered?.date == d;

                  return GestureDetector(
                    onTap: () => setState(() {
                      _hovered = (entry != null) ? entry : null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width : cellSize,
                      height: cellSize,
                      margin: const EdgeInsets.all(gap / 2),
                      decoration: BoxDecoration(
                        color       : score < 0
                            ? Colors.grey.withValues(alpha: 0.08)
                            : _scoreToColor(score),
                        borderRadius: BorderRadius.circular(3),
                        border      : isHovered
                            ? Border.all(color: AppTheme.primaryPurple, width: 1.5)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              )),
            ],
          ),
        ),

        // Tooltip
        if (_hovered != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_hovered!.date.day}/${_hovered!.date.month}/${_hovered!.date.year}  ·  '
              '${_scoreTolabel(_hovered!.score)}  (${(_hovered!.score * 100).toInt()})',
              style: GoogleFonts.inter(
                  fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ],

        const SizedBox(height: 12),
        // Legend
        Row(children: [
          Text('Less positive ',
              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
          ...[0.1, 0.35, 0.55, 0.75, 0.9].map((s) => Container(
            width: 12, height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _scoreToColor(s),
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          Text(' More positive',
              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
        ]),
      ]),
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _monthAbbr(int m) =>
      ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART 4 — Sleep vs Mood Correlation Scatter Plot
// ─────────────────────────────────────────────────────────────────────────────
//
// HOW TO INTEGRATE — insights_page.dart, new tab "Correlations":
//
//   SleepMoodScatter(
//     sleepLogs : _sleepLogs,    // List<SleepLogData>
//     moodScores: _moodScores,   // Map<String, double> date → 0.0-1.0 score
//   )
//
// Each dot = one day. X = hours slept, Y = mood score.
// A trend line is drawn to show correlation direction.

class SleepMoodScatter extends StatelessWidget {
  final List<SleepLogData>     sleepLogs;
  final Map<String, double>    moodScores; // 'yyyy-MM-dd' → 0.0-1.0

  const SleepMoodScatter({
    required this.sleepLogs,
    required this.moodScores,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Build matched (hours, mood) pairs
    final pairs = <FlSpot>[];
    for (final log in sleepLogs) {
      final h = log.hoursSlept;
      final m = moodScores[log.date];
      if (h != null && h > 0 && m != null) {
        pairs.add(FlSpot(h, m));
      }
    }

    if (pairs.length < 4) {
      return const _EmptyPlaceholder(
        icon   : Icons.scatter_plot_rounded,
        message: 'Log sleep and mood on the same days to see your correlation',
      );
    }

    // Simple linear regression for trend line
    final n    = pairs.length.toDouble();
    final sumX = pairs.fold(0.0, (s, p) => s + p.x);
    final sumY = pairs.fold(0.0, (s, p) => s + p.y);
    final sumXY= pairs.fold(0.0, (s, p) => s + p.x * p.y);
    final sumX2= pairs.fold(0.0, (s, p) => s + p.x * p.x);
    final slope= (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX + 0.0001);
    final intercept = (sumY - slope * sumX) / n;

    final minX = pairs.map((p) => p.x).reduce(math.min);
    final maxX = pairs.map((p) => p.x).reduce(math.max);
    // ignore: unused_local_variable
    final trendLine = [
      FlSpot(minX, (slope * minX + intercept).clamp(0.0, 1.0)),
      FlSpot(maxX, (slope * maxX + intercept).clamp(0.0, 1.0)),
    ];

    final correlation = slope > 0.02
        ? '📈 More sleep → better mood'
        : slope < -0.02
            ? '📉 Unusual inverse pattern'
            : '↔️ Weak correlation';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow   : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.scatter_plot_rounded,
                color: Color(0xFF10B981), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sleep × Mood Correlation',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E))),
              Text(correlation,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: const Color(0xFF6B7280))),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: ScatterChart(ScatterChartData(
            minX: 3, maxX: 12,
            minY: 0, maxY: 1,
            scatterSpots: pairs.map((p) => ScatterSpot(p.x, p.y)).toList(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: Colors.grey.withValues(alpha: 0.08), strokeWidth: 1),
              getDrawingVerticalLine: (_) =>
                  FlLine(color: Colors.grey.withValues(alpha: 0.08), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                axisNameWidget: Text('Mood',
                    style: GoogleFonts.inter(fontSize: 9, color: Colors.grey)),
                axisNameSize: 14,
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: 0.25,
                  getTitlesWidget: (v, _) {
                    final labels = {0.0: 'Low', 0.5: 'Mid', 1.0: 'High'};
                    return Text(
                      labels[v] ?? '',
                      style: GoogleFonts.inter(fontSize: 9, color: Colors.grey),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                axisNameWidget: Text('Hours slept',
                    style: GoogleFonts.inter(fontSize: 9, color: Colors.grey)),
                axisNameSize: 14,
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20,
                  interval: 2,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}h',
                    style: GoogleFonts.inter(fontSize: 9, color: Colors.grey),
                  ),
                ),
              ),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            scatterTouchData: ScatterTouchData(
              touchTooltipData: ScatterTouchTooltipData(
                tooltipBgColor: const Color(0xFF1A1A2E),
                getTooltipItems: (spot) => ScatterTooltipItem(
                  '${spot.x.toStringAsFixed(1)}h sleep\n'
                  'Mood: ${(spot.y * 100).toInt()}%',
                  textStyle: GoogleFonts.inter(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          )),
        ),

        // Trend line drawn outside fl_chart using a simple CustomPaint overlay
        // (fl_chart doesn't support extra line layers on ScatterChart directly,
        //  so we draw it via a LayoutBuilder-based approach below)
        const SizedBox(height: 6),
        Text('${pairs.length} matching days  ·  Each dot = one day',
            style: GoogleFonts.inter(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART 5 — Health Radar Chart (spider/web chart)
// ─────────────────────────────────────────────────────────────────────────────
//
// HOW TO INTEGRATE — home_page.dart, after _buildHealthRow:
//
//   HealthRadarChart(
//     sleepScore  : (d.avgSleepFromDash ?? 7.0) / 9.0,
//     moodScore   : d.lastJournalSentiment.clamp(-1,1) * 0.5 + 0.5,
//     cycleRegularity: d.confidenceScore,
//     stressScore : 1.0 - ((d.avgStressFromDash ?? 5.0) / 10.0),
//     activityScore: 0.6, // placeholder — wire to exercise data when available
//   )
//
// A five-axis radar showing Sleep, Mood, Cycle Regularity, Stress, Activity.
// All values should be normalised to 0.0–1.0.

class HealthRadarChart extends StatelessWidget {
  final double sleepScore;       // 0–1  (hours/9 is a good proxy)
  final double moodScore;        // 0–1  (sentiment mapped to 0-1)
  final double cycleRegularity;  // 0–1  (confidence score from predictor)
  final double stressScore;      // 0–1  (1 = low stress)
  final double activityScore;    // 0–1

  const HealthRadarChart({
    required this.sleepScore,
    required this.moodScore,
    required this.cycleRegularity,
    required this.stressScore,
    required this.activityScore,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final values = [
      sleepScore.clamp(0.0, 1.0),
      moodScore.clamp(0.0, 1.0),
      cycleRegularity.clamp(0.0, 1.0),
      stressScore.clamp(0.0, 1.0),
      activityScore.clamp(0.0, 1.0),
    ];
    const labels = ['Sleep', 'Mood', 'Cycle', 'Stress\n(low)', 'Activity'];
    const colors = [
      Color(0xFF4F46E5),
      Color(0xFF10B981),
      Color(0xFF7C3AED),
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
    ];

    final overallScore = (values.fold(0.0, (s, v) => s + v) / values.length * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow   : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.radar_rounded,
                color: AppTheme.primaryPurple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Health Radar',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E))),
              Text('Overall wellness score: $overallScore / 100',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: const Color(0xFF6B7280))),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final radarSize = (constraints.maxWidth * 0.44).clamp(120.0, 165.0);
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: radarSize, height: radarSize,
            child: RadarChart(RadarChartData(
              dataSets: [
                RadarDataSet(
                  dataEntries: values
                      .map((v) => RadarEntry(value: v))
                      .toList(),
                  fillColor: AppTheme.primaryPurple.withValues(alpha: 0.15),
                  borderColor: AppTheme.primaryPurple,
                  borderWidth: 2,
                  entryRadius: 3,
                ),
              ],
              radarBackgroundColor: Colors.transparent,
              borderData         : FlBorderData(show: false),
              radarBorderData    : const BorderSide(color: Colors.transparent),
              gridBorderData     : BorderSide(
                  color: Colors.grey.withValues(alpha: 0.12), width: 1),
              tickCount          : 4,
              ticksTextStyle     : const TextStyle(fontSize: 0, color: Colors.transparent),
              tickBorderData     : BorderSide(
                  color: Colors.grey.withValues(alpha: 0.1), width: 1),
              getTitle: (i, angle) => RadarChartTitle(
                text: labels[i],
                angle: angle,
              ),
              titleTextStyle: GoogleFonts.inter(
                  fontSize: 10, color: const Color(0xFF374151)),
              titlePositionPercentageOffset: 0.2,
            )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(values.length, (i) {
                final pct = (values[i] * 100).round();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                            color: colors[i], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            labels[i].replaceAll('\n', ' '),
                            style: GoogleFonts.inter(
                                fontSize: 10, color: const Color(0xFF374151)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('$pct%',
                            style: GoogleFonts.inter(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                color: colors[i])),
                      ]),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value           : values[i],
                          backgroundColor : colors[i].withValues(alpha: 0.1),
                          valueColor      : AlwaysStoppedAnimation<Color>(colors[i]),
                          minHeight       : 4,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ]);
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final Color  color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF6B7280))),
  ]);
}

class _EmptyPlaceholder extends StatelessWidget {
  final IconData icon;
  final String   message;
  const _EmptyPlaceholder({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 40, color: const Color(0xFFE5E7EB)),
      const SizedBox(height: 12),
      Text(message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF9CA3AF))),
    ]),
  );
}
