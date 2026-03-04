import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/local/local_database_service.dart';
import '../../../../core/theme/app_theme.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _DayData {
  final List<Map<String, dynamic>> symptoms;
  final Map<String, dynamic>?      journal;
  final Map<String, dynamic>?      mood;
  final String?                    flow;
  final String                     phase;

  const _DayData({
    this.symptoms = const [],
    this.journal,
    this.mood,
    this.flow,
    this.phase = 'unknown',
  });

  bool get hasAny =>
      symptoms.isNotEmpty || journal != null || mood != null || flow != null;
}

// ── Phase helpers ─────────────────────────────────────────────────────────────

const _phaseColors = {
  'menstrual'  : Color(0xFFFF6B6B),
  'follicular' : Color(0xFF4ECDC4),
  'ovulation'  : Color(0xFFFFBE0B),
  'luteal'     : Color(0xFF7C3AED),
  'unknown'    : Color(0xFFD1D5DB),
};

const _phaseLabels = {
  'menstrual'  : 'Menstrual',
  'follicular' : 'Follicular',
  'ovulation'  : 'Ovulation',
  'luteal'     : 'Luteal',
  'unknown'    : '—',
};

const _phaseIcons = {
  'menstrual'  : Icons.water_drop_rounded,
  'follicular' : Icons.eco_rounded,
  'ovulation'  : Icons.wb_sunny_rounded,
  'luteal'     : Icons.nightlight_round,
  'unknown'    : Icons.circle,
};

