class CyclePredictorService {
  static const int _defaultCycleLength = 28;
  static const int _defaultPeriodLength = 5;

  CyclePrediction predict({
    required List<int> pastCycleLengths,
    required DateTime lastPeriodStart,
    int? userDefinedCycleLength,
  }) {
    final avgCycleLength = _calculateAverage(pastCycleLengths) ??
        userDefinedCycleLength?.toDouble() ??
        _defaultCycleLength.toDouble();

    final stdDev = _calculateStdDev(pastCycleLengths, avgCycleLength);
    final confidence = _calculateConfidence(pastCycleLengths.length, stdDev);

    final nextPeriodDate =
        lastPeriodStart.add(Duration(days: avgCycleLength.round()));
    final ovulationDate = nextPeriodDate.subtract(const Duration(days: 14));

    final pmsRiskScore = _calculatePmsRisk(pastCycleLengths, stdDev);

    return CyclePrediction(
      nextPeriodDate: nextPeriodDate,
      ovulationDate: ovulationDate,
      ovulationWindowStart: ovulationDate.subtract(const Duration(days: 2)),
      ovulationWindowEnd: ovulationDate.add(const Duration(days: 2)),
      confidenceScore: confidence,
      pmsRiskScore: pmsRiskScore,
      averageCycleLength: avgCycleLength.round(),
    );
  }

  CyclePhase getCurrentPhase(DateTime lastPeriodStart,
      {int periodLength = _defaultPeriodLength,
      int cycleLength = _defaultCycleLength}) {
    final dayOfCycle =
        DateTime.now().difference(lastPeriodStart).inDays + 1;

    if (dayOfCycle <= periodLength) return CyclePhase.menstrual;
    if (dayOfCycle <= 13) return CyclePhase.follicular;
    if (dayOfCycle <= 16) return CyclePhase.ovulation;
    return CyclePhase.luteal;
  }

  double? _calculateAverage(List<int> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _calculateStdDev(List<int> values, double mean) {
    if (values.length < 2) return 3.0;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return variance > 0 ? variance / 2 : 3.0; // simplified sqrt approximation
  }

  double _calculateConfidence(int sampleSize, double stdDev) {
    if (sampleSize == 0) return 0.3;
    if (sampleSize >= 6 && stdDev < 2) return 0.95;
    if (sampleSize >= 3) return 0.75;
    return 0.5;
  }

  double _calculatePmsRisk(List<int> cycleLengths, double stdDev) {
    if (cycleLengths.isEmpty) return 0.3;
    final irregularity = (stdDev / 28.0).clamp(0.0, 1.0);
    return (0.2 + irregularity * 0.6).clamp(0.0, 1.0);
  }
}

class CyclePrediction {
  final DateTime nextPeriodDate;
  final DateTime ovulationDate;
  final DateTime ovulationWindowStart;
  final DateTime ovulationWindowEnd;
  final double confidenceScore;
  final double pmsRiskScore;
  final int averageCycleLength;

  CyclePrediction({
    required this.nextPeriodDate,
    required this.ovulationDate,
    required this.ovulationWindowStart,
    required this.ovulationWindowEnd,
    required this.confidenceScore,
    required this.pmsRiskScore,
    required this.averageCycleLength,
  });
}

enum CyclePhase { menstrual, follicular, ovulation, luteal }

extension CyclePhaseExtension on CyclePhase {
  String get displayName {
    switch (this) {
      case CyclePhase.menstrual:
        return 'Menstrual';
      case CyclePhase.follicular:
        return 'Follicular';
      case CyclePhase.ovulation:
        return 'Ovulation';
      case CyclePhase.luteal:
        return 'Luteal';
    }
  }

  String get description {
    switch (this) {
      case CyclePhase.menstrual:
        return 'Rest & restore. Your body is shedding the uterine lining.';
      case CyclePhase.follicular:
        return 'Energy rising. Estrogen increases, great time for new projects.';
      case CyclePhase.ovulation:
        return 'Peak energy. You\'re at your most social and communicative.';
      case CyclePhase.luteal:
        return 'Wind down. Progesterone rises, focus on calming activities.';
    }
  }
}
