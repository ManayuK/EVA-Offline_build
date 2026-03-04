library suggestion_engine;

// ──────────────────────────────────────────────────────────────────────────────
//  Data class for the input context
// ──────────────────────────────────────────────────────────────────────────────

class SuggestionContext {
  final String       cyclePhase;        // 'menstrual'|'follicular'|'ovulation'|'luteal'
  final String       currentMood;       // 'anxious'|'irritable'|'sad'|'tired'|'stressed'|'neutral'
  final double       energyLevel;       // 0–10
  final List<String> symptoms;          // e.g. ['cramps','bloating','headache']
  final double       sleepHours;        // last night's sleep
  final double       stressLevel;       // 0–10
  // ── profile fields (from onboarding) ──────────────────────────────────────
  final String       fitnessLevel;      // 'sedentary'|'light'|'moderate'|'active'|'very_active'
  final List<String> healthGoals;       // e.g. ['better_sleep','stress_reduction']
  final String       dietaryPreference; // 'omnivore'|'vegan'|'vegetarian'|'keto'|'paleo'
  final double       bmi;
  final int          age;
  final double       avgSleepHours;     // personal target from profile

  const SuggestionContext({
    required this.cyclePhase,
    this.currentMood       = 'neutral',
    this.energyLevel       = 5.0,
    this.symptoms          = const [],
    this.sleepHours        = 7.0,
    this.stressLevel       = 5.0,
    this.fitnessLevel      = 'moderate',
    this.healthGoals       = const [],
    this.dietaryPreference = 'omnivore',
    this.bmi               = 22.0,
    this.age               = 28,
    this.avgSleepHours     = 7.5,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
//  Output suggestion card
// ──────────────────────────────────────────────────────────────────────────────

class SuggestionCard {
  final String       category;       // diet|exercise|meditation|productivity|social|sleep|stress|symptom_relief|cycle_insight|mood_support
  final String       title;
  final String       description;
  final String       reason;
  final List<String> allSuggestions; // full list from this category (shown on detail)
  final String?      duration;       // for meditation cards
  final String?      benefits;       // for meditation cards
  final int          priority;       // higher = shown first

  const SuggestionCard({
    required this.category,
    required this.title,
    required this.description,
    required this.reason,
    this.allSuggestions = const [],
    this.duration,
    this.benefits,
    this.priority = 5,
  });
}

class SuggestionResult {
  final String            date;
  final String            cyclePhase;
  final List<SuggestionCard> suggestions; // top-10, sorted by priority
  final List<String>      workoutRecommendations;
  final List<String>      dietRecommendations;
  final String            meditationType;
  final List<String>      productivityTips;

  const SuggestionResult({
    required this.date,
    required this.cyclePhase,
    required this.suggestions,
    required this.workoutRecommendations,
    required this.dietRecommendations,
    required this.meditationType,
    required this.productivityTips,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
//  SuggestionEngine
// ──────────────────────────────────────────────────────────────────────────────

class SuggestionEngine {

  // ── Phase-based content tables ─────────────────────────────────────────────

  static const _phaseContent = <String, Map<String, dynamic>>{
    'menstrual': {
      'description': 'Your body is working hard. Focus on rest and gentle care.',
      'diet': [
        'Iron-rich foods (spinach, lentils, red meat) to replenish blood loss',
        'Magnesium-rich foods (dark chocolate, nuts) for cramp relief',
        'Anti-inflammatory foods (turmeric, ginger, berries)',
        'Stay hydrated — aim for 8–10 glasses of water',
        'Avoid excessive salt to reduce bloating',
      ],
      'exercise': [
        'Gentle yoga or stretching',
        'Light walking or swimming',
        'Avoid high-intensity workouts if cramping',
        'Focus on restorative movements',
        'Listen to your body — rest is productive too',
      ],
      'meditation': 'body_scan',
      'meditation_details': {
        'type':     'Body Scan Meditation',
        'duration': '10–15 minutes',
        'focus':    'Release tension and connect with your body',
        'benefits': 'Helps with pain management and relaxation',
      },
      'productivity': [
        'Tackle routine tasks that don\'t require peak creativity',
        'Schedule lighter workload if possible',
        'Take regular breaks',
        'Don\'t expect peak performance — be gentle with yourself',
      ],
      'social': [
        'Opt for quiet, intimate gatherings',
        'Communicate your needs to close friends',
        'It\'s okay to decline invitations',
        'Spend quality time with supportive people',
      ],
      'self_care': [
        'Use heating pad for cramps',
        'Take warm baths with Epsom salt',
        'Get extra sleep if needed',
        'Wear comfortable clothing',
      ],
    },
    'follicular': {
      'description': 'Rising estrogen brings energy and optimism. Great time for new beginnings!',
      'diet': [
        'Protein-rich foods for sustained energy',
        'Fresh fruits and vegetables',
        'Whole grains for steady blood sugar',
        'Fermented foods (yogurt, kimchi) for gut health',
        'Green tea for antioxidants',
      ],
      'exercise': [
        'High-intensity interval training (HIIT)',
        'Strength training — you\'ll recover faster',
        'Try new workout classes',
        'Cardio activities like running or cycling',
        'Group fitness classes for social energy',
      ],
      'meditation': 'visualization',
      'meditation_details': {
        'type':     'Visualisation Meditation',
        'duration': '10–20 minutes',
        'focus':    'Manifest goals and positive outcomes',
        'benefits': 'Harness your optimistic energy',
      },
      'productivity': [
        'Start new projects',
        'Schedule important meetings and presentations',
        'Tackle challenging creative work',
        'Make important decisions',
        'Network and build connections',
      ],
      'social': [
        'Great time for socialising and meeting new people',
        'Plan group activities',
        'Attend networking events',
        'Be open to new experiences',
      ],
      'self_care': [
        'Try new beauty routines',
        'Experiment with style',
        'Plan fun activities',
        'Take advantage of your natural confidence',
      ],
    },
    'ovulation': {
      'description': 'Peak fertility and confidence. You\'re magnetic and communicative!',
      'diet': [
        'Antioxidant-rich foods (berries, leafy greens)',
        'Healthy fats (avocado, nuts, olive oil)',
        'Stay well-hydrated',
        'Fibre-rich foods for hormone balance',
        'Limit processed foods',
      ],
      'exercise': [
        'Peak time for intense workouts',
        'Try challenging new exercises',
        'Competitive sports',
        'Dance classes',
        'Push your limits safely',
      ],
      'meditation': 'loving_kindness',
      'meditation_details': {
        'type':     'Loving-Kindness Meditation',
        'duration': '15 minutes',
        'focus':    'Send compassion to yourself and others',
        'benefits': 'Amplify your natural warmth and connection',
      },
      'productivity': [
        'Schedule crucial conversations',
        'Give presentations or pitches',
        'Negotiate deals or raises',
        'Lead team meetings',
        'Your communication skills are at peak',
      ],
      'social': [
        'Prime time for dates and romance',
        'Host gatherings',
        'Have important conversations',
        'You\'re naturally more attractive and confident',
      ],
      'self_care': [
        'Celebrate your vitality',
        'Embrace your confidence',
        'Take photos — you\'ll likely love them',
        'Enjoy feeling your best',
      ],
    },
    'luteal': {
      'description': 'Energy may fluctuate. Focus on completion and self-compassion.',
      'diet': [
        'Complex carbs (sweet potato, quinoa) for serotonin',
        'B-vitamins (eggs, salmon) for mood',
        'Calcium-rich foods for PMS symptom relief',
        'Limit caffeine and alcohol',
        'Reduce salt and sugar to minimise bloating',
        'Magnesium for anxiety and cramps',
      ],
      'exercise': [
        'Moderate-intensity workouts',
        'Pilates or barre',
        'Swimming',
        'Gentle jogging',
        'Listen to fatigue signals — reduce intensity if needed',
      ],
      'meditation': 'mindfulness',
      'meditation_details': {
        'type':     'Mindfulness Meditation',
        'duration': '15–20 minutes',
        'focus':    'Observe thoughts and emotions without judgement',
        'benefits': 'Manage mood swings and increase self-awareness',
      },
      'productivity': [
        'Complete ongoing projects',
        'Detail-oriented tasks',
        'Organisation and planning',
        'Analytical work',
        'Less ideal for starting new initiatives',
      ],
      'social': [
        'Prefer smaller gatherings',
        'Quality over quantity in social time',
        'Communicate needs clearly',
        'Set boundaries without guilt',
        'Alone time is valuable',
      ],
      'self_care': [
        'Practise extra self-compassion',
        'Journal your feelings',
        'Take naps if needed',
        'Prepare comfort foods',
        'Create a cosy environment',
        'Track PMS symptoms to identify patterns',
      ],
    },
  };

  // ── Mood-based overrides ───────────────────────────────────────────────────

  static const _moodAdjustments = <String, Map<String, dynamic>>{
    'anxious': {
      'priority_tips': [
        'Practise 4-7-8 breathing: inhale 4, hold 7, exhale 8',
        'Ground yourself: name 5 things you see, 4 you hear, 3 you touch',
        'Limit caffeine intake today',
      ],
      'exercise_modification': 'Prefer calming exercises like yoga or walking',
      'meditation_boost':      'Add 10 minutes of breathing exercises',
    },
    'irritable': {
      'priority_tips': [
        'You might be feeling hormonal — it\'s okay',
        'Take breaks before responding to triggers',
        'Physical movement can help release tension',
        'Communicate your needs clearly',
      ],
      'exercise_modification': 'Vigorous exercise can help release irritation',
      'meditation_boost':      'Try progressive muscle relaxation',
    },
    'sad': {
      'priority_tips': [
        'Gentle movement can boost mood',
        'Connect with a supportive friend',
        'Journal your feelings',
        'Remember: this feeling will pass',
      ],
      'exercise_modification': 'Light exercise or gentle yoga',
      'meditation_boost':      'Loving-kindness meditation may help',
    },
    'tired': {
      'priority_tips': [
        'Prioritise sleep tonight',
        'Take a short power nap if possible',
        'Check iron levels if frequently tired',
        'Hydrate well',
      ],
      'exercise_modification': 'Skip intense workouts — opt for gentle movement',
      'meditation_boost':      'Try yoga nidra for deep rest',
    },
    'stressed': {
      'priority_tips': [
        'Break tasks into smaller steps',
        'Delegate what you can',
        'Take regular 5-minute breaks',
        'Practise saying no to non-essentials',
      ],
      'exercise_modification': 'Moderate cardio can reduce stress hormones',
      'meditation_boost':      'Body scan or mindfulness meditation',
    },
  };

  // ── Symptom-specific cards ─────────────────────────────────────────────────

  static const _symptomRemedies = <String, Map<String, dynamic>>{
    'cramps': {
      'title':       'Cramp Relief',
      'description': 'Try a heating pad, magnesium supplement, gentle stretching, or ibuprofen',
      'priority':    9,
    },
    'bloating': {
      'title':       'Reduce Bloating',
      'description': 'Limit salt, stay hydrated, avoid carbonated drinks, eat smaller meals',
      'priority':    7,
    },
    'headache': {
      'title':       'Headache Management',
      'description': 'Stay hydrated, rest in a dark room, consider magnesium, limit screen time',
      'priority':    8,
    },
    'fatigue': {
      'title':       'Energy Boost',
      'description': 'Prioritise sleep, eat iron-rich foods, take short walks, limit caffeine',
      'priority':    8,
    },
    'anxiety': {
      'title':       'Anxiety Support',
      'description': 'Practise breathing exercises, limit caffeine, try calming tea',
      'priority':    9,
    },
    'mood_swings': {
      'title':       'Mood Balance',
      'description': 'This is likely hormonal. Be patient with yourself — exercise and sleep help.',
      'priority':    8,
    },
    'insomnia': {
      'title':       'Sleep Support',
      'description': 'Avoid screens 1 hr before bed, keep your room cool, try magnesium glycinate',
      'priority':    8,
    },
    'breast_tenderness': {
      'title':       'Breast Tenderness Relief',
      'description': 'Reduce caffeine, wear a supportive bra, evening primrose oil may help',
      'priority':    6,
    },
    'back_pain': {
      'title':       'Back Pain Relief',
      'description': 'Gentle stretching, heat therapy, and staying hydrated can ease the discomfort',
      'priority':    6,
    },
    'nausea': {
      'title':       'Nausea Relief',
      'description': 'Ginger tea, small frequent meals, and staying hydrated can ease nausea',
      'priority':    7,
    },
    'acne': {
      'title':       'Hormonal Acne Care',
      'description': 'Cleanse twice daily, avoid touching your face, spearmint tea may help balance hormones',
      'priority':    5,
    },
  };

  // ── Health-goal bonus cards ────────────────────────────────────────────────

  static const _goalCards = <String, List<String>>{
    //       [category,         title,                  description]
    'better_sleep':      ['sleep',      'Wind-Down Ritual',       'Dim lights 1 hr before bed and avoid screens to improve sleep quality.'],
    'stress_reduction':  ['stress',     'Stress Reset',           'Try 5-min journalling before bed to clear your mental load.'],
    'weight_management': ['diet',       'Mindful Eating',         'Eat slowly and stop at 80% fullness — supports hormonal health.'],
    'fitness':           ['exercise',   'Progressive Overload',   'Add one extra set or 5% more weight this week for steady gains.'],
    'mental_health':     ['meditation', 'Gratitude Practice',     'Write 3 things you\'re grateful for each morning.'],
    'hormone_balance':   ['diet',       'Hormone-Friendly Foods', 'Include cruciferous veg (broccoli, kale) to support oestrogen metabolism.'],
  };

  // ──────────────────────────────────────────────────────────────────────────
  //  Main entry point
  // ──────────────────────────────────────────────────────────────────────────

  SuggestionResult generateSuggestions(SuggestionContext ctx) {
    final phase = ctx.cyclePhase;
    final base  = _phaseContent[phase] ?? _phaseContent['follicular']!;
    final mood  = _moodAdjustments[ctx.currentMood] ?? const {};

    final cards = <SuggestionCard>[];

    // 1. Phase insight (always first)
    cards.add(SuggestionCard(
      category:    'cycle_insight',
      title:       'You\'re in the ${_capitalize(phase)} phase',
      description: base['description'] as String,
      reason:      'Understanding your cycle helps optimise your lifestyle',
      priority:    10,
    ));

    // 2. Mood-based urgent tips
    final priorityTips = (mood['priority_tips'] as List<String>?) ?? [];
    for (final tip in priorityTips) {
      cards.add(SuggestionCard(
        category:    'mood_support',
        title:       'Mood Support',
        description: tip,
        reason:      'Tailored for when you\'re feeling ${ctx.currentMood}',
        priority:    9,
      ));
    }

    // 3. Diet — personalised for dietary_preference + BMI
    final dietList    = (base['diet'] as List<String>);
    final dietPrefix  = _dietPrefix(ctx.dietaryPreference);
    final bmiNote     = _bmiNote(ctx.bmi);
    cards.add(SuggestionCard(
      category:       'diet',
      title:          'Nutrition Focus',
      description:    dietPrefix + dietList.first + bmiNote,
      allSuggestions: dietList,
      reason:         'Optimised for $phase phase & ${ctx.dietaryPreference} diet',
      priority:       8,
    ));

    // 4. Exercise — personalised for fitness_level + mood + energy
    final exerciseList = (base['exercise'] as List<String>);
    String exerciseDesc = exerciseList.first;

    // Fitness override (only when energy is acceptable)
    if (ctx.energyLevel >= 4) {
      const fitnessOverrides = <String, String>{
        'sedentary':   'Start with a 15-min walk — movement is medicine even when energy is low.',
        'light':       'A gentle 20–30 min walk or yoga session works great for your fitness level.',
        'very_active': 'Your fitness base is strong — push the intensity if energy allows.',
      };
      exerciseDesc = fitnessOverrides[ctx.fitnessLevel] ?? exerciseDesc;
    }
    // Mood override takes precedence
    if (mood.containsKey('exercise_modification')) {
      exerciseDesc = mood['exercise_modification'] as String;
    }
    // Low energy always wins
    if (ctx.energyLevel < 4) {
      exerciseDesc = 'Your energy is low — gentle stretching or a short walk is ideal.';
    }

    cards.add(SuggestionCard(
      category:       'exercise',
      title:          'Movement Recommendation',
      description:    exerciseDesc,
      allSuggestions: exerciseList,
      reason:         'Based on $phase phase, energy & ${ctx.fitnessLevel} fitness level',
      priority:       7,
    ));

    // 5. Meditation
    final med = (base['meditation_details'] as Map<String, String>);
    cards.add(SuggestionCard(
      category:    'meditation',
      title:       med['type']!,
      description: med['focus']!,
      duration:    med['duration'],
      benefits:    med['benefits'],
      reason:      'Ideal for $phase phase',
      priority:    6,
    ));

    // 6. Productivity — age-aware note
    final prodList  = (base['productivity'] as List<String>);
    final ageNote   = ctx.age >= 35 ? ' Schedule recovery time between deep-focus sessions.' : '';
    cards.add(SuggestionCard(
      category:       'productivity',
      title:          'Work & Productivity',
      description:    prodList.first + ageNote,
      allSuggestions: prodList,
      reason:         '$phase phase affects your mental energy',
      priority:       5,
    ));

    // 7. Social
    final socialList = (base['social'] as List<String>);
    cards.add(SuggestionCard(
      category:       'social',
      title:          'Social Energy',
      description:    socialList.first,
      allSuggestions: socialList,
      reason:         'Your cycle affects your social preferences',
      priority:       4,
    ));

    // 8. Sleep alert (personalised threshold)
    if (ctx.sleepHours < ctx.avgSleepHours - 0.5) {
      cards.add(SuggestionCard(
        category:    'sleep',
        title:       'Sleep Priority',
        description: 'You got ${ctx.sleepHours.toStringAsFixed(1)} hrs. '
                     'Your personal target is ${ctx.avgSleepHours.toStringAsFixed(0)} hrs — aim for that tonight.',
        reason:      'Adequate sleep is crucial for hormone balance',
        priority:    10,
      ));
    }

    // 9. Stress alert
    if (ctx.stressLevel > 6) {
      cards.add(const SuggestionCard(
        category:    'stress',
        title:       'Stress Management',
        description: 'Your stress is elevated. Take short breaks and practise box breathing (4-4-4-4).',
        reason:      'High stress disrupts hormone balance and cycle regularity',
        priority:    10,
      ));
    }

    // 10. Health goals bonus cards
    for (final goal in ctx.healthGoals) {
      final key  = goal.toLowerCase().replaceAll(' ', '_');
      final card = _goalCards[key];
      if (card != null) {
        cards.add(SuggestionCard(
          category:    card[0],
          title:       card[1],
          description: card[2],
          reason:      'Supports your goal: ${_capitalize(goal.replaceAll('_', ' '))}',
          priority:    8,
        ));
      }
    }

    // 11. Symptom-specific
    cards.addAll(_symptomCards(ctx.symptoms));

    // Sort by priority desc, cap at 10
    cards.sort((a, b) => b.priority.compareTo(a.priority));

    return SuggestionResult(
      date:                    _today(),
      cyclePhase:              phase,
      suggestions:             cards.take(10).toList(),
      workoutRecommendations:  base['exercise']    as List<String>,
      dietRecommendations:     base['diet']        as List<String>,
      meditationType:          base['meditation']  as String,
      productivityTips:        base['productivity'] as List<String>,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────────────────────────────────────────

  List<SuggestionCard> _symptomCards(List<String> symptoms) {
    final cards = <SuggestionCard>[];
    for (final s in symptoms) {
      final r = _symptomRemedies[s];
      if (r == null) continue;
      cards.add(SuggestionCard(
        category:    'symptom_relief',
        title:       r['title'] as String,
        description: r['description'] as String,
        reason:      'Addressing your $s',
        priority:    r['priority'] as int,
      ));
    }
    return cards;
  }

  static String _dietPrefix(String pref) {
    const prefixes = {
      'vegan':       'Plant-based focus: ',
      'vegetarian':  'Vegetarian option: ',
      'keto':        'Keto-friendly: ',
      'paleo':       'Paleo choice: ',
    };
    return prefixes[pref] ?? '';
  }

  static String _bmiNote(double bmi) {
    if (bmi < 18.5) return ' (prioritise calorie-dense nutrient sources)';
    if (bmi > 27.5) return ' (choose lower-glycaemic options)';
    return '';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

// ──────────────────────────────────────────────────────────────────────────────
//  Singleton
// ──────────────────────────────────────────────────────────────────────────────

SuggestionEngine? _instance;
SuggestionEngine getSuggestionEngine() => _instance ??= SuggestionEngine();
