// lib/features/reports/report_generator.dart
//
// Generates an offline AI Menstrual Health PDF report from real backend data.
//
// Two modes:
//   isDoctor = false  →  Personal Report  (purple branding, all sections)
//   isDoctor = true   →  Doctor Report    (B&W, clinical summary page first)
//
// pubspec.yaml dependencies needed:
//   pdf: ^3.10.8
//   path_provider: ^2.1.2
//   open_file: ^3.3.2
//   intl: ^0.19.0

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

class ReportData {
  final String username;
  final bool   isDoctor;

  // Cycle prediction
  final int?    predictedCycleLength;
  final int?    actualLastCycleLength;
  final String? nextPeriodDate;
  final int?    daysUntilPeriod;
  final String? currentPhase;
  final int?    currentCycleDay;
  final double? confidenceScore;
  final String? predictionMethod;

  // Ovulation & fertile window
  final String? ovulationDate;
  final String? fertileWindowStart;
  final String? fertileWindowEnd;

  // PMS
  final String? pmsPeakDate;
  final String? pmsRiskLevel;
  final double? pmsRiskScore;

  // Health score
  final double? healthScore;
  final double? avgSleep;
  final double? avgStress;
  final String? topMood;

  // AI insight
  final String? aiInsight;

  // Anomaly alerts  [{title, message, severity}]
  final List<Map<String, dynamic>> anomalyAlerts;

  // Phase tasks (personal only)
  final List<Map<String, dynamic>> phaseTasks;

  // Top emotions  {emotion: count}
  final Map<String, int> topEmotions;

  // Recent symptoms  [symptomType string]
  final List<String> recentSymptoms;

  // Kalman / sentiment diagnostics
  final double? avgJournalSentiment;
  final String? sentimentStressLevel;
  final double? sentimentVarianceEffect;
  final int?    kalmanNObservations;
  final double? kalmanStd;
  final String? kalmanMethod;

  // ── NEW: Cycle history  [{startDate, cycleLength, periodLength, flowIntensity}]
  final List<Map<String, dynamic>> cycleHistory;

  // ── NEW: Symptom frequency this cycle  [{name, avgSeverity, count}]
  final List<Map<String, dynamic>> symptomFrequency;

  // ── NEW: Prediction accuracy  [{cycleLabel, predicted, actual, offBy}]
  //   Derived: for cycle[i] predicted = avg of cycles[i+1..n]
  final List<Map<String, dynamic>> predictionAccuracy;

  // ── NEW: Ovulation confirmation logs  [{userDate, predictedDate, daysOff}]
  final List<Map<String, dynamic>> ovulationConfirmations;

  // ── NEW: Sleep trend data  [{date, hours}], plus summary stats
  final List<Map<String, dynamic>> sleepTrend;
  final int?    sleepNightsUnder6;
  final String? sleepTrendDirection;   // 'improving' | 'declining' | 'stable'

  // ── NEW: Mood by cycle phase  {phase -> avgSentiment -1..+1}
  final Map<String, double> moodByPhase;
  final String? bestMoodPhase;

  // ── NEW: PMS history  [{cycleLabel, arrivedAsPredicted, severity}]
  final List<Map<String, dynamic>> pmsHistory;

  const ReportData({
    this.username                = 'User',
    this.isDoctor                = false,
    this.predictedCycleLength,
    this.actualLastCycleLength,
    this.nextPeriodDate,
    this.daysUntilPeriod,
    this.currentPhase,
    this.currentCycleDay,
    this.confidenceScore,
    this.predictionMethod,
    this.ovulationDate,
    this.fertileWindowStart,
    this.fertileWindowEnd,
    this.pmsPeakDate,
    this.pmsRiskLevel,
    this.pmsRiskScore,
    this.healthScore,
    this.avgSleep,
    this.avgStress,
    this.topMood,
    this.aiInsight,
    this.anomalyAlerts          = const [],
    this.phaseTasks             = const [],
    this.topEmotions            = const {},
    this.recentSymptoms         = const [],
    this.avgJournalSentiment,
    this.sentimentStressLevel,
    this.sentimentVarianceEffect,
    this.kalmanNObservations,
    this.kalmanStd,
    this.kalmanMethod,
    this.cycleHistory           = const [],
    this.symptomFrequency       = const [],
    this.predictionAccuracy     = const [],
    this.ovulationConfirmations = const [],
    this.sleepTrend             = const [],
    this.sleepNightsUnder6,
    this.sleepTrendDirection,
    this.moodByPhase            = const {},
    this.bestMoodPhase,
    this.pmsHistory             = const [],
  });
}

// ─── Colour palettes ──────────────────────────────────────────────────────────

// Personal (purple)
const _purple      = PdfColor.fromInt(0xFF7B3FE4);
const _purpleLight = PdfColor.fromInt(0xFFEDE7F6);
const _purpleMid   = PdfColor.fromInt(0xFFB39DDB);
const _textDark    = PdfColor.fromInt(0xFF1A1A2E);
const _textGrey    = PdfColor.fromInt(0xFF6B6B8A);
const _white       = PdfColors.white;
const _redLight    = PdfColor.fromInt(0xFFFFEBEE);
const _red         = PdfColor.fromInt(0xFFE53935);
const _greenLight  = PdfColor.fromInt(0xFFE8F5E9);
const _green       = PdfColor.fromInt(0xFF43A047);
const _amberLight  = PdfColor.fromInt(0xFFFFF8E1);
const _amber       = PdfColor.fromInt(0xFFFB8C00);
const _tealLight   = PdfColor.fromInt(0xFFE0F2F1);
const _teal        = PdfColor.fromInt(0xFF00897B);
// ignore: unused_element
const _bgPage      = PdfColors.white;

