import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'voice_engine.dart';
import 'voice_state.dart';

/// Desktop always-on-top minimal bar.
/// Sits at the top of the screen (Windows/Mac/Web).
/// Collapses to a slim 36-px strip; expands on click or hotkey.
class DesktopVoiceBar extends StatefulWidget {
  final Widget child;
  const DesktopVoiceBar({super.key, required this.child});

  @override
  State<DesktopVoiceBar> createState() => _DesktopVoiceBarState();
}

class _DesktopVoiceBarState extends State<DesktopVoiceBar>
    with TickerProviderStateMixin {
  final _engine = VoiceEngine();
  bool _expanded = false;

  // Waveform
  final List<double> _wave = List.filled(48, 0.05);
  Timer? _waveTimer;
  final _rand = math.Random();

  static const Color _bg = Color(0xFF000000);
  static const Color _orange = Color(0xFFFF4500);
  static const Color _border = Color(0xFF1A1A1A);
  static const Color _text = Color(0xFFF0EDE8);
  static const Color _muted = Color(0xFF444444);
  static const double _barHeight = 40.0;
  static const double _expandedHeight = 140.0;

  @override
  void initState() {
    super.initState();
    _engine.stateStream.listen(_onState);
  }

  void _onState(VoiceState s) {
    if (!mounted) return;
    setState(() {});
    if (s == VoiceState.listening) {
      _startWave();
    } else {
      _stopWave();
    }
  }

  void _startWave() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 55), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _wave.length; i++) {
          final t = 0.05 + _rand.nextDouble() * 0.9;
          _wave[i] = _wave[i] * 0.55 + t * 0.45;
        }
      });
    });
  }

  void _stopWave() {
    _waveTimer?.cancel();
    Timer.periodic(const Duration(milliseconds: 35), (t) {
      if (!mounted) { t.cancel(); return; }
      bool done = true;
      setState(() {
        for (int i = 0; i < _wave.length; i++) {
          _wave[i] *= 0.75;
          if (_wave[i] > 0.01) done = false;
        }
      });
      if (done) t.cancel();
    });
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Always-on-top bar ──────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            height: _expanded ? _expandedHeight : _barHeight,
            decoration: BoxDecoration(
              color: _bg,
              border: Border(
                bottom: BorderSide(
                  color: _engine.currentState == VoiceState.listening
                      ? _orange.withValues(alpha: 0.6)
                      : _border,
                  width: _engine.currentState == VoiceState.listening ? 1.5 : 1,
                ),
              ),
            ),
            child: _expanded ? _buildExpandedBar() : _buildCollapsedBar(),
          ),
        ),
        // ── App content fills below ────────────────────────────────────
        Expanded(child: widget.child),
      ],
    );
  }

  // ── Collapsed bar (40 px) ──────────────────────────────────────────────
  Widget _buildCollapsedBar() {
    final state = _engine.currentState;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        // Status dot
        _dot(state),
        const SizedBox(width: 10),
        // Label
        Text(
          'ZEN',
          style: GoogleFonts.ibmPlexMono(
            fontSize: 10,
            color: _orange,
            letterSpacing: 3,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '/ ${state.displayLabel}',
          style: GoogleFonts.ibmPlexMono(
            fontSize: 9,
            color: _muted,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        // Waveform (mini) — shown when listening
        if (state == VoiceState.listening)
          SizedBox(
            width: 120,
            height: 22,
            child: CustomPaint(
              painter: _BarWavePainter(samples: _wave.sublist(0, 24), color: _orange),
            ),
          ),
        const SizedBox(width: 12),
        // Clipboard-aware context label
        Text(
          '⌘⇧Space',
          style: GoogleFonts.ibmPlexMono(fontSize: 9, color: _muted, letterSpacing: 0.5),
        ),
        const SizedBox(width: 12),
        // Mic toggle
        _micBtn(state, compact: true),
      ]),
    );
  }

  // ── Expanded bar (140 px) ──────────────────────────────────────────────
  Widget _buildExpandedBar() {
    final state = _engine.currentState;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _dot(state),
            const SizedBox(width: 8),
            Text(
              'ZEN  /  ${state.displayLabel}',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: _orange,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            _hintChip('⌘⇧Space  START/STOP'),
            const SizedBox(width: 8),
            _hintChip('ESC  DISMISS'),
            const SizedBox(width: 12),
            _micBtn(state, compact: false),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = false),
              child: const Icon(Icons.expand_less, size: 14, color: Color(0xFF444444)),
            ),
          ]),
          const SizedBox(height: 10),

          // Full oscilloscope waveform
          Expanded(
            child: CustomPaint(
              painter: _BarWavePainter(
                samples: _wave,
                color: state == VoiceState.listening ? _orange : _muted,
                strokeWidth: 1.2,
              ),
              child: Container(),
            ),
          ),

          // Transcript / response line
          if (_engine.lastTranscript.isNotEmpty || _engine.lastResponse.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _engine.lastTranscript.isNotEmpty
                    ? '› ${_engine.lastTranscript}'
                    : _engine.lastResponse,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 10,
                  color: _text.withValues(alpha: 0.6),
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _dot(VoiceState state) {
    final c = state == VoiceState.listening ? _orange
        : state == VoiceState.processing ? const Color(0xFFFF8C00)
        : state == VoiceState.speaking ? const Color(0xFF00C86A)
        : _muted;
    return Container(
      width: 6, height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)],
      ),
    );
  }

  Widget _micBtn(VoiceState state, {required bool compact}) {
    final listening = state == VoiceState.listening;
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        listening ? _engine.stopListening() : _engine.startListening();
      },
      child: Container(
        width: compact ? 28 : 34,
        height: compact ? 28 : 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: listening ? _orange : Colors.transparent,
          border: Border.all(color: listening ? _orange : _border),
        ),
        child: Icon(
          listening ? Icons.stop_rounded : Icons.mic_rounded,
          size: compact ? 13 : 16,
          color: listening ? Colors.black : _muted,
        ),
      ),
    );
  }

  Widget _hintChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _border),
      ),
      child: Text(label, style: GoogleFonts.ibmPlexMono(fontSize: 8, color: _muted, letterSpacing: 0.5)),
    );
  }
}

// ── Bar Waveform painter ────────────────────────────────────────────────────
class _BarWavePainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final double strokeWidth;

  const _BarWavePainter({
    required this.samples,
    required this.color,
    this.strokeWidth = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw as vertical bars (oscilloscope style)
    final barW = (size.width / samples.length) * 0.6;
    for (int i = 0; i < samples.length; i++) {
      final x = (i + 0.5) * size.width / samples.length;
      final h = samples[i].clamp(0.04, 1.0) * size.height;
      final top = (size.height - h) / 2;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + h),
        paint..strokeWidth = barW,
      );
    }
  }

  @override
  bool shouldRepaint(_BarWavePainter old) => old.samples != samples;
}
