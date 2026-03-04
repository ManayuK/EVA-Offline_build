library emotion_detector;

import 'dart:math' as math;

// ──────────────────────────────────────────────────────────────────────────────
//  Output types
// ──────────────────────────────────────────────────────────────────────────────

class EmotionAnalysisResult {
  final Map<String, double> emotionScores;
  final String              primaryEmotion;
  final String              suggestedMood;
  final double              sentimentScore;
  final double              stressLevel;
  final double              hormonalInfluence;
  final List<String>        keywords;
  final List<String>        topics;
  final int                 wordCount;
  final String              modelUsed;
  final MentalHealthConcern mentalHealth;

  const EmotionAnalysisResult({
    required this.emotionScores,
    required this.primaryEmotion,
    required this.suggestedMood,
    required this.sentimentScore,
    required this.stressLevel,
    required this.hormonalInfluence,
    required this.keywords,
    required this.topics,
    required this.wordCount,
    required this.modelUsed,
    required this.mentalHealth,
  });
}

enum MentalHealthLevel { low, moderate, high, critical }

class MentalHealthConcern {
  final bool              concernDetected;
  final bool              crisisDetected;
  final MentalHealthLevel level;
  final bool              supportRecommended;
  final List<String>      recommendations;
  final bool              professionalHelpSuggested;

