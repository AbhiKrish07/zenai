import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../core/database.dart';
import '../../models/study_session.dart';
import '../../services/spotify_service.dart';
import '../../voice/voice_engine.dart';
import '../../voice/voice_state.dart';
import '../../services/focus_service.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// FocusModeScreen — Zen Focus Engine
/// Blocks social media, plays Spotify, enters Ambient Mode
/// ─────────────────────────────────────────────────────────────────────────────
class FocusModeScreen extends StatefulWidget {
  const FocusModeScreen({super.key});
  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen>
    with TickerProviderStateMixin {
  // ── Platform channels ──────────────────────────────────────────────
  static const _focusChannel = MethodChannel('com.zen/focus');

  // ── DB & Spotify ───────────────────────────────────────────────────
  final _db = ZenDatabase();
  final _spotify = SpotifyService();

  final _focusService = FocusService();
  final _customMinutesController = TextEditingController();
  StreamSubscription? _focusSub;
  StreamSubscription? _completeSub;

  // UI state for drafting session (before start)
  int _selectedMinutes = 25;
  String _subject = 'Deep Work';
  bool _sessionComplete = false;

  // Active state read from persistent service
  bool get _isRunning => _focusService.isRunning;
  int get _secondsRemaining => _focusService.secondsRemaining;
  
  // ── Stats state ────────────────────────────────────────────────────
  int _totalFocusedMins = 0;
  int _sessionsCount = 0;
  List<String> _productivityTips = [];

  // ── Permissions & State ────────────────────────────────────────────
  bool _hasAccessibility = false;
  bool _hasOverlay = false;
  bool _blockedAppDetected = false;
  String? _blockedPackage;

  // ── Animations ─────────────────────────────────────────────────────
  late AnimationController _ringAnim;
  late AnimationController _pulseAnim;
  late AnimationController _shieldAnim;

  // ── Spotify mini state ─────────────────────────────────────────────
  Map<String, dynamic>? _track;
  Timer? _spotifyTimer;

  // Social media package → friendly name map
  final _socialNames = {
    'com.instagram.android': 'Instagram',
    'com.twitter.android': 'X (Twitter)',
    'com.zhiliaoapp.musically': 'TikTok',
    'com.facebook.katana': 'Facebook',
    'com.snapchat.android': 'Snapchat',
    'com.reddit.frontpage': 'Reddit',
    'com.linkedin.android': 'LinkedIn',
    'com.pinterest': 'Pinterest',
    'com.whatsapp': 'WhatsApp',
    'org.telegram.messenger': 'Telegram',
    'com.discord': 'Discord',
  };

  final List<String> _subjects = [
    'Deep Work', 'CS', 'Math', 'Physics', 'Design', 'Reading', 'Writing'
  ];

  @override
  void initState() {
    super.initState();
    _focusChannel.setMethodCallHandler((call) async {
      if (call.method == 'onBlockedAppDetected') {
        final pkg = call.arguments as String?;
        if (pkg != null) _onBlockedAppDetected(pkg);
      }
    });
    _checkPermissions();
    _initAnimations();
    _loadSpotify();
    _loadStats();
    _generateTips();
    _focusSub = _focusService.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
    _completeSub = _focusService.onComplete.listen((_) {
      if (mounted) _onSessionComplete();
    });
  }

  Future<void> _loadStats() async {
    final sessions = await _db.getStudySessions();
    int total = 0;
    for (var s in sessions) {
      total += s.durationMinutes;
    }
    if (mounted) {
      setState(() {
        _totalFocusedMins = total;
        _sessionsCount = sessions.length;
      });
    }
  }

  void _generateTips() {
    final tips = [
      "Try the 5-minute rule: commit to just 5 minutes of work to overcome procrastination.",
      "Clear your physical desk to clear your mental focus.",
      "Identify your 'One Big Thing' for this session before you start.",
      "Deep work depends on minimizing 'context switching' between apps.",
      "Longer sessions (90m+) are great for flow, but take a 15m break after.",
    ];
    tips.shuffle();
    setState(() => _productivityTips = tips.take(3).toList());
  }

  void _initAnimations() {
    _ringAnim = AnimationController(vsync: this, duration: const Duration(seconds: 60));
    _pulseAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _shieldAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  }

  @override
  void dispose() {
    _focusSub?.cancel();
    _completeSub?.cancel();
    _spotifyTimer?.cancel();
    _ringAnim.dispose();
    _pulseAnim.dispose();
    _shieldAnim.dispose();
    super.dispose();
  }

  // ── Permissions ────────────────────────────────────────────────────
  Future<void> _checkPermissions() async {
    try {
      final hasA = await _focusChannel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
      final hasO = await _focusChannel.invokeMethod<bool>('hasOverlayPermission') ?? false;
      if (mounted) {
        setState(() {
        _hasAccessibility = hasA;
        _hasOverlay = hasO;
      });
      }
    } catch (_) {}
  }

  // ── Spotify ────────────────────────────────────────────────────────
  Future<void> _loadSpotify() async {
    _spotifyTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final track = await _spotify.getCurrentTrack();
      if (mounted) setState(() => _track = track);
    });
  }

  Future<void> _openSpotify() async {
    try {
      await _focusChannel.invokeMethod('openSpotify');
    } catch (_) {}
  }

  // ── Focus Timer ────────────────────────────────────────────────────
  void _startFocus() {
    HapticFeedback.heavyImpact();
    _focusService.startFocus(_selectedMinutes, _subject);
    _focusChannel.invokeMethod('openSpotify');
    _ringAnim.forward(from: 0);
  }

  void _stopFocus() {
     _focusService.stopFocus();
     _ringAnim.stop();
  }

  void _onBlockedAppDetected(String pkg) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _blockedAppDetected = true;
      _blockedPackage = pkg;
    });
    _shieldAnim.forward(from: 0);

    // Bring app to foreground + show alert notification
    SystemNavigator.pop(); // This won't help; we bring Zen back via overlay
  }

  void _onSessionComplete() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _saveSession();
    _focusService.stopFocus();
    setState(() {
      _sessionComplete = true;
      _blockedAppDetected = false;
    });
  }

  Future<void> _saveSession({int? minutes}) async {
    final m = minutes ?? _selectedMinutes;
    if (m < 1) return;
    await _db.insertStudySession(
      StudySession(subject: _subject, durationMinutes: m),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────
  String get _timerDisplay {
    final m = _secondsRemaining ~/ 60;
    final s = _secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress {
    if (_selectedMinutes == 0) return 0;
    return 1.0 - (_secondsRemaining / (_selectedMinutes * 60));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Dark gradient bg ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF04050E), Color(0xFF0A0C22), Color(0xFF050B18)],
              ),
            ),
          ),

          // ── Ambient radial glow ──
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Positioned(
              top: -100,
              left: MediaQuery.of(context).size.width / 2 - 200,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    (_isRunning ? const Color(0xFF6E8CFF) : BlitzTheme.cyan)
                        .withValues(alpha: 0.07 + _pulseAnim.value * 0.04),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        if (!_hasAccessibility || !_hasOverlay) _buildPermissionBanners(),
                        if (_blockedAppDetected) _buildBlockAlert() else const SizedBox.shrink(),
                        if (_sessionComplete) _buildCompleteBanner() else const SizedBox.shrink(),
                        const SizedBox(height: 8),
                        _buildTimerRing(),
                        const SizedBox(height: 24),
                        if (!_isRunning) _buildSetupPanel(),
                        if (_isRunning) _buildStatusChips(),
                        const SizedBox(height: 20),
                        _buildSpotifyMini(),
                        const SizedBox(height: 24),
                        _buildStatsAndTips(),
                        const SizedBox(height: 24),
                        _buildBlockedAppslist(),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
                _buildActionButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: BlitzTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Text('FOCUS ENGINE', style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w800, color: BlitzTheme.textPrimary, letterSpacing: 2)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: _isRunning ? BlitzTheme.green.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: _isRunning ? BlitzTheme.green : BlitzTheme.border),
            ),
            child: Text(
              _isRunning ? '● ACTIVE' : '○ IDLE',
              style: GoogleFonts.spaceMono(fontSize: 9, color: _isRunning ? BlitzTheme.green : BlitzTheme.textMuted, letterSpacing: 1, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerRing() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => SizedBox(
        width: 240,
        height: 240,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow ring
            CustomPaint(
              size: const Size(240, 240),
              painter: _FocusRingPainter(
                progress: _progress,
                color: _isRunning ? const Color(0xFF6E8CFF) : BlitzTheme.cyan,
                pulse: _pulseAnim.value,
                isRunning: _isRunning,
              ),
            ),
            // Inner content
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isRunning ? _timerDisplay : '$_selectedMinutes:00',
                  style: GoogleFonts.spaceMono(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: BlitzTheme.textPrimary,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isRunning ? _subject.toUpperCase() : 'SELECT DURATION',
                  style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted, letterSpacing: 2),
                ),
                if (_isRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(Icons.shield_rounded, size: 20, color: BlitzTheme.accent.withValues(alpha: 0.7)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupPanel() {
    return Column(
      children: [
        // Duration chips
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [15, 25, 45, 60].map((d) {
            final sel = _selectedMinutes == d;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedMinutes = d);
                _customMinutesController.clear();
              },
              onTapDown: (_) => HapticFeedback.selectionClick(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
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
        const SizedBox(height: 14),
        // Custom minutes input
        SizedBox(
          width: 200,
          child: TextField(
            controller: _customMinutesController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceMono(color: Colors.white, fontSize: 13),
            onChanged: (val) {
              final m = int.tryParse(val);
              if (m != null && m > 0) {
                 setState(() => _selectedMinutes = m);
              }
            },
            decoration: InputDecoration(
              hintText: 'Custom mins...',
              hintStyle: GoogleFonts.spaceMono(color: Colors.white24, fontSize: 11),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: BlitzTheme.border)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: BlitzTheme.accent)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Subject chips
        Wrap(
          spacing: 6, runSpacing: 6,
          alignment: WrapAlignment.center,
          children: _subjects.map((s) {
            final sel = _subject == s;
            return GestureDetector(
              onTap: () => setState(() => _subject = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: sel ? BlitzTheme.cyan.withValues(alpha: 0.12) : Colors.transparent,
                  border: Border.all(color: sel ? BlitzTheme.cyan : BlitzTheme.border),
                ),
                child: Text(s, style: GoogleFonts.syne(fontSize: 11, color: sel ? BlitzTheme.cyan : BlitzTheme.textMuted, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStatusChips() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chip(Icons.shield_rounded, 'Apps Blocked', BlitzTheme.accent),
        const SizedBox(width: 10),
        _chip(Icons.music_note_rounded, 'Spotify Active', BlitzTheme.green),
      ],
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.syne(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildBlockAlert() {
    final appName = _socialNames[_blockedPackage] ?? 'Social Media';
    return AnimatedBuilder(
      animation: _shieldAnim,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: BlitzTheme.red.withValues(alpha: 0.1),
          border: Border.all(color: BlitzTheme.red.withValues(alpha: 0.5 + _shieldAnim.value * 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.block_rounded, color: BlitzTheme.red, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⛔ $appName Blocked!', style: GoogleFonts.syne(fontSize: 14, fontWeight: FontWeight.w700, color: BlitzTheme.red)),
                  Text('You are in Focus Mode. Get back to work.', style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompleteBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [
          BlitzTheme.green.withValues(alpha: 0.15),
          BlitzTheme.cyan.withValues(alpha: 0.1),
        ]),
        border: Border.all(color: BlitzTheme.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session Complete!', style: GoogleFonts.syne(fontSize: 14, fontWeight: FontWeight.w700, color: BlitzTheme.green)),
                Text('$_selectedMinutes mins of $_subject locked in. Apps unlocked! 🔓', style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotifyMini() {
    return GestureDetector(
      onTap: _openSpotify,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF1DB954).withValues(alpha: 0.08),
          border: Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF1DB954).withValues(alpha: 0.2),
              ),
              child: const Icon(Icons.music_note_rounded, color: Color(0xFF1DB954), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _track != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_track!['title'] ?? '', style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700, color: BlitzTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(_track!['artist'] ?? '', style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  )
                : Text('Tap to open Spotify →', style: GoogleFonts.syne(fontSize: 13, color: const Color(0xFF1DB954), fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF1DB954)),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionBanners() {
    return Column(
      children: [
        if (!_hasAccessibility)
          GestureDetector(
            onTap: () async {
              await _focusChannel.invokeMethod('requestAccessibilityPermission');
              await Future.delayed(const Duration(seconds: 2));
              if (context.mounted) _checkPermissions();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: BlitzTheme.red.withValues(alpha: 0.06),
                border: Border.all(color: BlitzTheme.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.accessibility_new_rounded, color: BlitzTheme.red, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Enable Accessibility Service', style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.w700, color: BlitzTheme.red)),
                      Text('Required for real app blocking. Tap → find "Zen" under Installed apps → toggle ON.', style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted)),
                    ],
                  )),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: BlitzTheme.red),
                ],
              ),
            ),
          ),
        if (!_hasOverlay)
          GestureDetector(
            onTap: () async {
              await _focusChannel.invokeMethod('requestOverlayPermission');
              await Future.delayed(const Duration(seconds: 2));
              if (context.mounted) _checkPermissions();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: BlitzTheme.gold.withValues(alpha: 0.06),
                border: Border.all(color: BlitzTheme.gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers_rounded, color: BlitzTheme.gold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Allow Display Over Other Apps', style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.w700, color: BlitzTheme.gold)),
                      Text('Needed to show the block screen on top of social apps. Tap to grant.', style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted)),
                    ],
                  )),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: BlitzTheme.gold),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsAndTips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _statItem('SESSIONS', '$_sessionsCount', Icons.bolt_rounded),
            _statItem('FOCUS TIME', '${_totalFocusedMins}m', Icons.timer_outlined),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.tips_and_updates_rounded, size: 14, color: BlitzTheme.gold),
            const SizedBox(width: 6),
            Text('HOW TO IMPROVE', style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        ..._productivityTips.map((tip) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•', style: GoogleFonts.syne(color: BlitzTheme.gold, fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(child: Text(tip, style: GoogleFonts.syne(fontSize: 11, color: Colors.white.withValues(alpha: 0.7), height: 1.4))),
            ],
          ),
        )),
      ],
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Container(
      width: (MediaQuery.of(context).size.width - 60) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: BlitzTheme.accent),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.spaceMono(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          Text(label, style: GoogleFonts.spaceMono(fontSize: 8, color: Colors.white38, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildBlockedAppslist() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_rounded, size: 14, color: BlitzTheme.accent),
                const SizedBox(width: 6),
                Text('BLOCKED APPS', style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              ],
            ),
            if (!_isRunning)
              GestureDetector(
                onTap: _addBlockedAppDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(border: Border.all(color: BlitzTheme.accent.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                  child: Text('+ ADD PKG', style: GoogleFonts.spaceMono(fontSize: 8, color: BlitzTheme.accent, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _socialNames.entries.map((entry) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: _isRunning ? BlitzTheme.red.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.03),
              border: Border.all(color: _isRunning ? BlitzTheme.red.withValues(alpha: 0.3) : BlitzTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded, size: 10, color: _isRunning ? BlitzTheme.red : BlitzTheme.textMuted),
                const SizedBox(width: 4),
                Text(entry.value, style: GoogleFonts.spaceMono(fontSize: 10, color: _isRunning ? BlitzTheme.red : BlitzTheme.textMuted)),
                if (!_isRunning) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _socialNames.remove(entry.key)),
                    child: const Icon(Icons.close_rounded, size: 12, color: Colors.white24),
                  ),
                ],
              ],
            ),
          )).toList(),
        ),
      ],
    );
  }

  void _addBlockedAppDialog() async {
    final List<dynamic>? apps = await _focusChannel.invokeMethod('getInstalledApps');
    if (apps == null || !mounted) return;
    if (!context.mounted) return;

    final List<Map<String, String>> appList = apps.map((a) => {
      'name': a['name'].toString(),
      'package': a['package'].toString(),
    }).toList();

    showDialog(
      context: context,
      builder: (c) => _AppSelectionDialog(apps: appList),
    ).then((selected) {
      if (selected != null && mounted) {
        setState(() {
          _socialNames[selected['package']] = selected['name'];
        });
      }
    });
  }

  Widget _buildActionButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: const Border(top: BorderSide(color: BlitzTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_isRunning)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                    Navigator.push(context, PageRouteBuilder(
                      pageBuilder: (_, __, ___) => _FocusAmbientOverlay(
                        minutes: _selectedMinutes,
                        onEnd: _stopFocus,
                      ),
                      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
                      transitionDuration: const Duration(milliseconds: 800),
                    ));
                      },
                      icon: const Icon(Icons.bedtime_rounded, size: 18, color: BlitzTheme.cyan),
                      label: Text('Ambient', style: GoogleFonts.syne(color: BlitzTheme.cyan, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: BlitzTheme.cyan.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _stopFocus,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: Text('End Session', style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BlitzTheme.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startFocus,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text('Activate Focus Mode', style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BlitzTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    shadowColor: BlitzTheme.accent.withValues(alpha: 0.5),
                    elevation: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Focus Ring Painter — arc progress ring
// ─────────────────────────────────────────────────────────────────────────────
class _FocusRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double pulse;
  final bool isRunning;

  _FocusRingPainter({required this.progress, required this.color, required this.pulse, required this.isRunning});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeW = 4.0;

    // Track
    canvas.drawCircle(center, radius, Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW);

    // Progress arc
    if (isRunning) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 2 * progress - math.pi / 2,
          colors: [color.withValues(alpha: 0.5), color],
          stops: const [0.0, 1.0],
          tileMode: TileMode.clamp,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW + 2
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint,
      );

      // Glow dot at end
      final angle = -math.pi / 2 + math.pi * 2 * progress;
      final dotX = center.dx + radius * math.cos(angle);
      final dotY = center.dy + radius * math.sin(angle);
      canvas.drawCircle(
        Offset(dotX, dotY),
        6 + pulse * 3,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(Offset(dotX, dotY), 5, Paint()..color = Colors.white);
    } else {
      // Dashed idle ring
      canvas.drawCircle(center, radius, Paint()
        ..color = color.withValues(alpha: 0.15 + pulse * 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW);
    }
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// FocusAmbientOverlay — dark ambient screen shown during active focus sessions
// ─────────────────────────────────────────────────────────────────────────────
class _AppSelectionDialog extends StatefulWidget {
  final List<Map<String, String>> apps;
  const _AppSelectionDialog({required this.apps});
  @override
  State<_AppSelectionDialog> createState() => _AppSelectionDialogState();
}

class _AppSelectionDialogState extends State<_AppSelectionDialog> {
  late List<Map<String, String>> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.apps;
  }

  void _filter(String q) {
    setState(() {
      _filtered = widget.apps
          .where((a) => a['name']!.toLowerCase().contains(q.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BlitzTheme.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Select App to Block',
          style: GoogleFonts.syne(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _filter,
              style: GoogleFonts.syne(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search apps...',
                hintStyle: GoogleFonts.syne(color: Colors.white24, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final app = _filtered[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(app['name']!,
                        style: GoogleFonts.syne(color: Colors.white, fontSize: 14)),
                    subtitle: Text(app['package']!,
                        style: GoogleFonts.spaceMono(
                            color: Colors.white38, fontSize: 9)),
                    onTap: () => Navigator.pop(context, app),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.syne(color: Colors.white38))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FocusAmbientOverlay — dark ambient screen shown during active focus sessions
// Integrated with Zen Voice Chat (STT/TTS)
// ─────────────────────────────────────────────────────────────────────────────
class _FocusAmbientOverlay extends StatefulWidget {
  final int minutes;
  final VoidCallback onEnd;

  const _FocusAmbientOverlay({required this.minutes, required this.onEnd});

  @override
  State<_FocusAmbientOverlay> createState() => _FocusAmbientOverlayState();
}

class _FocusAmbientOverlayState extends State<_FocusAmbientOverlay>
    with TickerProviderStateMixin {
  late AnimationController _breathe;
  DateTime _now = DateTime.now();
  Timer? _clock;

  // Voice Engine Integration
  final _voice = VoiceEngine();
  VoiceState _vState = VoiceState.idle;
  String _transcript = "";
  String _response = "";
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    // Subscriptions
    _subs.add(_voice.stateStream.listen((s) => setState(() => _vState = s)));
    _subs.add(_voice.transcriptStream.listen((t) => setState(() => _transcript = t)));
    _subs.add(_voice.responseStream.listen((r) => setState(() => _response = r)));

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    for (var s in _subs) {
      s.cancel();
    }
    _breathe.dispose();
    _clock?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Ambient Backdrop
            AnimatedBuilder(
              animation: _breathe,
              builder: (_, __) => Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.3),
                    radius: 1.0 + _breathe.value * 0.2,
                    colors: [
                      const Color(0xFF0A0C22).withValues(alpha: 0.8 + _breathe.value * 0.2),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            ),

            // Time & Goal
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${widget.minutes}m FOCUS SESSION',
                    style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.accent.withValues(alpha: 0.5), letterSpacing: 4)),
                  const SizedBox(height: 12),
                  Text('$h:$m',
                    style: GoogleFonts.spaceMono(fontSize: 84, fontWeight: FontWeight.w100, color: Colors.white, letterSpacing: -4)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    child: Text('TAP TO RETURN',
                      style: GoogleFonts.spaceMono(fontSize: 9, color: Colors.white24, letterSpacing: 2)),
                  ),
                ],
              ),
            ),

            // Zen Ambient Chat Display
            if (_vState != VoiceState.idle || _transcript.isNotEmpty)
              Positioned(
                bottom: 140,
                left: 30,
                right: 30,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: BlitzTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_transcript.isNotEmpty)
                        Text('“$_transcript”',
                          style: GoogleFonts.syne(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, fontStyle: FontStyle.italic)),
                      if (_response.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(_response,
                          style: GoogleFonts.syne(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
                      ],
                      if (_vState == VoiceState.processing)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation(BlitzTheme.accent),
                            minHeight: 1,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // Bottom Controls
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Mic Button (ZEN CHAT)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      if (_vState == VoiceState.listening) {
                        _voice.stopListening();
                      } else {
                        _voice.startListening();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _vState == VoiceState.listening ? BlitzTheme.accent : Colors.white.withValues(alpha: 0.05),
                        border: Border.all(color: _vState == VoiceState.listening ? BlitzTheme.accent : Colors.white24),
                        boxShadow: _vState == VoiceState.listening ? [
                          BoxShadow(color: BlitzTheme.accent.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)
                        ] : [],
                      ),
                      child: Icon(
                        _vState == VoiceState.listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _vState == VoiceState.listening ? Colors.black : Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  // Exit Button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context);
                      widget.onEnd();
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white38, size: 24),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
