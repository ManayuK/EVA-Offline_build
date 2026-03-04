import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/local/local_database_service.dart';
import '../../../../core/providers/dashboard_provider.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../reports/report_generator.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _nameCtrl;
  bool _nameSaved = false;
  bool _editingName = false;

  @override
  void initState() {
    super.initState();
    final currentName = context.read<AuthProvider>().currentUser?.name ?? 'Me';
    _nameCtrl = TextEditingController(text: currentName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await context.read<AuthProvider>().updateName(name);
    setState(() { _editingName = false; _nameSaved = true; });
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _nameSaved = false);
  }

  Future<int?> _showNumberDialog(
    BuildContext context, {
    required String title,
    required String hint,
    required int current,
    required int min,
    required int max,
  }) async {
    final ctrl = TextEditingController(text: current.toString());
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: GoogleFonts.inter(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v != null && v >= min && v <= max) {
                Navigator.pop(ctx, v);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Save', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text('Profile',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Avatar + editable name ───────────────────────────────────
          Center(
            child: Column(
              children: [
                // Avatar circle
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryPurple, AppTheme.accentPink],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      user?.name.isNotEmpty == true
                          ? user!.name[0].toUpperCase()
                          : 'M',
                      style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Name — tap to edit
                if (_editingName) ...[
                  // Inline edit field
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 220,
                      minWidth: 140,
                    ),
                    child: TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppTheme.primaryPurple),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppTheme.primaryPurple, width: 2),
                        ),
                      ),
                      onSubmitted: (_) => _saveName(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _editingName = false;
                        _nameCtrl.text =
                            user?.name ?? 'Me'; // revert
                      }),
                      child: Text('Cancel',
                          style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saveName,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryPurple,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Save',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                  ]),
                ] else ...[
                  // Display name with edit pencil
                  GestureDetector(
                    onTap: () => setState(() => _editingName = true),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        user?.name ?? 'Me',
                        style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary),
                      ),
                      const SizedBox(width: 6),
                      if (_nameSaved)
                        const Icon(Icons.check_circle,
                            size: 16, color: Colors.green)
                      else
                        const Icon(Icons.edit_outlined,
                            size: 16, color: AppTheme.textSecondary),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text('Tap name to edit',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textTertiary)),
                ],

                const SizedBox(height: 4),
                Text('All data stored locally on this device',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Cycle settings
          const _SectionHeader('Cycle Settings'),
          _EditableTile(
            icon: Icons.calendar_today_outlined,
            title: 'Average Cycle Length',
            value: '${user?.cycleLength ?? 28} days',
            onTap: () async {
              final result = await _showNumberDialog(
                context,
                title: 'Cycle Length',
                hint: 'Days (21–45)',
                current: user?.cycleLength ?? 28,
                min: 21,
                max: 45,
              );
              if (result != null && context.mounted) {
                await context.read<AuthProvider>().updateProfile(cycleLength: result);
              }
            },
          ),
          _EditableTile(
            icon: Icons.water_drop_outlined,
            title: 'Period Length',
            value: '${user?.periodLength ?? 5} days',
            onTap: () async {
              final result = await _showNumberDialog(
                context,
                title: 'Period Length',
                hint: 'Days (2–10)',
                current: user?.periodLength ?? 5,
                min: 2,
                max: 10,
              );
              if (result != null && context.mounted) {
                await context.read<AuthProvider>().updateProfile(periodLength: result);
              }
            },
          ),

          const SizedBox(height: 16),

          // Personal profile
          const _SectionHeader('Personal Profile'),
          _SettingsTile(
            Icons.fitness_center,
            'Fitness Level',
            (user?.onboardingCompleted == true)
                ? 'Set during onboarding'
                : 'Not set — complete onboarding',
          ),
          if (user?.onboardingCompleted == false)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome,
                      color: AppTheme.primaryPurple, size: 16),
                  label: Text('Complete Personalisation',
                      style: GoogleFonts.inter(
                          color: AppTheme.primaryPurple,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primaryPurple),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => context.go('/onboarding'),
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Reports
          const _SectionHeader('Reports'),
          _ReportTile(),

          const SizedBox(height: 16),

          // Health Tracking
          const _SectionHeader('Health Tracking'),
          _NavTile(
            icon: Icons.bedtime_outlined,
            title: 'Sleep Journal',
            subtitle: 'Log quality, wake time & dreams',
            color: const Color(0xFF4F46E5),
            onTap: () => context.push('/sleep'),
          ),
          _NavTile(
            icon: Icons.monitor_weight_outlined,
            title: 'Weight Tracker',
            subtitle: 'Log weight & body measurements',
            color: const Color(0xFF10B981),
            onTap: () => context.push('/weight'),
          ),

          const SizedBox(height: 16),

          // Offline mode badge (backend no longer required)
          const _SectionHeader('App Mode'),
          const _OfflineModeCard(),

          const SizedBox(height: 16),

          // Privacy dashboard
          const _SectionHeader('Privacy Dashboard'),
          const _PrivacyCard(),

          const SizedBox(height: 24),

          // Reset all data
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset App Data?'),
                    content: const Text(
                        'This will permanently delete all your cycles, journal entries, and settings from this device.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Reset',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  // Clear in-memory provider state FIRST so no stale data
                  // is briefly shown when the app re-lands on home.
                  context.read<DashboardProvider>().resetState();
                  await context.read<AuthProvider>().resetAppData();
                  if (context.mounted) context.go('/onboarding');
                }
              },
              icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed),
              label: Text('Reset App Data',
                  style: GoogleFonts.inter(color: AppTheme.errorRed)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.errorRed),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 0.5)),
      );
}

