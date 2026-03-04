
library kalman_filter_service;

import 'dart:math' as math;

// ── Noise constants (tuned to published menstrual-cycle literature) ──────────
// ignore: constant_identifier_names
const double _Q   = 0.15;    // process noise (days² per cycle)
// ignore: constant_identifier_names
const double _R   = 5.0;     // measurement noise (days² — ~2.2d std)
// ignore: constant_identifier_names
const double _P0  = 25.0;    // initial variance (5-day std prior)
// ignore: constant_identifier_names
const double _TAU = 8.0;     // blending time constant

const int    _minCycle = 21;
const int    _maxCycle = 40;

// ── Sentiment-variance constants ─────────────────────────────────────────────
const int    _sentimentCap     = 30;
const double _sentimentTrigger = -0.20;
const double _sentimentScale   = 0.80;

// ── KalmanState ───────────────────────────────────────────────────────────────

class KalmanState {
  double         mean;
  double         variance;
  int            nObservations;
  List<double>   cycleHistory;
  List<double>   sentimentHistory;

  KalmanState({
    required this.mean,
    required this.variance,
    this.nObservations   = 0,
    List<double>? cycleHistory,
    List<double>? sentimentHistory,
  })  : cycleHistory     = cycleHistory     ?? [],
        sentimentHistory = sentimentHistory ?? [];

  // ── Factory constructors ──────────────────────────────────────────────────

  factory KalmanState.initial({double priorMean = 28.5}) =>
      KalmanState(mean: priorMean, variance: _P0);

  factory KalmanState.fromMap(Map<String, dynamic> m) => KalmanState(
        mean: (m['kalman_mean'] as num?)?.toDouble() ?? 28.5,
        variance: (m['kalman_variance'] as num?)?.toDouble() ?? _P0,
        nObservations: (m['n_observations'] as num?)?.toInt() ?? 0,
        cycleHistory:
            (m['cycle_history'] as List? ?? []).cast<num>().map((e) => e.toDouble()).toList(),
        sentimentHistory:
            (m['sentiment_history'] as List? ?? []).cast<num>().map((e) => e.toDouble()).toList(),
      );

  Map<String, dynamic> toMap() => {
        'kalman_mean'       : mean,
        'kalman_variance'   : variance,
        'n_observations'    : nObservations,
        'cycle_history'     : cycleHistory,
        'sentiment_history' : sentimentHistory,
      };

  // ── Derived properties ────────────────────────────────────────────────────

  double get std => math.sqrt(math.max(0, variance));

  double? get avgSentiment {
    if (sentimentHistory.isEmpty) return null;
    return sentimentHistory.reduce((a, b) => a + b) / sentimentHistory.length;
  }

  String get sentimentStressLevel {
    final avg = avgSentiment;
    if (avg == null) return 'unknown';
    if (avg < -0.5) return 'high';
    if (avg < -0.2) return 'moderate';
    if (avg < 0.1)  return 'low';
    return 'positive';
  }

  bool get isConfident => nObservations >= 4 && std < 2.5;

  // ── Hard update — called when user logs a cycle ───────────────────────────

  void update(double observedLength) {
    final z = observedLength.clamp(_minCycle.toDouble(), _maxCycle.toDouble());

    // Predict
    final pPred = variance + _Q;

    // Kalman gain
    final K = pPred / (pPred + _R);

    // Update
    mean     = mean + K * (z - mean);
    variance = (1.0 - K) * pPred;
    nObservations++;

    cycleHistory.add(double.parse(z.toStringAsFixed(1)));
    if (cycleHistory.length > 20) cycleHistory.removeAt(0);
  }

  // ── Soft update — called when user saves a journal entry ─────────────────

  void updateFromSentiment(double score) {
    final s = score.clamp(-1.0, 1.0);
    sentimentHistory.add(double.parse(s.toStringAsFixed(4)));
    if (sentimentHistory.length > _sentimentCap) sentimentHistory.removeAt(0);

    final avg = sentimentHistory.reduce((a, b) => a + b) / sentimentHistory.length;
    if (avg < _sentimentTrigger) {
      final stressFactor = math.min(
          1.0, (-avg - _sentimentTrigger.abs()) / (1.0 - _sentimentTrigger.abs()));
      final bump = stressFactor * _sentimentScale;
      variance   = math.min(_P0, variance + bump);
    }
  }
}

// ── Blend predictions (XGBoost / statistical baseline + Kalman) ──────────────

Map<String, dynamic> blendPredictions({
  required double baselinePrediction,
  required KalmanState kalmanState,
  required int nLoggedCycles,
}) {
  final w = 1.0 - math.exp(-nLoggedCycles / _TAU);

  final blendedRaw = (1.0 - w) * baselinePrediction + w * kalmanState.mean;
  final blended    = blendedRaw.clamp(_minCycle.toDouble(), _maxCycle.toDouble()).round();

  final baseUncertainty  = nLoggedCycles > 0 ? kalmanState.std : 5.0;
  final avgSent          = kalmanState.avgSentiment;
  double sentimentPenalty = 0.0;
  if (avgSent != null && avgSent < _sentimentTrigger) {
    final sf = math.min(
        1.0, (-avgSent - _sentimentTrigger.abs()) / (1.0 - _sentimentTrigger.abs()));
    sentimentPenalty = double.parse((sf * 0.08).toStringAsFixed(4));
  }

  final confidence = (1.0
        - (baseUncertainty / 14.0)
        - (nLoggedCycles < 2 ? 0.05 : 0.0)
        - sentimentPenalty)
      .clamp(0.45, 0.96);

  String method;
  if (nLoggedCycles == 0) {
    method = 'statistical_baseline';
  } else if (w < 0.4) {
    method = 'baseline_dominant';
  } else if (w < 0.65) {
    method = 'baseline_kalman_mix';
  } else {
    method = 'kalman_dominant';
  }

  return {
    'predicted_cycle_length'   : blended,
    'confidence_score'         : double.parse(confidence.toStringAsFixed(3)),
    'method'                   : method,
    'kalman_weight'            : double.parse(w.toStringAsFixed(3)),
    'baseline_prediction'      : baselinePrediction.round(),
    'kalman_prediction'        : kalmanState.mean.round(),
    'kalman_std'               : double.parse(kalmanState.std.toStringAsFixed(2)),
    'n_personal_cycles'        : nLoggedCycles,
    'avg_journal_sentiment'    : avgSent,
    'sentiment_stress_level'   : kalmanState.sentimentStressLevel,
    'sentiment_variance_effect': double.parse((sentimentPenalty * 100).toStringAsFixed(1)),
  };
}
