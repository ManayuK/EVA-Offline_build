library onnx_cycle_predictor;

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Scaler parameters (StandardScaler fitted on 12,000 synthetic cycles)
//  Embedded so no extra asset is needed at runtime.
// ─────────────────────────────────────────────────────────────────────────────

const List<double> _scalerMean = [
  28.5015, 28.4992, 28.5130, 28.5046, 1.0545, 5.0225,
  7.0136,  4.5203,  3.1721, 0.1497,  0.1004, 0.1178,
  0.2403,  0.2853,  0.2581, 0.2452,  0.1726, 0.7243,
  0.2757,  28.017,  23.615,
];

const List<double> _scalerStd = [
  3.9431, 3.9689, 3.9597, 3.7725, 0.5621, 1.1896,
  1.1970, 1.9715, 1.6565, 0.3568, 0.3005, 0.3224,
  0.1374, 0.1679, 0.1588, 0.1550, 0.1082, 0.1494,
  0.1494, 5.8823, 4.3008,
];

// ─────────────────────────────────────────────────────────────────────────────
//  Input / output types
// ─────────────────────────────────────────────────────────────────────────────

class OnnxPredictorInput {
  final List<double> recentCycleLengths;   // most recent first
  final double avgPeriodLength;
  final double avgSleepHours;
  final double avgStressLevel;
  final double exerciseDaysPerWeek;
  final bool   hadStressEvent;
  final bool   wasIll;
  final bool   traveled;
  final Map<String, double> recentSymptomScores;
  final List<double> recentMoodScores;     // 0–1 scale
  final double age;
  final double bmi;

  const OnnxPredictorInput({
    required this.recentCycleLengths,
    this.avgPeriodLength        = 5.0,
    this.avgSleepHours          = 7.0,
    this.avgStressLevel         = 5.0,
    this.exerciseDaysPerWeek    = 3.0,
    this.hadStressEvent         = false,
    this.wasIll                 = false,
    this.traveled               = false,
    this.recentSymptomScores    = const {},
    this.recentMoodScores       = const [],
    this.age                    = 28.0,
    this.bmi                    = 22.0,
  });
}

class OnnxPrediction {
  final double predictedCycleLength;
  final bool   usedOnnxModel;
  final double confidence;     // 0–1
  final String method;         // 'onnx_gbr' | 'statistical_baseline'