// Doctor (greyscale)
const _drAccent    = PdfColor.fromInt(0xFF1A1A2E);
const _drLight     = PdfColor.fromInt(0xFFF5F5F5);
const _drMid       = PdfColor.fromInt(0xFFBDBDBD);
const _drText      = PdfColor.fromInt(0xFF1A1A2E);
const _drGrey      = PdfColor.fromInt(0xFF757575);

// ─── Public entry point ───────────────────────────────────────────────────────

Future<void> generateAndDownloadReport(
  BuildContext context,
  ReportData data,
) async {
  final label = data.isDoctor ? 'Doctor Report' : 'Health Report';
  try {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Generating your $label...'),
          ]),
          duration: const Duration(seconds: 30),
        ),
      );
    }

    final pdf   = _buildPdf(data);
    final bytes = await pdf.save();

    if (kIsWeb) {
      final filename = data.isDoctor ? 'eva_doctor_report.pdf' : 'eva_health_report.pdf';
      downloadBytesOnWeb(bytes, filename);
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label downloaded!')),
        );
      }
      return;
    }

    final dir       = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final prefix    = data.isDoctor ? 'eva_doctor_' : 'eva_report_';
    final file      = File('${dir.path}/$prefix$timestamp.pdf');
    await file.writeAsBytes(bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label saved to ${file.path}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => OpenFile.open(file.path),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    await OpenFile.open(file.path);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e')),
      );
    }
  }
}

// ─── PDF builder ─────────────────────────────────────────────────────────────

pw.Document _buildPdf(ReportData d) {
  final pdf = pw.Document();
  final now = DateFormat('MMMM d, yyyy').format(DateTime.now());

  if (d.isDoctor) {
    // Doctor version: clinical summary first, then detail page(s)
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin    : const pw.EdgeInsets.all(40),
        header    : (ctx) => _header(d.username, now, doctor: true),
        footer    : (ctx) => _footer(ctx, doctor: true),
        build     : (ctx) => _buildDoctorPages(d),
      ),
    );
  } else {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin    : const pw.EdgeInsets.all(36),
        header    : (ctx) => _header(d.username, now),
        footer    : (ctx) => _footer(ctx),
        build     : (ctx) => _buildPersonalPages(d),
      ),
    );
  }
  return pdf;
}

// ─── Personal pages ───────────────────────────────────────────────────────────

List<pw.Widget> _buildPersonalPages(ReportData d) {
  return [
    // 1. Cycle Prediction
    _sectionTitle('Cycle Prediction'),
    _cyclePredictionCard(d),
    pw.SizedBox(height: 14),

    // 2. Fertile Window
    _sectionTitle('Fertile Window & Ovulation'),
    _fertileCard(d),
    pw.SizedBox(height: 14),

    // 3. PMS Risk
    _sectionTitle('PMS Risk'),
    _pmsCard(d),
    pw.SizedBox(height: 14),

    // 4. Health Score
    _sectionTitle('Health Score'),
    _healthScoreCard(d),
    pw.SizedBox(height: 14),

    // 5. ANOMALY ALERTS — shown prominently early
    if (d.anomalyAlerts.isNotEmpty) ...[
      _sectionTitle('Alerts'),
      _anomalyCard(d),
      pw.SizedBox(height: 14),
    ],

    // 6. Cycle History Table — most important
    if (d.cycleHistory.isNotEmpty) ...[
      _sectionTitle('Cycle History'),
      _cycleHistoryCard(d),
      pw.SizedBox(height: 14),
    ],

    // 7. Symptom Frequency
    if (d.symptomFrequency.isNotEmpty) ...[
      _sectionTitle('Symptom Frequency This Cycle'),
      _symptomFrequencyCard(d),
      pw.SizedBox(height: 14),
    ],

    // 8. Prediction Accuracy
    if (d.predictionAccuracy.isNotEmpty) ...[
      _sectionTitle('Prediction Accuracy Track Record'),
      _predictionAccuracyCard(d),
      pw.SizedBox(height: 14),
    ],

    // 9. Ovulation Confirmation
    if (d.ovulationConfirmations.isNotEmpty) ...[
      _sectionTitle('Ovulation Confirmation'),
      _ovulationConfirmCard(d),
      pw.SizedBox(height: 14),
    ],

    // 10. Sleep Trend
    if (d.sleepTrend.isNotEmpty || d.avgSleep != null) ...[
      _sectionTitle('Sleep Trend — Last 30 Days'),
      _sleepTrendCard(d),
      pw.SizedBox(height: 14),
    ],

    // 11. Mood by Phase
    if (d.moodByPhase.isNotEmpty) ...[
      _sectionTitle('Mood Pattern Across Cycle Phases'),
      _moodByPhaseCard(d),
      pw.SizedBox(height: 14),
    ],

    // 12. PMS History
    if (d.pmsHistory.isNotEmpty) ...[
      _sectionTitle('PMS History'),
      _pmsHistoryCard(d),
      pw.SizedBox(height: 14),
    ],

    // 13. Prediction Intelligence
    _sectionTitle('Prediction Intelligence & Journal Influence'),
    _kalmanSentimentCard(d),
    pw.SizedBox(height: 14),

    // 14. Emotions
    if (d.topEmotions.isNotEmpty) ...[
      _sectionTitle('Emotional Patterns (Last 30 Days)'),
      _emotionsCard(d),
      pw.SizedBox(height: 14),
    ],

    // 15. AI Insight
    if (d.aiInsight != null && d.aiInsight!.isNotEmpty) ...[
      _sectionTitle("Today's Insight"),
      _insightCard(d),
      pw.SizedBox(height: 14),
    ],

    // 16. Phase Tasks
    if (d.phaseTasks.isNotEmpty) ...[
      _sectionTitle('Recommended Actions for ${_capPhase(d.currentPhase)} Phase'),
      _phaseTasksCard(d),
      pw.SizedBox(height: 14),
    ],

    pw.SizedBox(height: 10),
    _disclaimer(),
  ];
}

