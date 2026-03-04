
import 'api_service.dart';
import '../local/local_database_service.dart';

// ── Dashboard / Prediction ─────────────────────────────────────────────────────

class DashboardData {
  final bool hasData;
  final String? message;

  final int currentCycleDay;
  final String currentPhase;
  final String? nextPeriodDate;
  final int daysUntilPeriod;
  final String? ovulationDate;
  final String? fertileWindowStart;
  final String? fertileWindowEnd;
  final double confidenceScore;
  final String predictionMethod;

  final String? moodToday;
  final List<String> symptomsToday;
  final double healthScore;

  final String aiInsightTitle;
  final String aiInsightMessage;
  final bool ollamaAvailable;
  final double lastJournalSentiment;

  // ── Cycle prediction extras ────────────────────────────────────────────────
  final int?    cycleLengthPrediction;
  final String? pmsPeakDate;
  final String? pmsRiskLevel;
  final double? pmsRiskScore;

  // ── Health averages from dashboard ────────────────────────────────────────
  final double? avgSleepFromDash;    // avg_sleep from dashboard response
  final double? avgStressFromDash;   // avg_stress from dashboard response

  // ── Kalman / sentiment diagnostics ────────────────────────────────────────
  final String? sentimentStressLevel;
  final double? sentimentVarianceEffect;
  final int?    nPersonalCycles;
  final double? kalmanStd;

  const DashboardData({
    required this.hasData,
    this.message,
    this.currentCycleDay = 0,
    this.currentPhase = 'follicular',
    this.nextPeriodDate,
    this.daysUntilPeriod = 0,
    this.ovulationDate,
    this.fertileWindowStart,
    this.fertileWindowEnd,
    this.confidenceScore = 0,
    this.predictionMethod = 'baseline',
    this.moodToday,
    this.symptomsToday = const [],
    this.healthScore = 0,
    this.aiInsightTitle = 'Daily Insight',
    this.aiInsightMessage = '',
    this.ollamaAvailable = false,
    this.lastJournalSentiment = 0.0,
    this.cycleLengthPrediction,
    this.pmsPeakDate,
    this.pmsRiskLevel,
    this.pmsRiskScore,
    this.avgSleepFromDash,
    this.avgStressFromDash,
    this.sentimentStressLevel,
    this.sentimentVarianceEffect,
    this.nPersonalCycles,
    this.kalmanStd,
  });

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    // ai_insight can be a plain String (rule-based) or a Map {title, message}
    final rawInsight = j['ai_insight'];
    final String insightTitle;
    final String insightMessage;
    if (rawInsight is Map<String, dynamic>) {
      insightTitle   = rawInsight['title']   as String? ?? 'Daily Insight';
      insightMessage = rawInsight['message'] as String? ?? '';
    } else {
      insightTitle   = 'Daily Insight';
      insightMessage = rawInsight as String? ?? '';
    }
    final pms = j['pms_prediction'] as Map<String, dynamic>?;
    return DashboardData(
      hasData: j['has_data'] == true,
      message: j['message'],
      currentCycleDay: j['current_cycle_day'] ?? 0,
      currentPhase: j['current_phase'] ?? 'follicular',
      nextPeriodDate: j['next_period_date'],
      daysUntilPeriod: j['days_until_period'] ?? 0,
      ovulationDate: j['ovulation_date'],
      fertileWindowStart: j['fertile_window_start'],
      fertileWindowEnd: j['fertile_window_end'],
      confidenceScore: (j['confidence_score'] as num?)?.toDouble() ?? 0,
      predictionMethod: j['prediction_method'] ?? 'baseline',
      moodToday: j['mood_today'],
      symptomsToday: List<String>.from(j['symptoms_today'] ?? []),
      healthScore: (j['health_score'] as num?)?.toDouble() ?? 0,
      aiInsightTitle: insightTitle,
      aiInsightMessage: insightMessage,
      ollamaAvailable: j['runanywhere_on_device'] == true || j['ollama_available'] == true,
      lastJournalSentiment: (j['last_journal_sentiment'] as num?)?.toDouble() ?? 0.0,
      // ── New fields ─────────────────────────────────────────────────────────
      cycleLengthPrediction  : j['cycle_length_prediction'] as int?,
      pmsPeakDate            : pms?['pms_peak_date'] as String?,
      pmsRiskLevel           : pms?['risk_level'] as String?,
      pmsRiskScore           : (pms?['pms_risk_score'] as num?)?.toDouble(),
      avgSleepFromDash       : (j['avg_sleep'] as num?)?.toDouble(),
      avgStressFromDash      : (j['avg_stress'] as num?)?.toDouble(),
      sentimentStressLevel   : j['sentiment_stress_level'] as String?,
      sentimentVarianceEffect: (j['sentiment_variance_effect'] as num?)?.toDouble(),
      nPersonalCycles        : j['n_personal_cycles'] as int?,
      kalmanStd              : (j['kalman_std'] as num?)?.toDouble(),
    );
  }
}