  const OnnxPrediction({
    required this.predictedCycleLength,
    required this.usedOnnxModel,
    required this.confidence,
    required this.method,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Service
// ─────────────────────────────────────────────────────────────────────────────

class OnnxCyclePredictorService {
  static const String _assetPath = 'assets/ml/cycle_model.onnx';

  OrtSession? _session;
  bool _loadAttempted = false;
  bool _loaded        = false;

  OnnxCyclePredictorService._();
  static final OnnxCyclePredictorService instance = OnnxCyclePredictorService._();

  bool get isLoaded => _loaded;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_loadAttempted) return;
    _loadAttempted = true;
    try {
      OrtEnv.instance.init();
      final bytes    = await rootBundle.load(_assetPath);
      final data     = bytes.buffer.asUint8List();
      final options  = OrtSessionOptions();
      _session       = OrtSession.fromBuffer(data, options);
      _loaded        = true;
    } catch (_) {
      // ONNX asset not found or init failure → statistical fallback
      _loaded = false;
    }
  }

  // ── Feature vector (exact port of cycle_predictor.py prepare_features) ────

  Float32List _buildFeatures(OnnxPredictorInput input) {
    // Ensure 3 recent cycles (pad with mean if fewer)
    final raw = List<double>.from(input.recentCycleLengths);
    while (raw.length < 3) { raw.insert(0, raw.isEmpty ? 28.0 : raw.first); }
    final r = raw.sublist(raw.length - 3); // [oldest, middle, newest]

    final avgR = _mean(r);
    final stdR = _std(r);

    final syms      = input.recentSymptomScores;
    final avgSymp   = syms.isEmpty ? 0.3 : syms.values.reduce((a,b)=>a+b) / syms.length;
    final moods     = input.recentMoodScores.isNotEmpty
        ? input.recentMoodScores : List.filled(7, 0.5);
    final avgMood   = _mean(moods);

    // Feature order matches Python FEATURE_COLUMNS exactly:
    //  0 prev_cycle_1 (most recent)  1 prev_cycle_2  2 prev_cycle_3
    final f = Float32List(21);
    f[0]  = r[2];          // prev_cycle_1 — most recent
    f[1]  = r[1];          // prev_cycle_2
    f[2]  = r[0];          // prev_cycle_3
    f[3]  = avgR;          // avg_recent_cycle_length
    f[4]  = stdR;          // cycle_variability_std
    f[5]  = input.avgPeriodLength;
    f[6]  = input.avgSleepHours;
    f[7]  = input.avgStressLevel;
    f[8]  = input.exerciseDaysPerWeek;
    f[9]  = input.hadStressEvent ? 1.0 : 0.0;
    f[10] = input.wasIll         ? 1.0 : 0.0;
    f[11] = input.traveled       ? 1.0 : 0.0;
    f[12] = avgSymp;
    f[13] = syms['cramps']       ?? avgSymp * 0.8;
    f[14] = syms['bloating']     ?? avgSymp * 0.7;
    f[15] = syms['mood_swings']  ?? avgSymp * 0.9;
    f[16] = syms['insomnia']     ?? avgSymp * 0.5;
    f[17] = avgMood;             // avg_energy_level
    f[18] = 1.0 - avgMood;      // avg_irritability
    f[19] = input.age;
    f[20] = input.bmi;

    // StandardScaler transform
    for (int i = 0; i < 21; i++) {
      f[i] = ((f[i] - _scalerMean[i]) / _scalerStd[i]).toDouble();
      // cast is just to satisfy Float32List — values are already doubles
      f[i] = (f[i].isNaN || f[i].isInfinite) ? 0.0 : f[i];
    }
    return f;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  Future<OnnxPrediction> predict(OnnxPredictorInput input) async {
    if (!_loaded || _session == null) {
      return _baseline(input);
    }
    try {
      final features = _buildFeatures(input);
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        features, [1, 21],
      );
      final runOpts = OrtRunOptions();
      // synchronous run() for onnxruntime Flutter package
      List<OrtValue?>? outputs;
      try {
        // Try the synchronous run API (onnxruntime >= 1.0)
        outputs = _session!.run(runOpts, {'float_input': inputTensor});
      } catch (e) {
        // If run() itself throws, fall back to baseline
        inputTensor.release();
        runOpts.release();
        return _baseline(input);
      }
      inputTensor.release();
      runOpts.release();

      if (outputs.isEmpty || outputs.first == null) {
        return _baseline(input);
      }
      final raw = outputs.first!.value;
      double pred;
      if (raw is List && raw.isNotEmpty) {
        final first = raw[0];
        pred = (first is List && first.isNotEmpty)
            ? (first[0] as num).toDouble()
            : (first as num).toDouble();
      } else {
        return _baseline(input);
      }
      for (final o in outputs) { o?.release(); }

      final clamped = pred.clamp(21.0, 40.0);
      return OnnxPrediction(
        predictedCycleLength: clamped,
        usedOnnxModel: true,
        confidence: _confidence(input, clamped),
        method: 'onnx_gbr',
      );
    } catch (_) {
      return _baseline(input);
    }
  }

  // ── Statistical fallback (same as Python _xgb_predict fallback) ───────────

  OnnxPrediction _baseline(OnnxPredictorInput input) {
    final raw = List<double>.from(input.recentCycleLengths);
    if (raw.isEmpty) {
      return const OnnxPrediction(
        predictedCycleLength: 28.5,
        usedOnnxModel: false,
        confidence: 0.50,
        method: 'statistical_baseline',
      );
    }
    final n   = math.min(raw.length, 3);
    final w   = [0.5, 0.3, 0.2].sublist(0, n);
    final wSum = w.fold(0.0, (a, b) => a + b);
    final recent = raw.sublist(raw.length - n);
    double pred = 0;
    for (int i = 0; i < n; i++) {
      pred += recent[i] * w[i] / wSum;
    }
    pred = pred.clamp(21.0, 40.0);
    return OnnxPrediction(
      predictedCycleLength: pred,
      usedOnnxModel: false,
      confidence: _confidence(input, pred),
      method: 'statistical_baseline',
    );
  }

  double _confidence(OnnxPredictorInput input, double pred) {
    final n = input.recentCycleLengths.length.clamp(0, 12);
    final baseCf = _loaded ? 0.78 : 0.55;
    return (baseCf + n * 0.012).clamp(0.50, 0.93);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static double _mean(List<double> xs) =>
      xs.isEmpty ? 0 : xs.fold(0.0, (a, b) => a + b) / xs.length;

  static double _std(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = _mean(xs);
    return math.sqrt(xs.map((x) => math.pow(x - m, 2).toDouble())
        .fold(0.0, (a, b) => a + b) / xs.length);
  }
}