// ─── Doctor pages ─────────────────────────────────────────────────────────────

List<pw.Widget> _buildDoctorPages(ReportData d) {
  return [
    // ── PAGE 1: Clinical summary ──────────────────────────────────────────────
    _drSectionTitle('CLINICAL SUMMARY'),
    _clinicalSummaryCard(d),
    pw.SizedBox(height: 16),

    if (d.anomalyAlerts.isNotEmpty) ...[
      _drSectionTitle('FLAGGED ANOMALIES'),
      _anomalyCard(d, doctor: true),
      pw.SizedBox(height: 16),
    ],

    // ── PAGE 2+: Detail sections ──────────────────────────────────────────────
    if (d.cycleHistory.isNotEmpty) ...[
      _drSectionTitle('CYCLE HISTORY'),
      _cycleHistoryCard(d, doctor: true),
      pw.SizedBox(height: 16),
    ],

    if (d.symptomFrequency.isNotEmpty) ...[
      _drSectionTitle('SYMPTOM SEVERITY (CURRENT CYCLE)'),
      _symptomFrequencyCard(d, doctor: true),
      pw.SizedBox(height: 16),
    ],

    if (d.predictionAccuracy.isNotEmpty) ...[
      _drSectionTitle('CYCLE LENGTH PREDICTION ACCURACY'),
      _predictionAccuracyCard(d, doctor: true),
      pw.SizedBox(height: 16),
    ],

    if (d.ovulationConfirmations.isNotEmpty) ...[
      _drSectionTitle('OVULATION CONFIRMATION LOG'),
      _ovulationConfirmCard(d, doctor: true),
      pw.SizedBox(height: 16),
    ],

    if (d.moodByPhase.isNotEmpty) ...[
      _drSectionTitle('MOOD BY CYCLE PHASE'),
      _moodByPhaseCard(d, doctor: true),
      pw.SizedBox(height: 16),
    ],

    if (d.pmsHistory.isNotEmpty) ...[
      _drSectionTitle('PMS HISTORY'),
      _pmsHistoryCard(d, doctor: true),
      pw.SizedBox(height: 16),
    ],

    pw.SizedBox(height: 10),
    _disclaimer(doctor: true),
  ];
}

// ─── Clinical Summary Card (Doctor only) ─────────────────────────────────────

pw.Widget _clinicalSummaryCard(ReportData d) {
  // Cycle regularity: std dev of cycle lengths
  final lengths = d.cycleHistory
      .map((c) => c['cycleLength'] as int?)
      .whereType<int>()
      .toList();
  final String regularity;
  double? avgLen;
  double? stdDev;
  if (lengths.isNotEmpty) {
    avgLen = lengths.reduce((a, b) => a + b) / lengths.length;
    final variance = lengths.map((l) => math.pow(l - avgLen!, 2)).reduce((a, b) => a + b) / lengths.length;
    stdDev = math.sqrt(variance);
    regularity = stdDev <= 3 ? 'Regular' : stdDev <= 7 ? 'Mildly Irregular' : 'Irregular';
  } else {
    regularity = 'Insufficient data';
  }

  // Flow consistency
  final flows = d.cycleHistory
      .map((c) => c['flowIntensity'] as String?)
      .whereType<String>()
      .toList();
  final flowConsistency = flows.isEmpty
      ? '—'
      : flows.toSet().length == 1
          ? 'Consistent (${flows.first})'
          : 'Variable (${flows.toSet().join(' / ')})';

  // Recurring symptoms (logged 2+ times)
  final recurring = d.symptomFrequency
      .where((s) => (s['count'] as int? ?? 0) >= 2)
      .map((s) => '${s['name']} (avg ${s['avgSeverity']}/10, ${s['count']}x)')
      .toList();

  final rows = <Map<String, String>>[
    {'label': 'Cycle Regularity',         'value': regularity},
    if (avgLen != null)
      {'label': 'Average Cycle Length',   'value': '${avgLen.toStringAsFixed(1)} days ${stdDev != null ? "(+/- ${stdDev.toStringAsFixed(1)} days)" : ""}'},
    {'label': 'Current Phase',            'value': _capPhase(d.currentPhase)},
    {'label': 'Predicted Cycle Length',   'value': d.predictedCycleLength != null ? '${d.predictedCycleLength} days' : '—'},
    {'label': 'Prediction Confidence',    'value': d.confidenceScore != null ? '${(d.confidenceScore! * 100).round()}%' : '—'},
    {'label': 'Next Period Estimate',     'value': _fmtDate(d.nextPeriodDate)},
    {'label': 'Flow Consistency',         'value': flowConsistency},
    {'label': 'Average Sleep',            'value': d.avgSleep != null ? '${d.avgSleep!.toStringAsFixed(1)} hrs/night' : '—'},
    {'label': 'Average Stress',           'value': d.avgStress != null ? '${d.avgStress!.toStringAsFixed(1)}/10' : '—'},
    {'label': 'PMS Risk Level',           'value': (d.pmsRiskLevel ?? 'Unknown').toUpperCase()},
    {'label': 'Anomalies Flagged',        'value': d.anomalyAlerts.isEmpty ? 'None' : '${d.anomalyAlerts.length} alert(s)'},
  ];

  return _card(
    bg: _drLight,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Table(
          columnWidths: {
            0: const pw.FixedColumnWidth(170),
            1: const pw.FlexColumnWidth(),
          },
          children: rows.map((r) => pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(r['label']!, style: const pw.TextStyle(fontSize: 10, color: _drGrey)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(r['value']!,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _drText)),
            ),
          ])).toList(),
        ),
        if (recurring.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Divider(color: _drMid, thickness: 0.5),
          pw.SizedBox(height: 6),
          pw.Text('Recurring Symptoms:', style: const pw.TextStyle(fontSize: 9, color: _drGrey)),
          pw.SizedBox(height: 4),
          ...recurring.map((s) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text('  - $s', style: const pw.TextStyle(fontSize: 9, color: _drText)),
          )),
        ],
      ],
    ),
  );
}

