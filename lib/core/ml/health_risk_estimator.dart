library health_risk_estimator;

import 'dart:math' as math;

// ──────────────────────────────────────────────────────────────────────────────
//  Input context
// ──────────────────────────────────────────────────────────────────────────────

class RiskAssessmentInput {
  final List<Map<String, dynamic>> cycleHistory;

  final List<Map<String, dynamic>> symptomHistory;

  final List<Map<String, dynamic>> moodHistory;

  final double avgJournalSentiment;

  final double bmi;

  const RiskAssessmentInput({
    required this.cycleHistory,
    required this.symptomHistory,
    required this.moodHistory,
    this.avgJournalSentiment = 0.0,
    this.bmi                 = 22.0,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
//  Output
// ──────────────────────────────────────────────────────────────────────────────

class HealthRiskResult {
  final double       irregularCycleRisk;
  final double       pcosProbability;
  final double       hormonalImbalanceIndicator;
  final double       anemiaRisk;
  final String       riskLevel;            // 'low' | 'medium' | 'high'
  final List<String> recommendations;
  final bool         medicalConsultationRecommended;
  final int          cycleCount;
  final String       dataQuality;          // 'no_data' | 'building' | 'good'
  static const String disclaimer =
      'This is NOT a medical diagnosis. Consult a healthcare provider for concerns.';

  const HealthRiskResult({
    required this.irregularCycleRisk,
    required this.pcosProbability,
    required this.hormonalImbalanceIndicator,
    required this.anemiaRisk,
    required this.riskLevel,
    required this.recommendations,
    required this.medicalConsultationRecommended,
    required this.cycleCount,
    required this.dataQuality,
  });

  Map<String, dynamic> toMap() => {
    'irregular_cycle_risk'           : irregularCycleRisk,
    'pcos_pattern_probability'       : pcosProbability,
    'hormonal_imbalance_indicator'   : hormonalImbalanceIndicator,
    'anemia_risk'                    : anemiaRisk,
    'risk_level'                     : riskLevel,
    'recommendations'                : recommendations,
    'medical_consultation_recommended': medicalConsultationRecommended,
    'cycle_count'                    : cycleCount,
    'data_quality'                   : dataQuality,
    'disclaimer'                     : disclaimer,
  };
}

// ──────────────────────────────────────────────────────────────────────────────
//  HealthRiskEstimator
// ──────────────────────────────────────────────────────────────────────────────

class HealthRiskEstimator {

  HealthRiskResult assess(RiskAssessmentInput input) {
    final features = _extractFeatures(input);

    final irregularRisk = _irregularCycleRisk(features);
    final pcosRisk      = _pcosPatternRisk(features);
    final hormonalRisk  = _hormonalImbalanceRisk(features);
    final anemiaRisk    = _anemiaRisk(features);

    final maxRisk = [irregularRisk, pcosRisk, hormonalRisk, anemiaRisk]
        .reduce(math.max);

    String riskLevel;
    if (maxRisk > 0.65) {
      riskLevel = 'high';
    } else if (maxRisk > 0.35) riskLevel = 'medium';
    else                     riskLevel = 'low';

    final cycleCount = features['cycle_count'] as int;
    final recommendations = _buildRecommendations(
      irregularRisk, pcosRisk, hormonalRisk, anemiaRisk, cycleCount,
    );

    String dataQuality;
    if (cycleCount >= 3) {
      dataQuality = 'good';
    } else if (cycleCount >= 1) dataQuality = 'building';
    else                      dataQuality = 'no_data';

    return HealthRiskResult(
      irregularCycleRisk:             double.parse(irregularRisk.toStringAsFixed(3)),
      pcosProbability:                double.parse(pcosRisk.toStringAsFixed(3)),
      hormonalImbalanceIndicator:     double.parse(hormonalRisk.toStringAsFixed(3)),
      anemiaRisk:                     double.parse(anemiaRisk.toStringAsFixed(3)),
      riskLevel:                      riskLevel,
      recommendations:                recommendations,
      medicalConsultationRecommended: maxRisk > 0.55,
      cycleCount:                     cycleCount,
      dataQuality:                    dataQuality,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Feature extraction
  // ──────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _extractFeatures(RiskAssessmentInput input) {
    final cycles = input.cycleHistory;
    final cycleLengths = cycles
        .map((c) => c['cycle_length'])
        .whereType<int>()
        .map((l) => l.toDouble())
        .toList();

    final cycleStd    = cycleLengths.length >= 2 ? _std(cycleLengths) : 0.0;
    final avgCycleLen = cycleLengths.isNotEmpty  ? _avg(cycleLengths) : 28.0;

    final heavyFlowCount = cycles
        .where((c) => c['flow_intensity'] == 'heavy')
        .length;
    final heavyFlowRate = cycles.isNotEmpty
        ? heavyFlowCount / cycles.length : 0.0;

    // Symptom frequency map
    final symptomFreq = <String, int>{};
    for (final s in input.symptomHistory) {
      final t = s['symptom_type'] as String?;
      if (t != null) symptomFreq[t] = (symptomFreq[t] ?? 0) + 1;
    }

    // Mood volatility
    const negativeMoods = {'sad', 'anxious', 'irritable', 'stressed', 'depressed'};
    final moodLogs = input.moodHistory;
    final negativeCount = moodLogs
        .where((m) => negativeMoods.contains(m['primary_mood']))
        .length;
    final moodVolatility = moodLogs.isNotEmpty
        ? negativeCount / moodLogs.length : 0.0;

    return {
      'cycle_std'            : cycleStd,
      'avg_cycle_length'     : avgCycleLen,
      'heavy_flow_rate'      : heavyFlowRate,
      'symptom_frequency'    : symptomFreq,
      'mood_volatility'      : moodVolatility,
      'avg_journal_sentiment': input.avgJournalSentiment,
      'avg_bmi'              : input.bmi,
      'cycle_count'          : cycleLengths.length,
      'raw_cycle_count'      : cycles.length,
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Risk components (tuned to match Python thresholds exactly)
  // ──────────────────────────────────────────────────────────────────────────

  double _irregularCycleRisk(Map<String, dynamic> f) {
    final cycleCount = f['cycle_count'] as int;
    if (cycleCount == 0) return 0.0;

    double risk = 0.0;
    final std    = f['cycle_std'] as double;
    final avgLen = f['avg_cycle_length'] as double;

    // Variability score
    if (std > 7) {
      risk += 0.55;
    } else if (std > 4) risk += 0.35;
    else if (std > 2) risk += 0.15;

    // Out-of-normal-range cycle length
    if (avgLen < 21 || avgLen > 38) {
      risk += 0.45;
    } else if (avgLen < 24 || avgLen > 35) risk += 0.25;
    else if (avgLen < 26 || avgLen > 32) risk += 0.10;

    return math.min(1.0, risk);
  }

  double _pcosPatternRisk(Map<String, dynamic> f) {
    final cycleCount = f['cycle_count'] as int;
    if (cycleCount == 0) return 0.0;

    double risk = 0.0;
    final std         = f['cycle_std'] as double;
    final avgLen      = f['avg_cycle_length'] as double;
    final bmi         = f['avg_bmi'] as double;
    final symptomFreq = f['symptom_frequency'] as Map<String, int>;
    final sentiment   = f['avg_journal_sentiment'] as double;

    if (std > 5) {
      risk += 0.30;
    } else if (std > 2) risk += 0.10;

    if (avgLen > 38) {
      risk += 0.35;
    } else if (avgLen > 33) risk += 0.15;

    if (bmi > 27) risk += 0.20;

    if ((symptomFreq['acne'] ?? 0) >= 2)        risk += 0.20;
    if ((symptomFreq['mood_swings'] ?? 0) >= 2) risk += 0.10;
    if (sentiment < -0.4)                       risk += 0.10;

    return math.min(1.0, risk);
  }

  double _hormonalImbalanceRisk(Map<String, dynamic> f) {
    double risk = 0.0;
    final moodVol     = f['mood_volatility'] as double;
    final sentiment   = f['avg_journal_sentiment'] as double;
    final std         = f['cycle_std'] as double;
    final symptomFreq = f['symptom_frequency'] as Map<String, int>;

    // Mood volatility
    if (moodVol > 0.5) {
      risk += 0.35;
    } else if (moodVol > 0.3) risk += 0.15;

    // Journal sentiment
    if (sentiment < -0.5) {
      risk += 0.30;
    } else if (sentiment < -0.25) risk += 0.15;
    else if (sentiment < -0.1)  risk += 0.05;

    // Cycle irregularity
    if (std > 4) {
      risk += 0.25;
    } else if (std > 2) risk += 0.10;

    // Multiple hormonal symptoms
    const hormonalSymptoms = [
      'mood_swings', 'acne', 'breast_tenderness', 'bloating', 'insomnia',
    ];
    final hormonalCount = hormonalSymptoms
        .where((s) => (symptomFreq[s] ?? 0) >= 2)
        .length;
    if (hormonalCount >= 3) {
      risk += 0.30;
    } else if (hormonalCount >= 2) risk += 0.15;
    else if (hormonalCount >= 1) risk += 0.05;

    return math.min(1.0, risk);
  }

  double _anemiaRisk(Map<String, dynamic> f) {
    double risk = 0.0;
    final heavyFlowRate = f['heavy_flow_rate'] as double;
    final symptomFreq   = f['symptom_frequency'] as Map<String, int>;

    if (heavyFlowRate > 0.4) {
      risk += 0.45;
    } else if (heavyFlowRate > 0.2) risk += 0.20;

    final fatigueCount = symptomFreq['fatigue'] ?? 0;
    if (fatigueCount >= 3) {
      risk += 0.35;
    } else if (fatigueCount >= 1) risk += 0.15;

    return math.min(1.0, risk);
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Recommendations
  // ──────────────────────────────────────────────────────────────────────────

  List<String> _buildRecommendations(
    double irregularRisk,
    double pcosRisk,
    double hormonalRisk,
    double anemiaRisk,
    int cycleCount,
  ) {
    if (cycleCount < 2) {
      return [
        'Log at least 2–3 cycle start dates so EVA can calculate your personal '
        'cycle length and detect patterns.',
      ];
    }

    final recs = <String>[];

    if (irregularRisk > 0.4) {
      recs.add(
        'Your cycle length variability is above average. Keep tracking — '
        'consult a gynaecologist if irregularity persists beyond 3 months.',
      );
    }
    if (pcosRisk > 0.35) {
      recs.add(
        'Some PCOS-associated patterns detected (irregular cycles, acne, mood changes). '
        'Consider discussing with your healthcare provider.',
      );
    }
    if (hormonalRisk > 0.35) {
      recs.add(
        'Hormonal fluctuation indicators present. Focus on consistent sleep, '
        'stress reduction, and magnesium-rich foods (dark chocolate, nuts, avocado).',
      );
    }
    if (anemiaRisk > 0.35) {
      recs.add(
        'Heavy flow history suggests monitoring iron levels. Eat iron-rich foods '
        '(spinach, lentils, red meat) paired with vitamin C for absorption.',
      );
    }

    if (recs.isEmpty) {
      recs.add(
        'Your patterns look healthy! Continue tracking to maintain awareness '
        'and improve prediction accuracy.',
      );
    }

    return recs;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Math helpers
  // ──────────────────────────────────────────────────────────────────────────

  static double _avg(List<double> xs) =>
      xs.isEmpty ? 0.0 : xs.reduce((a, b) => a + b) / xs.length;

  static double _std(List<double> xs) {
    if (xs.length < 2) return 0.0;
    final avg = _avg(xs);
    return math.sqrt(
      xs.map((x) => math.pow(x - avg, 2)).reduce((a, b) => a + b) / xs.length,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  Singleton
// ──────────────────────────────────────────────────────────────────────────────

HealthRiskEstimator? _instance;
HealthRiskEstimator getHealthRiskEstimator() =>
    _instance ??= HealthRiskEstimator();