// ── Page ──────────────────────────────────────────────────────────────────────

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay  = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  Map<String, _DayData> _data     = {};
  Map<String, String>   _phaseMap = {};
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchMonth(_focusedDay);
  }

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _fetchMonth(DateTime month) async {
    setState(() { _loading = true; _error = null; });
    final startDate = DateTime(month.year, month.month, 1);
    final endDate   = DateTime(month.year, month.month + 1, 0);
    try {
      final localDb = getIt<LocalDatabaseService>();

      // Load data in parallel (cycles needed for accurate past-phase coloring)
      final results = await Future.wait([
        localDb.getDashboard(),
        localDb.getSymptoms(limit: 200),
        localDb.getJournalEntries(),
        localDb.getCycles(limit: 36),
      ]);

      final dash      = results[0] as LocalDashboardData;
      final allSymps  = results[1] as List<LocalSymptomRecord>;
      final allJournal= results[2] as List<LocalJournalEntry>;
      final cycles    = results[3] as List<LocalCycleRecord>;

      // Build past-phase map from real cycle records
      final pastPhaseMap = <String, String>{};
      for (final c in cycles) {
        final cycleStart = DateTime.tryParse(c.startDate);
        if (cycleStart == null) continue;
        final cycleLen = c.cycleLength ?? (dash.cycleLengthPrediction ?? 28);
        DateTime d = cycleStart;
        for (int day = 1; day <= cycleLen; day++) {
          final key = _fmt(d);
          if (day <= 5)       { pastPhaseMap[key] = 'menstrual'; }
          else if (day <= 13) { pastPhaseMap[key] = 'follicular'; }
          else if (day <= 16) { pastPhaseMap[key] = 'ovulation'; }
          else                { pastPhaseMap[key] = 'luteal'; }
          d = d.add(const Duration(days: 1));
        }
      }

      // Index by date
      final sympsByDate  = <String, List<Map<String, dynamic>>>{};
      for (final s in allSymps) {
        final d = s.date.split('T').first;
        sympsByDate.putIfAbsent(d, () => []);
        sympsByDate[d]!.add({'symptom_type': s.symptomType, 'severity': s.severity});
      }
      final journalByDate = <String, Map<String, dynamic>>{};
      for (final j in allJournal) {
        journalByDate[j.date] = {
          'entry_text'    : j.entryText,
          'sentiment_score': j.sentimentScore,
          'primary_emotion': j.primaryEmotion,
        };
      }

      final today = DateTime.now();
      // Build phase map and day data
      final phaseMap = <String, String>{};
      final parsed   = <String, _DayData>{};
      DateTime current = startDate;
      while (!current.isAfter(endDate)) {
        final key = _fmt(current);
        // Past days: use actual logged cycle data only.
        // Today + future: use ML prediction from dashboard.
        String phase;
        if (!current.isAfter(today)) {
          phase = pastPhaseMap[key] ?? 'unknown';
        } else {
          phase = _predictedPhaseForFutureDate(current, dash);
        }
        phaseMap[key] = phase;
        final jEntry = journalByDate[key];
        parsed[key] = _DayData(
          symptoms: sympsByDate[key] ?? [],
          journal : jEntry,
          mood    : jEntry != null && jEntry['primary_emotion'] != null
              ? {'mood': jEntry['primary_emotion']} : null,
          flow    : null, // flow is embedded in cycle records
          phase   : phase,
        );
        current = current.add(const Duration(days: 1));
      }

      setState(() {
        _data     = parsed;
        _phaseMap = phaseMap;
        _loading  = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _predictedPhaseForFutureDate(DateTime date, LocalDashboardData dash) {
    if (!dash.hasData || dash.nextPeriodDate == null) return 'unknown';
    final nextPeriod = DateTime.tryParse(dash.nextPeriodDate!);
    if (nextPeriod == null) return 'unknown';
    final cycleLen = dash.cycleLengthPrediction ?? 28;
    // Walk backwards from nextPeriod to find the cycle that contains 'date'
    DateTime periodStart = nextPeriod;
    while (date.isBefore(periodStart)) {
      periodStart = periodStart.subtract(Duration(days: cycleLen));
    }
    while (date.isAfter(periodStart.add(Duration(days: cycleLen - 1)))) {
      periodStart = periodStart.add(Duration(days: cycleLen));
    }
    final dayInCycle = date.difference(periodStart).inDays + 1;
    if (dayInCycle <= 5)  return 'menstrual';
    if (dayInCycle <= 13) return 'follicular';
    if (dayInCycle <= 16) return 'ovulation';
    return 'luteal';
  }

  _DayData? _dayData(DateTime day) => _data[_fmt(day)];
  String    _dayPhase(DateTime day) => _phaseMap[_fmt(day)] ?? 'unknown';

  @override
  Widget build(BuildContext context) {
    final selected = _dayData(_selectedDay);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryPurple,
        foregroundColor: Colors.white,
        title: Text('Cycle Calendar',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
        elevation: 0,
      ),
      body: Column(children: [

        // Phase legend
        Container(
          color: AppTheme.primaryPurple,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _phaseColors.entries
                .where((e) => e.key != 'unknown')
                .map((e) => _LegendDot(color: e.value, label: _phaseLabels[e.key]!))
                .toList(),
          ),
        ),

        // Calendar
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 8)],
          ),
          child: _loading
              ? const SizedBox(
                  height: 340,
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryPurple, strokeWidth: 2)))
              : TableCalendar(
                  firstDay: DateTime(2020),
                  lastDay : DateTime(2030),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
                  calendarFormat: CalendarFormat.month,
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w700, fontSize: 15,
                        color: const Color(0xFF1A1A2E)),
                    leftChevronIcon : const Icon(Icons.chevron_left_rounded,
                        color: AppTheme.primaryPurple),
                    rightChevronIcon: const Icon(Icons.chevron_right_rounded,
                        color: AppTheme.primaryPurple),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: GoogleFonts.inter(fontSize: 11,
                        fontWeight: FontWeight.w600, color: const Color(0xFF9CA3AF)),
                    weekendStyle: GoogleFonts.inter(fontSize: 11,
                        fontWeight: FontWeight.w600, color: const Color(0xFF9CA3AF)),
                  ),
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder : _buildCell,
                    todayBuilder   : _buildCell,
                    selectedBuilder: _buildCell,
                    outsideBuilder : (ctx, day, focused) =>
                        _buildCell(ctx, day, focused, outside: true),
                  ),
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay = selected;
                      _focusedDay  = focused;
                    });
                  },
                  onPageChanged: (focused) {
                    _focusedDay = focused;
                    _fetchMonth(focused);
                  },
                ),
        ),

        const SizedBox(height: 4),

        // Day detail panel
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!,
                    style: GoogleFonts.inter(color: Colors.red, fontSize: 13)))
              : _DayDetail(
                  date : _selectedDay,
                  data : selected,
                  phase: _dayPhase(_selectedDay),
                ),
        ),
      ]),
    );
  }

  Widget _buildCell(BuildContext ctx, DateTime day, DateTime focused,
      {bool outside = false}) {
    final isSelected = isSameDay(day, _selectedDay);
    final isToday    = isSameDay(day, DateTime.now());
    final phase      = _dayPhase(day);
    final phaseColor = _phaseColors[phase] ?? const Color(0xFFD1D5DB);
    final dayData    = _dayData(day);

    final hasDots = dayData != null && !outside &&
        (dayData.symptoms.isNotEmpty || dayData.journal != null || dayData.mood != null);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Perfect circle cell
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? AppTheme.primaryPurple
                  : isToday
                      ? phaseColor.withValues(alpha: 0.25)
                      : phaseColor.withValues(alpha: outside ? 0.04 : 0.14),
              border: isToday && !isSelected
                  ? Border.all(color: phaseColor, width: 1.5)
                  : null,
            ),
            child: Center(
              child: Text(
                '${day.day}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : outside
                          ? const Color(0xFFD1D5DB)
                          : const Color(0xFF1A1A2E),
                ),
              ),
            ),
          ),
          // Data indicator dots below the circle
          if (hasDots)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dayData.symptoms.isNotEmpty)
                    _Dot(color: isSelected ? Colors.white70 : const Color(0xFFEF4444)),
                  if (dayData.journal != null)
                    _Dot(color: isSelected ? Colors.white70 : const Color(0xFF22C55E)),
                  if (dayData.mood != null)
                    _Dot(color: isSelected ? Colors.white70 : const Color(0xFFF59E0B)),
                ],
              ),
            )
          else
            const SizedBox(height: 6), // keep rows even height
        ],
      ),
    );
  }
}