// ─── Cycle History Table ──────────────────────────────────────────────────────

pw.Widget _cycleHistoryCard(ReportData d, {bool doctor = false}) {
  final accent = doctor ? _drAccent : _purple;
  final bg     = doctor ? _drLight  : _purpleLight;

  final headers = ['Cycle', 'Start Date', 'Length', 'Period', 'Flow'];
  return _card(
    bg: bg,
    child: pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(46),
        1: const pw.FixedColumnWidth(80),
        2: const pw.FixedColumnWidth(60),
        3: const pw.FixedColumnWidth(56),
        4: const pw.FlexColumnWidth(),
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: pw.BoxDecoration(color: accent),
          children: headers.map((h) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: pw.Text(h,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _white)),
          )).toList(),
        ),
        // Data rows
        ...d.cycleHistory.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value;
          final bg2 = i.isEven ? _white : (doctor ? const PdfColor.fromInt(0xFFFAFAFA) : _purpleLight);
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: bg2),
            children: [
              _tCell('Cycle ${d.cycleHistory.length - i}'),
              _tCell(_fmtDate(c['startDate'] as String?)),
              _tCell(c['cycleLength'] != null ? '${c['cycleLength']} days' : '—'),
              _tCell(c['periodLength'] != null ? '${c['periodLength']} days' : '—'),
              _tCell(_capPhase(c['flowIntensity'] as String?)),
            ],
          );
        }),
      ],
    ),
  );
}

pw.Widget _tCell(String text) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  child: pw.Text(text, style: const pw.TextStyle(fontSize: 9, color: _textDark)),
);

// ─── Symptom Frequency ────────────────────────────────────────────────────────

pw.Widget _symptomFrequencyCard(ReportData d, {bool doctor = false}) {
  final accent = doctor ? _drAccent : _purple;
  final bg     = doctor ? _drLight  : _purpleLight;

  return _card(
    bg: bg,
    child: pw.Column(
      children: d.symptomFrequency.take(8).map((s) {
        final name  = s['name'] as String? ?? '';
        final sev   = (s['avgSeverity'] as num?)?.toDouble() ?? 0;
        final count = s['count'] as int? ?? 0;
        final frac  = (sev / 10).clamp(0.01, 1.0);
        final filled = (frac * 100).round().clamp(1, 99);

        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(children: [
            pw.SizedBox(
              width: 100,
              child: pw.Text(name,
                style: const pw.TextStyle(fontSize: 9, color: _textDark)),
            ),
            pw.Expanded(
              child: pw.Row(children: [
                pw.Expanded(
                  flex: filled,
                  child: pw.Container(
                    height: 8,
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 100 - filled,
                  child: pw.Container(
                    height: 8,
                    color: doctor ? _drMid : _purpleMid,
                  ),
                ),
              ]),
            ),
            pw.SizedBox(width: 8),
            pw.SizedBox(
              width: 70,
              child: pw.Text(
                '${sev.toStringAsFixed(1)}/10  (${count}x)',
                style: const pw.TextStyle(fontSize: 8, color: _textGrey),
              ),
            ),
          ]),
        );
      }).toList(),
    ),
  );
}

// ─── Prediction Accuracy ─────────────────────────────────────────────────────

pw.Widget _predictionAccuracyCard(ReportData d, {bool doctor = false}) {
  final bg = doctor ? _drLight : _purpleLight;

  return _card(
    bg: bg,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        ...d.predictionAccuracy.take(6).map((row) {
          final offBy  = (row['offBy'] as int?) ?? 0;
          final isGood = offBy.abs() <= 2;
          final color  = isGood ? (doctor ? _drAccent : _green) : (doctor ? _drGrey : _amber);
          final tick   = isGood ? 'Good' : 'Off';

          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(children: [
              pw.SizedBox(
                width: 80,
                child: pw.Text(row['cycleLabel'] as String? ?? '',
                  style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
              ),
              pw.Expanded(
                child: pw.Text(
                  'Predicted ${row['predicted']} days  →  Actual ${row['actual']} days',
                  style: const pw.TextStyle(fontSize: 9, color: _textDark),
                ),
              ),
              pw.Container(
                decoration: pw.BoxDecoration(
                  color        : color,
                  borderRadius : const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: pw.Text(
                  offBy == 0 ? 'Exact  $tick' : 'Off by $offBy day${offBy.abs() == 1 ? '' : 's'}  $tick',
                  style: const pw.TextStyle(fontSize: 7, color: _white),
                ),
              ),
            ]),
          );
        }),
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: const pw.BoxDecoration(
            color: _white,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            'Predicted values are the running average of prior cycles — '
            'showing how the model improves as more data is logged.',
            style: pw.TextStyle(fontSize: 8, color: _textGrey, fontStyle: pw.FontStyle.italic),
          ),
        ),
      ],
    ),
  );
}

