import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../theme.dart';
import '../../core/database.dart';
import '../../models/study_session.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/shared_widgets.dart';

class StudyModuleScreen extends StatefulWidget {
  const StudyModuleScreen({super.key});
  @override
  State<StudyModuleScreen> createState() => _StudyModuleScreenState();
}

class _StudyModuleScreenState extends State<StudyModuleScreen> {
  final _db = ZenDatabase();
  
  // Pomodoro state
  int _pomodoroMinutes = 25;
  int _secondsRemaining = 0;
  bool _isRunning = false;
  Timer? _timer;
  String _currentSubject = '';
  
  // Stats
  int _streak = 0;
  int _todayMinutes = 0;
  List<StudySession> _recentSessions = [];
  bool _loading = true;

  final List<String> _subjects = ['Math', 'Physics', 'CS', 'English', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final streak = await _db.getStudyStreak();
    final today = await _db.getTotalStudyMinutesToday();
    final sessions = await _db.getStudySessions(days: 7);
    if (mounted) {
      setState(() {
        _streak = streak;
        _todayMinutes = today;
        _recentSessions = sessions;
        _loading = false;
      });
    }
  }

  void _startPomodoro() {
    if (_currentSubject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Select a subject first', style: GoogleFonts.syne()), backgroundColor: BlitzTheme.surface),
      );
      return;
    }
    
    HapticFeedback.mediumImpact();
    setState(() {
      _secondsRemaining = _pomodoroMinutes * 60;
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 0) {
        timer.cancel();
        _completeSession();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  void _stopPomodoro() {
    _timer?.cancel();
    final elapsed = _pomodoroMinutes * 60 - _secondsRemaining;
    if (elapsed > 60) { // At least 1 minute
      _saveSession(elapsed ~/ 60);
    }
    setState(() { _isRunning = false; _secondsRemaining = 0; });
  }

  void _completeSession() {
    HapticFeedback.heavyImpact();
    _saveSession(_pomodoroMinutes);
    setState(() { _isRunning = false; _secondsRemaining = 0; });
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: BlitzTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('🎉 Session Complete!', style: GoogleFonts.syne(color: BlitzTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('$_pomodoroMinutes minutes of $_currentSubject logged.', style: GoogleFonts.syne(color: BlitzTheme.textMuted)),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(c), child: const Text('Nice'))],
      ),
    );
  }

  Future<void> _saveSession(int minutes) async {
    final session = StudySession(subject: _currentSubject, durationMinutes: minutes);
    await _db.insertStudySession(session);
    _loadData();
  }

  String get _timerDisplay {
    final m = _secondsRemaining ~/ 60;
    final s = _secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlitzTheme.bg,
      appBar: AppBar(title: Text('Study', style: GoogleFonts.syne(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildStatsRow(),
                  const SizedBox(height: 16),
                  _buildPomodoroCard(),
                  const SizedBox(height: 16),
                  _buildRecentSessions(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: MetricCard(label: 'STREAK', value: '$_streak 🔥', icon: Icons.local_fire_department, color: BlitzTheme.gold)),
        const SizedBox(width: 8),
        Expanded(child: MetricCard(label: 'TODAY', value: '${_todayMinutes}m', icon: Icons.timer, color: BlitzTheme.green)),
      ],
    );
  }

  Widget _buildPomodoroCard() {
    return GlassContainer(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(24),
      borderColor: _isRunning ? BlitzTheme.accent.withValues(alpha: 0.3) : null,
      child: Column(
        children: [
          Text('POMODORO', style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Timer display
          Container(
            width: 180, height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _isRunning ? BlitzTheme.accent : BlitzTheme.border, width: 3),
              boxShadow: _isRunning ? [BoxShadow(color: BlitzTheme.accent.withValues(alpha: 0.2), blurRadius: 30)] : null,
            ),
            child: Center(
              child: Text(
                _isRunning ? _timerDisplay : '$_pomodoroMinutes:00',
                style: GoogleFonts.spaceMono(fontSize: 40, fontWeight: FontWeight.w700, color: BlitzTheme.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Duration selector
          if (!_isRunning) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [15, 25, 45, 60].map((d) {
                final sel = _pomodoroMinutes == d;
                return GestureDetector(
                  onTap: () => setState(() => _pomodoroMinutes = d),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: sel ? BlitzTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
                      border: Border.all(color: sel ? BlitzTheme.accent : BlitzTheme.border),
                    ),
                    child: Text('${d}m', style: GoogleFonts.spaceMono(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? BlitzTheme.accent : BlitzTheme.textMuted)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Subject selector
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _subjects.map((s) {
                final sel = _currentSubject == s;
                return GestureDetector(
                  onTap: () => setState(() => _currentSubject = s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: sel ? BlitzTheme.green.withValues(alpha: 0.12) : Colors.transparent,
                      border: Border.all(color: sel ? BlitzTheme.green : BlitzTheme.border),
                    ),
                    child: Text(s, style: GoogleFonts.syne(fontSize: 12, color: sel ? BlitzTheme.green : BlitzTheme.textMuted, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isRunning ? _stopPomodoro : _startPomodoro,
              style: ElevatedButton.styleFrom(backgroundColor: _isRunning ? BlitzTheme.red : BlitzTheme.accent),
              child: Text(_isRunning ? 'Stop' : 'Start Focus', style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSessions() {
    if (_recentSessions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'RECENT SESSIONS', icon: Icons.history_rounded, color: BlitzTheme.accent),
        ..._recentSessions.take(10).map((s) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white.withValues(alpha: 0.03), border: Border.all(color: BlitzTheme.border)),
          child: Row(
            children: [
              const Icon(Icons.book_rounded, size: 16, color: BlitzTheme.green),
              const SizedBox(width: 10),
              Expanded(child: Text(s.subject, style: GoogleFonts.syne(fontSize: 13, color: BlitzTheme.textPrimary, fontWeight: FontWeight.w600))),
              Text('${s.durationMinutes}m', style: GoogleFonts.spaceMono(fontSize: 11, color: BlitzTheme.textMuted, fontWeight: FontWeight.w700)),
            ],
          ),
        )),
      ],
    );
  }
}