  const MentalHealthConcern({
    required this.concernDetected,
    required this.crisisDetected,
    required this.level,
    required this.supportRecommended,
    required this.recommendations,
    required this.professionalHelpSuggested,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
//  EmotionDetector
// ──────────────────────────────────────────────────────────────────────────────

class EmotionDetector {

  // ── Keyword tables ──────────────────────────────────────────────────────────

  static const _patternPhrases = <String, List<String>>{
    'joy':      ['feel amazing', 'so happy', 'love this', 'wonderful', 'so excited', 'best day'],
    'sadness':  ['feel so alone', 'want to cry', "can't stop crying", 'feel hopeless', 'feel empty'],
    'anger':    ['so angry', 'makes me furious', 'so frustrated'],
    'fear':     ['so scared', 'terrified of', 'panic attack', 'heart racing'],
    'disgust':  ['makes me sick', 'revolting'],
    'surprise': ["can't believe", 'never expected'],
    'neutral':  ['just a normal', 'regular day'],
  };

  static const _patternWords = <String, List<String>>{
    'joy':      ['happy','joyful','excited','great','delighted','cheerful','content','elated','thrilled','positive'],
    'sadness':  ['sad','depressed','unhappy','miserable','gloomy','tearful','lonely','heartbroken','hopeless','empty'],
    'anger':    ['angry','furious','mad','irritated','annoyed','frustrated','rage','hate','livid','bitter'],
    'fear':     ['scared','afraid','fearful','terrified','frightened','dread','panic','nervous','anxious'],
    'disgust':  ['disgust','gross','revolting','repulsed','vile'],
    'surprise': ['surprised','shocked','astonished','stunned'],
    'neutral':  ['okay','fine','alright','normal','usual','regular'],
  };

  static const _patternWeights = <String, double>{
    'joy': 1.0, 'sadness': 1.0, 'anger': 1.0, 'fear': 1.0,
    'disgust': 1.0, 'surprise': 0.8, 'neutral': 0.6,
  };

  static const _negations = {
    'not', "don't", "didn't", "won't", "isn't", "wasn't", 'no', 'never', 'hardly',
  };

  static const _emotionToMood = <String, String>{
    'joy': 'happy', 'sadness': 'sad', 'anger': 'irritable',
    'fear': 'anxious', 'disgust': 'stressed', 'neutral': 'neutral', 'surprise': 'neutral',
  };

  static const _hormonalWeights = <String, double>{
    'anger': 0.75, 'sadness': 0.65, 'fear': 0.70, 'disgust': 0.55,
    'neutral': 0.10, 'joy': -0.20, 'surprise': 0.15,
  };

  static const _crisisPhrases = [
    'kill myself', 'end my life', 'want to die', 'better off dead',
    'no point living', 'hurt myself', 'self harm', 'suicide', 'end it all',
  ];

  static const _depressionWords = [
    'hopeless','worthless','numb','empty','pointless','meaningless','defeated','broken',
  ];

  static const _anxietyPhrases = [
    "can't breathe", 'panic attack', 'heart is racing', 'breaking down', 'overwhelming dread',
  ];

  static const _topicMap = <String, List<String>>{
    'work_stress':     ['work','job','boss','deadline','office','project','meeting','career'],
    'relationships':   ['partner','boyfriend','girlfriend','husband','wife','friend','family'],
    'physical_pain':   ['pain','cramps','ache','hurt','sore','headache','backache','nausea'],
    'body_image':      ['weight','body','bloated','appearance','eating','diet'],
    'cycle_awareness': ['cycle','period','ovulation','pms','hormone','menstrual'],
    'sleep':           ['sleep','insomnia','tired','exhausted','fatigue'],
    'anxiety_stress':  ['anxious','stressed','overwhelmed','worried','panic','nervous'],
  };

  static const _stopwords = {
    'the','a','an','and','or','but','in','on','at','to','for','of','with','by',
    'from','as','is','was','am','are','been','be','have','has','had','do','does',
    'did','will','would','could','should','may','might','can','this','that','it',
    'my','me','i','so','just','really','very','feel','feeling','today','day',
    'time','like','know','think','want','need',
  };

  // ──────────────────────────────────────────────────────────────────────────
  //  Main analysis entry point
  // ──────────────────────────────────────────────────────────────────────────

  EmotionAnalysisResult analyze(String text, {String? cyclePhase}) {
    if (text.trim().isEmpty) return _emptyResult();

    final lower     = text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    final wordCount = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    var scores = _keywordScores(lower);

    // Negation correction (mirrors Python _apply_negation_correction)
    if (_hasNegatedPositive(lower)) {
      scores = Map.of(scores);
      final transferred = (scores['joy'] ?? 0.0) * 0.75;
      scores['joy']     = (scores['joy']     ?? 0.0) - transferred;
      scores['sadness'] = (scores['sadness'] ?? 0.0) + transferred * 0.70;
      scores['neutral'] = (scores['neutral'] ?? 0.0) + transferred * 0.30;
      final total = scores.values.fold(0.0, (a, b) => a + b);
      if (total > 0) {
        scores.updateAll((k, v) => double.parse((v / total).toStringAsFixed(4)));
      }
    }

    final primary = scores.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    final sentiment        = _computeSentiment(scores);
    final stressLevel      = _computeStress(scores);
    final hormonalInfluence = _computeHormonalInfluence(scores, cyclePhase);
    final keywords         = _extractKeywords(lower);
    final topics           = _detectTopics(lower);
    final mentalHealth     = _analyzeMentalHealth(lower, sentiment, scores);

    return EmotionAnalysisResult(
      emotionScores:     scores,
      primaryEmotion:    primary,
      suggestedMood:     _emotionToMood[primary] ?? 'neutral',
      sentimentScore:    double.parse(sentiment.toStringAsFixed(4)),
      stressLevel:       double.parse(stressLevel.toStringAsFixed(4)),
      hormonalInfluence: double.parse(hormonalInfluence.toStringAsFixed(4)),
      keywords:          keywords,
      topics:            topics,
      wordCount:         wordCount,
      modelUsed:         'keyword_dart',
      mentalHealth:      mentalHealth,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Keyword scoring (softmax)
  // ──────────────────────────────────────────────────────────────────────────

  Map<String, double> _keywordScores(String lower) {
    final words = lower.split(RegExp(r'\s+'));
    final raw   = <String, double>{};
    // Very short text (< 3 words) — return neutral to avoid noise
    if (words.length < 3) {
      const u = 1.0 / 7;
      return { 'anger': u, 'disgust': u, 'fear': u, 'joy': u, 'neutral': u + 0.1, 'sadness': u, 'surprise': u - 0.01 };
    }

    for (final emotion in _patternPhrases.keys) {
      double score = 0.0;

      for (final phrase in _patternPhrases[emotion]!) {
        if (lower.contains(phrase)) score += 2.0;
      }

      final weight = _patternWeights[emotion]!;
      final wWords = _patternWords[emotion]!;
      for (int i = 0; i < words.length; i++) {
        if (wWords.contains(words[i])) {
          final preceding = words.sublist((i - 2).clamp(0, i), i).toSet();
          score += preceding.intersection(_negations).isNotEmpty ? -0.5 : weight;
        }
      }

      raw[emotion] = score < 0.0 ? 0.0 : score;
    }

    // Softmax
    final exp   = raw.map((k, v) => MapEntry(k, math.exp(v.clamp(-20, 20))));
    final total = exp.values.fold(0.0, (a, b) => a + b);
    if (total > 0) {
      return exp.map((k, v) => MapEntry(k, double.parse((v / total).toStringAsFixed(4))));
    }
    final n = raw.length.toDouble();
    return raw.map((k, _) => MapEntry(k, double.parse((1.0 / n).toStringAsFixed(4))));
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Negation correction
  // ──────────────────────────────────────────────────────────────────────────

  static bool _hasNegatedPositive(String t) {
    return [
      RegExp(r"\b(not|don'?t|doesn'?t|didn'?t|can'?t|never|no)\s+feel(?:ing)?\s+(good|well|great|okay|ok|fine|happy|alright)\b"),
      RegExp(r"\b(not|don'?t|no)\s+(good|well|great|okay|ok|fine|happy|alright)\b"),
      RegExp(r"\bfeel(?:ing)?\s+(bad|awful|terrible|horrible|sick|down|low|unwell)\b"),
      RegExp(r"\b(bad|awful|terrible|horrible|unwell)\s+day\b"),
    ].any((p) => p.hasMatch(t));
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Derived signals
  // ──────────────────────────────────────────────────────────────────────────

  static double _computeSentiment(Map<String, double> s) {
    final joy     = s['joy']     ?? 0.0;
    final surprise= s['surprise']?? 0.0;
    final sadness = s['sadness'] ?? 0.0;
    final anger   = s['anger']   ?? 0.0;
    final fear    = s['fear']    ?? 0.0;
    final disgust = s['disgust'] ?? 0.0;

    // Detect near-uniform distribution (no keywords matched) → neutral
    final allValues = [joy, surprise, sadness, anger, fear, disgust];
    final maxVal = allValues.reduce((a, b) => a > b ? a : b);
    final minVal = allValues.reduce((a, b) => a < b ? a : b);
    if ((maxVal - minVal) < 0.06) return 0.0; // essentially uniform → neutral

    final pos   = joy + surprise * 0.3;
    final neg   = sadness + anger + fear + disgust;
    final total = pos + neg;
    if (total == 0) return 0.0;
    return ((pos - neg) / total).clamp(-1.0, 1.0);
  }

  static double _computeStress(Map<String, double> s) =>
      ((s['fear']    ?? 0.0) * 0.90 +
       (s['anger']   ?? 0.0) * 0.75 +
       (s['sadness'] ?? 0.0) * 0.55 +
       (s['disgust'] ?? 0.0) * 0.45).clamp(0.0, 1.0);

  static double _computeHormonalInfluence(Map<String, double> s, String? phase) {
    double base = 0.0;
    for (final e in _hormonalWeights.entries) {
      base += (s[e.key] ?? 0.0) * e.value;
    }
    const phaseMultipliers = <String, double>{
      'luteal': 1.35, 'menstrual': 1.20, 'ovulation': 0.95, 'follicular': 0.75,
    };
    return (base * (phaseMultipliers[phase] ?? 1.0)).clamp(0.0, 1.0);
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Keywords & topics
  // ──────────────────────────────────────────────────────────────────────────

  static List<String> _extractKeywords(String lower) {
    final wordRe = RegExp(r'\b[a-z]{4,}\b');
    final seen   = <String>{};
    final result = <String>[];
    for (final m in wordRe.allMatches(lower)) {
      final w = m.group(0)!;
      if (!_stopwords.contains(w) && seen.add(w)) {
        result.add(w);
        if (result.length >= 12) break;
      }
    }
    return result;
  }

  static List<String> _detectTopics(String lower) {
    final out = <String>[];
    for (final e in _topicMap.entries) {
      if (e.value.any(lower.contains)) {
        out.add(e.key);
        if (out.length >= 4) break;
      }
    }
    return out;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Crisis / mental health detection
  // ──────────────────────────────────────────────────────────────────────────

  MentalHealthConcern _analyzeMentalHealth(
      String lower, double sentiment, Map<String, double> scores) {
    final crisis         = _crisisPhrases.any(lower.contains);
    final deprHits       = _depressionWords.where((w) => lower.split(' ').contains(w)).length;
    final severeDepr     = deprHits >= 3;
    final severeAnxiety  = _anxietyPhrases.any(lower.contains);
    final negSent        = sentiment < -0.6;

    MentalHealthLevel level;
    if (crisis) {
      level = MentalHealthLevel.critical;
    } else if (severeDepr || ((scores['sadness'] ?? 0.0) > 0.7 && negSent)) {
      level = MentalHealthLevel.high;
    } else if (severeAnxiety) {
      level = MentalHealthLevel.moderate;
    } else {
      level = MentalHealthLevel.low;
    }

    return MentalHealthConcern(
      concernDetected:          level != MentalHealthLevel.low,
      crisisDetected:           crisis,
      level:                    level,
      supportRecommended:       level == MentalHealthLevel.high || level == MentalHealthLevel.critical,
      recommendations:          _mentalHealthRecs(level, crisis, severeDepr, severeAnxiety),
      professionalHelpSuggested: crisis || severeDepr,
    );
  }

  static List<String> _mentalHealthRecs(
      MentalHealthLevel level, bool crisis, bool depression, bool anxiety) {
    if (crisis) {
      return [
        "If you're in immediate danger, call emergency services",
        'Crisis support: Samaritans 116 123 (UK) | 988 Lifeline (US) — free, 24/7',
        'Text HOME to 85258 (UK) | 741741 (US)',
        'You are not alone — please reach out to someone you trust',
      ];
    }
    if (depression) {
      return [
        'Consider speaking with your GP or a therapist',
        'Mind helpline: 0300 123 3393 (UK) | NAMI: 1-800-950-6264 (US)',
        'Be gentle with yourself — what you feel is valid and treatable',
      ];
    }
    if (anxiety) {
      return [
        'Try box breathing: inhale 4, hold 4, exhale 4, hold 4',
        'Grounding: name 5 things you see, 4 you can touch, 3 you hear',
        'If anxiety persists, speak with a healthcare provider',
      ];
    }
    return [
      'Journalling regularly is a powerful wellbeing practice — keep going',
      'Stay connected with people who support you',
    ];
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Convenience: AI response text for journal confirmation UI
  // ──────────────────────────────────────────────────────────────────────────

  static String generateJournalResponse(EmotionAnalysisResult r) {
    if (r.mentalHealth.crisisDetected) {
      return "I'm concerned about what you've shared. Please reach out to a "
             "crisis line — you don't have to face this alone.";
    }
    const responses = <String, String>{
      'joy':      "It's wonderful to see you feeling positive! Your mood today is giving off great energy.",
      'sadness':  "It sounds like today has been tough. Be kind to yourself — it's okay to feel this way.",
      'anger':    "It makes sense to feel frustrated sometimes. Journalling is a healthy outlet.",
      'fear':     "I hear that you're feeling stressed. Try taking a few slow breaths.",
      'disgust':  "Something is clearly bothering you. Give yourself space to process it.",
      'surprise': "What a day! Unexpected things can be a lot to take in.",
      'neutral':  "Thank you for sharing. Your reflections help track how you're doing over time.",
    };
    return responses[r.primaryEmotion] ??
        "Thank you for sharing. Your reflections help track how you're doing over time.";
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Empty result
  // ──────────────────────────────────────────────────────────────────────────

  static EmotionAnalysisResult _emptyResult() {
    const u = 1.0 / 7;
    return const EmotionAnalysisResult(
      emotionScores: {
        'anger': u, 'disgust': u, 'fear': u, 'joy': u,
        'neutral': u, 'sadness': u, 'surprise': u,
      },
      primaryEmotion: 'neutral', suggestedMood: 'neutral',
      sentimentScore: 0.0, stressLevel: 0.0, hormonalInfluence: 0.0,
      keywords: [], topics: [], wordCount: 0, modelUsed: 'keyword_dart',
      mentalHealth: MentalHealthConcern(
        concernDetected: false, crisisDetected: false,
        level: MentalHealthLevel.low, supportRecommended: false,
        recommendations: [], professionalHelpSuggested: false,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  Singleton
// ──────────────────────────────────────────────────────────────────────────────

EmotionDetector? _instance;
EmotionDetector getEmotionDetector() => _instance ??= EmotionDetector();