// ─── Ovulation Confirmation ───────────────────────────────────────────────────

pw.Widget _ovulationConfirmCard(ReportData d, {bool doctor = false}) {
  final bg = doctor ? _drLight : _tealLight;

  return _card(
    bg: bg,
    child: pw.Column(
      children: d.ovulationConfirmations.take(6).map((ov) {
        final daysOff   = ov['daysOff'] as int?;
        final accurate  = daysOff != null && daysOff.abs() <= 1;
        final color     = accurate ? (doctor ? _drAccent : _teal) : (doctor ? _drGrey : _amber);
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Predicted: ${_fmtDate(ov['predictedDate'] as String?)}',
                    style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
                  pw.Text('Confirmed: ${_fmtDate(ov['userDate'] as String?)}',
                    style: pw.TextStyle(fontSize: 9, color: _textDark, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            if (daysOff != null)
              pw.Container(
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: pw.Text(
                  daysOff == 0 ? 'Exact' : '${daysOff.abs()} day${daysOff.abs() == 1 ? '' : 's'} ${daysOff > 0 ? 'late' : 'early'}',
                  style: const pw.TextStyle(fontSize: 8, color: _white),
                ),
              ),
          ]),
        );
      }).toList(),
    ),
  );
}

// ─── Sleep Trend ─────────────────────────────────────────────────────────────

pw.Widget _sleepTrendCard(ReportData d, {bool doctor = false}) {
  final bg    = doctor ? _drLight : _purpleLight;
  final accent= doctor ? _drAccent : _purple;

  final under6 = d.sleepNightsUnder6 ?? 0;
  final total  = d.sleepTrend.length;
  final dir    = d.sleepTrendDirection ?? 'stable';
  final arrow  = dir == 'improving' ? '(Improving)' : dir == 'declining' ? '(Declining)' : '(Stable)';

  return _card(
    bg: bg,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _miniRow('Average', d.avgSleep != null ? '${d.avgSleep!.toStringAsFixed(1)} hrs/night' : '—'),
                _miniRow('Nights under 6 hrs',
                    total > 0 ? '$under6 out of $total nights' : (d.sleepNightsUnder6 != null ? '$under6 nights' : '—')),
                _miniRow('Trend', '$dir $arrow'),
              ],
            ),
          ),
          // Mini bar chart — last 14 nights
          if (d.sleepTrend.isNotEmpty)
            pw.SizedBox(
              width: 120, height: 40,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: d.sleepTrend.reversed.take(14).toList().reversed.map((pt) {
                  final h = (pt['hours'] as num?)?.toDouble() ?? 0;
                  final barH = (h / 10 * 36).clamp(2.0, 36.0);
                  final isLow = h < 6;
                  return pw.Container(
                    width: 6,
                    height: barH,
                    color: isLow ? (doctor ? _drGrey : _amber) : accent,
                  );
                }).toList(),
              ),
            ),
        ]),
      ],
    ),
  );
}

// ─── Mood by Phase ────────────────────────────────────────────────────────────

pw.Widget _moodByPhaseCard(ReportData d, {bool doctor = false}) {
  final bg     = doctor ? _drLight : _purpleLight;
  final accent = doctor ? _drAccent : _purple;

  const phaseOrder = ['menstrual', 'follicular', 'ovulation', 'luteal'];
  final phases = phaseOrder.where((p) => d.moodByPhase.containsKey(p)).toList();

  return _card(
    bg: bg,
    child: pw.Column(
      children: phases.map((phase) {
        final avg      = d.moodByPhase[phase] ?? 0.0;
        final label    = avg > 0.3 ? 'Good' : avg > -0.1 ? 'Neutral' : avg > -0.4 ? 'Low' : 'Poor';
        final isBest   = phase == d.bestMoodPhase;
        final frac     = ((avg + 1) / 2).clamp(0.05, 0.95);
        final filled   = (frac * 100).round().clamp(1, 99);

        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(children: [
            pw.SizedBox(
              width: 90,
              child: pw.Row(children: [
                pw.Text(_capPhase(phase),
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: _textDark,
                    fontWeight: isBest ? pw.FontWeight.bold : pw.FontWeight.normal,
                  )),
                if (isBest)
                  pw.Text(' (best)',
                    style: pw.TextStyle(fontSize: 7, color: accent)),
              ]),
            ),
            pw.Expanded(
              child: pw.Row(children: [
                pw.Expanded(
                  flex: filled,
                  child: pw.Container(
                    height: 8,
                    decoration: pw.BoxDecoration(
                      color: accent,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 100 - filled,
                  child: pw.Container(height: 8, color: doctor ? _drMid : _purpleMid),
                ),
              ]),
            ),
            pw.SizedBox(width: 8),
            pw.SizedBox(
              width: 50,
              child: pw.Text(label,
                style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
            ),
          ]),
        );
      }).toList(),
    ),
  );
}

// ─── PMS History ──────────────────────────────────────────────────────────────

pw.Widget _pmsHistoryCard(ReportData d, {bool doctor = false}) {
  final bg = doctor ? _drLight : _amberLight;

  // Summary stats
  final correct = d.pmsHistory.where((p) => p['arrivedAsPredicted'] == true).length;
  final total   = d.pmsHistory.length;
  final accuracyStr = total > 0 ? '$correct/$total cycles predicted correctly' : '—';

  final severities = d.pmsHistory
      .map((p) => p['severity'] as int?)
      .whereType<int>()
      .toList();
  String trend = '—';
  if (severities.length >= 3) {
    final first = severities.take(3).reduce((a, b) => a + b) / 3;
    final last  = severities.reversed.take(3).reduce((a, b) => a + b) / 3;
    trend = last > first + 0.5 ? 'Worsening' : last < first - 0.5 ? 'Improving' : 'Stable';
  }

  return _card(
    bg: bg,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          pw.Expanded(child: _miniRow('Prediction Accuracy', accuracyStr)),
          pw.Expanded(child: _miniRow('Severity Trend', trend)),
        ]),
        pw.SizedBox(height: 8),
        pw.Table(
          columnWidths: {
            0: const pw.FixedColumnWidth(60),
            1: const pw.FlexColumnWidth(),
            2: const pw.FixedColumnWidth(60),
          },
          children: [
            pw.TableRow(children: [
              _tCell('Cycle'),
              _tCell('PMS Arrived as Predicted?'),
              _tCell('Severity'),
            ]),
            ...d.pmsHistory.take(6).toList().asMap().entries.map((e) {
              final p     = e.value;
              final ok    = p['arrivedAsPredicted'] == true;
              final sev   = p['severity'] as int?;
              return pw.TableRow(children: [
                _tCell(p['cycleLabel'] as String? ?? 'Cycle ${e.key + 1}'),
                _tCell(ok ? 'Yes' : 'No'),
                _tCell(sev != null ? '$sev/5' : '—'),
              ]);
            }),
          ],
        ),
      ],
    ),
  );
}

