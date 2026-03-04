import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/local/local_database_service.dart';
import '../../../../core/di/injection.dart';

class CyclesHistoryPage extends StatefulWidget {
  const CyclesHistoryPage({super.key});

  @override
  State<CyclesHistoryPage> createState() => _CyclesHistoryPageState();
}

class _CyclesHistoryPageState extends State<CyclesHistoryPage>
    with SingleTickerProviderStateMixin {
  late final LocalDatabaseService _aiService;
  late TabController _tabCtrl;
  List<LocalCycleRecord> _cycles = [];
  bool _loading = true;
  String? _error;

  // Calendar state
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _aiService = getIt<LocalDatabaseService>();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cycles = await _aiService.getCycles(limit: 48);
      setState(() {
        _cycles = cycles;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Statistics ────────────────────────────────────────────────────────────

  int? get _avgLength {
    final lengths = _cycles.where((c) => c.cycleLength != null).map((c) => c.cycleLength!).toList();
    if (lengths.isEmpty) return null;
    return (lengths.reduce((a, b) => a + b) / lengths.length).round();
  }

  int? get _shortestLength {
    final lengths = _cycles.where((c) => c.cycleLength != null).map((c) => c.cycleLength!).toList();
    if (lengths.isEmpty) return null;
    return lengths.reduce((a, b) => a < b ? a : b);
  }

  int? get _longestLength {
    final lengths = _cycles.where((c) => c.cycleLength != null).map((c) => c.cycleLength!).toList();
    if (lengths.isEmpty) return null;
    return lengths.reduce((a, b) => a > b ? a : b);
  }

  bool get _isRegular {
    final lengths = _cycles.where((c) => c.cycleLength != null).map((c) => c.cycleLength!).toList();
    if (lengths.length < 3) return true;
    final avg = lengths.reduce((a, b) => a + b) / lengths.length;
    return lengths.every((l) => (l - avg).abs() <= 5);
  }

  // ── Cycle phase calculator ────────────────────────────────────────────────
  Color _colorForDate(DateTime day) {
    if (_cycles.isEmpty) return Colors.transparent;
    for (final cycle in _cycles) {
      final start = DateTime.parse(cycle.startDate);
      // Menstrual phase
      final periodEnd = start.add(Duration(days: (cycle.periodLength ?? 5)));
      if (!day.isBefore(start) && day.isBefore(periodEnd)) {
        return AppTheme.menstrualRed;
      }
      // Follicular
      final cycleLen = cycle.cycleLength ?? 28;
      final follEnd = start.add(Duration(days: (cycleLen * 0.45).round()));
      if (!day.isBefore(periodEnd) && day.isBefore(follEnd)) {
        return AppTheme.follicularGreen;
      }
      // Ovulation window
      final ovulEnd = start.add(Duration(days: (cycleLen * 0.55).round()));
      if (!day.isBefore(follEnd) && day.isBefore(ovulEnd)) {
        return AppTheme.ovulationOrange;
      }
      // Luteal (rest)
      final nextPeriod = start.add(Duration(days: cycleLen));
      if (!day.isBefore(ovulEnd) && day.isBefore(nextPeriod)) {
        return AppTheme.lutealPurple;
      }
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {

    const bgColor = AppTheme.backgroundLight;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Cycle History',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.primaryPurple,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'History'),
            Tab(text: 'Calendar'),
            Tab(text: 'Tracking'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/log-cycle');
          _load();
        },
        backgroundColor: AppTheme.primaryPurple,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Log Cycle',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    // Tab 1: History list
                    _cycles.isEmpty
                        ? _EmptyView()
                        : _HistoryBody(
                            cycles: _cycles,
                            avgLength: _avgLength,
                            shortestLength: _shortestLength,
                            longestLength: _longestLength,
                            isRegular: _isRegular,
                          ),
                    // Tab 2: Calendar
                    _buildCalendarTab(),
                    // Tab 3: Tracking (ovulation + PMS)
                    _buildTrackingTab(),
                  ],
                ),
    );
  }

  Widget _buildCalendarTab() {
    const cardColor = Colors.white;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Legend
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: const Wrap(spacing: 16, runSpacing: 8, children: [
            _LegendDot(color: AppTheme.menstrualRed, label: 'Menstrual'),
            _LegendDot(color: AppTheme.follicularGreen, label: 'Follicular'),
            _LegendDot(color: AppTheme.ovulationOrange, label: 'Ovulation'),
            _LegendDot(color: AppTheme.lutealPurple, label: 'Luteal'),
          ]),
        ),
        const SizedBox(height: 12),

        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
          ),
          child: TableCalendar(
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now().add(const Duration(days: 60)),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
            },
            onPageChanged: (focused) => setState(() => _focusedDay = focused),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: const TextStyle(color: Colors.black87),
              weekendTextStyle: const TextStyle(color: Colors.black54),
              todayDecoration: const BoxDecoration(
                color: AppTheme.primaryPurple, shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: AppTheme.primaryPurple.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primaryPurple, width: 2),
              ),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E)),
              leftChevronIcon: const Icon(Icons.chevron_left,
                  color: Colors.black54),
              rightChevronIcon: const Icon(Icons.chevron_right,
                  color: Colors.black54),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, focusedDay) {
                final phaseColor = _colorForDate(day);
                if (phaseColor == Colors.transparent) return null;
                return Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: phaseColor.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                          fontSize: 13,
                          color: phaseColor.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Selected day info
        if (_selectedDay != null) ...[
          const SizedBox(height: 16),
          _SelectedDayCard(
              day: _selectedDay!,
              cycles: _cycles,
              ),
        ],

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildTrackingTab() {

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _OvulationConfirmCard(aiService: _aiService),
        const SizedBox(height: 16),
        _PmsFeedbackCard(aiService: _aiService),
        const SizedBox(height: 80),
      ],
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _HistoryBody extends StatelessWidget {
  final List<LocalCycleRecord> cycles;
  final int? avgLength;
  final int? shortestLength;
  final int? longestLength;
  final bool isRegular;

  const _HistoryBody({
    required this.cycles,
    required this.avgLength,
    required this.shortestLength,
    required this.longestLength,
    required this.isRegular,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats row
        _StatsCard(
          avgLength: avgLength,
          shortest: shortestLength,
          longest: longestLength,
          totalLogged: cycles.length,
          isRegular: isRegular,
        ),
        const SizedBox(height: 20),

        // Chart — bar chart of cycle lengths
        if (avgLength != null) ...[
          _CycleLengthChart(cycles: cycles),
          const SizedBox(height: 20),
        ],

        Text('All Cycles',
            style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 12),

        // Cycle cards — most recent first
        ...cycles.asMap().entries.map((entry) {
          final index = entry.key;
          final cycle = entry.value;
          return _CycleCard(
            cycle: cycle,
            cycleNumber: cycles.length - index,
            isLatest: index == 0,
          );
        }),

        const SizedBox(height: 100), // FAB clearance
      ],
    );
  }
}

