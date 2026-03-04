import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/local/local_database_service.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// ── Shared colour tokens (matches login & register) ──────────────────────────
const _kTextPrimary   = Color(0xFF1A1A2E);
const _kTextSecondary = Color(0xFF6B7280);
const _kTextLabel     = Color(0xFF374151);
const _kBorder        = Color(0xFFE5E7EB);
const _kFill          = Color(0xFFF9FAFB);
const _kBg            = Color(0xFFF5F0FF);
const _kPurple        = Color(0xFF9333EA);

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  int  _step      = 0;
  bool _submitting = false;

  // ── Step 1 ──────────────────────────────────────────────────────────────────
  final _dobCtrl    = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  DateTime? _dob;

  // ── Step 2 ──────────────────────────────────────────────────────────────────
  double _cycleLength  = 28;
  double _periodLength = 5;

  // ── Step 3 ──────────────────────────────────────────────────────────────────
  double _sleepHours   = 7.5;
  double _stressLevel  = 5;
  String _fitnessLevel = 'moderate';

  // ── Step 4 ──────────────────────────────────────────────────────────────────
  final Set<String> _goals = {};
  String _diet = 'omnivore';

  final _pageCtrl = PageController();

  static const _fitnessOptions = [
    ('sedentary',   'Sedentary',   Icons.chair_outlined),
    ('light',       'Light',       Icons.directions_walk),
    ('moderate',    'Moderate',    Icons.directions_run),
    ('active',      'Active',      Icons.fitness_center),
    ('very_active', 'Very Active', Icons.electric_bolt),
  ];

  static const _goalOptions = [
    ('better_sleep',      'Better Sleep',      Icons.nightlight_round),
    ('stress_reduction',  'Stress Reduction',  Icons.spa_outlined),
    ('weight_management', 'Weight Management', Icons.monitor_weight_outlined),
    ('fitness',           'Fitness',           Icons.fitness_center),
    ('mental_health',     'Mental Health',     Icons.psychology_outlined),
    ('hormone_balance',   'Hormone Balance',   Icons.water_drop_outlined),
  ];

  static const _dietOptions = [
    ('omnivore',   'Omnivore',   '🥩'),
    ('vegetarian', 'Vegetarian', '🥗'),
    ('vegan',      'Vegan',      '🌱'),
    ('keto',       'Keto',       '🥑'),
    ('paleo',      'Paleo',      '🍖'),
    ('other',      'Other',      '🍽️'),
  ];

  void _next() {
    if (_step < 3) {
      setState(() => _step++);
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.previousPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    }
  }

  Future<void> _submit() async {
    // Validate height/weight ranges (9-year-old minimum)
    final h = double.tryParse(_heightCtrl.text);
    final w = double.tryParse(_weightCtrl.text);
    if (h != null && (h < 50 || h > 300)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Height must be between 50 and 300 cm')),
      );
      return;
    }
    if (w != null && (w < 10 || w > 600)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weight must be between 10 and 600 kg')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final ai = getIt<LocalDatabaseService>();
      await ai.saveOnboarding(
        dob:              _dob,
        heightCm:         double.tryParse(_heightCtrl.text),
        weightKg:         double.tryParse(_weightCtrl.text),
        avgCycleLength:   _cycleLength.round(),
        avgPeriodLength:  _periodLength.round(),
        fitnessLevel:     _fitnessLevel,
        healthGoals:      _goals.toList(),
        avgSleepHours:    _sleepHours,
        avgStressLevel:   _stressLevel.round(),
        dietaryPreference: _diet,
      );
      if (!mounted) return;
      await context.read<AuthProvider>().updateProfile(onboardingCompleted: true);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save profile: $e')),
        );
      }
    }
    setState(() => _submitting = false);
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),  // default to young adult; picker allows 9-150 year olds
      firstDate: DateTime(1875),  // supports up to 150 years old
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 9)),  // minimum 9 years old
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: _kPurple),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobCtrl.text =
            '${picked.day.toString().padLeft(2, '0')} / '
            '${picked.month.toString().padLeft(2, '0')} / '
            '${picked.year}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(step: _step),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Step1(
                    dobCtrl:    _dobCtrl,
                    heightCtrl: _heightCtrl,
                    weightCtrl: _weightCtrl,
                    onPickDob:  _pickDob,
                  ),
                  _Step2(
                    cycleLength:     _cycleLength,
                    periodLength:    _periodLength,
                    onCycleChanged:  (v) => setState(() => _cycleLength = v),
                    onPeriodChanged: (v) => setState(() => _periodLength = v),
                  ),
                  _Step3(
                    sleepHours:      _sleepHours,
                    stressLevel:     _stressLevel,
                    fitnessLevel:    _fitnessLevel,
                    fitnessOptions:  _fitnessOptions,
                    onSleepChanged:   (v) => setState(() => _sleepHours = v),
                    onStressChanged:  (v) => setState(() => _stressLevel = v),
                    onFitnessChanged: (v) => setState(() => _fitnessLevel = v),
                  ),
                  _Step4(
                    goals:        _goals,
                    diet:         _diet,
                    goalOptions:  _goalOptions,
                    dietOptions:  _dietOptions,
                    onGoalToggled: (g) => setState(() {
                      _goals.contains(g) ? _goals.remove(g) : _goals.add(g);
                    }),
                    onDietChanged: (d) => setState(() => _diet = d),
                  ),
                ],
              ),
            ),
            _Footer(
              step:       _step,
              submitting: _submitting,
              onBack:     _step > 0 ? _back : null,
              onNext:     _next,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int step;
  const _Header({required this.step});

  static const _titles = [
    'About You',
    'Your Cycle',
    'Your Lifestyle',
    'Goals & Diet',
  ];
  static const _subtitles = [
    'Help the model understand your body baseline',
    'Set your cycle defaults for accurate predictions',
    'Your daily habits fuel personalised recommendations',
    'What matters most to you?',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF9333EA), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Text('Personalise EVA',
              style: GoogleFonts.inter(
                  color: Colors.white70, fontSize: 12, letterSpacing: 0.8)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${step + 1} of 4',
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 14),
        Text(_titles[step],
            style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(_subtitles[step],
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 18),
        // Progress segments
        Row(
          children: List.generate(4, (i) => Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
              decoration: BoxDecoration(
                color: i <= step
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )),
        ),
      ]),
    );
  }
}

// ── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final int step;
  final bool submitting;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  const _Footer({
    required this.step,
    required this.submitting,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      decoration: const BoxDecoration(color: Colors.white),
      child: Row(children: [
        if (onBack != null) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kPurple),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: Text('Back',
                  style: GoogleFonts.inter(
                      color: _kPurple, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: submitting ? null : onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text(
                    step < 3 ? 'Continue' : 'Start My Journey',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w600,
                        fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ── Step 1: Personal Info ─────────────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  final TextEditingController dobCtrl;
  final TextEditingController heightCtrl;
  final TextEditingController weightCtrl;
  final VoidCallback onPickDob;

  const _Step1({
    required this.dobCtrl,
    required this.heightCtrl,
    required this.weightCtrl,
    required this.onPickDob,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _InfoBanner(
          icon: Icons.psychology_outlined,
          text: 'Your age, height and weight let the model calculate '
              'accurate BMI and age-adjusted hormone recommendations.',
        ),
        const SizedBox(height: 24),

        const _FieldLabel('Date of Birth'),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onPickDob,
          child: AbsorbPointer(
            child: _StyledInput(
              controller: dobCtrl,
              hint: 'DD / MM / YYYY',
              icon: Icons.calendar_today_outlined,
            ),
          ),
        ),
        const SizedBox(height: 18),

        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('Height (cm)'),
              const SizedBox(height: 6),
              _StyledInput(
                controller: heightCtrl,
                hint: 'e.g. 140 (50–300)',
                icon: Icons.height,
                keyboardType: TextInputType.number,
              ),
            ],
          )),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('Weight (kg)'),
              const SizedBox(height: 6),
              _StyledInput(
                controller: weightCtrl,
                hint: 'e.g. 50 (10–600)',
                icon: Icons.monitor_weight_outlined,
                keyboardType: TextInputType.number,
              ),
            ],
          )),
        ]),
        const SizedBox(height: 24),
        _PrivacyNote(),
      ]),
    );
  }
}

// ── Step 2: Cycle Info ────────────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  final double cycleLength;
  final double periodLength;
  final ValueChanged<double> onCycleChanged;
  final ValueChanged<double> onPeriodChanged;

  const _Step2({
    required this.cycleLength,
    required this.periodLength,
    required this.onCycleChanged,
    required this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _InfoBanner(
          icon: Icons.loop,
          text: 'These defaults pre-load the XGBoost + Kalman cycle predictor. '
              'The model will refine them as you log more cycles.',
        ),
        const SizedBox(height: 24),
        _SliderCard(
          label: 'Average Cycle Length',
          value: cycleLength,
          min: 21, max: 45, divisions: 24, unit: 'days',
          description: 'Days from period start to next period start',
          onChanged: onCycleChanged,
        ),
        const SizedBox(height: 16),
        _SliderCard(
          label: 'Period Duration',
          value: periodLength,
          min: 2, max: 10, divisions: 8, unit: 'days',
          description: 'How many days your period typically lasts',
          onChanged: onPeriodChanged,
        ),
      ]),
    );
  }
}

// ── Step 3: Lifestyle ─────────────────────────────────────────────────────────

class _Step3 extends StatelessWidget {
  final double sleepHours;
  final double stressLevel;
  final String fitnessLevel;
  final List<(String, String, IconData)> fitnessOptions;
  final ValueChanged<double> onSleepChanged;
  final ValueChanged<double> onStressChanged;
  final ValueChanged<String> onFitnessChanged;

