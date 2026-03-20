import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'voice_engine.dart';
import 'voice_state.dart';

/// ═══════════════════════════════════════════════════════════════
///  ZEN VOICE MODE SCREEN
///  Full-screen immersive takeover — Zen-style device control.
///  Entered intentionally by the user, never ambient.
///
///  Features:
///   • Animated orb that pulses / oscillates with voice state
///   • Real-time waveform bars
///   • Live transcript + streaming response display
///   • Quick-action device commands (volume, brightness, media)
///   • Demo mode toggle (fully testable offline)
///   • Debug log panel (slide up from bottom)
///   • Keyboard input fallback (tap → type if voice unavailable)
/// ═══════════════════════════════════════════════════════════════
class VoiceModeScreen extends StatefulWidget {
  const VoiceModeScreen({super.key});

  static Route<void> route() => PageRouteBuilder(
    pageBuilder: (_, a1, a2) => const VoiceModeScreen(),
    transitionsBuilder: (_, a1, a2, child) => FadeTransition(
      opacity: a1,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a1), child: child),
    ),
    transitionDuration: const Duration(milliseconds: 280),
  );

  @override
  State<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends State<VoiceModeScreen>
    with TickerProviderStateMixin {

  final _engine = VoiceEngine();

  // ── Animation controllers ──
  late AnimationController _orbCtrl;         // orb pulse loop
  late AnimationController _ringCtrl;        // outer ring on listen
  late AnimationController _entryCtrl;       // entrance animation

  // ── State mirrors ──
  VoiceState  _state       = VoiceState.idle;
  String      _transcript  = '';
  String      _response    = '';
  List<double> _wave       = List.filled(32, 0.0);
  bool        _showDebug   = false;
  bool        _showInput   = false;
  List<String> _log        = [];
  final _inputCtrl         = TextEditingController();
  final _scrollCtrl        = ScrollController();

  // ── Stream subs ──
  final List<StreamSubscription> _subs = [];

  // ── Design tokens ──
  static const Color _bg      = Color(0xFF000000);
  static const Color _orange  = Color(0xFFFF4500);
  static const Color _text    = Color(0xFFF0EDE8);
  static const Color _muted   = Color(0xFF444444);
  static const Color _border  = Color(0xFF1A1A1A);
  static const Color _surface = Color(0xFF0A0A0A);

  @override
  void initState() {
    super.initState();

    // ── Animation setup ──
    _orbCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);

    _ringCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();

    _entryCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();

    // Mirror engine state
    _state    = _engine.currentState;
    _subs.add(_engine.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      if (s == VoiceState.listening) {
        _ringCtrl.repeat();
      } else {
        _ringCtrl.stop();
      }
    }));

    _subs.add(_engine.transcriptStream.listen((t) {
      if (!mounted) return;
      setState(() { _transcript = t; _response = ''; });
    }));

    _subs.add(_engine.responseStream.listen((r) {
      if (!mounted) return;
      setState(() => _response = r);
      // Auto-scroll
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }));

    _subs.add(_engine.waveformStream.listen((w) {
      if (!mounted) return;
      setState(() => _wave = w);
    }));

    _subs.add(_engine.logStream.listen((l) {
      if (!mounted) return;
      setState(() => _log = l);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _orbCtrl.dispose();
    _ringCtrl.dispose();
    _entryCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: FadeTransition(
            opacity: _entryCtrl,
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        _buildOrb(),
                        const SizedBox(height: 20),
                        _buildStateLabel(),
                        const SizedBox(height: 32),
                        _buildWaveform(),
                        const SizedBox(height: 28),
                        if (_transcript.isNotEmpty) _buildTranscriptCard(),
                        if (_response.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildResponseCard(),
                        ],
                        const SizedBox(height: 24),
                        _buildQuickCommands(),
                        const SizedBox(height: 16),
                        if (_showInput) _buildKeyboardInput(),
                        if (_showDebug) ...[
                          const SizedBox(height: 16),
                          _buildDebugLog(),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Top bar  ×  DEMO mode toggle
  // ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _muted),
        ),
        const SizedBox(width: 12),
        Text('VOICE MODE', style: GoogleFonts.ibmPlexMono(
          fontSize: 11, color: _orange, letterSpacing: 3, fontWeight: FontWeight.w600,
        )),
        const Spacer(),
        // Demo mode toggle
        GestureDetector(
          onTap: () {
            setState(() => _engine.setDemoMode(!_engine.demoMode));
            HapticFeedback.selectionClick();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: _engine.demoMode ? _orange.withValues(alpha: 0.15) : Colors.transparent,
              border: Border.all(
                color: _engine.demoMode ? _orange : _border,
                width: _engine.demoMode ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.science_outlined, size: 11,
                  color: _engine.demoMode ? _orange : _muted),
                const SizedBox(width: 4),
                Text(
                  _engine.demoMode ? 'DEMO ON' : 'DEMO',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    color: _engine.demoMode ? _orange : _muted,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Debug log toggle
        GestureDetector(
          onTap: () => setState(() => _showDebug = !_showDebug),
          child: Icon(
            Icons.terminal_rounded, size: 18,
            color: _showDebug ? _orange : _muted,
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Animated orb
  // ─────────────────────────────────────────────────────────────
  Widget _buildOrb() {
    final listening  = _state == VoiceState.listening;
    final processing = _state == VoiceState.processing;
    final speaking   = _state == VoiceState.speaking;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        if (_state == VoiceState.listening) {
          _engine.stopListening();
        } else if (_state == VoiceState.idle || _state == VoiceState.error) {
          _engine.startListening();
        }
      },
      child: SizedBox(
        width: 160,
        height: 160,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing ring — only when listening
            if (listening)
              AnimatedBuilder(
                animation: _ringCtrl,
                builder: (_, __) {
                  final r = _ringCtrl.value;
                  return Container(
                    width: 140 + r * 30,
                    height: 140 + r * 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _orange.withValues(alpha: (1 - r) * 0.4),
                        width: 1.5,
                      ),
                    ),
                  );
                },
              ),

            // Main orb
            AnimatedBuilder(
              animation: _orbCtrl,
              builder: (_, __) {
                final pulse = listening
                    ? 0.1 + _orbCtrl.value * 0.2
                    : processing
                        ? 0.15 + _orbCtrl.value * 0.1
                        : speaking
                            ? 0.08 + _orbCtrl.value * 0.08
                            : 0.0;

                final size = 100.0 + pulse * 30;

                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _bg,
                    border: Border.all(
                      color: listening  ? _orange
                           : processing ? const Color(0xFFFF8C00)
                           : speaking   ? const Color(0xFF00C86A)
                           : _border,
                      width: listening ? 2.0 : 1.5,
                    ),
                    boxShadow: listening ? [
                      BoxShadow(color: _orange.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 4),
                      BoxShadow(color: _orange.withValues(alpha: 0.12), blurRadius: 80),
                    ] : processing ? [
                      BoxShadow(color: const Color(0xFFFF8C00).withValues(alpha: 0.25), blurRadius: 30),
                    ] : speaking ? [
                      BoxShadow(color: const Color(0xFF00C86A).withValues(alpha: 0.25), blurRadius: 30),
                    ] : [],
                  ),
                  child: Center(
                    child: Icon(
                      listening  ? Icons.mic_rounded
                                 : processing ? Icons.psychology_rounded
                                 : speaking   ? Icons.volume_up_rounded
                                 : Icons.mic_none_rounded,
                      size: 32,
                      color: listening  ? _orange
                           : processing ? const Color(0xFFFF8C00)
                           : speaking   ? const Color(0xFF00C86A)
                           : _muted,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  State label below orb
  // ─────────────────────────────────────────────────────────────
  Widget _buildStateLabel() {
    final label = switch (_state) {
      VoiceState.idle       => 'TAP TO SPEAK',
      VoiceState.listening  => 'LISTENING...',
      VoiceState.processing => 'THINKING...',
      VoiceState.speaking   => 'SPEAKING...',
      VoiceState.error      => 'TRY AGAIN',
    };
    final color = switch (_state) {
      VoiceState.listening  => _orange,
      VoiceState.processing => const Color(0xFFFF8C00),
      VoiceState.speaking   => const Color(0xFF00C86A),
      VoiceState.error      => const Color(0xFFFF3B30),
      _                     => _muted,
    };

    return Column(
      children: [
        Text(label, style: GoogleFonts.ibmPlexMono(
          fontSize: 11, color: color, letterSpacing: 3,
        )),
        if (_engine.demoMode) ...[
          const SizedBox(height: 4),
          Text('DEMO MODE — no backend needed',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 9, color: _orange.withValues(alpha: 0.5), letterSpacing: 1,
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Waveform
  // ─────────────────────────────────────────────────────────────
  Widget _buildWaveform() {
    return SizedBox(
      height: 48,
      child: CustomPaint(
        painter: _WavePainter(
          samples: _wave,
          color: switch (_state) {
            VoiceState.listening  => _orange,
            VoiceState.processing => const Color(0xFFFF8C00),
            VoiceState.speaking   => const Color(0xFF00C86A),
            _                     => _border,
          },
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Transcript card
  // ─────────────────────────────────────────────────────────────
  Widget _buildTranscriptCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _orange.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOU', style: GoogleFonts.ibmPlexMono(
            fontSize: 9, color: _orange.withValues(alpha: 0.7), letterSpacing: 2,
          )),
          const SizedBox(height: 8),
          Text(_transcript, style: GoogleFonts.ibmPlexMono(
            fontSize: 13, color: _text, height: 1.5,
          )),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Response card (streams in word by word)
  // ─────────────────────────────────────────────────────────────
  Widget _buildResponseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('ZEN', style: GoogleFonts.ibmPlexMono(
              fontSize: 9, color: _muted, letterSpacing: 2,
            )),
            const Spacer(),
            // Copy button
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _response));
                HapticFeedback.selectionClick();
              },
              child: const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF333333)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(_response, style: GoogleFonts.ibmPlexMono(
            fontSize: 13, color: _text, height: 1.55,
          )),
          if (_state == VoiceState.processing) ...[
            const SizedBox(height: 8),
            _blinkingCursor(),
          ],
        ],
      ),
    );
  }

  Widget _blinkingCursor() {
    return AnimatedBuilder(
      animation: _orbCtrl,
      builder: (_, __) => Opacity(
        opacity: _orbCtrl.value > 0.5 ? 1.0 : 0.0,
        child: Container(
          width: 7, height: 14,
          color: _orange,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Quick commands  (device control shortcuts)
  // ─────────────────────────────────────────────────────────────
  Widget _buildQuickCommands() {
    final cmds = [
      const _Cmd('Vol +',   Icons.volume_up_rounded,        'volume up'),
      const _Cmd('Vol −',   Icons.volume_down_rounded,       'volume down'),
      const _Cmd('Pause',   Icons.pause_circle_outline,      'pause music'),
      const _Cmd('Next',    Icons.skip_next_rounded,         'next track'),
      const _Cmd('Search',  Icons.search_rounded,            'search '),
      const _Cmd('Task',    Icons.add_task_rounded,          'create task '),
      const _Cmd('Remind',  Icons.alarm_rounded,             'set a reminder '),
      const _Cmd('Screen',  Icons.screenshot_monitor_rounded,'take a screenshot'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUICK COMMANDS',
          style: GoogleFonts.ibmPlexMono(fontSize: 9, color: _muted, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cmds.map((c) => _quickChip(c)).toList(),
        ),
      ],
    );
  }

  Widget _quickChip(_Cmd cmd) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _engine.submitText(cmd.text);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(cmd.icon, size: 13, color: _muted),
            const SizedBox(width: 6),
            Text(cmd.label, style: GoogleFonts.ibmPlexMono(
              fontSize: 10, color: _text.withValues(alpha: 0.7), letterSpacing: 0.5,
            )),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Keyboard input fallback
  // ─────────────────────────────────────────────────────────────
  Widget _buildKeyboardInput() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _orange.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _inputCtrl,
            autofocus: true,
            style: GoogleFonts.ibmPlexMono(fontSize: 12, color: _text),
            decoration: InputDecoration(
              hintText: 'type a command...',
              hintStyle: GoogleFonts.ibmPlexMono(fontSize: 12, color: _muted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                _engine.submitText(v.trim());
                _inputCtrl.clear();
              }
            },
          ),
        ),
        GestureDetector(
          onTap: () {
            final v = _inputCtrl.text.trim();
            if (v.isNotEmpty) {
              _engine.submitText(v);
              _inputCtrl.clear();
            }
          },
          child: const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.send_rounded, size: 18, color: _orange),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Debug log panel
  // ─────────────────────────────────────────────────────────────
  Widget _buildDebugLog() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(children: [
              Text('DEBUG LOG', style: GoogleFonts.ibmPlexMono(
                fontSize: 9, color: _muted, letterSpacing: 2,
              )),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showDebug = false),
                child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF333333)),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _log.length,
              itemBuilder: (_, i) => Text(
                _log[i],
                style: GoogleFonts.ibmPlexMono(fontSize: 9, color: const Color(0xFF555555)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Bottom bar — mic button + controls
  // ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final listening = _state == VoiceState.listening;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(children: [
        // Keyboard input toggle
        _iconBtn(
          icon: _showInput ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded,
          active: _showInput,
          onTap: () => setState(() => _showInput = !_showInput),
        ),
        const SizedBox(width: 12),
        // Wake word toggle
        _iconBtn(
          icon: _engine.wakeWordEnabled ? Icons.hearing_rounded : Icons.hearing_disabled_rounded,
          active: _engine.wakeWordEnabled,
          onTap: () { setState(() => _engine.toggleWakeWord()); HapticFeedback.selectionClick(); },
          label: _engine.wakeWordEnabled ? 'WAKE ON' : 'WAKE',
        ),
        const Spacer(),

        // ── Main mic button ──────────────────────────
        GestureDetector(
          onTap: () {
            HapticFeedback.heavyImpact();
            if (listening) {
              _engine.stopListening();
            } else if (_state == VoiceState.idle || _state == VoiceState.error) {
              _engine.startListening();
            }
          },
          onLongPressStart: (_) {
            HapticFeedback.heavyImpact();
            _engine.startListening();
          },
          onLongPressEnd: (_) => _engine.stopListening(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: listening ? 72 : 64,
            height: listening ? 72 : 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: listening ? _orange : _surface,
              border: Border.all(
                color: listening ? _orange : _border,
                width: listening ? 0 : 1.5,
              ),
              boxShadow: listening ? [
                BoxShadow(color: _orange.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 2),
              ] : [],
            ),
            child: Icon(
              listening ? Icons.stop_rounded : Icons.mic_rounded,
              size: listening ? 28 : 24,
              color: listening ? Colors.black : _muted,
            ),
          ),
        ),

        const Spacer(),
        // Speaker toggle
        _iconBtn(
          icon: _engine.speakEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          active: _engine.speakEnabled,
          onTap: () { setState(() => _engine.setSpeakEnabled(!_engine.speakEnabled)); HapticFeedback.selectionClick(); },
        ),
        const SizedBox(width: 12),
        // Settings / help
        _iconBtn(
          icon: Icons.info_outline_rounded,
          onTap: () => _showHelpSheet(),
        ),
      ]),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    bool active = false,
    required VoidCallback onTap,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: active ? _orange.withValues(alpha: 0.12) : Colors.transparent,
              border: Border.all(color: active ? _orange.withValues(alpha: 0.4) : _border),
            ),
            child: Icon(icon, size: 18, color: active ? _orange : _muted),
          ),
          if (label != null) ...[
            const SizedBox(height: 3),
            Text(label, style: GoogleFonts.ibmPlexMono(
              fontSize: 7, color: active ? _orange : _muted, letterSpacing: 0.5,
            )),
          ],
        ],
      ),
    );
  }

  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF050505),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VOICE MODE', style: GoogleFonts.ibmPlexMono(
              fontSize: 11, color: _orange, letterSpacing: 3,
            )),
            const SizedBox(height: 16),
            ...[
              ['Tap orb / mic button', 'Start/stop listening'],
              ['Hold mic button',      'Push-to-talk (hold)'],
              ['DEMO toggle',          'Test without any backend'],
              ['⌨ button',             'Type instead of speaking'],
              ['Quick commands',       'Tap to send preset text'],
              ['WAKE toggle',          'Always-on "Hey Zen"'],
              ['🔊 button',            'Toggle voice playback'],
              ['⌘ button',            'Show debug log'],
            ].map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(width: 160,
                  child: Text(r[0], style: GoogleFonts.ibmPlexMono(
                    fontSize: 10, color: _text,
                  )),
                ),
                Text(r[1], style: GoogleFonts.ibmPlexMono(
                  fontSize: 10, color: _muted,
                )),
              ]),
            )).toList(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Data class for quick commands ─────────────────────────────────────────
class _Cmd {
  final String label;
  final IconData icon;
  final String text;
  const _Cmd(this.label, this.icon, this.text);
}

// ── Waveform painter ──────────────────────────────────────────────────────
class _WavePainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  const _WavePainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = color;

    final barW = (size.width / samples.length) * 0.55;
    for (int i = 0; i < samples.length; i++) {
      final x = (i + 0.5) * size.width / samples.length;
      final h = math.max(2.0, samples[i] * size.height);
      final top = (size.height - h) / 2;
      paint.strokeWidth = barW;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.samples != samples || old.color != color;
}