// ─── Existing cards (fixed for emoji + doctor) ────────────────────────────────

pw.Widget _cyclePredictionCard(ReportData d) {
  final rows = <Map<String, String>>[
    {'label': 'Current Phase',            'value': _capPhase(d.currentPhase)},
    {'label': 'Cycle Day',                'value': d.currentCycleDay != null ? 'Day ${d.currentCycleDay}' : '—'},
    {'label': 'Predicted Cycle Length',   'value': d.predictedCycleLength != null ? '${d.predictedCycleLength} days' : '—'},
    {'label': 'Actual Last Cycle Length', 'value': d.actualLastCycleLength != null ? '${d.actualLastCycleLength} days' : '—'},
    {'label': 'Next Period',              'value': _fmtDate(d.nextPeriodDate)},
    {'label': 'Days Until Period',        'value': d.daysUntilPeriod != null ? '${d.daysUntilPeriod} days' : '—'},
    {'label': 'Prediction Confidence',    'value': d.confidenceScore != null ? '${(d.confidenceScore! * 100).round()}%' : '—'},
    {'label': 'Model',                    'value': d.predictionMethod?.replaceAll('_', ' ').toUpperCase() ?? '—'},
  ];
  return _card(
    child: pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(160),
        1: const pw.FlexColumnWidth(),
      },
      children: rows.map((r) => pw.TableRow(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Text(r['label']!, style: const pw.TextStyle(fontSize: 10, color: _textGrey)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Text(r['value']!,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _textDark)),
        ),
      ])).toList(),
    ),
  );
}

pw.Widget _fertileCard(ReportData d) {
  return _card(
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        _statBlock('Fertile Window Opens',  _fmtDate(d.fertileWindowStart)),
        _divider(),
        _statBlock('Ovulation Day',         _fmtDate(d.ovulationDate)),
        _divider(),
        _statBlock('Fertile Window Closes', _fmtDate(d.fertileWindowEnd)),
      ],
    ),
  );
}

pw.Widget _pmsCard(ReportData d) {
  final level = (d.pmsRiskLevel ?? 'unknown').toLowerCase();
  final color = level == 'high' ? _red : level == 'medium' ? _amber : _green;
  final bg    = level == 'high' ? _redLight : level == 'medium' ? _amberLight : _greenLight;

  return _card(
    bg: bg,
    child: pw.Row(children: [
      pw.Expanded(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Risk Level', style: const pw.TextStyle(fontSize: 10, color: _textGrey)),
          pw.SizedBox(height: 4),
          pw.Text(level.toUpperCase(),
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
          if (d.pmsRiskScore != null)
            pw.Text('Score: ${(d.pmsRiskScore! * 100).round()}%',
              style: const pw.TextStyle(fontSize: 10, color: _textGrey)),
        ],
      )),
      pw.Expanded(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Peak PMS Date', style: const pw.TextStyle(fontSize: 10, color: _textGrey)),
          pw.SizedBox(height: 4),
          pw.Text(_fmtDate(d.pmsPeakDate),
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _textDark)),
        ],
      )),
    ]),
  );
}

pw.Widget _healthScoreCard(ReportData d) {
  final score = d.healthScore ?? 0.0;
  final pct   = (score * 100).round();
  final color = pct >= 70 ? _green : pct >= 45 ? _amber : _red;

  return _card(
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 70, height: 70,
          decoration: pw.BoxDecoration(
            border       : pw.Border.all(color: color, width: 3),
            borderRadius : const pw.BorderRadius.all(pw.Radius.circular(35)),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text('$pct%',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _miniRow('Avg Sleep',  d.avgSleep  != null ? '${d.avgSleep!.toStringAsFixed(1)} hrs' : '—'),
            _miniRow('Avg Stress', d.avgStress != null ? '${d.avgStress!.toStringAsFixed(1)}/10' : '—'),
            _miniRow('Top Mood',   d.topMood   ?? '—'),
          ],
        )),
      ],
    ),
  );
}