// ── Stats Card ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final int? avgLength;
  final int? shortest;
  final int? longest;
  final int totalLogged;
  final bool isRegular;

  const _StatsCard({
    required this.avgLength,
    required this.shortest,
    required this.longest,
    required this.totalLogged,
    required this.isRegular,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryPurple, AppTheme.secondaryPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.loop, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          Text('Cycle Statistics',
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 12, letterSpacing: 0.6)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isRegular
                  ? Colors.green.withValues(alpha: 0.25)
                  : Colors.orange.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isRegular ? 'Regular' : 'Irregular',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isRegular ? Colors.greenAccent : Colors.orangeAccent,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _StatPill(label: 'Logged', value: '$totalLogged cycles'),
            const SizedBox(width: 10),
            _StatPill(label: 'Avg Length', value: avgLength != null ? '$avgLength days' : '—'),
            const SizedBox(width: 10),
            _StatPill(label: 'Range',
                value: (shortest != null && longest != null)
                    ? '$shortest – $longest'
                    : '—'),
          ]),
        ),
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    // NOTE: must NOT use Expanded here — this widget lives inside a
    // SingleChildScrollView(horizontal) Row which has unbounded width.
    return SizedBox(
      width: 110,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inter(fontSize: 10, color: Colors.white60),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ── Bar Chart ─────────────────────────────────────────────────────────────────

class _CycleLengthChart extends StatelessWidget {
  final List<LocalCycleRecord> cycles;

  const _CycleLengthChart({required this.cycles});

  @override
  Widget build(BuildContext context) {
    // Show last 12 cycles with lengths, oldest first
    final withLengths = cycles
        .where((c) => c.cycleLength != null)
        .toList()
        .reversed
        .take(12)
        .toList();

    if (withLengths.isEmpty) return const SizedBox.shrink();

    final maxLen = withLengths.map((c) => c.cycleLength!).reduce((a, b) => a > b ? a : b);
    final avg = withLengths.map((c) => c.cycleLength!).reduce((a, b) => a + b) / withLengths.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Cycle Length Trend',
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        Text('Last ${withLengths.length} cycles  ·  avg ${avg.round()} days',
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 16),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: withLengths.asMap().entries.map((entry) {
              final c = entry.value;
              final len = c.cycleLength!;
              final heightFrac = len / maxLen;
              final isNormal = len >= 21 && len <= 35;
              final barColor = isNormal
                  ? AppTheme.primaryPurple
                  : len < 21
                      ? AppTheme.errorRed
                      : AppTheme.warningOrange;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Tooltip(
                    message: '${c.startDate}: $len days',
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(
                        height: 60 * heightFrac,
                        decoration: BoxDecoration(
                          color: barColor.withValues(alpha: 0.85),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        const Row(children: [
          _Legend(color: AppTheme.primaryPurple, label: 'Normal (21-35d)'),
          SizedBox(width: 12),
          _Legend(color: AppTheme.errorRed, label: 'Short (<21d)'),
          SizedBox(width: 12),
          _Legend(color: AppTheme.warningOrange, label: 'Long (>35d)'),
        ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label,
            style:
                GoogleFonts.inter(fontSize: 10, color: AppTheme.textTertiary)),
      ]);
}

// ── Cycle Card ────────────────────────────────────────────────────────────────

class _CycleCard extends StatelessWidget {
  final LocalCycleRecord cycle;
  final int cycleNumber;
  final bool isLatest;

  const _CycleCard({
    required this.cycle,
    required this.cycleNumber,
    required this.isLatest,
  });

  String _formatDate(String raw) {
    try {
      final d = DateTime.parse(raw);
      return DateFormat('MMM d, yyyy').format(d);
    } catch (_) {
      return raw;
    }
  }

  Color get _flowColor {
    switch (cycle.flowIntensity) {
      case 'heavy':  return AppTheme.errorRed;
      case 'medium': return AppTheme.warningOrange;
      case 'light':  return AppTheme.successGreen;
      default:       return AppTheme.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isLatest
            ? Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.4), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.lightPurple,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text('$cycleNumber',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryPurple,
                        fontSize: 14)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(_formatDate(cycle.startDate),
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary),
                      overflow: TextOverflow.ellipsis)),
                  if (isLatest) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Current',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppTheme.primaryPurple,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
                if (cycle.cycleLength != null)
                  Text('${cycle.cycleLength} day cycle',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppTheme.textSecondary)),
              ]),
            ),
            if (cycle.cycleLength != null)
              _CycleLengthBadge(length: cycle.cycleLength!),
          ]),

          // Details row
          const SizedBox(height: 12),
          Row(children: [
            if (cycle.periodLength != null)
              _DetailChip(
                  icon: Icons.water_drop_outlined,
                  label: '${cycle.periodLength}d period',
                  color: AppTheme.errorRed),
            if (cycle.flowIntensity != null) ...[
              const SizedBox(width: 8),
              _DetailChip(
                  icon: Icons.opacity,
                  label: cycle.flowIntensity!,
                  color: _flowColor),
            ],
            if (cycle.isRegular == false) ...[
              const SizedBox(width: 8),
              const _DetailChip(
                  icon: Icons.warning_amber_outlined,
                  label: 'Irregular',
                  color: AppTheme.warningOrange),
            ],
          ]),

          // Ovulation/fertile window if available
          if (cycle.ovulationDate != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.ovulationOrange.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.wb_sunny_outlined,
                    size: 14, color: AppTheme.ovulationOrange),
                const SizedBox(width: 6),
                Text(
                  'Ovulation: ${_formatDate(cycle.ovulationDate!)}${cycle.fertileWindowStart != null && cycle.fertileWindowEnd != null
                          ? '  ·  Fertile: ${_formatDate(cycle.fertileWindowStart!)} – ${_formatDate(cycle.fertileWindowEnd!)}'
                          : ''}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ]),
            ),
          ],

          if (cycle.notes != null && cycle.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${cycle.notes}',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontStyle: FontStyle.italic)),
          ],
        ]),
      ),
    );
  }
}

