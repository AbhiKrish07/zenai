import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../core/database.dart';
import '../../models/mood.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/shared_widgets.dart';

class MoodModuleScreen extends StatefulWidget {
  const MoodModuleScreen({super.key});
  @override
  State<MoodModuleScreen> createState() => _MoodModuleScreenState();
}

class _MoodModuleScreenState extends State<MoodModuleScreen> {
  final _db = ZenDatabase();
  List<MoodEntry> _history = [];
  MoodEntry? _today;
  double _avgEnergy = 5;
  bool _loading = true;

  // Check-in state
  int _moodScore = 5;
  int _energyLevel = 5;
  final _notesCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final history = await _db.getMoodHistory(days: 30);
    final today = await _db.getTodaysMood();
    final avg = await _db.getAverageEnergy(days: 7);
    if (mounted) setState(() { _history = history; _today = today; _avgEnergy = avg; _loading = false; });
  }

  Future<void> _checkIn() async {
    HapticFeedback.mediumImpact();
    final entry = MoodEntry(moodScore: _moodScore, energyLevel: _energyLevel, notes: _notesCtrl.text.trim());
    await _db.insertMood(entry);
    _notesCtrl.clear();
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check-in saved! ${entry.moodEmoji}', style: GoogleFonts.syne()), backgroundColor: BlitzTheme.surface),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlitzTheme.bg,
      appBar: AppBar(title: Text('Mood & Energy', style: GoogleFonts.syne(fontWeight: FontWeight.w800))),
      body: _loading ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent)) : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Stats row
          Row(children: [
            Expanded(child: MetricCard(label: '7-DAY ENERGY', value: _avgEnergy.toStringAsFixed(1), icon: Icons.bolt, color: BlitzTheme.gold, subtitle: '/10')),
            const SizedBox(width: 8),
            Expanded(child: MetricCard(
              label: 'TODAY',
              value: _today != null ? '${_today!.moodEmoji} ${_today!.moodScore}/10' : 'Not checked in',
              icon: Icons.mood, color: BlitzTheme.accent,
            )),
          ]),
          const SizedBox(height: 16),
          // Check-in card
          GlassContainer(
            margin: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_today != null ? 'UPDATE CHECK-IN' : 'DAILY CHECK-IN', style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              // Mood slider
              Text('How are you feeling?', style: GoogleFonts.syne(fontSize: 14, color: BlitzTheme.textPrimary, fontWeight: FontWeight.w600)),
              Row(children: [
                const Text('😢', style: TextStyle(fontSize: 20)),
                Expanded(child: SliderTheme(
                  data: SliderThemeData(activeTrackColor: BlitzTheme.accent, thumbColor: BlitzTheme.accent, inactiveTrackColor: BlitzTheme.faint, overlayColor: BlitzTheme.accent.withValues(alpha: 0.1)),
                  child: Slider(value: _moodScore.toDouble(), min: 1, max: 10, divisions: 9, label: '$_moodScore', onChanged: (v) => setState(() => _moodScore = v.round())),
                )),
                const Text('🌟', style: TextStyle(fontSize: 20)),
              ]),
              const SizedBox(height: 8),
              // Energy slider
              Text('Energy level?', style: GoogleFonts.syne(fontSize: 14, color: BlitzTheme.textPrimary, fontWeight: FontWeight.w600)),
              Row(children: [
                const Text('😴', style: TextStyle(fontSize: 20)),
                Expanded(child: SliderTheme(
                  data: SliderThemeData(activeTrackColor: BlitzTheme.gold, thumbColor: BlitzTheme.gold, inactiveTrackColor: BlitzTheme.faint, overlayColor: BlitzTheme.gold.withValues(alpha: 0.1)),
                  child: Slider(value: _energyLevel.toDouble(), min: 1, max: 10, divisions: 9, label: '$_energyLevel', onChanged: (v) => setState(() => _energyLevel = v.round())),
                )),
                const Text('⚡', style: TextStyle(fontSize: 20)),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _notesCtrl, style: GoogleFonts.syne(color: BlitzTheme.textPrimary, fontSize: 13), maxLines: 2, decoration: const InputDecoration(hintText: 'Notes (optional)')),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _checkIn, child: const Text('Save Check-in'))),
            ]),
          ),
          const SizedBox(height: 16),
          // History
          const SectionHeader(title: 'HISTORY', icon: Icons.bar_chart, color: BlitzTheme.accent),
          if (_history.isEmpty)
            const EmptyState(icon: Icons.mood, title: 'No History', subtitle: 'Start checking in daily', color: BlitzTheme.accent)
          else
            ..._history.take(14).map((m) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white.withValues(alpha: 0.03), border: Border.all(color: BlitzTheme.border)),
              child: Row(children: [
                Text(m.moodEmoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${m.date.month}/${m.date.day} · Mood ${m.moodScore}/10', style: GoogleFonts.syne(fontSize: 12, color: BlitzTheme.textPrimary, fontWeight: FontWeight.w600)),
                  if (m.notes.isNotEmpty) Text(m.notes, style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Text('${m.energyEmoji} ${m.energyLevel}', style: GoogleFonts.spaceMono(fontSize: 11, color: BlitzTheme.gold)),
              ]),
            )),
        ]),
      ),
    );
  }
}