class SuggestionData {
  final String category;
  final String title;
  final String description;
  final String reason;
  final bool isAI;

  const SuggestionData({
    required this.category,
    required this.title,
    required this.description,
    required this.reason,
    this.isAI = false,
  });

  factory SuggestionData.fromJson(Map<String, dynamic> j,
          {bool isAI = false}) =>
      SuggestionData(
        category: j['category'] ?? '',
        title: j['title'] ?? '',
        description: j['description'] ?? '',
        reason: j['reason'] ?? '',
        isAI: isAI,
      );
}

class HealthRisk {
  final String name;
  final double score;
  final String level;
  final List<String> recommendations;

  const HealthRisk({
    required this.name,
    required this.score,
    required this.level,
    required this.recommendations,
  });
}

// ── Journal / Emotion ──────────────────────────────────────────────────────────

class EmotionResult {
  final Map<String, double> emotionScores;
  final String primaryEmotion;
  final String suggestedMood;
  final double sentimentScore;
  final double stressLevel;
  final double hormonalInfluence;
  final List<String> keywords;
  final List<String> topics;
  final String modelUsed;
  final String aiResponse;
  final bool mentalHealthConcern;
  final bool crisisDetected;
  final List<String> supportRecommendations;

  const EmotionResult({
    required this.emotionScores,
    required this.primaryEmotion,
    required this.suggestedMood,
    required this.sentimentScore,
    required this.stressLevel,
    required this.hormonalInfluence,
    required this.keywords,
    required this.topics,
    required this.modelUsed,
    required this.aiResponse,
    required this.mentalHealthConcern,
    required this.crisisDetected,
    required this.supportRecommendations,
  });