class _EditableTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _EditableTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryPurple, size: 20),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 14, color: AppTheme.textPrimary))),
              Text(value,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.primaryPurple,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined,
                  size: 14, color: AppTheme.textTertiary),
            ],
          ),
        ),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  const _SettingsTile(this.icon, this.title, this.value);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryPurple, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child: Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 14, color: AppTheme.textPrimary))),
            Text(value,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 16, color: AppTheme.textTertiary),
          ],
        ),
      );
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.successGreen.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppTheme.successGreen.withValues(alpha: 0.25)),
        ),
        child: const Column(children: [
          _PrivacyRow(
              Icons.storage_outlined, 'Data Storage', 'Local device only'),
          Divider(height: 16),
          _PrivacyRow(
              Icons.psychology_outlined, 'AI Processing', 'On-device'),
          Divider(height: 16),
          _PrivacyRow(
              Icons.cloud_off_outlined, 'Cloud Sync', 'Disabled'),
          Divider(height: 16),
          _PrivacyRow(
              Icons.lock_outline, 'Encryption', 'AES-256 local DB'),
        ]),
      );
}

class _PrivacyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _PrivacyRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: AppTheme.successGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppTheme.textPrimary)),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 0,
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.successGreen,
                  fontWeight: FontWeight.w500)),
        ),
      ]);
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary)),
                ])),
            const Icon(Icons.chevron_right,
                size: 16, color: AppTheme.textTertiary),
          ]),
        ),
      );
}

class _OfflineModeCard extends StatelessWidget {
  const _OfflineModeCard();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.offline_bolt_rounded,
                color: Color(0xFF059669), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('100% On-Device',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: const Color(0xFF065F46))),
              const SizedBox(height: 3),
              Text('All data stays on your phone. No server needed.',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF047857),
                      height: 1.3)),
            ]),
          ),
        ]),
      );
}

// ignore: unused_element
class _ConnectivityBadge extends StatelessWidget {
  const _ConnectivityBadge();

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.offline_bolt_rounded, color: Color(0xFF059669), size: 10),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'On-device mode — no server needed',
            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF047857)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]);
}

// ─── Report Tile ──────────────────────────────────────────────────────────────
class _ReportTile extends StatefulWidget {
  @override
  State<_ReportTile> createState() => _ReportTileState();
}

class _ReportTileState extends State<_ReportTile> {
  bool _generatingPersonal = false;
  bool _generatingDoctor   = false;