  const _Step3({
    required this.sleepHours,
    required this.stressLevel,
    required this.fitnessLevel,
    required this.fitnessOptions,
    required this.onSleepChanged,
    required this.onStressChanged,
    required this.onFitnessChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _InfoBanner(
          icon: Icons.insights,
          text: 'Sleep and stress directly influence hormone levels. '
              'Your fitness baseline shapes exercise recommendations.',
        ),
        const SizedBox(height: 20),
        _SliderCard(
          label: 'Typical Sleep',
          value: sleepHours,
          min: 4, max: 12, divisions: 16, unit: 'hrs',
          description: 'Average hours of sleep per night',
          onChanged: onSleepChanged,
        ),
        const SizedBox(height: 16),
        _SliderCard(
          label: 'Typical Stress Level',
          value: stressLevel,
          min: 1, max: 10, divisions: 9, unit: '/ 10',
          description: 'How stressed you usually feel on a typical day',
          onChanged: onStressChanged,
        ),
        const SizedBox(height: 22),
        const _FieldLabel('Fitness Level'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: fitnessOptions.map((opt) {
            final (key, label, icon) = opt;
            final selected = fitnessLevel == key;
            return GestureDetector(
              onTap: () => onFitnessChanged(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? _kPurple : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? _kPurple : _kBorder,
                    width: selected ? 2 : 1.5,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(
                          color: _kPurple.withValues(alpha: 0.25), blurRadius: 8)]
                      : [],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon,
                      size: 16,
                      color: selected ? Colors.white : _kTextSecondary),
                  const SizedBox(width: 6),
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : _kTextPrimary)),
                ]),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }
}

// ── Step 4: Goals & Diet ──────────────────────────────────────────────────────

class _Step4 extends StatelessWidget {
  final Set<String> goals;
  final String diet;
  final List<(String, String, IconData)> goalOptions;
  final List<(String, String, String)>   dietOptions;
  final ValueChanged<String> onGoalToggled;
  final ValueChanged<String> onDietChanged;

  const _Step4({
    required this.goals,
    required this.diet,
    required this.goalOptions,
    required this.dietOptions,
    required this.onGoalToggled,
    required this.onDietChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _InfoBanner(
          icon: Icons.flag_outlined,
          text: 'Goals unlock targeted suggestion cards in Insights. '
              'Diet preference shapes nutrition recommendations.',
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Health Goals  (pick all that apply)'),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          final ratio = constraints.maxWidth < 320 ? 2.2
                      : constraints.maxWidth < 360 ? 2.5
                      : 2.8;
          return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: ratio,
          ),
          itemCount: goalOptions.length,
          itemBuilder: (_, i) {
            final (key, label, icon) = goalOptions[i];
            final selected = goals.contains(key);
            return GestureDetector(
              onTap: () => onGoalToggled(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? _kPurple.withValues(alpha: 0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? _kPurple : _kBorder,
                    width: selected ? 2 : 1.5,
                  ),
                ),
                child: Row(children: [
                  Icon(icon,
                      size: 16,
                      color: selected ? _kPurple : _kTextSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: selected ? _kPurple : _kTextPrimary)),
                  ),
                ]),
              ),
            );
          },
        );
        }),
        const SizedBox(height: 22),
        const _FieldLabel('Dietary Preference'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: dietOptions.map((opt) {
            final (key, label, emoji) = opt;
            final selected = diet == key;
            return GestureDetector(
              onTap: () => onDietChanged(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? _kPurple : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? _kPurple : _kBorder,
                    width: selected ? 2 : 1.5,
                  ),
                ),
                child: Text('$emoji  $label',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : _kTextPrimary)),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _kTextLabel));
}

class _StyledInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;

  const _StyledInput({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller:   controller,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(
            fontSize: 15,
            color: _kTextPrimary,
            fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(
              color: const Color(0xFFD1D5DB), fontSize: 15),
          prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
          filled:     true,
          fillColor:  _kFill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBorder, width: 1.5)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBorder, width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kPurple, width: 2)),
        ),
      );
}

class _SliderCard extends StatelessWidget {
  final String label;
  final double value;
  final double min, max;
  final int divisions;
  final String unit, description;
  final ValueChanged<double> onChanged;

  const _SliderCard({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.description,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kTextPrimary)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _kPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${value % 1 == 0 ? value.toInt() : value.toStringAsFixed(1)} $unit',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _kPurple),
            ),
          ),
        ]),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: _kPurple,
          inactiveColor: _kPurple.withValues(alpha: 0.15),
          onChanged: onChanged,
        ),
        Text(description,
            style: GoogleFonts.inter(
                fontSize: 11, color: _kTextSecondary)),
      ]),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kPurple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kPurple.withValues(alpha: 0.18)),
        ),
        child: Row(children: [
          Icon(icon, color: _kPurple, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _kTextPrimary,
                    height: 1.4)),
          ),
        ]),
      );
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(children: [
          const Icon(Icons.shield_outlined,
              color: Color(0xFF16A34A), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'All data stays on your device — never shared externally.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: const Color(0xFF16A34A)),
            ),
          ),
        ]),
      );
}
