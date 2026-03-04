
library local_database_service;

import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'eva_database.dart';
import 'kalman_filter_service.dart';
import '../ml/suggestion_engine.dart' as se;
import '../ml/health_risk_estimator.dart' as hre;
import '../ml/emotion_detector.dart';
import '../ml/onnx_cycle_predictor.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Re-export all data classes from ai_service so callers need zero changes.
//  (These are defined at the bottom of this file to avoid circular imports.)
// ─────────────────────────────────────────────────────────────────────────────

class LocalDatabaseService {
  final EvaDatabase _db = EvaDatabase();

  // Every row is always for user_id = 1 (single-user, no backend auth needed)
  static const int _uid = 1;

  // ── User / Profile ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getProfile() async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [_uid]);
    if (rows.isEmpty) {
      await _ensureDefaultUser();
      return getProfile();
    }
    final u = Map<String, dynamic>.from(rows.first);
    u['health_goals'] = EvaDatabase.decodeList(u['health_goals'] as String?);
    return u;
  }

  Future<void> saveOnboarding({
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
    await _ensureDefaultUser();
    final updates = <String, dynamic>{};
    if (dob != null) {
      updates['date_of_birth'] =
          '${dob.year}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}';
    }
    if (heightCm != null)        updates['height_cm']            = heightCm;
    if (weightKg != null)        updates['weight_kg']            = weightKg;
    if (avgCycleLength != null)  updates['avg_cycle_length']     = avgCycleLength;
    if (avgPeriodLength != null) updates['avg_period_length']    = avgPeriodLength;
    if (fitnessLevel != null)    updates['fitness_level']        = fitnessLevel;
    if (healthGoals != null)     updates['health_goals']         = EvaDatabase.encodeList(healthGoals);
    if (avgSleepHours != null)   updates['avg_sleep_hours']      = avgSleepHours;
    if (avgStressLevel != null)  updates['avg_stress_level']     = avgStressLevel;
    if (dietaryPreference != null) updates['dietary_preference'] = dietaryPreference;
    updates['onboarding_completed'] = 1;

    if (updates.isNotEmpty) {
      await _db.update('users', updates, where: 'id = ?', whereArgs: [_uid]);
    }

    // Also seed a weight log with onboarding weight
    if (weightKg != null) {
      final today = _today();
      await logWeight(date: today, weightKg: weightKg, notes: 'Starting weight from onboarding');
    }

    // Persist onboarding_completed to SharedPreferences for AuthProvider
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('local_profile');
    if (stored != null) {
      try {
        final profile = jsonDecode(stored) as Map<String, dynamic>;
        profile['onboarding_completed'] = true;
        if (avgCycleLength != null) profile['cycle_length'] = avgCycleLength;
        if (avgPeriodLength != null) profile['period_length'] = avgPeriodLength;
        await prefs.setString('local_profile', jsonEncode(profile));
      } catch (_) {}
    }
  }

  // ── Cycles ─────────────────────────────────────────────────────────────────

  Future<LocalCycleRecord> logCycleStart(String startDate) async {
    await _ensureDefaultUser();

    // Fetch immediately previous cycle
    final prev = await _db.query('cycles',
        where: 'user_id = ? AND start_date < ?',
        whereArgs: [_uid, startDate],
        orderBy: 'start_date DESC',
        limit: 1);

    final row = <String, dynamic>{
      'user_id'    : _uid,
      'start_date' : startDate,
      'created_at' : _now(),
    };

    int? cycleLength;

    if (prev.isNotEmpty) {
      final gap = _daysBetween(prev.first['start_date'] as String, startDate);
      if (gap >= 15 && gap <= 60) {
        cycleLength = gap;
        row['cycle_length'] = gap;
        // Backfill previous cycle if missing
        if (prev.first['cycle_length'] == null) {
          await _db.update('cycles', {'cycle_length': gap},
              where: 'id = ?', whereArgs: [prev.first['id']]);
        }
      }
    }

    // Look ahead for a later cycle (out-of-order entry)
    final later = await _db.query('cycles',
        where: 'user_id = ? AND start_date > ?',
        whereArgs: [_uid, startDate],
        orderBy: 'start_date ASC',
        limit: 1);
    if (later.isNotEmpty) {
      final gap = _daysBetween(startDate, later.first['start_date'] as String);
      if (gap >= 15 && gap <= 60) {
        await _db.update('cycles', {'cycle_length': gap},
            where: 'id = ?', whereArgs: [later.first['id']]);
        cycleLength ??= gap;
      }
    }

    final id = await _db.insert('cycles', row);

    // Update Kalman with the new cycle length
    if (cycleLength != null && cycleLength >= 21 && cycleLength <= 45) {
      await _updateKalmanFromCycle(cycleLength.toDouble());
      // Update user avg_cycle_length
      await _updateUserAvgCycleLength();
    }

    final result = await _db.query('cycles', where: 'id = ?', whereArgs: [id]);
    return LocalCycleRecord.fromRow(result.first);
  }

  Future<List<LocalCycleRecord>> getCycles({int limit = 24}) async {
    final rows = await _db.query('cycles',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'start_date DESC',
        limit: limit);
    return rows.map(LocalCycleRecord.fromRow).toList();
  }

  Future<void> updateCycleFlow(String flowIntensity) async {
    final rows = await _db.query('cycles',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'start_date DESC',
        limit: 1);
    if (rows.isEmpty) return;
    await _db.update('cycles', {'flow_intensity': flowIntensity},
        where: 'id = ?', whereArgs: [rows.first['id']]);
  }

  // ── Symptoms ────────────────────────────────────────────────────────────────

  Future<void> logSymptom({
    required String date,
    required String symptomType,
    required int severity,
    String? notes,
  }) async {
    await _db.insert('symptoms', {
      'user_id'      : _uid,
      'date'         : date,
      'symptom_type' : symptomType,
      'severity'     : severity,
      if (notes != null) 'notes': notes,
      'created_at'   : _now(),
    });
  }

  Future<List<LocalSymptomRecord>> getSymptoms({int limit = 100}) async {
    final rows = await _db.query('symptoms',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'date DESC',
        limit: limit);
    return rows.map(LocalSymptomRecord.fromRow).toList();
  }

  // ── Moods ───────────────────────────────────────────────────────────────────

  Future<void> logMood({
    required String date,
    required String mood,
    required double intensity,
    double? sleepHours,
    int? energyLevel,
    bool? exercise,
  }) async {
    // Upsert — one mood per day
    await _db.insert('mood_logs', {
      'user_id'      : _uid,
      'date'         : date,
      'primary_mood' : mood,
      'intensity'    : intensity.clamp(0.0, 1.0),
      if (sleepHours  != null) 'sleep_hours'  : sleepHours,
      if (energyLevel != null) 'energy_level' : energyLevel,
      if (exercise    != null) 'exercise'      : exercise ? 1 : 0,
      'created_at'   : _now(),
    });
  }

  // ── Journal ─────────────────────────────────────────────────────────────────

  Future<LocalEmotionResult> analyzeJournalEntry(String text, String date) async {
    // Truncate very long entries for analysis to prevent memory issues.
    // We store the FULL text but only analyze the first ~500 words.
    final words = text.trim().split(RegExp(r'\s+'));
    final analyzeText = words.length > 500
        ? words.take(500).join(' ')
        : text;
    // Phase 3: full EmotionDetector (keyword + negation + mental health)
    // Get current cycle phase for hormonal-influence weighting
    String? phase;
    try {
      final rows = await _db.query('cycles',
          where: 'user_id = ?', whereArgs: [_uid], orderBy: 'start_date DESC', limit: 1);
      if (rows.isNotEmpty) {
        final lastStart = DateTime.parse(rows.first['start_date'] as String);
        final dayInCycle = DateTime.now().difference(lastStart).inDays % 28;
        if (dayInCycle < 5) {
          phase = 'menstrual';
        } else if (dayInCycle < 13) phase = 'follicular';
        else if (dayInCycle < 16) phase = 'ovulation';
        else                      phase = 'luteal';
      }
    } catch (_) {}

    final detector = EmotionDetector();
    final result   = detector.analyze(analyzeText, cyclePhase: phase);
    final aiResponse = EmotionDetector.generateJournalResponse(result);

    // Persist with richer data
    final row = {
      'user_id'          : _uid,
      'date'             : date,
      'entry_text'       : text,
      'sentiment_score'  : result.sentimentScore,
      'primary_emotion'  : result.primaryEmotion,
      'emotion_analysis' : EvaDatabase.encodeMap({
        'scores'         : result.emotionScores,
        'topics'         : result.topics,
        'stress_level'   : result.stressLevel,
        'hormonal'       : result.hormonalInfluence,
        'crisis'         : result.mentalHealth.crisisDetected,
        'concern_level'  : result.mentalHealth.level.name,
      }),
      'keywords'         : EvaDatabase.encodeList(result.keywords),
      'word_count'       : result.wordCount,
      'model_version'    : result.modelUsed,
      'created_at'       : _now(),
    };

    // FIX #3: For "Daily log" (slider-only entries), upsert so only 1 per day.
    // For text journal entries, always insert to allow multiple per day.
    final isDailyLog = text.startsWith('Daily log —');
    if (isDailyLog) {
      final existing = await _db.query('journal_entries',
          where: "user_id = ? AND date = ? AND entry_text LIKE 'Daily log —%'",
          whereArgs: [_uid, date]);
      if (existing.isEmpty) {
        await _db.insert('journal_entries', row);
      } else {
        await _db.update('journal_entries', row,
            where: "user_id = ? AND date = ? AND entry_text LIKE 'Daily log —%'",
            whereArgs: [_uid, date]);
      }
    } else {
      // Text journal entries: allow multiple per day BUT deduplicate
      // identical text to prevent accidental double-saves.
      final dupe = await _db.query('journal_entries',
          where: 'user_id = ? AND date = ? AND entry_text = ?',
          whereArgs: [_uid, date, text], limit: 1);
      if (dupe.isEmpty) {
        await _db.insert('journal_entries', row);
      } else {
        // Update sentiment on the existing entry instead
        await _db.update('journal_entries', row,
            where: 'id = ?', whereArgs: [dupe.first['id']]);
      }
    }

    await _updateKalmanFromSentiment(result.sentimentScore);
    await logMood(
      date      : date,
      mood      : result.suggestedMood,
      intensity : (result.sentimentScore + 1) / 2,
    );

    return LocalEmotionResult(
      sentiment      : result.sentimentScore,
      primaryEmotion : result.primaryEmotion,
      emotionScores  : result.emotionScores,
      aiResponse     : aiResponse,
      keywords       : result.keywords,
    );
  }

  Future<List<LocalJournalEntry>> getJournalEntries() async {
    final rows = await _db.query('journal_entries',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'date DESC');
    return rows.map(LocalJournalEntry.fromRow).toList();
  }

  Future<void> deleteJournalEntry(int id) async {
    await _db.delete('journal_entries',
        where: 'id = ? AND user_id = ?', whereArgs: [id, _uid]);
  }

  Future<LocalEmotionResult> updateJournalEntry(int id, String newText, String date) async {
    final result = await analyzeJournalEntry(newText, date);
    // The analyzeJournalEntry always inserts for text entries; clean up the extra row.
    // Instead: update the existing row directly.
    await _db.update('journal_entries', {
      'entry_text'       : newText,
      'sentiment_score'  : result.sentiment,
      'primary_emotion'  : result.primaryEmotion,
      'emotion_analysis' : EvaDatabase.encodeMap({'scores': result.emotionScores}),
      'keywords'         : EvaDatabase.encodeList(result.keywords),
    },
        where: 'id = ? AND user_id = ?', whereArgs: [id, _uid]);
    // Remove the duplicate entry that analyzeJournalEntry just inserted
    final rows = await _db.query('journal_entries',
        where: 'user_id = ? AND date = ? AND id != ?',
        whereArgs: [_uid, date, id],
        orderBy: 'id DESC', limit: 1);
    if (rows.isNotEmpty) {
      await _db.delete('journal_entries',
          where: 'id = ?', whereArgs: [rows.first['id']]);
    }
    return result;
  }

  // ── Sleep ───────────────────────────────────────────────────────────────────

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
    // 0h is valid (all-nighter). Cap at 12h max.
    final hours = hoursSlept?.clamp(0.0, 12.0);
    final row = {
      'user_id'   : _uid,
      'date'      : date,
      if (hours       != null) 'hours_slept' : hours,
      if (quality     != null) 'quality'     : quality,
      if (wakeTime    != null) 'wake_time'   : wakeTime,
      if (bedTime     != null) 'bed_time'    : bedTime,
      if (hadDreams   != null) 'had_dreams'  : hadDreams ? 1 : 0,
      if (dreamNotes  != null) 'dream_notes' : dreamNotes,
      if (notes       != null) 'notes'       : notes,
      'created_at': _now(),
    };
    // No bed time = main night sleep → upsert (no duplicates).
    // Bed time provided = explicit nap entry → always insert.
    if (bedTime == null || bedTime.isEmpty) {
      final existing = await _db.query('sleep_logs',
          where: "user_id = ? AND date = ? AND (bed_time IS NULL OR bed_time = '')",
          whereArgs: [_uid, date]);
      if (existing.isNotEmpty) {
        await _db.update('sleep_logs', row,
            where: 'id = ?', whereArgs: [existing.first['id']]);
        return;
      }
    }
    await _db.insert('sleep_logs', row);
  }

  Future<List<LocalSleepLogData>> getSleepLogs({int limit = 30}) async {
    final rows = await _db.query('sleep_logs',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'date DESC',
        limit: limit);
    return rows.map(LocalSleepLogData.fromRow).toList();
  }

  Future<Map<String, dynamic>> getSleepStats() async {
    final rows = await _db.query('sleep_logs',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'date DESC',
        limit: 30);
    if (rows.isEmpty) return {'avg_hours': 0.0, 'avg_quality': 0.0, 'entry_count': 0};
    final hours = rows.where((r) => r['hours_slept'] != null).map((r) => (r['hours_slept'] as num).toDouble()).toList();
    final quals = rows.where((r) => r['quality'] != null).map((r) => (r['quality'] as num).toDouble()).toList();
    return {
      'avg_hours'  : hours.isNotEmpty ? _avg(hours) : 0.0,
      'avg_quality': quals.isNotEmpty ? _avg(quals) : 0.0,
      'entry_count': rows.length,
    };
  }

  // ── Weight ──────────────────────────────────────────────────────────────────

  Future<void> logWeight({
    required String date,
    required double weightKg,
    double? waistCm,
    double? hipsCm,
    double? bustCm,
    String? notes,
  }) async {
    final profile = await getProfile();
    final hCm = (profile['height_cm'] as num?)?.toDouble();
    double? bmi;
    if (hCm != null && hCm > 0) bmi = weightKg / math.pow(hCm / 100, 2);

    await _db.insert('weight_logs', {
      'user_id'  : _uid,
      'date'     : date,
      'weight_kg': weightKg,
      if (bmi     != null) 'bmi'      : double.parse(bmi.toStringAsFixed(1)),
      if (waistCm != null) 'waist_cm' : waistCm,
      if (hipsCm  != null) 'hips_cm'  : hipsCm,
      if (bustCm  != null) 'bust_cm'  : bustCm,
      if (notes   != null) 'notes'    : notes,
      'created_at': _now(),
    });
  }

  Future<List<LocalWeightLogData>> getWeightLogs({int limit = 90}) async {
    final rows = await _db.query('weight_logs',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'date DESC',
        limit: limit);
    return rows.map(LocalWeightLogData.fromRow).toList();
  }

  Future<Map<String, dynamic>> getWeightChart({int days = 90}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final sinceStr = _dateStr(since);
    final rows = await _db.query('weight_logs',
        where: 'user_id = ? AND date >= ?',
        whereArgs: [_uid, sinceStr],
        orderBy: 'date ASC');
    return {
      'entries': rows.map((r) => {
            'date'      : r['date'],
            'weight_kg' : r['weight_kg'],
            'bmi'       : r['bmi'],
          }).toList(),
      'days': days,
    };
  }

  // ── Ovulation ───────────────────────────────────────────────────────────────

  Future<void> confirmOvulation({
    required String date,
    String? dischargeType,
    double? basalTemp,
    bool? hadCramps,
    bool? lhSurge,
    String? notes,
  }) async {
    // Find predicted ovulation date from latest dashboard prediction
    final dash = await getDashboard();
    final predictedDate = dash.ovulationDate;
    int? daysOff;
    if (predictedDate != null) {
      daysOff = _daysBetween(predictedDate, date).abs();
    }

    await _db.insert('ovulation_logs', {
      'user_id'                   : _uid,
      'date'                      : date,
      if (dischargeType != null)  'discharge_type'           : dischargeType,
      if (basalTemp != null)      'basal_temp'               : basalTemp,
      if (hadCramps != null)      'had_cramps'               : hadCramps ? 1 : 0,
      if (lhSurge != null)        'lh_surge'                 : lhSurge ? 1 : 0,
      if (notes != null)          'notes'                    : notes,
      if (predictedDate != null)  'predicted_ovulation_date' : predictedDate,
      if (daysOff != null)        'days_off_prediction'      : daysOff,
      'created_at': _now(),
    });
  }

  Future<List<LocalOvulationLog>> getOvulationLogs({int limit = 12}) async {
    final rows = await _db.query('ovulation_logs',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'date DESC',
        limit: limit);
    return rows.map(LocalOvulationLog.fromRow).toList();
  }

  Future<Map<String, dynamic>> getOvulationAccuracy() async {
    final logs = await getOvulationLogs(limit: 24);
    if (logs.isEmpty) return {'total': 0, 'exact': 0, 'within_2_days': 0};
    final exact  = logs.where((l) => (l.daysOff ?? 99) == 0).length;
    final within2 = logs.where((l) => (l.daysOff ?? 99) <= 2).length;
    return {
      'total'       : logs.length,
      'exact'       : exact,
      'within_2_days': within2,
      'accuracy_pct': logs.isNotEmpty ? (within2 / logs.length * 100).round() : 0,
    };
  }

  // ── PMS Feedback ────────────────────────────────────────────────────────────

  Future<void> submitPmsFeedback({
    required bool arrivedAsPredicted,
    String? actualPmsStart,
    int? severity,
    String? notes,
  }) async {
    final dash  = await getDashboard();
    final pmsDate = dash.pmsPeakDate;
    await _db.insert('pms_feedback', {
      'user_id'                  : _uid,
      'pms_arrived_as_predicted' : arrivedAsPredicted ? 1 : 0,
      if (actualPmsStart != null) 'actual_pms_start': actualPmsStart,
      if (pmsDate != null)        'predicted_pms_date': pmsDate,
      if (severity != null)       'pms_severity': severity,
      if (notes != null)          'notes': notes,
      'created_at': _now(),
    });
  }

  Future<List<LocalPmsFeedbackRecord>> getPmsFeedback({int limit = 12}) async {
    final rows = await _db.query('pms_feedback',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'created_at DESC',
        limit: limit);
    return rows.map(LocalPmsFeedbackRecord.fromRow).toList();
  }

  // ── Dashboard (replaces GET /api/dashboard/) ────────────────────────────────

  Future<LocalDashboardData> getDashboard() async {
    await _ensureDefaultUser();
    final profile  = await getProfile();
    final cycles   = await getCycles(limit: 12);
    final moods    = await _getMoodRows(limit: 14);
    final sleep    = await getSleepLogs(limit: 14);

    if (cycles.isEmpty) {
      return const LocalDashboardData(
        hasData: false,
        message: 'Log your first cycle to unlock AI predictions!',
      );
    }

    final avgCycleLength = (profile['avg_cycle_length'] as num?)?.toInt() ?? 28;
    final latest         = cycles.first;
    final today          = DateTime.now();

    // ── Kalman prediction ───────────────────────────────────────────────────
    final kalman = await _loadKalmanState();
    final recentLengths = cycles
        .where((c) => c.cycleLength != null)
        .take(6)
        .map((c) => c.cycleLength!.toDouble())
        .toList();

    // Phase 3: ONNX GradientBoosting prediction (falls back to weighted avg)
    double baseline = avgCycleLength.toDouble();
    try {
      final profile = await getProfile();
      final dob = profile['date_of_birth'] as String?;
      final age = dob != null
          ? (DateTime.now().year - DateTime.parse(dob).year).toDouble()
          : 28.0;
      final bmi = _computeBmi(profile) ?? 22.0;
      final sleepRows = await getSleepLogs(limit: 7);
      final moodRows  = await _getMoodRows(limit: 7);
      final sympRows  = await getSymptoms(limit: 30);

      final avgSleep = sleepRows.where((s) => s.hoursSlept != null)
          .map((s) => s.hoursSlept!).fold(0.0, (a,b)=>a+b) /
          (sleepRows.where((s)=>s.hoursSlept!=null).length + 0.001);
      final avgStress = moodRows.isNotEmpty
          ? moodRows.map((m)=>(m['intensity']as num?)?.toDouble()??5.0)
              .fold(0.0,(a,b)=>a+b) / moodRows.length * 10
          : 5.0;

      final sympMap = <String, double>{};
      for (final s in sympRows) {
        sympMap[s.symptomType] = ((sympMap[s.symptomType] ?? 0) + s.severity / 10) / 2;
      }

      final onnxInput = OnnxPredictorInput(
        recentCycleLengths  : recentLengths,
        avgPeriodLength     : avgCycleLength > 0 ? avgCycleLength * 0.18 : 5.0,
        avgSleepHours       : avgSleep > 1 ? avgSleep : 7.0,
        avgStressLevel      : avgStress,
        exerciseDaysPerWeek : (profile['exercise_days_per_week'] as num?)?.toDouble() ?? 3.0,
        recentSymptomScores : sympMap,
        age                 : age,
        bmi                 : bmi,
      );
      final onnxResult = await OnnxCyclePredictorService.instance.predict(onnxInput);
      baseline = onnxResult.predictedCycleLength;
    } catch (_) {
      // Fallback: weighted average
      if (recentLengths.isNotEmpty) {
        final n = math.min(recentLengths.length, 3);
        final w = [0.5, 0.3, 0.2].take(n).toList();
        final wSum = w.reduce((a, b) => a + b);
        baseline = 0;
        for (int i = 0; i < n; i++) {
          baseline += recentLengths[i] * w[i] / wSum;
        }
      }
    }

    final blendResult = blendPredictions(
      baselinePrediction: baseline,
      kalmanState: kalman ?? KalmanState.initial(),
      nLoggedCycles: kalman?.nObservations ?? 0,
    );

    final predictedCycleLen = blendResult['predicted_cycle_length'] as int;
    final confidence = blendResult['confidence_score'] as double;
    final method = blendResult['method'] as String;

    // ── Dates ───────────────────────────────────────────────────────────────
    final lastStart    = DateTime.parse(latest.startDate);
    final nextPeriod   = lastStart.add(Duration(days: predictedCycleLen));
    final ovulation    = nextPeriod.subtract(const Duration(days: 14));
    final fertileStart = ovulation.subtract(const Duration(days: 5));
    final fertileEnd   = ovulation.add(const Duration(days: 1));

    final cycleDay = today.difference(lastStart).inDays + 1;
    final daysUntil = nextPeriod.difference(today).inDays;

    // Phase
    final phase = _cyclePhase(cycleDay, predictedCycleLen);

    // PMS
    final pmsPeak   = nextPeriod.subtract(const Duration(days: 3));
    final recentStress = moods.where((m) => m['intensity'] != null).map((m) => (m['intensity'] as num).toDouble() * 10).toList();
    final sleepHours   = sleep.where((s) => s.hoursSlept != null).map((s) => s.hoursSlept!).toList();
    final pmsRisk = _computePmsRisk(recentStress, sleepHours);

    // Health score
    final healthScore = _computeHealthScore(profile, moods, sleepHours, recentStress);

    // Today's mood / symptoms
    final todayStr   = _today();
    final todayMoods = moods.where((m) => m['date'] == todayStr).toList();
    final todayMood  = todayMoods.isNotEmpty ? todayMoods.first['primary_mood'] as String? : null;
    final todaySympRows = await _db.query('symptoms',
        where: 'user_id = ? AND date = ?', whereArgs: [_uid, todayStr]);
    final todaySymptoms = todaySympRows.map((r) => r['symptom_type'] as String).toList();

    // Last journal sentiment
    final journals = await _db.query('journal_entries',
        where: 'user_id = ? AND date = ?', whereArgs: [_uid, todayStr], limit: 1);
    final lastSentiment = journals.isNotEmpty ? (journals.first['sentiment_score'] as num?)?.toDouble() ?? 0.0 : 0.0;

    // Sleep/stress averages for last 7 days
    final recentSleep7 = sleepHours.take(7).toList();
    final recentStress7 = recentStress.take(7).toList();

    return LocalDashboardData(
      hasData              : true,
      currentCycleDay      : cycleDay,
      currentPhase         : phase,
      nextPeriodDate       : _dateStr(nextPeriod),
      daysUntilPeriod      : daysUntil,
      ovulationDate        : _dateStr(ovulation),
      fertileWindowStart   : _dateStr(fertileStart),
      fertileWindowEnd     : _dateStr(fertileEnd),
      confidenceScore      : confidence,
      predictionMethod     : method,
      moodToday            : todayMood,
      symptomsToday        : todaySymptoms,
      healthScore          : healthScore,
      aiInsightTitle       : 'Daily Insight',
      aiInsightMessage     : _ruleBasedInsight(phase, recentSleep7.isNotEmpty ? _avg(recentSleep7) : 7.0, recentStress7.isNotEmpty ? _avg(recentStress7) : 5.0),
      ollamaAvailable      : true,
      lastJournalSentiment : lastSentiment,
      cycleLengthPrediction: predictedCycleLen,
      pmsPeakDate          : _dateStr(pmsPeak),
      pmsRiskLevel         : pmsRisk > 0.65 ? 'high' : pmsRisk > 0.35 ? 'medium' : 'low',
      pmsRiskScore         : pmsRisk,
      avgSleepFromDash     : recentSleep7.isNotEmpty ? _avg(recentSleep7) : null,
      avgStressFromDash    : recentStress7.isNotEmpty ? _avg(recentStress7) : null,
      sentimentStressLevel : (kalman ?? KalmanState.initial()).sentimentStressLevel,
      sentimentVarianceEffect: (blendResult['sentiment_variance_effect'] as num?)?.toDouble(),
      nPersonalCycles      : kalman?.nObservations ?? 0,
      kalmanStd            : (blendResult['kalman_std'] as num?)?.toDouble(),
    );
  }

  // ── Suggestions (replaces GET /api/dashboard/suggestions) ──────────────────

  Future<List<LocalSuggestionData>> getSuggestions() async {
    final dash    = await getDashboard();

    // No cycle logged yet → return empty so the UI shows the prompt
    // 'Log a cycle to get personalised suggestions' instead of generic ones.
    if (!dash.hasData) return [];

    final profile = await getProfile();

    final moods    = await _getMoodRows(limit: 7);
    final sleep    = await getSleepLogs(limit: 7);
    final symptoms = await getSymptoms(limit: 30);

    final sleepHours = sleep.where((s) => s.hoursSlept != null).map((s) => s.hoursSlept!).toList();
    final avgSleep   = sleepHours.isNotEmpty ? _avg(sleepHours) : (profile['avg_sleep_hours'] as num?)?.toDouble() ?? 7.0;
    final stressVals = moods.where((m) => m['intensity'] != null).map((m) => (m['intensity'] as num).toDouble() * 10).toList();
    final avgStress  = stressVals.isNotEmpty ? _avg(stressVals) : (profile['avg_stress_level'] as num?)?.toDouble() ?? 5.0;

    // Today's mood
    final todayMoods = moods.where((m) => m['date'] == _today()).toList();
    final currentMood = todayMoods.isNotEmpty
        ? todayMoods.first['primary_mood'] as String? ?? 'neutral'
        : 'neutral';
    final energyVal = todayMoods.isNotEmpty
        ? (todayMoods.first['energy_level'] as num?)?.toDouble() ?? 5.0
        : 5.0;

    // Build context for SuggestionEngine (matches Python generate_suggestions() contract)
    final userContext = se.SuggestionContext(
      cyclePhase       : dash.currentPhase,
      currentMood      : currentMood,
      energyLevel      : energyVal,
      symptoms         : symptoms.take(10).map((s) => s.symptomType).toSet().toList(),
      sleepHours       : sleepHours.isNotEmpty ? sleepHours.first : avgSleep,
      stressLevel      : avgStress,
      avgSleepHours    : avgSleep,
      fitnessLevel     : profile['fitness_level'] as String? ?? 'moderate',
      healthGoals      : (profile['health_goals'] is List)
          ? List<String>.from(profile['health_goals'] as List)
          : EvaDatabase.decodeList(profile['health_goals'] as String?).cast<String>(),
      dietaryPreference: profile['dietary_preference'] as String? ?? 'omnivore',
      bmi              : _computeBmi(profile) ?? 22.0,
      age              : _ageFromProfile(profile).toInt(),
    );

    final result = se.SuggestionEngine().generateSuggestions(userContext);

    return result.suggestions.map((s) => LocalSuggestionData(
      category   : s.category,
      title      : s.title,
      description: s.description,
      reason     : s.reason,
    )).toList();
  }
  // ── Health Risks ─────────────────────────────────────────────────────────────

  Future<List<LocalHealthRisk>> getHealthRisks() async {
    final cycles   = await getCycles(limit: 24);
    final symptoms = await getSymptoms(limit: 200);
    final moods    = await _getMoodRows(limit: 60);

    final journals = await _db.query('journal_entries',
        where: 'user_id = ?', whereArgs: [_uid], orderBy: 'date DESC', limit: 60);
    final sentiments = journals
        .where((j) => j['sentiment_score'] != null)
        .map((j) => (j['sentiment_score'] as num).toDouble())
        .toList();
    final avgSentiment = sentiments.isNotEmpty
        ? sentiments.reduce((a, b) => a + b) / sentiments.length : 0.0;

    final result = hre.HealthRiskEstimator().assess(hre.RiskAssessmentInput(
      cycleHistory        : cycles.map((c) => <String, dynamic>{
        'cycle_length'  : c.cycleLength,
        'flow_intensity': c.flowIntensity,
      }).toList(),
      symptomHistory      : symptoms.map((s) => <String, dynamic>{
        'symptom_type': s.symptomType,
        'severity'    : s.severity,
      }).toList(),
      moodHistory         : moods.map((m) => <String, dynamic>{
        'primary_mood': m['primary_mood'],
        'intensity'   : m['intensity'],
      }).toList(),
      avgJournalSentiment : avgSentiment,
    ));

    String pickLevel(double score) =>
        score > 0.65 ? 'high' : score > 0.35 ? 'medium' : 'low';

    // FIX #8: Severity-based names + recommendations
    String irregularName;
    List<String> irregularRecs;
    final ir = result.irregularCycleRisk;
    if (ir < 0.20) {
      irregularName = 'Cycle Consistency ✓';
      irregularRecs = ['Great tracking! Your cycle shows good consistency — keep logging to maintain accuracy.'];
    } else if (ir < 0.45) {
      irregularName = 'Cycle Variability (Mild)';
      irregularRecs = [
        'Minor cycle variation detected. Try maintaining consistent sleep (7–9h) and managing stress through breathing or light yoga.',
        'Mood tracking can help — log how you feel each day to spot patterns.',
      ];
    } else if (ir < 0.70) {
      irregularName = 'Cycle Variability (Moderate)';
      irregularRecs = [
        'Your cycles show moderate variability. Focus on stress reduction, consistent sleep, and balanced nutrition.',
        'Keeping a mood + symptom log helps identify what\'s affecting your cycle rhythm.',
        'Consider speaking with a gynecologist if this persists beyond 2–3 months.',
      ];
    } else {
      irregularName = 'Irregular Cycle Pattern';
      irregularRecs = result.recommendations
          .where((r) => r.contains('variability') || r.contains('irregular') || r.contains('Log at least'))
          .toList();
    }

    return [
      LocalHealthRisk(
        name: irregularName,
        score: ir,
        level: pickLevel(ir),
        recommendations: irregularRecs,
      ),
      LocalHealthRisk(
        name: 'PCOS Pattern Risk',
        score: result.pcosProbability,
        level: pickLevel(result.pcosProbability),
        recommendations: result.recommendations
            .where((r) => r.contains('PCOS'))
            .toList(),
      ),
      LocalHealthRisk(
        name: 'Hormonal Balance',
        score: result.hormonalImbalanceIndicator,
        level: pickLevel(result.hormonalImbalanceIndicator),
        recommendations: result.hormonalImbalanceIndicator < 0.35
            ? ['Hormonal balance looks good. Continue consistent sleep and stress management.']
            : result.recommendations
                .where((r) => r.contains('Hormonal') || r.contains('magnesium'))
                .toList(),
      ),
      LocalHealthRisk(
        name: 'Anemia Risk',
        score: result.anemiaRisk,
        level: pickLevel(result.anemiaRisk),
        recommendations: result.recommendations
            .where((r) => r.contains('iron') || r.contains('flow'))
            .toList(),
      ),
    ];
  }

  // ── Phase Tasks ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPhaseTasks() async {
    final dash = await getDashboard();
    final phase = dash.currentPhase;
    return {
      'phase'    : phase,
      'cycle_day': dash.currentCycleDay,
      'tasks'    : _phaseTasks[phase] ?? _phaseTasks['follicular'],
    };
  }

  // ── Emotion Timeline ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getEmotionTimeline({int days = 30}) async {
    final since    = DateTime.now().subtract(Duration(days: days));
    final sinceStr = _dateStr(since);

    final journals = await _db.query('journal_entries',
        where: 'user_id = ? AND date >= ?',
        whereArgs: [_uid, sinceStr],
        orderBy: 'date ASC');

    final moods = await _db.query('mood_logs',
        where: 'user_id = ? AND date >= ?',
        whereArgs: [_uid, sinceStr],
        orderBy: 'date ASC');

    final timeline = <Map<String, dynamic>>[];

    for (final e in journals) {
      timeline.add({
        'date'      : e['date'],
        'source'    : 'journal',
        'sentiment' : e['sentiment_score'],
        'emotion'   : e['primary_emotion'],
        'word_count': e['word_count'],
      });
    }

    for (final m in moods) {
      timeline.add({
        'date'   : m['date'],
        'source' : 'mood',
        'sentiment': null,
        'emotion': m['primary_mood'],
        'energy' : m['energy_level'],
      });
    }

    timeline.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    final emotions = timeline.where((t) => t['emotion'] != null).map((t) => t['emotion'] as String).toList();
    final emotionFreq = <String, int>{};
    for (final e in emotions) {
      emotionFreq[e] = (emotionFreq[e] ?? 0) + 1;
    }
    final topEmotions = Map.fromEntries(
        emotionFreq.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));

    final sentiments = timeline.where((t) => t['sentiment'] != null).map((t) => (t['sentiment'] as num).toDouble()).toList();
    final avgSentiment = sentiments.isNotEmpty ? _avg(sentiments) : 0.0;

    return {
      'days'          : days,
      'entry_count'   : journals.length,
      'mood_log_count': moods.length,
      'avg_sentiment' : double.parse(avgSentiment.toStringAsFixed(3)),
      'top_emotions'  : topEmotions,
      'timeline'      : timeline,
    };
  }

  // ── Chat Memory ──────────────────────────────────────────────────────────────

  Future<LocalChatMemorySummary> getChatMemory() async {
    final since    = DateTime.now().subtract(const Duration(days: 30));
    final sinceStr = _dateStr(since);

    final journals = await _db.query('journal_entries',
        where: 'user_id = ? AND date >= ?',
        whereArgs: [_uid, sinceStr],
        orderBy: 'date DESC');

    final moods = await _db.query('mood_logs',
        where: 'user_id = ? AND date >= ?',
        whereArgs: [_uid, sinceStr]);

    final cycles = await getCycles(limit: 3);

    // Keyword frequency
    final allKeywords = <String>[];
    for (final j in journals) {
      allKeywords.addAll(EvaDatabase.decodeList(j['keywords'] as String?).cast<String>());
    }
    final keyFreq = <String, int>{};
    for (final k in allKeywords) {
      keyFreq[k] = (keyFreq[k] ?? 0) + 1;
    }
    final sortedKeys = keyFreq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topKeywords = Map.fromEntries(sortedKeys.take(8));

    // Top mood
    final moodCounts = <String, int>{};
    for (final m in moods) {
      final mood = m['primary_mood'] as String? ?? 'neutral';
      moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
    }
    final topMood = moodCounts.isNotEmpty
        ? (moodCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key
        : 'neutral';

    // Phase sentiment correlation
    final phaseAvg = <String, double>{};
    if (cycles.isNotEmpty) {
      final lastStart = DateTime.parse(cycles.first.startDate);
      final avgCL = cycles.first.cycleLength ?? 28;
      final phaseSentiments = <String, List<double>>{};

      for (final j in journals) {
        if (j['sentiment_score'] == null) continue;
        final jDate = DateTime.parse(j['date'] as String);
        final day = jDate.difference(lastStart).inDays + 1;
        final phase = _cyclePhase(day, avgCL);
        phaseSentiments.putIfAbsent(phase, () => []);
        phaseSentiments[phase]!.add((j['sentiment_score'] as num).toDouble());
      }

      phaseAvg.addAll(phaseSentiments.map((phase, scores) =>
          MapEntry(phase, double.parse(_avg(scores).toStringAsFixed(2)))));
    }

    final bestPhase = phaseAvg.isNotEmpty
        ? (phaseAvg.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key
        : null;

    // Summary bullets
    final summaries = <String>[];
    if (journals.length >= 3) summaries.add('You\'ve written ${journals.length} journal entries this month.');
    if (topKeywords.isNotEmpty) {
      final top3 = topKeywords.keys.take(3).join(', ');
      summaries.add('You often write about: $top3.');
    }
    final stressKeys = allKeywords.where((k) => ['stress', 'work', 'anxiety', 'tired', 'exhausted', 'overwhelmed', 'sad', 'pressure'].contains(k)).length;
    if (stressKeys >= 3) summaries.add('Work stress has appeared $stressKeys times in your journals this month.');

    return LocalChatMemorySummary(
      totalJournalEntries: journals.length,
      topMood            : topMood,
      topKeywords        : topKeywords.map((k, v) => MapEntry(k, v)),
      phaseAvgSentiment  : phaseAvg,
      bestPhase          : bestPhase,
      summaries          : summaries,
    );
  }

  // ── Anomaly Detection ────────────────────────────────────────────────────────

  Future<List<LocalAnomalyAlert>> getCycleAnomalies() async {
    final cycles  = await getCycles(limit: 6);
    final profile = await getProfile();
    if (cycles.length < 2) return [];

    final alerts = <LocalAnomalyAlert>[];
    final today  = DateTime.now();
    final latest = cycles.first;
    final avgCL  = (profile['avg_cycle_length'] as num?)?.toInt() ?? 28;

    // 1. Late period
    final daysSince = today.difference(DateTime.parse(latest.startDate)).inDays;
    if (daysSince > avgCL + 5) {
      final daysLate = daysSince - avgCL;
      alerts.add(LocalAnomalyAlert(
        type     : 'late_period',
        severity : daysLate < 14 ? 'medium' : 'high',
        title    : 'Period is $daysLate days late',
        message  : 'Your period is $daysLate days overdue based on your average $avgCL-day cycle.',
      ));
    }

    // 2. Flow anomaly
    final recentFlows = cycles.take(4).where((c) => c.flowIntensity != null).map((c) => c.flowIntensity!).toList();
    if (recentFlows.length >= 3 && latest.flowIntensity != null) {
      final flowMap = {'light': 1, 'medium': 2, 'heavy': 3};
      final scores  = recentFlows.skip(1).map((f) => flowMap[f] ?? 2).toList();
      final avgScore = _avg(scores.map((e) => e.toDouble()).toList());
      final curScore = (flowMap[latest.flowIntensity!] ?? 2).toDouble();
      if ((curScore - avgScore).abs() >= 1.5) {
        final label = curScore > avgScore ? 'heavier' : 'lighter';
        alerts.add(LocalAnomalyAlert(
          type    : 'flow_anomaly',
          severity: 'low',
          title   : 'Unusually $label flow this cycle',
          message : 'Your current flow (${latest.flowIntensity}) is notably $label than your recent cycles.',
        ));
      }
    }

    // 3. Cycle length anomaly
    final lengths = cycles.skip(1).take(4).where((c) => c.cycleLength != null).map((c) => c.cycleLength!.toDouble()).toList();
    if (lengths.length >= 3 && latest.cycleLength != null) {
      final avgLen = _avg(lengths);
      final diff   = latest.cycleLength! - avgLen;
      if (diff.abs() >= 7) {
        final label = diff > 0 ? 'longer' : 'shorter';
        alerts.add(LocalAnomalyAlert(
          type    : 'cycle_length_anomaly',
          severity: 'low',
          title   : 'Cycle was ${diff.abs().round()} days $label than usual',
          message : 'This cycle (${latest.cycleLength} days) is notably $label than your recent average (${avgLen.round()} days).',
        ));
      }
    }

    return alerts;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  Internal helpers
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _ensureDefaultUser() async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [_uid]);
    if (rows.isEmpty) {
      await _db.insert('users', {
        'id'        : _uid,
        'email'     : 'local@eva.app',
        'username'  : 'Me',
        'created_at': _now(),
      });
    }
  }

  Future<KalmanState?> _loadKalmanState() async {
    final rows = await _db.query('user_kalman_states',
        where: 'user_id = ?', whereArgs: [_uid]);
    if (rows.isEmpty) return null;
    return KalmanState.fromMap({
      'kalman_mean'      : rows.first['kalman_mean'],
      'kalman_variance'  : rows.first['kalman_variance'],
      'n_observations'   : rows.first['n_observations'],
      'cycle_history'    : EvaDatabase.decodeList(rows.first['cycle_history'] as String?),
      'sentiment_history': EvaDatabase.decodeList(rows.first['sentiment_history'] as String?),
    });
  }

  Future<void> _updateKalmanFromCycle(double observedLength) async {
    var state = await _loadKalmanState() ?? KalmanState.initial();
    state.update(observedLength);
    await _saveKalmanState(state);
  }

  Future<void> updateKalmanSentimentOnly(String text) async {
    try {
      final detector = EmotionDetector();
      final result   = detector.analyze(text);
      await _updateKalmanFromSentiment(result.sentimentScore);
    } catch (_) {}
  }

  Future<void> _updateKalmanFromSentiment(double score) async {
    var state = await _loadKalmanState() ?? KalmanState.initial();
    state.updateFromSentiment(score);
    await _saveKalmanStatePartial(state);
  }

  Future<void> _saveKalmanState(KalmanState s) async {
    final row = {
      'user_id'         : _uid,
      'kalman_mean'     : s.mean,
      'kalman_variance' : s.variance,
      'n_observations'  : s.nObservations,
      'cycle_history'   : EvaDatabase.encodeList(s.cycleHistory),
      'sentiment_history': EvaDatabase.encodeList(s.sentimentHistory),
      'updated_at'      : _now(),
    };
    await _db.insert('user_kalman_states', row); // REPLACE conflict algo
  }

  Future<void> _saveKalmanStatePartial(KalmanState s) async {
    final existing = await _db.query('user_kalman_states',
        where: 'user_id = ?', whereArgs: [_uid]);
    if (existing.isEmpty) {
      await _saveKalmanState(s);
    } else {
      await _db.update('user_kalman_states', {
        'kalman_variance'  : s.variance,
        'sentiment_history': EvaDatabase.encodeList(s.sentimentHistory),
        'updated_at'       : _now(),
      }, where: 'user_id = ?', whereArgs: [_uid]);
    }
  }

  Future<void> _updateUserAvgCycleLength() async {
    final cycles = await getCycles(limit: 6);
    final lengths = cycles.where((c) => c.cycleLength != null).map((c) => c.cycleLength!).toList();
    if (lengths.isEmpty) return;
    final avg = (_avg(lengths.map((e) => e.toDouble()).toList())).round();
    await _db.update('users', {'avg_cycle_length': avg},
        where: 'id = ?', whereArgs: [_uid]);
  }

  Future<List<Map<String, dynamic>>> _getMoodRows({int limit = 14}) async {
    return _db.query('mood_logs',
        where: 'user_id = ?',
        whereArgs: [_uid],
        orderBy: 'date DESC',
        limit: limit);
  }

  // ── Phase calculation ─────────────────────────────────────────────────────

  String _cyclePhase(int cycleDay, int cycleLength) {
    final day = ((cycleDay - 1) % cycleLength) + 1;
    if (day <= 5)  return 'menstrual';
    if (day <= 13) return 'follicular';
    if (day <= 16) return 'ovulation';
    return 'luteal';
  }

  // ── Score helpers ─────────────────────────────────────────────────────────

  double _computePmsRisk(List<double> stress, List<double> sleep) {
    final avgStress = stress.isNotEmpty ? _avg(stress) : 5.0;
    final avgSleep  = sleep.isNotEmpty  ? _avg(sleep)  : 7.0;
    return math.min(1.0, (avgStress / 10) * 0.65 + math.max(0, (7.5 - avgSleep) / 7.5) * 0.35);
  }

  double _computeHealthScore(Map<String, dynamic> profile, List<Map<String, dynamic>> moods,
      List<double> sleep, List<double> stress) {
    final avgSleep  = sleep.isNotEmpty  ? _avg(sleep)  : (profile['avg_sleep_hours']  as num?)?.toDouble() ?? 7.0;
    final avgStress = stress.isNotEmpty ? _avg(stress) : (profile['avg_stress_level'] as num?)?.toDouble() ?? 5.0;
    final moods7    = moods.take(7).toList();
    final avgMood   = moods7.isNotEmpty ? _avg(moods7.map((m) => 1.0 - ((m['intensity'] as num?)?.toDouble() ?? 0.5)).toList()) : 0.5;

    final sleepScore  = math.min(1.0, avgSleep / 8.5);
    final stressScore = math.max(0.0, 1.0 - avgStress / 10.0);
    final bmi         = _computeBmi(profile);
    final bmiScore    = bmi == null ? 0.8 : (bmi >= 18.5 && bmi <= 24.9) ? 1.0 : (bmi >= 17.0 && bmi <= 29.9) ? 0.75 : 0.5;

    return double.parse(
        (sleepScore * 0.30 + stressScore * 0.30 + avgMood * 0.25 + bmiScore * 0.15).toStringAsFixed(3));
  }

  double? _computeBmi(Map<String, dynamic> profile) {
    final h = (profile['height_cm'] as num?)?.toDouble();
    final w = (profile['weight_kg'] as num?)?.toDouble();
    if (h == null || w == null || h == 0) return null;
    return w / math.pow(h / 100, 2);
  }

  int _ageFromProfile(Map<String, dynamic> profile) {
    final dob = profile['date_of_birth'] as String?;
    if (dob == null || dob.isEmpty) return 28;
    try {
      final birth = DateTime.parse(dob);
      return DateTime.now().difference(birth).inDays ~/ 365;
    } catch (_) { return 28; }
  }

  // ignore: unused_element
  String _riskLevel(double score) {
    if (score > 0.65) return 'high';
    if (score > 0.35) return 'medium';
    return 'low';
  }

  String _ruleBasedInsight(String phase, double avgSleep, double avgStress) {
    final lines = {
      'menstrual' : 'Rest and iron-rich foods are your allies today. Be gentle with yourself.',
      'follicular': 'Your energy is rising — a great day for new ideas and light exercise.',
      'ovulation' : 'Peak communication phase. Connect with the people who matter to you.',
      'luteal'    : 'Support your body with magnesium and calming routines today.',
    };
    var base = lines[phase] ?? 'Tracking your patterns helps reveal what your body needs most.';
    if (avgSleep < 6) {
      base += ' Prioritise sleep tonight — it makes everything easier.';
    } else if (avgStress > 7) base += ' Take a few slow breaths. Stress is high; small breaks really help.';
    return base;
  }

  // ── Local text analysis (replaces DistilRoBERTa) ─────────────────────────

  // ── Math utilities ────────────────────────────────────────────────────────

  double _avg(List<double> list) =>
      list.isEmpty ? 0.0 : list.reduce((a, b) => a + b) / list.length;

  // ignore: unused_element
  double _std(List<double> list) {
    if (list.length < 2) return 0.0;
    final avg = _avg(list);
    return math.sqrt(
        list.map((x) => math.pow(x - avg, 2)).reduce((a, b) => a + b) / list.length);
  }

  String _today() => _dateStr(DateTime.now());
  String _now()   => DateTime.now().toIso8601String();

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _daysBetween(String a, String b) {
    final da = DateTime.parse(a);
    final db = DateTime.parse(b);
    return db.difference(da).inDays;
  }

  // ── Phase Tasks data table ─────────────────────────────────────────────────

  static const Map<String, List<Map<String, String>>> _phaseTasks = {
    'menstrual': [
      {'task': 'Cancel non-essential commitments and rest',       'priority': 'high'},
      {'task': 'Use a heating pad for cramp relief',              'priority': 'high'},
      {'task': 'Journal about how you\'re feeling',               'priority': 'medium'},
      {'task': 'Light yoga or stretching — avoid intense cardio', 'priority': 'medium'},
      {'task': 'Stock up on iron-rich foods (spinach, lentils)',   'priority': 'medium'},
      {'task': 'Postpone important decisions if possible',        'priority': 'low'},
    ],
    'follicular': [
      {'task': 'Schedule hard conversations — estrogen is rising',           'priority': 'high'},
      {'task': 'Start that new project you\'ve been putting off',            'priority': 'high'},
      {'task': 'Book social events — you\'ll feel more outgoing',            'priority': 'medium'},
      {'task': 'Plan your most demanding workouts this week',                'priority': 'medium'},
      {'task': 'Try a creative activity — brain fog is at its lowest',       'priority': 'medium'},
      {'task': 'Set your goals for this cycle',                              'priority': 'low'},
    ],
    'ovulation': [
      {'task': 'Schedule your most important meetings or presentations',     'priority': 'high'},
      {'task': 'Have difficult conversations now — charisma peaks today',    'priority': 'high'},
      {'task': 'Log ovulation signs (discharge, temperature, cramps)',       'priority': 'high'},
      {'task': 'Book a first date or social gathering',                      'priority': 'medium'},
      {'task': 'Maximum intensity workout — body is at peak strength',       'priority': 'medium'},
      {'task': 'Take on leadership opportunities at work',                   'priority': 'low'},
    ],
    'luteal': [
      {'task': 'Avoid major life decisions in late luteal (PMS window)',     'priority': 'high'},
      {'task': 'Prepare easy meals — appetite and cravings will spike',      'priority': 'high'},
      {'task': 'Reduce caffeine and alcohol to ease PMS symptoms',           'priority': 'high'},
      {'task': 'Prioritise sleep — aim for 8+ hours',                       'priority': 'medium'},
      {'task': 'Schedule solo activities — social battery depletes faster',  'priority': 'medium'},
      {'task': 'Set boundaries at work — say no to extra commitments',       'priority': 'medium'},
      {'task': 'Do a gentle walk or swim — avoid HIIT',                     'priority': 'low'},
    ],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data classes (mirror ai_service.dart counterparts for drop-in compatibility)
// ─────────────────────────────────────────────────────────────────────────────

class LocalDashboardData {
  final bool    hasData;
  final String? message;
  final int     currentCycleDay;
  final String  currentPhase;
  final String? nextPeriodDate;
  final int     daysUntilPeriod;
  final String? ovulationDate;
  final String? fertileWindowStart;
  final String? fertileWindowEnd;
  final double  confidenceScore;
  final String  predictionMethod;
  final String? moodToday;
  final List<String> symptomsToday;
  final double  healthScore;
  final String  aiInsightTitle;
  final String  aiInsightMessage;
  final bool    ollamaAvailable;
  final double  lastJournalSentiment;
  final int?    cycleLengthPrediction;
  final String? pmsPeakDate;
  final String? pmsRiskLevel;
  final double? pmsRiskScore;
  final double? avgSleepFromDash;
  final double? avgStressFromDash;
  final String? sentimentStressLevel;
  final double? sentimentVarianceEffect;
  final int?    nPersonalCycles;
  final double? kalmanStd;

  const LocalDashboardData({
    required this.hasData,
    this.message,
    this.currentCycleDay      = 0,
    this.currentPhase         = 'follicular',
    this.nextPeriodDate,
    this.daysUntilPeriod      = 0,
    this.ovulationDate,
    this.fertileWindowStart,
    this.fertileWindowEnd,
    this.confidenceScore      = 0,
    this.predictionMethod     = 'statistical_baseline',
    this.moodToday,
    this.symptomsToday        = const [],
    this.healthScore          = 0,
    this.aiInsightTitle       = 'Daily Insight',
    this.aiInsightMessage     = '',
    this.ollamaAvailable      = true,
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
}

class LocalSuggestionData {
  final String category;
  final String title;
  final String description;
  final String reason;
  final bool   isAI;
  const LocalSuggestionData({
    required this.category,
    required this.title,
    required this.description,
    required this.reason,
    this.isAI = false,
  });
}

class LocalHealthRisk {
  final String name;
  final double score;
  final String level;
  final List<String> recommendations;
  const LocalHealthRisk({required this.name, required this.score, required this.level, required this.recommendations});
}

class LocalEmotionResult {
  final double              sentiment;
  final String              primaryEmotion;
  final Map<String, double> emotionScores;
  final String              aiResponse;
  final List<String>        keywords;
  const LocalEmotionResult({
    required this.sentiment,
    required this.primaryEmotion,
    required this.emotionScores,
    required this.aiResponse,
    required this.keywords,
  });
}

class LocalJournalEntry {
  final int     id;
  final String  date;
  final String  entryText;
  final double? sentimentScore;
  final String? primaryEmotion;
  final Map<String, dynamic> emotionAnalysis;
  final List<String> keywords;
  const LocalJournalEntry({
    required this.id,
    required this.date,
    required this.entryText,
    this.sentimentScore,
    this.primaryEmotion,
    this.emotionAnalysis = const {},
    this.keywords        = const [],
  });
  factory LocalJournalEntry.fromRow(Map<String, dynamic> r) => LocalJournalEntry(
    id            : r['id'] as int? ?? 0,
    date          : r['date'] as String? ?? '',
    entryText     : r['entry_text'] as String? ?? '',
    sentimentScore: (r['sentiment_score'] as num?)?.toDouble(),
    primaryEmotion: r['primary_emotion'] as String?,
    emotionAnalysis: EvaDatabase.decodeMap(r['emotion_analysis'] as String?),
    keywords      : EvaDatabase.decodeList(r['keywords'] as String?).cast<String>(),
  );
}

class LocalCycleRecord {
  final int     id;
  final String  startDate;
  final String? endDate;
  final int?    cycleLength;
  final int?    periodLength;
  final String? flowIntensity;
  final String? ovulationDate;
  final String? fertileWindowStart;
  final String? fertileWindowEnd;
  final bool    isRegular;
  final String? notes;
  const LocalCycleRecord({
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
  factory LocalCycleRecord.fromRow(Map<String, dynamic> r) => LocalCycleRecord(
    id              : r['id'] as int? ?? 0,
    startDate       : r['start_date'] as String? ?? '',
    endDate         : r['end_date'] as String?,
    cycleLength     : r['cycle_length'] as int?,
    periodLength    : r['period_length'] as int?,
    flowIntensity   : r['flow_intensity'] as String?,
    ovulationDate   : r['ovulation_date'] as String?,
    fertileWindowStart: r['fertile_window_start'] as String?,
    fertileWindowEnd  : r['fertile_window_end'] as String?,
    isRegular       : (r['is_regular'] as int? ?? 1) == 1,
    notes           : r['notes'] as String?,
  );
}

class LocalSymptomRecord {
  final int    id;
  final String date;
  final String symptomType;
  final int    severity;
  final String? notes;
  const LocalSymptomRecord({required this.id, required this.date, required this.symptomType, required this.severity, this.notes});
  factory LocalSymptomRecord.fromRow(Map<String, dynamic> r) => LocalSymptomRecord(
    id          : r['id'] as int? ?? 0,
    date        : r['date'] as String? ?? '',
    symptomType : r['symptom_type'] as String? ?? '',
    severity    : r['severity'] as int? ?? 1,
    notes       : r['notes'] as String?,
  );
}

class LocalSleepLogData {
  final int     id;
  final String  date;
  final double? hoursSlept;
  final int?    quality;
  final String? wakeTime;
  final String? bedTime;
  final bool?   hadDreams;
  final String? notes;
  const LocalSleepLogData({required this.id, required this.date, this.hoursSlept, this.quality, this.wakeTime, this.bedTime, this.hadDreams, this.notes});
  factory LocalSleepLogData.fromJson(Map<String, dynamic> j) => LocalSleepLogData(
    id        : j['id'] as int? ?? 0,
    date      : j['date'] as String? ?? '',
    hoursSlept: (j['hours_slept'] as num?)?.toDouble(),
    quality   : j['quality'] as int?,
    wakeTime  : j['wake_time'] as String?,
    bedTime   : j['bed_time'] as String?,
    hadDreams : j['had_dreams'] as bool?,
    notes     : j['notes'] as String?,
  );
  factory LocalSleepLogData.fromRow(Map<String, dynamic> r) => LocalSleepLogData(
    id        : r['id'] as int? ?? 0,
    date      : r['date'] as String? ?? '',
    hoursSlept: (r['hours_slept'] as num?)?.toDouble(),
    quality   : r['quality'] as int?,
    wakeTime  : r['wake_time'] as String?,
    bedTime   : r['bed_time'] as String?,
    hadDreams : r['had_dreams'] == null ? null : (r['had_dreams'] as int) == 1,
    notes     : r['notes'] as String?,
  );
}

class LocalWeightLogData {
  final int     id;
  final String  date;
  final double  weightKg;
  final double? bmi;
  final double? waistCm;
  final double? hipsCm;
  final double? bustCm;
  final String? notes;
  const LocalWeightLogData({required this.id, required this.date, required this.weightKg, this.bmi, this.waistCm, this.hipsCm, this.bustCm, this.notes});
  factory LocalWeightLogData.fromRow(Map<String, dynamic> r) => LocalWeightLogData(
    id       : r['id'] as int? ?? 0,
    date     : r['date'] as String? ?? '',
    weightKg : (r['weight_kg'] as num?)?.toDouble() ?? 0.0,
    bmi      : (r['bmi'] as num?)?.toDouble(),
    waistCm  : (r['waist_cm'] as num?)?.toDouble(),
    hipsCm   : (r['hips_cm'] as num?)?.toDouble(),
    bustCm   : (r['bust_cm'] as num?)?.toDouble(),
    notes    : r['notes'] as String?,
  );
}

class LocalOvulationLog {
  final int     id;
  final String  date;
  final String? predictedDate;
  final int?    daysOff;
  final String? dischargeType;
  final double? basalTemp;
  final bool?   hadCramps;
  final bool?   lhSurge;
  final String? notes;
  const LocalOvulationLog({required this.id, required this.date, this.predictedDate, this.daysOff, this.dischargeType, this.basalTemp, this.hadCramps, this.lhSurge, this.notes});
  factory LocalOvulationLog.fromRow(Map<String, dynamic> r) => LocalOvulationLog(
    id           : r['id'] as int? ?? 0,
    date         : r['date'] as String? ?? '',
    predictedDate: r['predicted_ovulation_date'] as String?,
    daysOff      : r['days_off_prediction'] as int?,
    dischargeType: r['discharge_type'] as String?,
    basalTemp    : (r['basal_temp'] as num?)?.toDouble(),
    hadCramps    : r['had_cramps'] == null ? null : (r['had_cramps'] as int) == 1,
    lhSurge      : r['lh_surge'] == null ? null : (r['lh_surge'] as int) == 1,
    notes        : r['notes'] as String?,
  );
}

class LocalPmsFeedbackRecord {
  final int     id;
  final bool?   arrivedAsPredicted;
  final String? actualPmsStart;
  final String? predictedPmsDate;
  final int?    severity;
  final String? notes;
  const LocalPmsFeedbackRecord({required this.id, this.arrivedAsPredicted, this.actualPmsStart, this.predictedPmsDate, this.severity, this.notes});
  factory LocalPmsFeedbackRecord.fromRow(Map<String, dynamic> r) => LocalPmsFeedbackRecord(
    id                 : r['id'] as int? ?? 0,
    arrivedAsPredicted : r['pms_arrived_as_predicted'] == null ? null : (r['pms_arrived_as_predicted'] as int) == 1,
    actualPmsStart     : r['actual_pms_start'] as String?,
    predictedPmsDate   : r['predicted_pms_date'] as String?,
    severity           : r['pms_severity'] as int?,
    notes              : r['notes'] as String?,
  );
}

class LocalAnomalyAlert {
  final String type;
  final String severity;
  final String title;
  final String message;
  const LocalAnomalyAlert({required this.type, required this.severity, required this.title, required this.message});
}

class LocalChatMemorySummary {
  final int                  totalJournalEntries;
  final String               topMood;
  final Map<String, int>     topKeywords;
  final Map<String, double>  phaseAvgSentiment;
  final String?              bestPhase;
  final List<String>         summaries;
  const LocalChatMemorySummary({
    required this.totalJournalEntries,
    required this.topMood,
    required this.topKeywords,
    required this.phaseAvgSentiment,
    this.bestPhase,
    required this.summaries,
  });
}

// ── SleepLogData — typedef so eva_charts.dart & sleep_log_page.dart can use either name ──
typedef SleepLogData = LocalSleepLogData;

// ── PhaseTask — parsed from getPhaseTasks() response ─────────────────────────

class PhaseTask {
  final String task;
  final String icon;
  final String priority;

  const PhaseTask({
    required this.task,
    required this.icon,
    required this.priority,
  });

  factory PhaseTask.fromJson(Map<String, dynamic> j) => PhaseTask(
        task    : j['task']     as String? ?? '',
        icon    : j['icon']     as String? ?? '',
        priority: j['priority'] as String? ?? 'medium',
      );
}

// ── EmotionTimelinePoint — parsed from getEmotionTimeline() response ─────────

class EmotionTimelinePoint {
  final String  date;
  final String  source;    // 'journal' | 'mood'
  final double? sentiment;
  final String? emotion;
  final int?    wordCount;
  final int?    energy;

  const EmotionTimelinePoint({
    required this.date,
    required this.source,
    this.sentiment,
    this.emotion,
    this.wordCount,
    this.energy,
  });

  factory EmotionTimelinePoint.fromJson(Map<String, dynamic> j) =>
      EmotionTimelinePoint(
        date      : j['date']       as String? ?? '',
        source    : j['source']     as String? ?? 'journal',
        sentiment : (j['sentiment'] as num?)?.toDouble(),
        emotion   : j['emotion']    as String?,
        wordCount : j['word_count'] as int?,
        energy    : j['energy']     as int?,
      );
}
