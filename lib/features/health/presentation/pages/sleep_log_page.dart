import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/local/local_database_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/eva_charts.dart';

class SleepLogPage extends StatefulWidget {
  const SleepLogPage({super.key});

  @override
  State<SleepLogPage> createState() => _SleepLogPageState();
}

class _SleepLogPageState extends State<SleepLogPage> {
  late final LocalDatabaseService _localDb;

  double _hoursSlept = 7.0;
  int _quality = 3;
  bool? _hadDreams;
  final _wakeTimeCtrl   = TextEditingController();
  final _bedTimeCtrl    = TextEditingController();
  final _dreamNotesCtrl = TextEditingController();
  final _notesCtrl      = TextEditingController();

  bool _submitting = false;
  Map<String, dynamic>? _stats;
  List<LocalSleepLogData> _logs = [];

  @override
  void initState() {
    super.initState();
    _localDb = getIt<LocalDatabaseService>();
    _loadData();
    _bedTimeCtrl.addListener(_recalcWakeTime);
  }

  @override
  void dispose() {
    _bedTimeCtrl.removeListener(_recalcWakeTime);
    _wakeTimeCtrl.dispose();
    _bedTimeCtrl.dispose();
    _dreamNotesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  int? _parseTime(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  String _formatTime(int totalMinutes) {
    final mins = totalMinutes % (24 * 60);
    final h = (mins ~/ 60) % 24;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  void _recalcWakeTime() {
    final bedMins = _parseTime(_bedTimeCtrl.text);
    if (bedMins == null) return;
    final wakeMins = bedMins + (_hoursSlept * 60).round();
    final newWake  = _formatTime(wakeMins);
    if (_wakeTimeCtrl.text != newWake) {
      _wakeTimeCtrl.text = newWake;
      _wakeTimeCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _wakeTimeCtrl.text.length),
      );
    }
  }

  Future<void> _loadData() async {
    try {
      final stats = await _localDb.getSleepStats();
      final logs  = await _localDb.getSleepLogs(limit: 14);
      setState(() {
        _stats = stats;
        _logs  = logs;
      });
    } catch (_) {}
  }

  Future<void> _pickTime(TextEditingController ctrl, {bool isWake = false}) async {
    final now = TimeOfDay.now();
    // Pre-fill from controller text if valid
    TimeOfDay initial = now;
    final parts = ctrl.text.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isWake ? 'WAKE TIME' : 'BED TIME',
    );
    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      ctrl.text = formatted;
      ctrl.selection = TextSelection.fromPosition(
          TextPosition(offset: formatted.length));
      if (!isWake) _recalcWakeTime(); // auto-recalc wake after bed pick
    }
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _localDb.logSleep(
        date:       today,
        hoursSlept: _hoursSlept,
        quality:    _quality,
        wakeTime:   _wakeTimeCtrl.text.isEmpty  ? null : _wakeTimeCtrl.text,
        bedTime:    _bedTimeCtrl.text.isEmpty    ? null : _bedTimeCtrl.text,
        hadDreams:  _hadDreams,
        dreamNotes: _dreamNotesCtrl.text.isEmpty ? null : _dreamNotesCtrl.text,
        notes:      _notesCtrl.text.isEmpty      ? null : _notesCtrl.text,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sleep logged! 🌙'), backgroundColor: Colors.indigo),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        title: Text('Sleep Journal', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_stats != null && (_stats!['count'] as int? ?? 0) > 0)
            _StatsBanner(stats: _stats!),
          if (_logs.length >= 3) ...[
            const SizedBox(height: 16),
            SleepDualAxisChart(logs: _logs.map((l) => SleepLogData(
              id        : l.id,
              date      : l.date,
              hoursSlept: l.hoursSlept,
              quality   : l.quality,
              wakeTime  : l.wakeTime,
              bedTime   : l.bedTime,
              hadDreams : l.hadDreams,
              notes     : l.notes,
            )).toList()),
          ],
          const SizedBox(height: 16),
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Log Last Night\'s Sleep',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: const Color(0xFF1A1A2E))),
              const SizedBox(height: 20),
              _Label('Hours slept: ${_hoursSlept.toStringAsFixed(1)}h'),
              Slider(
                value: _hoursSlept,
                min: 0, max: 12, divisions: 24,
                activeColor: const Color(0xFF4F46E5),
                onChanged: (v) {
                  setState(() => _hoursSlept = v);
                  _recalcWakeTime();
                },
              ),
              const SizedBox(height: 12),
              const _Label('Sleep quality'),
              const SizedBox(height: 8),
              Row(children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _quality = star),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      star <= _quality ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: star <= _quality ? const Color(0xFFFBBF24) : Colors.grey,
                      size: 36,
                    ),
                  ),
                );
              })),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => _pickTime(_bedTimeCtrl),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _bedTimeCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Bed time',
                        hintText: 'Tap to set',
                        prefixIcon: Icon(Icons.bedtime_outlined, size: 18),
                        suffixIcon: Icon(Icons.access_time, size: 16),
                      ),
                    ),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: () => _pickTime(_wakeTimeCtrl, isWake: true),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _wakeTimeCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Wake time',
                        hintText: 'Tap to set',
                        prefixIcon: Icon(Icons.wb_sunny_outlined, size: 18),
                        suffixIcon: Icon(Icons.access_time, size: 16),
                      ),
                    ),
                  ),
                )),
              ]),
              const SizedBox(height: 4),
              Text('Tap fields to pick times — wake auto-fills from bed + hours',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),
              const _Label('Did you dream?'),
              const SizedBox(height: 8),
              Row(children: [
                _ToggleChip(label: 'Yes 💭', selected: _hadDreams == true,
                    onTap: () => setState(() => _hadDreams = _hadDreams == true ? null : true)),
                const SizedBox(width: 8),
                _ToggleChip(label: 'No 😴', selected: _hadDreams == false,
                    onTap: () => setState(() => _hadDreams = _hadDreams == false ? null : false)),
              ]),
              if (_hadDreams == true) ...[
                const SizedBox(height: 12),
                TextField(controller: _dreamNotesCtrl, maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Dream notes (optional)')),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Save Sleep Log',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),
          ),
          if (_logs.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Recent Sleep',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 12),
            ..._logs.take(7).map((l) => _SleepHistoryTile(log: l)),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _StatsBanner extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsBanner({required this.stats});

  @override
  Widget build(BuildContext context) {
    final avgHours   = stats['avg_hours'];
    final avgQuality = stats['avg_quality'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _StatItem(label: 'Avg Sleep', value: avgHours != null ? '${avgHours}h' : '--'),
        _StatItem(label: 'Avg Quality', value: avgQuality != null ? '$avgQuality/5 ⭐' : '--'),
        _StatItem(label: 'This Month', value: '${stats['count']} nights'),
      ]),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label, value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
      Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
    ]);
  }
}

class _SleepHistoryTile extends StatelessWidget {
  final LocalSleepLogData log;
  const _SleepHistoryTile({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(children: [
        const Text('🌙', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(log.date, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF1A1A2E))),
          if (log.hoursSlept != null)
            Text('${log.hoursSlept!.toStringAsFixed(1)}h slept', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
        ])),
        if (log.quality != null)
          Row(mainAxisSize: MainAxisSize.min,
              children: List.generate(log.quality!, (_) => const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14))),
        if (log.hadDreams == true)
          const Padding(padding: EdgeInsets.only(left: 8), child: Text('💭', style: TextStyle(fontSize: 14))),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF374151)));
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4F46E5) : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFF4F46E5) : Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                color: selected ? Colors.white : Colors.grey,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13)),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}
