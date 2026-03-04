import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../../core/local/local_database_service.dart';
import '../../../../core/di/injection.dart';

class WeightTrackerPage extends StatefulWidget {
  const WeightTrackerPage({super.key});

  @override
  State<WeightTrackerPage> createState() => _WeightTrackerPageState();
}

class _WeightTrackerPageState extends State<WeightTrackerPage> {
  late final LocalDatabaseService _localDb;

  final _weightCtrl = TextEditingController();
  final _waistCtrl  = TextEditingController();
  final _hipsCtrl   = TextEditingController();
  bool _submitting  = false;

  Map<String, dynamic>? _chartData;
  List<LocalWeightLogData> _logs = [];

  @override
  void initState() {
    super.initState();
    _localDb = getIt<LocalDatabaseService>();
    _loadData();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _waistCtrl.dispose();
    _hipsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final chart = await _localDb.getWeightChart(days: 90);
      final logs  = await _localDb.getWeightLogs(limit: 90);
      setState(() {
        _chartData = chart;
        _logs = logs.reversed.toList(); // chronological for chart
      });
      if (_logs.isNotEmpty && _weightCtrl.text.isEmpty) {
        final latest = _logs.last.weightKg;
        if (latest > 0) {
          _weightCtrl.text = latest % 1 == 0
              ? latest.toInt().toString()
              : latest.toStringAsFixed(1);
        }
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight < 10 || weight > 600) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight (10–600 kg)')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _localDb.logWeight(
        date     : today,
        weightKg : weight,
        waistCm  : double.tryParse(_waistCtrl.text),
        hipsCm   : double.tryParse(_hipsCtrl.text),
      );
      _weightCtrl.clear();
      _waistCtrl.clear();
      _hipsCtrl.clear();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Weight logged!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    setState(() => _submitting = false);
  }

  List<FlSpot> get _weightSpots {
    if (_logs.isEmpty) return [];
    return _logs.asMap().entries
        .where((e) => e.value.weightKg > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value.weightKg))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor    = isDark ? const Color(0xFF1E1B2E) : Colors.white;
    final bgColor      = isDark ? const Color(0xFF0D0A1A) : const Color(0xFFF0FDF4);
    final textPrimary  = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final textSecondary= isDark ? Colors.white60 : const Color(0xFF6B7280);

    final chart = _chartData;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Weight Tracker',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (chart != null && (chart['count'] as int? ?? 0) > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _StatItem(
                  label: 'Current',
                  value: chart['latest_weight'] != null ? '${chart['latest_weight']}kg' : '--',
                ),
                _StatItem(
                  label: 'BMI',
                  value: chart['latest_bmi'] != null ? '${chart['latest_bmi']}' : '--',
                ),
                _StatItem(
                  label: '90d Change',
                  value: chart['change'] != null
                      ? '${chart['change'] > 0 ? '+' : ''}${chart['change']}kg'
                      : '--',
                ),
              ]),
            ),

          const SizedBox(height: 16),

          if (_weightSpots.length >= 2)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Weight History (90 days)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: textPrimary)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 160,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: (isDark ? Colors.white : Colors.grey).withValues(alpha: 0.1),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (v, _) => Text(
                              v.toStringAsFixed(0),
                              style: TextStyle(fontSize: 10, color: textSecondary),
                            ),
                          ),
                        ),
                        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles:    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _weightSpots,
                          isCurved: true,
                          color: const Color(0xFF10B981),
                          barWidth: 2.5,
                          dotData: FlDotData(show: _weightSpots.length < 15),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Log Today\'s Weight',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: isDark ? Colors.white : null),
                decoration: InputDecoration(
                  labelText: 'Weight (kg) *',
                  fillColor: isDark ? const Color(0xFF2A2740) : null,
                  suffixText: 'kg',
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(
                  controller: _waistCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: isDark ? Colors.white : null),
                  decoration: InputDecoration(
                    labelText: 'Waist (cm)',
                    fillColor: isDark ? const Color(0xFF2A2740) : null,
                    suffixText: 'cm',
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: _hipsCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: isDark ? Colors.white : null),
                  decoration: InputDecoration(
                    labelText: 'Hips (cm)',
                    fillColor: isDark ? const Color(0xFF2A2740) : null,
                    suffixText: 'cm',
                  ),
                )),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Save Weight',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),
          ),

          if (_logs.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('History',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
            const SizedBox(height: 12),
            ..._logs.reversed.take(10).map((l) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? const Color(0xFF2D2B45) : const Color(0xFFE5E7EB)),
              ),
              child: Row(children: [
                const Icon(Icons.monitor_weight_outlined, size: 20, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(child: Text(l.date,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: textPrimary))),
                Text('${l.weightKg}kg',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700,
                        color: const Color(0xFF10B981))),
                if (l.bmi != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text('BMI ${l.bmi}',
                        style: GoogleFonts.inter(fontSize: 11, color: textSecondary)),
                  ),
              ]),
            )),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
      Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
    ]);
  }
}