class _CycleLengthBadge extends StatelessWidget {
  final int length;

  const _CycleLengthBadge({required this.length});

  Color get _color {
    if (length < 21) return AppTheme.errorRed;
    if (length > 35) return AppTheme.warningOrange;
    return AppTheme.successGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$length d',
        style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: _color),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DetailChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.inter(fontSize: 11, color: color)),
        ]),
      );
}

// ── Empty / Error ─────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.calendar_month_outlined,
              size: 80, color: AppTheme.primaryPurple.withValues(alpha: 0.3)),
          const SizedBox(height: 20),
          Text('No cycles logged yet',
              style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'Log your first period to start tracking your cycle history '
            'and unlock personalised predictions.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
          ),
        ]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 64, color: AppTheme.errorRed),
          const SizedBox(height: 16),
          Text('Could not load cycles',
              style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.errorRed)),
          const SizedBox(height: 8),
          Text(error,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Legend dot ────────────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12, height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
    ]);
  }
}

// ── Selected day info card ────────────────────────────────────────────────────
class _SelectedDayCard extends StatelessWidget {
  final DateTime day;
  final List<LocalCycleRecord> cycles;
  const _SelectedDayCard({required this.day, required this.cycles, });

  String _phaseForDay() {
    for (final cycle in cycles) {
      final start = DateTime.parse(cycle.startDate);
      final cycleLen = cycle.cycleLength ?? 28;
      final periodLen = cycle.periodLength ?? 5;
      if (!day.isBefore(start) && day.isBefore(start.add(Duration(days: periodLen)))) return 'Menstrual';
      if (!day.isBefore(start.add(Duration(days: periodLen))) &&
          day.isBefore(start.add(Duration(days: (cycleLen * 0.45).round())))) {
        return 'Follicular';
      }
      if (!day.isBefore(start.add(Duration(days: (cycleLen * 0.45).round()))) &&
          day.isBefore(start.add(Duration(days: (cycleLen * 0.55).round())))) {
        return 'Ovulation';
      }
      if (!day.isBefore(start.add(Duration(days: (cycleLen * 0.55).round()))) &&
          day.isBefore(start.add(Duration(days: cycleLen)))) {
        return 'Luteal';
      }
    }
    return 'No data';
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Colors.white;
    final phase = _phaseForDay();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Row(children: [
        const Icon(Icons.calendar_month_rounded, size: 22, color: Colors.grey),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('MMMM d, yyyy').format(day),
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14,
                  color: const Color(0xFF1A1A2E))),
          Text(phase,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.primaryPurple,
                  fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

// ── Ovulation Confirmation Card ───────────────────────────────────────────────
class _OvulationConfirmCard extends StatefulWidget {
  final LocalDatabaseService aiService;
  const _OvulationConfirmCard({required this.aiService, });

  @override
  State<_OvulationConfirmCard> createState() => _OvulationConfirmCardState();
}

class _OvulationConfirmCardState extends State<_OvulationConfirmCard> {
  String? _discharge;
  bool? _lhSurge;
  bool? _cramps;
  bool _saving = false;

  static const _dischargeOptions = [
    ('dry', 'dry'), ('sticky', 'sticky'), ('creamy', 'creamy'),
    ('watery', 'watery'), ('egg_white', 'egg white'),
  ];

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await widget.aiService.confirmOvulation(
        date: today,
        dischargeType: _discharge,
        hadCramps: _cramps,
        lhSurge: _lhSurge,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ovulation signs logged!')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Colors.white;
    const textPrimary = Color(0xFF1A1A2E);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.ovulationOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.wb_sunny_rounded, color: AppTheme.ovulationOrange, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Confirm Ovulation Signs',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: textPrimary)),
        ]),
        const SizedBox(height: 4),
        Text('Help EVA learn your body\'s unique pattern',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),

        Text('Discharge type', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13,
            color: const Color(0xFF374151))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: _dischargeOptions.map((opt) {
          final selected = _discharge == opt.$1;
          // Map discharge type to a meaningful icon
          final dischargeIcons = <String, IconData>{
            'dry'       : Icons.water_drop_outlined,
            'sticky'    : Icons.opacity,
            'creamy'    : Icons.circle_outlined,
            'watery'    : Icons.water,
            'egg_white' : Icons.egg_outlined,
          };
          final iconData = dischargeIcons[opt.$1] ?? Icons.circle_outlined;
          return GestureDetector(
            onTap: () => setState(() => _discharge = selected ? null : opt.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? AppTheme.ovulationOrange : AppTheme.ovulationOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? AppTheme.ovulationOrange : AppTheme.ovulationOrange.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(iconData, size: 13,
                    color: selected ? Colors.white : AppTheme.ovulationOrange),
                const SizedBox(width: 5),
                Text(opt.$2,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : AppTheme.ovulationOrange)),
              ]),
            ),
          );
        }).toList()),

        const SizedBox(height: 12),

        Row(children: [
          Expanded(child: _YesNoChip(
            label: 'LH Surge',
            value: _lhSurge,
            onChange: (v) => setState(() => _lhSurge = v),
            color: AppTheme.follicularGreen,
          )),
          const SizedBox(width: 8),
          Expanded(child: _YesNoChip(
            label: 'Cramps',
            value: _cramps,
            onChange: (v) => setState(() => _cramps = v),
            color: AppTheme.menstrualRed,
          )),
        ]),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_discharge == null && _lhSurge == null && _cramps == null) || _saving
                ? null
                : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.ovulationOrange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Log Ovulation Signs',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