  factory EmotionResult.fromJson(Map<String, dynamic> j) {
    // Emotion data is nested under 'emotion_analysis'
    final analysis = j['emotion_analysis'] as Map<String, dynamic>? ?? j;
    final scores = (analysis['emotion_scores'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
    final mental = j['mental_health_check'] as Map<String, dynamic>? ?? {};

    return EmotionResult(
      emotionScores: scores,
      primaryEmotion: analysis['primary_emotion'] as String? ?? 'neutral',
      suggestedMood: analysis['suggested_mood'] as String? ?? 'neutral',
      sentimentScore:
          (analysis['sentiment_score'] as num?)?.toDouble() ?? 0,
      stressLevel:
          (analysis['stress_level'] as num?)?.toDouble() ?? 0,
      hormonalInfluence:
          (analysis['hormonal_influence'] as num?)?.toDouble() ?? 0,
      keywords: List<String>.from(analysis['keywords'] ?? []),
      topics: List<String>.from(analysis['topics'] ?? []),
      modelUsed: analysis['model_used'] as String? ?? 'keyword_fallback',
      // ai_response is at the TOP LEVEL of the response, not nested
      aiResponse: j['ai_response'] as String? ?? '',
      mentalHealthConcern: mental['mental_health_concern'] == true,
      crisisDetected: mental['crisis_detected'] == true,
      supportRecommendations:
          List<String>.from(mental['recommendations'] ?? []),
    );
  }

  String get emoji {
    const map = {
      'joy': 'joy',
      'sadness': 'sad',
      'anger': 'anger',
      'fear': 'fear',
      'disgust': 'disgust',
      'surprise': 'surprise',
      'neutral': 'neutral',
    };
    return map[primaryEmotion] ?? 'neutral';
  }

  String get sentimentLabel {
    if (sentimentScore > 0.3) return 'Positive';
    if (sentimentScore < -0.3) return 'Negative';
    return 'Neutral';
  }
}

class JournalEntry {
  final int id;
  final String date;
  final String entryText;
  final String? primaryEmotion;
  final double? sentimentScore;
  final bool crisisDetected;

  const JournalEntry({
    required this.id,
    required this.date,
    required this.entryText,
    this.primaryEmotion,
    this.sentimentScore,
    this.crisisDetected = false,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> j) {
    // primary_emotion is inside emotion_analysis, not at top level
    final analysis = j['emotion_analysis'] as Map<String, dynamic>? ?? {};
    return JournalEntry(
      id: j['id'] as int,
      date: j['date'] as String,
      entryText: j['entry_text'] as String,
      primaryEmotion: analysis['primary_emotion'] as String?,
      sentimentScore: (j['sentiment_score'] as num?)?.toDouble(),
      crisisDetected: j['crisis_detected'] == true ||
          j['mental_health_concern'] == true,
    );
  }

  String get emoji {
    const map = {
      'joy': 'joy',
      'sadness': 'sad',
      'anger': 'anger',
      'fear': 'fear',
      'disgust': 'disgust',
      'surprise': 'surprise',
    };
    return map[primaryEmotion] ?? 'note';
  }
}

// ── The Service ────────────────────────────────────────────────────────────────

class AiService {
  final ApiService _api;
  ApiService get api => _api;

  AiService(this._api);

  Future<DashboardData> getDashboard() async {
    final data = await api.get('/dashboard/');
    return DashboardData.fromJson(data);
  }

  Future<List<SuggestionData>> getSuggestions() async {
    final data = await api.get('/dashboard/suggestions');
    final List<SuggestionData> results = [];
    for (final s in (data['ai_suggestions'] as List? ?? [])) {
      results.add(
          SuggestionData.fromJson(s as Map<String, dynamic>, isAI: true));
    }
    for (final s in (data['rule_based_suggestions'] as List? ?? [])) {
      results.add(SuggestionData.fromJson(s as Map<String, dynamic>));
    }
    return results;
  }

  Future<List<HealthRisk>> getHealthRisks() async {
    final data = await api.get('/predictions/health-risks');
    return [
      HealthRisk(
        name: 'PCOS Pattern Risk',
        score:
            (data['pcos_pattern_probability'] as num?)?.toDouble() ?? 0,
        level: data['risk_level'] ?? 'low',
        recommendations:
            List<String>.from(data['recommendations'] ?? []),
      ),
      HealthRisk(
        name: 'Irregular Cycle Risk',
        score:
            (data['irregular_cycle_risk'] as num?)?.toDouble() ?? 0,
        level: data['risk_level'] ?? 'low',
        recommendations: [],
      ),
      HealthRisk(
        name: 'Hormonal Imbalance',
        score: (data['hormonal_imbalance_indicator'] as num?)
                ?.toDouble() ??
            0,
        level: data['risk_level'] ?? 'low',
        recommendations: [],
      ),
    ];
  }

  Future<EmotionResult> analyzeJournalEntry(String text, String date) async {
    final data = await api.postLong('/journal/', {
      'entry_text': text,
      'date': date,
    });
    return EmotionResult.fromJson(data);
  }

  Future<List<JournalEntry>> getJournalEntries() async {
    final data = await api.get('/journal/');
    // ApiService wraps List responses as {'data': [...]}
    final list = data['data'] as List? ?? data['entries'] as List? ?? [];
    return list
        .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> logMood({
    required String date,
    required String mood,
    required double intensity,
    double?  sleepHours,
    int?     energyLevel,
    bool?    exercise,
  }) async {
    try {
      await api.post('/moods/', {
        'date'          : date,
        'primary_mood'  : mood,
        'intensity'     : intensity.clamp(0.0, 1.0),
        if (sleepHours  != null) 'sleep_hours'  : sleepHours,
        if (energyLevel != null) 'energy_level' : energyLevel,
        if (exercise    != null) 'exercise'      : exercise,
      });
    } catch (_) {
      // Non-critical — don't block journal save if mood log fails
    }
  }

  Future<void> logCycleStart(String startDate) async {
    await api.post('/cycles/', {'start_date': startDate});
  }

  Future<List<CycleRecord>> getCycles({int limit = 24}) async {
    final data = await api.get('/cycles/?limit=$limit');
    final list = data['data'] as List? ?? [];
    return list
        .map((e) => CycleRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SymptomRecord>> getSymptoms({int limit = 100}) async {
    final data = await api.get('/symptoms/?limit=$limit');
    final List<dynamic> raw = data is List
        ? List<dynamic>.from(data as List)
        : List<dynamic>.from(
            ((data as Map<String, dynamic>?)?['data'] as List?) ?? []);
    return raw
        .whereType<Map<String, dynamic>>()
        .map((e) => SymptomRecord.fromJson(e))
        .toList();
  }

  Future<void> submitOnboarding({
    DateTime? dob,
    double? heightCm,
    double? weightKg,
    int? avgCycleLength,
    int? avgPeriodLength,
    String? fitnessLevel,
    List<String>? healthGoals,
    double? avgSleepHours,
    int? avgStressLevel,
    String? dietaryPreference,
  }) async {
    final body = <String, dynamic>{};
    if (dob != null) {
      body['date_of_birth'] =
          '${dob.year}-${dob.month.toString().padLeft(2, '0')}-'
          '${dob.day.toString().padLeft(2, '0')}';
    }
    if (heightCm != null)        body['height_cm']           = heightCm;
    if (weightKg != null)        body['weight_kg']           = weightKg;
    if (avgCycleLength != null)  body['avg_cycle_length']    = avgCycleLength;
    if (avgPeriodLength != null) body['avg_period_length']   = avgPeriodLength;
    if (fitnessLevel != null)    body['fitness_level']       = fitnessLevel;
    if (healthGoals != null)     body['health_goals']        = healthGoals;
    if (avgSleepHours != null)   body['avg_sleep_hours']     = avgSleepHours;
    if (avgStressLevel != null)  body['avg_stress_level']    = avgStressLevel;
    if (dietaryPreference != null) {
      body['dietary_preference'] = dietaryPreference;
    }
    // Best-effort: send to backend if authenticated; silently skip if not.
    // onboardingCompleted is always marked locally via refreshCurrentUser().
    if (api.hasToken) {
      try {
        await api.post('/auth/onboard', body);

        // Also create a weight log entry so the weight entered during onboarding
        // appears immediately in the Weight Tracker and is used as the baseline.
        if (weightKg != null) {
          try {
            final today = '${DateTime.now().year}'
                '-${DateTime.now().month.toString().padLeft(2, '0')}'
                '-${DateTime.now().day.toString().padLeft(2, '0')}';
            await api.post('/weight/', {
              'date': today,
              'weight_kg': weightKg,
              'notes': 'Starting weight from onboarding',
            });
          } catch (_) {} // Weight log is best-effort
        }
      } catch (_) {
        // Backend unavailable or token expired — onboarding data saved locally only
      }
    }
  }
}

// ── Cycle Record (for cycle history page) ────────────────────────────────────

// ── SymptomRecord ─────────────────────────────────────────────────────────────
class SymptomRecord {
  final int    id;
  final String date;
  final String symptomType;
  final int    severity;
  final String? notes;

  const SymptomRecord({
    required this.id,
    required this.date,
    required this.symptomType,
    required this.severity,
    this.notes,
  });

  factory SymptomRecord.fromJson(Map<String, dynamic> j) => SymptomRecord(
        id          : j['id'] as int? ?? 0,
        date        : j['date'] as String? ?? '',
        symptomType : j['symptom_type'] as String? ?? 'unknown',
        severity    : j['severity'] as int? ?? 1,
        notes       : j['notes'] as String?,
      );
}

class CycleRecord {
  final int id;
  final String startDate;
  final String? endDate;
  final int? cycleLength;
  final int? periodLength;
  final String? flowIntensity;
  final String? ovulationDate;
  final String? fertileWindowStart;
  final String? fertileWindowEnd;
  final bool isRegular;
  final String? notes;

  const CycleRecord({
    required this.id,
    required this.startDate,
    this.endDate,
    this.cycleLength,
    this.periodLength,
    this.flowIntensity,
    this.ovulationDate,
    this.fertileWindowStart,
    this.fertileWindowEnd,
    this.isRegular = true,
    this.notes,
  });

  factory CycleRecord.fromJson(Map<String, dynamic> j) => CycleRecord(
        id: j['id'] as int,
        startDate: j['start_date'] as String,
        endDate: j['end_date'] as String?,
        cycleLength: j['cycle_length'] as int?,
        periodLength: j['period_length'] as int?,
        flowIntensity: j['flow_intensity'] as String?,
        ovulationDate: j['ovulation_date'] as String?,
        fertileWindowStart: j['fertile_window_start'] as String?,
        fertileWindowEnd: j['fertile_window_end'] as String?,
        isRegular: j['is_regular'] == true,
        notes: j['notes'] as String?,
      );
}

// ── New Data Models ─────────────────────────────────────────────────────────
// SleepLogData is now defined in local_database_service.dart.
// The typedef there (SleepLogData = LocalSleepLogData) is the canonical source.

class WeightLogData {
  final int? id;
  final String date;
  final double weightKg;
  final double? bmi;
  final double? waistCm;
  final double? hipsCm;
  final double? bustCm;

  const WeightLogData({
    this.id,
    required this.date,
    required this.weightKg,
    this.bmi,
    this.waistCm,
    this.hipsCm,
    this.bustCm,
  });

  factory WeightLogData.fromJson(Map<String, dynamic> j) => WeightLogData(
        id: j['id'] as int?,
        date: j['date'] as String,
        weightKg: (j['weight_kg'] as num).toDouble(),
        bmi: (j['bmi'] as num?)?.toDouble(),
        waistCm: (j['waist_cm'] as num?)?.toDouble(),
        hipsCm: (j['hips_cm'] as num?)?.toDouble(),
        bustCm: (j['bust_cm'] as num?)?.toDouble(),
      );
}

class PhaseTask {
  final String task;
  final String icon;
  final String priority;

  const PhaseTask({required this.task, required this.icon, required this.priority});

  factory PhaseTask.fromJson(Map<String, dynamic> j) => PhaseTask(
        task: j['task'] as String,
        icon: j['icon'] as String? ?? 'check',
        priority: j['priority'] as String? ?? 'medium',
      );
}

class EmotionTimelinePoint {
  final String date;
  final String source;
  final double? sentiment;
  final String? emotion;
  final int? energy;

  const EmotionTimelinePoint({
    required this.date,
    required this.source,
    this.sentiment,
    this.emotion,
    this.energy,
  });

  factory EmotionTimelinePoint.fromJson(Map<String, dynamic> j) =>
      EmotionTimelinePoint(
        date: j['date'] as String,
        source: j['source'] as String,
        sentiment: (j['sentiment'] as num?)?.toDouble(),
        emotion: j['emotion'] as String?,
        energy: j['energy'] as int?,
      );
}

class ChatMemorySummary {
  final String? username;
  final List<String> summaries;
  final String? topMood;
  final String? bestPhase;
  final Map<String, double> phaseAvgSentiment;

  const ChatMemorySummary({
    this.username,
    required this.summaries,
    this.topMood,
    this.bestPhase,
    this.phaseAvgSentiment = const {},
  });

  factory ChatMemorySummary.fromJson(Map<String, dynamic> j) =>
      ChatMemorySummary(
        username: j['username'] as String?,
        summaries: List<String>.from(j['summaries'] ?? []),
        topMood: j['top_mood'] as String?,
        bestPhase: j['best_phase_for_mood'] as String?,
        phaseAvgSentiment: (j['phase_sentiment_avg'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            {},
      );
}

class AnomalyAlert {
  final String type;
  final String severity;
  final String title;
  final String message;

  const AnomalyAlert({
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
  });

  factory AnomalyAlert.fromJson(Map<String, dynamic> j) => AnomalyAlert(
        type: j['type'] as String,
        severity: j['severity'] as String? ?? 'low',
        title: j['title'] as String,
        message: j['message'] as String,
      );
}

// ── Ovulation confirmation log ────────────────────────────────────────────────

class OvulationLog {
  final int     id;
  final String  date;             // user-confirmed date
  final String? predictedDate;   // predicted_ovulation_date from backend
  final int?    daysOff;         // days_off_prediction (positive = later, negative = earlier)
  final String? dischargeType;
  final double? basalTemp;
  final bool?   hadCramps;
  final bool?   lhSurge;

  const OvulationLog({
    required this.id,
    required this.date,
    this.predictedDate,
    this.daysOff,
    this.dischargeType,
    this.basalTemp,
    this.hadCramps,
    this.lhSurge,
  });

  factory OvulationLog.fromJson(Map<String, dynamic> j) => OvulationLog(
    id           : j['id'] as int,
    date         : j['date'] as String,
    predictedDate: j['predicted_ovulation_date'] as String?,
    daysOff      : j['days_off_prediction'] as int?,
    dischargeType: j['discharge_type'] as String?,
    basalTemp    : (j['basal_temp'] as num?)?.toDouble(),
    hadCramps    : j['had_cramps'] as bool?,
    lhSurge      : j['lh_surge'] as bool?,
  );
}

// ── PMS feedback record ───────────────────────────────────────────────────────

class PmsFeedbackRecord {
  final int    id;
  final bool   arrivedAsPredicted;
  final String? actualPmsStart;
  final String? predictedPmsDate;
  final int?   severity;
  final String? notes;

  const PmsFeedbackRecord({
    required this.id,
    required this.arrivedAsPredicted,
    this.actualPmsStart,
    this.predictedPmsDate,
    this.severity,
    this.notes,
  });

  factory PmsFeedbackRecord.fromJson(Map<String, dynamic> j) => PmsFeedbackRecord(
    id                  : j['id'] as int,
    arrivedAsPredicted  : j['pms_arrived_as_predicted'] as bool,
    actualPmsStart      : j['actual_pms_start'] as String?,
    predictedPmsDate    : j['predicted_pms_date'] as String?,
    severity            : j['pms_severity'] as int?,
    notes               : j['notes'] as String?,
  );
}

class OvulationConfirmData {
  final String date;
  final String? dischargeType;
  final double? basalTemp;
  final bool? hadCramps;
  final bool? lhSurge;
  final String? notes;

  const OvulationConfirmData({
    required this.date,
    this.dischargeType,
    this.basalTemp,
    this.hadCramps,
    this.lhSurge,
    this.notes,
  });
}

// ── New AiService Extension Methods ─────────────────────────────────────────

extension AiServiceExtensions on AiService {

  // Sleep
  Future<void> logSleep({
    required String date,
    double? hoursSlept,
    int? quality,
    String? wakeTime,
    String? bedTime,
    bool? hadDreams,
    String? dreamNotes,
    String? notes,
  }) async {
    await api.post('/sleep/', {
      'date': date,
      if (hoursSlept != null) 'hours_slept': hoursSlept,
      if (quality != null) 'quality': quality,
      if (wakeTime != null) 'wake_time': wakeTime,
      if (bedTime != null) 'bed_time': bedTime,
      if (hadDreams != null) 'had_dreams': hadDreams,
      if (dreamNotes != null) 'dream_notes': dreamNotes,
      if (notes != null) 'notes': notes,
    });
  }

  Future<List<SleepLogData>> getSleepLogs({int limit = 30}) async {
    final data = await api.get('/sleep/?limit=$limit');
    final raw = data['data'] ?? data;
    final list = (raw is List) ? raw : <dynamic>[];
    return list.map((e) => SleepLogData.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getSleepStats() async {
    return await api.get('/sleep/stats');
  }

  // Weight
  Future<void> logWeight({
    required String date,
    required double weightKg,
    double? waistCm,
    double? hipsCm,
    double? bustCm,
    String? notes,
  }) async {
    await api.post('/weight/', {
      'date': date,
      'weight_kg': weightKg,
      if (waistCm != null) 'waist_cm': waistCm,
      if (hipsCm != null) 'hips_cm': hipsCm,
      if (bustCm != null) 'bust_cm': bustCm,
      if (notes != null) 'notes': notes,
    });
  }

  Future<Map<String, dynamic>> getWeightChart({int days = 90}) async {
    return await api.get('/weight/chart?days=$days');
  }

  Future<List<WeightLogData>> getWeightLogs({int limit = 90}) async {
    final data = await api.get('/weight/?limit=$limit');
    final raw = data['data'] ?? data;
    final list = (raw is List) ? raw : <dynamic>[];
    return list.map((e) => WeightLogData.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Phase tasks
  Future<Map<String, dynamic>> getPhaseTasks() async {
    return await api.get('/insights/phase-tasks');
  }

  // Emotion timeline
  Future<Map<String, dynamic>> getEmotionTimeline({int days = 30}) async {
    return await api.get('/insights/emotion-timeline?days=$days');
  }

  // Chat memory
  Future<ChatMemorySummary> getChatMemory() async {
    final data = await api.get('/insights/chat-memory');
    return ChatMemorySummary.fromJson(data);
  }

  // Anomaly
  Future<List<AnomalyAlert>> getCycleAnomalies() async {
    final data = await api.get('/insights/anomaly');
    final list = data['alerts'] as List? ?? [];
    return list.map((e) => AnomalyAlert.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Ovulation logs (user-confirmed dates + accuracy vs prediction)
  Future<List<OvulationLog>> getOvulationLogs({int limit = 12}) async {
    final data = await api.get('/ovulation/?limit=$limit');
    final raw  = data is List ? data : (data['data'] ?? data);
    final list = (raw is List) ? raw : <dynamic>[];
    return list.map((e) => OvulationLog.fromJson(e as Map<String, dynamic>)).toList();
  }

  // PMS feedback history
  Future<List<PmsFeedbackRecord>> getPmsFeedback({int limit = 12}) async {
    final data = await api.get('/ovulation/pms-feedback?limit=$limit');
    final raw  = data is List ? data : (data['data'] ?? data);
    final list = (raw is List) ? raw : <dynamic>[];
    return list.map((e) => PmsFeedbackRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Ovulation + PMS accuracy summary
  Future<Map<String, dynamic>> getOvulationAccuracy() async {
    return await api.get('/ovulation/accuracy');
  }

  // Ovulation confirmation
  Future<void> confirmOvulation(OvulationConfirmData d) async {
    await api.post('/ovulation/', {
      'date': d.date,
      if (d.dischargeType != null) 'discharge_type': d.dischargeType,
      if (d.basalTemp != null) 'basal_temp': d.basalTemp,
      if (d.hadCramps != null) 'had_cramps': d.hadCramps,
      if (d.lhSurge != null) 'lh_surge': d.lhSurge,
      if (d.notes != null) 'notes': d.notes,
    });
  }

  // PMS feedback
  Future<void> submitPmsFeedback({
    required bool arrivedAsPredicted,
    String? actualPmsStart,
    int? severity,
    String? notes,
  }) async {
    await api.post('/ovulation/pms-feedback', {
      'pms_arrived_as_predicted': arrivedAsPredicted,
      if (actualPmsStart != null) 'actual_pms_start': actualPmsStart,
      if (severity != null) 'pms_severity': severity,
      if (notes != null) 'notes': notes,
    });
  }
}