// ── Legend dot ────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label,
          style: GoogleFonts.inter(fontSize: 10,
              color: Colors.white70, fontWeight: FontWeight.w500)),
    ],
  );
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 4, height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ── Day detail ────────────────────────────────────────────────────────────────

class _DayDetail extends StatelessWidget {
  final DateTime  date;
  final _DayData? data;
  final String    phase;

  const _DayDetail({
    required this.date,
    required this.data,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    final phaseColor = _phaseColors[phase] ?? const Color(0xFFD1D5DB);
    final dateLabel  = DateFormat('EEEE, d MMMM yyyy').format(date);
    final isToday    = isSameDay(date, DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Date header + phase badge
        Row(children: [
          Expanded(
            child: Text(isToday ? 'Today' : dateLabel,
                style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                    fontSize: 16, color: const Color(0xFF1A1A2E))),
          ),
          if (phase != 'unknown')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: phaseColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: phaseColor.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_phaseIcons[phase]!, size: 14, color: phaseColor),
                const SizedBox(width: 4),
                Text(_phaseLabels[phase]!,
                    style: GoogleFonts.inter(fontSize: 11,
                        fontWeight: FontWeight.w600, color: phaseColor)),
              ]),
            ),
        ]),
        if (!isToday)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(dateLabel,
                style: GoogleFonts.inter(
                    fontSize: 11, color: const Color(0xFF9CA3AF))),
          ),
        const SizedBox(height: 16),

        if (data == null || !data!.hasAny)
          _EmptyDay(phaseColor: phaseColor)
        else ...[
          if (data!.flow != null)
            _Section(icon: Icons.water_drop_rounded, label: 'Flow',
                color: const Color(0xFFFF6B6B),
                child: _FlowBadge(flow: data!.flow!)),

          if (data!.symptoms.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(
              icon: Icons.bolt_rounded, label: 'Symptoms',
              color: const Color(0xFFEF4444),
              child: Wrap(
                spacing: 6, runSpacing: 6,
                children: data!.symptoms.map((s) => _SymptomChip(
                  type    : s['type'] as String,
                  severity: s['severity'] as int?,
                )).toList(),
              ),
            ),
          ],

          if (data!.mood != null) ...[
            const SizedBox(height: 12),
            _Section(icon: Icons.sentiment_satisfied_alt_rounded, label: 'Mood',
                color: const Color(0xFFF59E0B),
                child: _MoodRow(mood: data!.mood!)),
          ],

          if (data!.journal != null) ...[
            const SizedBox(height: 12),
            _Section(
              icon : data!.journal!['is_quick_log'] == true ? Icons.bolt_rounded : Icons.menu_book_rounded,
              label: data!.journal!['is_quick_log'] == true
                  ? 'Quick Log Entry'
                  : 'Journal Entry',
              color: const Color(0xFF22C55E),
              child: _JournalCard(journal: data!.journal!),
            ),
          ],
        ],
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color  color;
  final Widget child;
  const _Section({required this.icon, required this.label,
      required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 12,
            fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 10),
      child,
    ]),
  );
}

class _FlowBadge extends StatelessWidget {
  final String flow;
  const _FlowBadge({required this.flow});