pw.Widget _kalmanSentimentCard(ReportData d) {
  final stress = (d.sentimentStressLevel ?? 'unknown').toLowerCase();
  final PdfColor bg;
  final PdfColor accentColor;
  final String stressLabel;
  switch (stress) {
    case 'high':
      bg = _redLight; accentColor = _red; stressLabel = 'HIGH — Elevated cycle uncertainty';
    case 'moderate':
      bg = _amberLight; accentColor = _amber; stressLabel = 'MODERATE — Some prediction caution';
    case 'low':
      bg = _greenLight; accentColor = _green; stressLabel = 'LOW — Cycle well-modelled';
    case 'positive':
      bg = _tealLight; accentColor = _teal; stressLabel = 'POSITIVE — Optimal predictability';
    default:
      bg = _purpleLight; accentColor = _purple; stressLabel = 'No journal data yet';
  }

  final nCycles   = d.kalmanNObservations ?? 0;
  final kalmanPct = nCycles == 0
      ? 'XGBoost only (no personal cycles yet)'
      : nCycles < 3
          ? '$nCycles cycle${nCycles == 1 ? '' : 's'} — still building personal model'
          : '$nCycles cycles — personal Kalman active';
  final sentPct = d.avgJournalSentiment != null
      ? '${(d.avgJournalSentiment! * 100).round() > 0 ? '+' : ''}${(d.avgJournalSentiment! * 100).round()}%'
      : '—';
  final varianceEffect = d.sentimentVarianceEffect != null && d.sentimentVarianceEffect! > 0
      ? '-${d.sentimentVarianceEffect!.toStringAsFixed(1)}% confidence'
      : 'None';
  final stdText = d.kalmanStd != null ? '+/-${d.kalmanStd!.toStringAsFixed(1)} days' : '—';

  return _card(
    bg: bg,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Emotional Stress Level', style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
              pw.SizedBox(height: 3),
              pw.Text(stressLabel,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: accentColor)),
            ],
          )),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Prediction Spread', style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
              pw.SizedBox(height: 3),
              pw.Text(stdText,
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _textDark)),
            ],
          ),
        ]),
        pw.SizedBox(height: 10),
        pw.Divider(color: accentColor, thickness: 0.5),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _miniRow('Avg Journal Sentiment', sentPct),
              _miniRow('Stress Effect on Confidence', varianceEffect),
            ],
          )),
          pw.SizedBox(width: 12),
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _miniRow('Personal Cycles Logged', kalmanPct),
            ],
          )),
        ]),
        pw.SizedBox(height: 10),
        pw.Container(
          decoration: const pw.BoxDecoration(
            color: _white,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            'EVA uses your journal entries to continuously refine its cycle predictions. '
            'Chronic negative sentiment (stress) is known to disrupt ovulation timing via '
            'the HPA-cortisol pathway, so EVA widens its uncertainty range accordingly — '
            'giving you a more honest confidence score rather than a false sense of precision.',
            style: pw.TextStyle(fontSize: 8, color: _textGrey, fontStyle: pw.FontStyle.italic),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _emotionsCard(ReportData d) {
  final sorted = d.topEmotions.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final max = sorted.isEmpty ? 1 : sorted.first.value;

  return _card(
    child: pw.Column(
      children: sorted.take(5).map((e) {
        final frac   = e.value / max;
        final filled = (frac * 100).round().clamp(1, 99);
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(children: [
            pw.SizedBox(
              width: 90,
              child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 10, color: _textDark)),
            ),
            pw.Expanded(
              child: pw.Row(children: [
                pw.Expanded(
                  flex: filled,
                  child: pw.Container(
                    height: 10,
                    decoration: const pw.BoxDecoration(
                      color        : _purple,
                      borderRadius : pw.BorderRadius.all(pw.Radius.circular(5)),
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 100 - filled,
                  child: pw.Container(
                    height: 10,
                    decoration: const pw.BoxDecoration(
                      color        : _purpleLight,
                      borderRadius : pw.BorderRadius.all(pw.Radius.circular(5)),
                    ),
                  ),
                ),
              ]),
            ),
            pw.SizedBox(width: 6),
            pw.Text('${e.value}x', style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
          ]),
        );
      }).toList(),
    ),
  );
}

pw.Widget _insightCard(ReportData d) {
  return _card(
    bg: const PdfColor.fromInt(0xFFF3E5F5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 4, height: 40,
          color: _purple,
          margin: const pw.EdgeInsets.only(right: 10),
        ),
        pw.Expanded(
          child: pw.Text(d.aiInsight!,
            style: pw.TextStyle(fontSize: 11, color: _textDark, fontStyle: pw.FontStyle.italic)),
        ),
      ],
    ),
  );
}