class _YesNoChip extends StatelessWidget {
  final String label;
  final bool? value;
  final ValueChanged<bool?> onChange;
  final Color color;

  const _YesNoChip({required this.label, required this.value, required this.onChange, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey)),
    ]),
      const SizedBox(height: 6),
      Row(children: [
        _chip('Yes', value == true, color, () => onChange(value == true ? null : true)),
        const SizedBox(width: 6),
        _chip('No', value == false, Colors.grey, () => onChange(value == false ? null : false)),
      ]),
    ]);
  }

  Widget _chip(String text, bool selected, Color c, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : c)),
      ),
    );
  }
}

// ── PMS Feedback Card ─────────────────────────────────────────────────────────

class _PmsFeedbackCard extends StatefulWidget {
  final LocalDatabaseService aiService;
  const _PmsFeedbackCard({required this.aiService, });

  @override
  State<_PmsFeedbackCard> createState() => _PmsFeedbackCardState();
}

class _PmsFeedbackCardState extends State<_PmsFeedbackCard> {
  bool? _arrivedAsPredicted;
  int _severity = 3;
  bool _saving = false;

  Future<void> _save() async {
    if (_arrivedAsPredicted == null) return;
    setState(() => _saving = true);
    try {
      await widget.aiService.submitPmsFeedback(
        arrivedAsPredicted: _arrivedAsPredicted!,
        severity: _arrivedAsPredicted! ? _severity : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PMS feedback saved! Thank you')),
        );
        setState(() => _arrivedAsPredicted = null);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Colors.white;
    const textPrimary = Color(0xFF1A1A2E);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.lutealPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.feedback_outlined, color: AppTheme.lutealPurple, size: 18),
          ),
          const SizedBox(width: 10),
          Text('PMS Prediction Accuracy',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: textPrimary)),
        ]),
        const SizedBox(height: 4),
        Text('Did your PMS arrive as predicted this cycle?',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),

        Row(children: [
          Expanded(child: _BigButton(
            label: 'Yes, on time ✓',
            selected: _arrivedAsPredicted == true,
            color: AppTheme.follicularGreen,
            onTap: () => setState(() => _arrivedAsPredicted = true),
          )),
          const SizedBox(width: 10),
          Expanded(child: _BigButton(
            label: 'No, it didn\'t ✗',
            selected: _arrivedAsPredicted == false,
            color: AppTheme.menstrualRed,
            onTap: () => setState(() => _arrivedAsPredicted = false),
          )),
        ]),

        if (_arrivedAsPredicted == true) ...[
          const SizedBox(height: 14),
          Text('How severe was it? $_severity/5',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13,
                  color: const Color(0xFF374151))),
          Slider(
            value: _severity.toDouble(),
            min: 1, max: 5, divisions: 4,
            activeColor: AppTheme.lutealPurple,
            onChanged: (v) => setState(() => _severity = v.round()),
          ),
        ],

        if (_arrivedAsPredicted != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.lutealPurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Submit Feedback',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _BigButton({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : color.withValues(alpha: 0.3)),
        ),
        child: Center(child: Text(label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : color))),
      ),
    );
  }
}