  @override
  Widget build(BuildContext context) {
    final colors = {
      'light'   : const Color(0xFFFFB3BA),
      'medium'  : const Color(0xFFFF6B6B),
      'moderate': const Color(0xFFFF6B6B),
      'heavy'   : const Color(0xFFCC0000),
    };
    final c = colors[flow.toLowerCase()] ?? const Color(0xFFFF6B6B);
    final label = flow[0].toUpperCase() + flow.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text('$label flow',
          style: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

class _SymptomChip extends StatelessWidget {
  final String type;
  final int?   severity;
  const _SymptomChip({required this.type, this.severity});

  @override
  Widget build(BuildContext context) {
    const c     = Color(0xFFEF4444);
    final label = type.replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color : c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11,
            fontWeight: FontWeight.w500, color: const Color(0xFF374151))),
        if (severity != null) ...[
          const SizedBox(width: 4),
          Container(
            width: 16, height: 16,
            decoration: const BoxDecoration(color: c, shape: BoxShape.circle),
            child: Center(
              child: Text('$severity',
                  style: GoogleFonts.inter(fontSize: 9,
                      fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _MoodRow extends StatelessWidget {
  final Map<String, dynamic> mood;
  const _MoodRow({required this.mood});

  IconData _emoji(String? m) {
    switch (m?.toLowerCase()) {
      case 'happy'    : return Icons.sentiment_very_satisfied;
      case 'calm'     : return Icons.sentiment_satisfied;
      case 'neutral'  : return Icons.sentiment_neutral;
      case 'tired'    : return Icons.bedtime_outlined;
      case 'anxious'  : return Icons.sentiment_dissatisfied;
      case 'irritable': return Icons.sentiment_very_dissatisfied;
      case 'sad'      : return Icons.sentiment_dissatisfied;
      case 'stressed' : return Icons.sentiment_dissatisfied;
      default         : return Icons.sentiment_neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m      = mood['primary_mood'] as String?;
    final sleep  = mood['sleep_hours'];
    final energy = mood['energy_level'];
    final label  = m != null ? '${m[0].toUpperCase()}${m.substring(1)}' : 'Logged';
    return Row(children: [
      Icon(_emoji(m), size: 22, color: const Color(0xFF6B7280)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13,
            fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
        if (sleep != null || energy != null)
          Text([
            if (sleep  != null) '${sleep}h',
            if (energy != null) 'Energy $energy/10',
          ].join('  '),
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9CA3AF))),
      ])),
    ]);
  }
}

class _JournalCard extends StatefulWidget {
  final Map<String, dynamic> journal;
  const _JournalCard({required this.journal});

  @override
  State<_JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<_JournalCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text      = widget.journal['text'] as String? ?? '';
    final sentiment = (widget.journal['sentiment'] as num?)?.toDouble() ?? 0;
    final keywords  = List<String>.from(widget.journal['keywords'] as List? ?? []);
    final isPos     = sentiment > 0.1;
    final isNeg     = sentiment < -0.1;
    final sentColor = isPos
        ? const Color(0xFF22C55E)
        : isNeg ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final sentLabel = isPos ? 'Positive' : isNeg ? 'Negative' : 'Neutral';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color : sentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: sentColor.withValues(alpha: 0.3)),
        ),
        child: Text(sentLabel,
            style: GoogleFonts.inter(fontSize: 10,
                fontWeight: FontWeight.w600, color: sentColor)),
      ),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            text,
            maxLines : _expanded ? null : 3,
            overflow : _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style    : GoogleFonts.inter(fontSize: 13,
                color: const Color(0xFF374151), height: 1.5),
          ),
          if (text.length > 150)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _expanded ? 'Show less ↑' : 'Read more ↓',
                style: GoogleFonts.inter(fontSize: 11,
                    color: AppTheme.primaryPurple, fontWeight: FontWeight.w600),
              ),
            ),
        ]),
      ),
      if (keywords.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 4, runSpacing: 4,
          children: keywords.take(5).map((k) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(k, style: GoogleFonts.inter(
                fontSize: 10, color: const Color(0xFF6B7280))),
          )).toList(),
        ),
      ],
    ]);
  }
}

class _EmptyDay extends StatelessWidget {
  final Color phaseColor;
  const _EmptyDay({required this.phaseColor});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 36),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.calendar_today_rounded,
          size: 42, color: phaseColor.withValues(alpha: 0.3)),
      const SizedBox(height: 12),
      Text('Nothing logged this day',
          style: GoogleFonts.inter(fontSize: 14,
              fontWeight: FontWeight.w600, color: const Color(0xFF9CA3AF))),
      const SizedBox(height: 4),
      Text('Use Quick Log or Journal to track your day',
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFD1D5DB))),
    ]),
  );
}