pw.Widget _anomalyCard(ReportData d, {bool doctor = false}) {
  return pw.Column(
    children: d.anomalyAlerts.map((a) {
      final sev   = a['severity'] as String? ?? 'low';
      final bg    = doctor
          ? _drLight
          : sev == 'high' ? _redLight : sev == 'medium' ? _amberLight : _purpleLight;
      final color = doctor
          ? _drAccent
          : sev == 'high' ? _red : sev == 'medium' ? _amber : _purple;
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        child : _card(
          bg: bg,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(children: [
                pw.Container(
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const pw.EdgeInsets.only(right: 8),
                  child: pw.Text(sev.toUpperCase(),
                    style: pw.TextStyle(fontSize: 7, color: _white, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Text(a['title'] ?? '',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
              ]),
              pw.SizedBox(height: 4),
              pw.Text(a['message'] ?? '',
                style: const pw.TextStyle(fontSize: 10, color: _textDark)),
            ],
          ),
        ),
      );
    }).toList(),
  );
}

pw.Widget _phaseTasksCard(ReportData d) {
  final high   = d.phaseTasks.where((t) => t['priority'] == 'high').toList();
  final medium = d.phaseTasks.where((t) => t['priority'] == 'medium').toList();
  final rows   = [...high, ...medium].take(6).toList();

  return _card(
    child: pw.Column(
      children: rows.map((t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              decoration: pw.BoxDecoration(
                color        : t['priority'] == 'high' ? _purple : _purpleMid,
                borderRadius : const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const pw.EdgeInsets.only(right: 8, top: 1),
              child: pw.Text(
                (t['priority'] as String? ?? '').toUpperCase(),
                style: const pw.TextStyle(fontSize: 7, color: _white),
              ),
            ),
            pw.Expanded(
              child: pw.Text(t['task'] ?? '',
                style: const pw.TextStyle(fontSize: 10, color: _textDark)),
            ),
          ],
        ),
      )).toList(),
    ),
  );
}

// ─── Header & Footer ─────────────────────────────────────────────────────────

pw.Widget _header(String username, String date, {bool doctor = false}) {
  if (doctor) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _drAccent, width: 1.5)),
      ),
      padding : const pw.EdgeInsets.only(bottom: 10),
      margin  : const pw.EdgeInsets.only(bottom: 18),
      child   : pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('EVA HEALTH REPORT — CLINICAL SUMMARY',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _drAccent)),
              pw.Text('Patient: $username',
                style: const pw.TextStyle(fontSize: 10, color: _drGrey)),
            ],
          ),
          pw.Text(date, style: const pw.TextStyle(fontSize: 9, color: _drGrey)),
        ],
      ),
    );
  }

  return pw.Container(
    decoration: const pw.BoxDecoration(
      color        : _purple,
      borderRadius : pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    padding : const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    margin  : const pw.EdgeInsets.only(bottom: 20),
    child   : pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('EVA Health Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _white)),
            pw.SizedBox(height: 4),
            pw.Text('Prepared for $username',
              style: const pw.TextStyle(fontSize: 11, color: _purpleLight)),
          ],
        ),
        pw.Text(date, style: const pw.TextStyle(fontSize: 10, color: _purpleLight)),
      ],
    ),
  );
}

pw.Widget _footer(pw.Context ctx, {bool doctor = false}) {
  return pw.Container(
    alignment: pw.Alignment.centerRight,
    margin   : const pw.EdgeInsets.only(top: 8),
    child    : pw.Text(
      'EVA App  -  Page ${ctx.pageNumber} of ${ctx.pagesCount}  -  Private & Confidential',
      style: const pw.TextStyle(fontSize: 8, color: _textGrey),
    ),
  );
}

// ─── Section titles ───────────────────────────────────────────────────────────

pw.Widget _sectionTitle(String title) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(children: [
      pw.Container(width: 4, height: 16, color: _purple),
      pw.SizedBox(width: 8),
      pw.Text(title,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _purple)),
    ]),
  );
}

pw.Widget _drSectionTitle(String title) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(children: [
      pw.Container(width: 4, height: 14, color: _drAccent),
      pw.SizedBox(width: 8),
      pw.Text(title,
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _drAccent,
          letterSpacing: 0.8)),
    ]),
  );
}

// ─── Card shell ───────────────────────────────────────────────────────────────

pw.Widget _card({required pw.Widget child, PdfColor bg = _purpleLight}) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      color        : bg,
      borderRadius : const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    padding: const pw.EdgeInsets.all(14),
    child  : child,
  );
}

// ─── Disclaimer ───────────────────────────────────────────────────────────────

pw.Widget _disclaimer({bool doctor = false}) {
  final text = doctor
      ? 'This report contains patient-reported data from the EVA AI wellness tracking system. '
        'It is not a clinical diagnosis. Data reflects user self-reporting and AI estimation only. '
        'Consult clinical records and professional judgement before making medical decisions.'
      : 'Disclaimer: This report is generated by the EVA AI system for personal wellness '
        'tracking only. It is not a medical diagnosis. Consult a qualified healthcare '
        'professional for medical advice, diagnosis, or treatment.';

  return pw.Container(
    decoration: pw.BoxDecoration(
      border       : pw.Border.all(color: _textGrey, width: 0.5),
      borderRadius : const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    padding: const pw.EdgeInsets.all(10),
    child  : pw.Text(text,
      style: pw.TextStyle(fontSize: 8, color: _textGrey, fontStyle: pw.FontStyle.italic)),
  );
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

pw.Widget _statBlock(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(value,
        style    : pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _purple),
        textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 4),
      pw.Text(label,
        style    : const pw.TextStyle(fontSize: 8, color: _textGrey),
        textAlign: pw.TextAlign.center),
    ],
  );
}

pw.Widget _divider() => pw.Container(width: 0.5, height: 36, color: _purpleMid);

pw.Widget _miniRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(children: [
      pw.Text('$label:  ', style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
      pw.Flexible(
        child: pw.Text(value,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _textDark),
          maxLines: 2),
      ),
    ]),
  );
}

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return DateFormat('MMM d, yyyy').format(DateTime.parse(iso));
  } catch (_) { return iso; }
}

String _capPhase(String? phase) {
  if (phase == null || phase.isEmpty) return '—';
  return phase[0].toUpperCase() + phase.substring(1);
}