  Future<void> _generate({required bool isDoctor}) async {
    final dash = context.read<DashboardProvider>().dashboard;
    if (dash == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dashboard data not loaded yet — open the Home tab first.'),
        ),
      );
      return;
    }

    setState(() => isDoctor ? _generatingDoctor = true : _generatingPersonal = true);

    try {
      final auth     = context.read<AuthProvider>();
      final username = auth.currentUser?.name ?? 'User';
      final localDb  = getIt<LocalDatabaseService>();

      // ── Fetch all data in parallel ────────────────────────────────────────
      final results = await Future.wait([
        localDb.getCycles(limit: 12).catchError((_) => <LocalCycleRecord>[]),
        localDb.getSymptoms(limit: 60).catchError((_) => <LocalSymptomRecord>[]),
        localDb.getSleepLogs(limit: 30).catchError((_) => <LocalSleepLogData>[]),
        localDb.getPhaseTasks().catchError((_) => <String, dynamic>{}),
        localDb.getEmotionTimeline(days: 30).catchError((_) => <String, dynamic>{}),
        localDb.getCycleAnomalies().catchError((_) => <LocalAnomalyAlert>[]),
        localDb.getOvulationLogs(limit: 12).catchError((_) => <LocalOvulationLog>[]),
        localDb.getPmsFeedback(limit: 12).catchError((_) => <LocalPmsFeedbackRecord>[]),
        localDb.getChatMemory().catchError((_) => const LocalChatMemorySummary(totalJournalEntries: 0, topMood: 'neutral', topKeywords: {}, phaseAvgSentiment: {}, summaries: [])),
      ]);

      final cycles        = results[0] as List<LocalCycleRecord>;
      final symptoms      = results[1] as List<LocalSymptomRecord>;
      final sleepLogs     = results[2] as List<LocalSleepLogData>;
      final tasksMap      = results[3] as Map<String, dynamic>;
      final emotionMap    = results[4] as Map<String, dynamic>;
      final anomalies     = results[5] as List<LocalAnomalyAlert>;
      final ovLogs        = results[6] as List<LocalOvulationLog>;
      final pmsFeedback   = results[7] as List<LocalPmsFeedbackRecord>;
      final chatMemory    = results[8] as LocalChatMemorySummary;

      // ── Cycle history list ────────────────────────────────────────────────
      final cycleHistory = cycles.map((c) => {
        'startDate'    : c.startDate,
        'cycleLength'  : c.cycleLength,
        'periodLength' : c.periodLength,
        'flowIntensity': c.flowIntensity,
      }).toList();

      // ── Actual last cycle length ──────────────────────────────────────────
      final int? actualLastCycleLength = cycles.length >= 2
          ? cycles[1].cycleLength
          : (cycles.length == 1 ? cycles[0].cycleLength : null);

      // ── Symptom frequency this cycle (filter by current cycle start) ──────
      final cycleStartStr = cycles.isNotEmpty ? cycles.first.startDate : null;
      final DateTime? cycleStart = cycleStartStr != null
          ? DateTime.tryParse(cycleStartStr) : null;
      final thisCtSymptoms = cycleStart != null
          ? symptoms.where((s) {
              final d = DateTime.tryParse(s.date);
              return d != null && !d.isBefore(cycleStart);
            }).toList()
          : symptoms;

      // Aggregate: {symptomType -> {totalSeverity, count}}
      final Map<String, Map<String, num>> aggSymptoms = {};
      for (final s in thisCtSymptoms) {
        final name = s.symptomType
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
            .join(' ');
        aggSymptoms[name] ??= {'total': 0, 'count': 0};
        aggSymptoms[name]!['total'] = aggSymptoms[name]!['total']! + s.severity;
        aggSymptoms[name]!['count'] = aggSymptoms[name]!['count']! + 1;
      }
      final symptomFrequency = aggSymptoms.entries
          .map((e) => {
                'name'       : e.key,
                'avgSeverity': (e.value['total']! / e.value['count']!).toStringAsFixed(1),
                'count'      : e.value['count']!.toInt(),
              })
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      // ── Prediction accuracy (running average method) ──────────────────────
      final completedCycles = cycles.where((c) => c.cycleLength != null).toList();
      final predictionAccuracy = <Map<String, dynamic>>[];
      for (int i = 0; i < completedCycles.length - 1 && i < 6; i++) {
        final priorLengths = completedCycles
            .skip(i + 1)
            .map((c) => c.cycleLength!)
            .toList();
        if (priorLengths.isEmpty) continue;
        final predicted = (priorLengths.reduce((a, b) => a + b) / priorLengths.length).round();
        final actual    = completedCycles[i].cycleLength!;
        final label     = DateFormat('MMM yyyy').format(
            DateTime.tryParse(completedCycles[i].startDate) ?? DateTime.now());
        predictionAccuracy.add({
          'cycleLabel': label,
          'predicted' : predicted,
          'actual'    : actual,
          'offBy'     : (actual - predicted).abs(),
        });
      }

      // ── Ovulation confirmations ───────────────────────────────────────────
      final ovulationConfirmations = ovLogs.map((ov) => {
        'userDate'     : ov.date,
        'predictedDate': ov.predictedDate,
        'daysOff'      : ov.daysOff,
      }).toList();

      // ── Sleep trend ───────────────────────────────────────────────────────
      final sleepTrend = sleepLogs
          .where((s) => s.hoursSlept != null)
          .map((s) => {'date': s.date, 'hours': s.hoursSlept!})
          .toList();
      final sleepHours = sleepLogs
          .map((s) => s.hoursSlept)
          .whereType<double>()
          .toList();
      final int sleepNightsUnder6 = sleepHours.where((h) => h < 6).length;
      String sleepTrendDirection = 'stable';
      if (sleepHours.length >= 6) {
        final firstHalf = sleepHours.take(sleepHours.length ~/ 2).reduce((a, b) => a + b) /
            (sleepHours.length ~/ 2);
        final secondHalf = sleepHours.skip(sleepHours.length ~/ 2).reduce((a, b) => a + b) /
            (sleepHours.length - sleepHours.length ~/ 2);
        if (secondHalf - firstHalf > 0.3) {
          sleepTrendDirection = 'improving';
        } else if (firstHalf - secondHalf > 0.3) sleepTrendDirection = 'declining';
      }

      // ── Avg sleep & stress (prefer dashboard values, fall back to computed) ─
      final double? avgSleep = dash.avgSleepFromDash ??
          (sleepHours.isNotEmpty ? sleepHours.reduce((a, b) => a + b) / sleepHours.length : null);
      final double? avgStress = dash.avgStressFromDash;

      // ── Mood by phase (from chat memory) ─────────────────────────────────
      final moodByPhase = chatMemory.phaseAvgSentiment;
      final bestMoodPhase = chatMemory.bestPhase;

      // ── PMS history ───────────────────────────────────────────────────────
      final pmsHistory = pmsFeedback.asMap().entries.map((e) => {
        'cycleLabel'         : 'Cycle ${e.key + 1}',
        'arrivedAsPredicted' : e.value.arrivedAsPredicted,
        'severity'           : e.value.severity,
      }).toList();

      // ── Top emotions ──────────────────────────────────────────────────────
      final Map<String, int> topEmotions = {};
      final topEmotionsRaw = emotionMap['top_emotions'] as Map<String, dynamic>? ?? {};
      topEmotionsRaw.forEach((k, v) => topEmotions[k] = (v as num).toInt());

      // ── Phase tasks ───────────────────────────────────────────────────────
      final List<Map<String, dynamic>> phaseTasks =
          (tasksMap['tasks'] as List?)
              ?.map((t) => Map<String, dynamic>.from(t as Map))
              .toList() ?? [];

      // ── Anomaly alerts ────────────────────────────────────────────────────
      final anomalyList = anomalies.map((a) => {
        'title'   : a.title,
        'message' : a.message,
        'severity': a.severity,
      }).toList();

      // ── Top mood ─────────────────────────────────────────────────────────
      final String? topMood = chatMemory.topMood.isNotEmpty ? chatMemory.topMood : dash.moodToday;

      // ── Build ReportData ─────────────────────────────────────────────────
      final data = ReportData(
        username               : username,
        isDoctor               : isDoctor,
        nextPeriodDate         : dash.nextPeriodDate,
        daysUntilPeriod        : dash.daysUntilPeriod,
        currentPhase           : dash.currentPhase,
        currentCycleDay        : dash.currentCycleDay,
        confidenceScore        : dash.confidenceScore,
        predictionMethod       : dash.predictionMethod,
        ovulationDate          : dash.ovulationDate,
        fertileWindowStart     : dash.fertileWindowStart,
        fertileWindowEnd       : dash.fertileWindowEnd,
        healthScore            : dash.healthScore,
        aiInsight              : isDoctor ? null : dash.aiInsightMessage,
        predictedCycleLength   : dash.cycleLengthPrediction,
        actualLastCycleLength  : actualLastCycleLength,
        pmsPeakDate            : dash.pmsPeakDate,
        pmsRiskLevel           : dash.pmsRiskLevel,
        pmsRiskScore           : dash.pmsRiskScore,
        avgSleep               : avgSleep,
        avgStress              : avgStress,
        topMood                : topMood,
        avgJournalSentiment    : dash.lastJournalSentiment,
        sentimentStressLevel   : dash.sentimentStressLevel,
        sentimentVarianceEffect: dash.sentimentVarianceEffect,
        kalmanNObservations    : dash.nPersonalCycles,
        kalmanStd              : dash.kalmanStd,
        kalmanMethod           : dash.predictionMethod,
        anomalyAlerts          : anomalyList,
        phaseTasks             : isDoctor ? [] : phaseTasks,
        topEmotions            : isDoctor ? {} : topEmotions,
        recentSymptoms         : [],
        cycleHistory           : cycleHistory,
        symptomFrequency       : symptomFrequency
            .map((s) => {
              ...s,
              'avgSeverity': double.tryParse(s['avgSeverity'].toString()) ?? 0.0,
            })
            .toList(),
        predictionAccuracy     : predictionAccuracy,
        ovulationConfirmations : ovulationConfirmations,
        sleepTrend             : sleepTrend,
        sleepNightsUnder6      : sleepNightsUnder6,
        sleepTrendDirection    : sleepTrendDirection,
        moodByPhase            : moodByPhase,
        bestMoodPhase          : bestMoodPhase,
        pmsHistory             : pmsHistory,
      );

      if (!mounted) return;
      await generateAndDownloadReport(context, data);
    } finally {
      if (mounted) {
        setState(() {
          _generatingPersonal = false;
          _generatingDoctor   = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _reportButton(
          icon     : Icons.favorite_border_rounded,
          title    : 'Personal Health Report',
          subtitle : 'Full PDF — cycle, sleep, moods & AI insights',
          color    : const Color(0xFF7B3FE4),
          bgColor  : const Color(0xFFEDE7F6),
          loading  : _generatingPersonal,
          onTap    : _generatingPersonal || _generatingDoctor ? null : () => _generate(isDoctor: false),
        ),
        const SizedBox(height: 8),
        _reportButton(
          icon     : Icons.local_hospital_outlined,
          title    : 'Doctor Report',
          subtitle : 'Clinical summary — B&W, no personal AI content',
          color    : const Color(0xFF1A1A2E),
          bgColor  : const Color(0xFFF5F5F5),
          loading  : _generatingDoctor,
          onTap    : _generatingPersonal || _generatingDoctor ? null : () => _generate(isDoctor: true),
        ),
      ],
    );
  }

  Widget _reportButton({
    required IconData icon,
    required String   title,
    required String   subtitle,
    required Color    color,
    required Color    bgColor,
    required bool     loading,
    required VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bgColor),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E))),
        subtitle: Text(subtitle,
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF6B6B8A))),
        trailing: loading
            ? SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(Icons.download_rounded, color: color, size: 22),
        onTap: onTap,
      ),
    );
  }
}
