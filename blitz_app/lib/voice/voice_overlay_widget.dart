import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../voice/voice_engine.dart';
import '../voice/voice_state.dart';

/// The floating pill/capsule widget — primary voice interaction surface.
/// Lives above all other content (via Overlay or Stack).
class VoiceOverlayWidget extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  const VoiceOverlayWidget({
    super.key,
    required this.isExpanded,
    required this.onToggle,
    required this.onClose,
  });

  @override
  State<VoiceOverlayWidget> createState() => _VoiceOverlayWidgetState();
}

class _VoiceOverlayWidgetState extends State<VoiceOverlayWidget>
    with TickerProviderStateMixin {
  final _engine = VoiceEngine();

  // ── Animation controllers ──
  late AnimationController _expandCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _waveCtrl;
  late Animation<double> _expandAnim;
  late Animation<double> _pulseAnim;

  // ── Waveform sample buffer ──
  final List<double> _waveform = List.filled(32, 0.05);
  Timer? _waveTimer;
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();

    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );

    _engine.stateStream.listen(_onVoiceStateChange);
  }

  void _onVoiceStateChange(VoiceState state) {
    if (!mounted) return;
    setState(() {});
    if (state == VoiceState.listening) {
      _startWaveform();
      _pulseCtrl.repeat(reverse: true);
    } else {
      _stopWaveform();
      if (state == VoiceState.idle) {
        _pulseCtrl.stop();
        _pulseCtrl.value = 0;
      }
    }
  }

  void _startWaveform() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _waveform.length; i++) {
          final target = _engine.currentState == VoiceState.listening
              ? 0.1 + _rand.nextDouble() * 0.85
              : 0.05;
          _waveform[i] = _waveform[i] * 0.6 + target * 0.4;
        }
      });
    });
  }

  void _stopWaveform() {
    _waveTimer?.cancel();
    // Decay to zero
    Timer.periodic(const Duration(milliseconds: 40), (t) {
      if (!mounted) { t.cancel(); return; }
      bool allZero = true;
      setState(() {
        for (int i = 0; i < _waveform.length; i++) {
          _waveform[i] *= 0.7;
          if (_waveform[i] > 0.01) allZero = false;
        }
      });
      if (allZero) t.cancel();
    });
  }

  @override
  void didUpdateWidget(VoiceOverlayWidget old) {
    super.didUpdateWidget(old);
    if (widget.isExpanded != old.isExpanded) {
      if (widget.isExpanded) {
        _expandCtrl.forward();
      } else {
        _expandCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    _expandCtrl.dispose();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  // ── Colours ──
  static const Color _bg = Color(0xFF000000);
  static const Color _orange = Color(0xFFFF4500);
  static const Color _text = Color(0xFFF0EDE8);
  static const Color _muted = Color(0xFF666666);
  static const Color _border = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_expandAnim, _pulseAnim]),
      builder: (context, _) {
        final isListening = _engine.currentState == VoiceState.listening;
        final isThinking = _engine.currentState == VoiceState.processing;
        final isSpeaking = _engine.currentState == VoiceState.speaking;

        return GestureDetector(
          onTap: widget.onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: widget.isExpanded
                ? MediaQuery.of(context).size.width - 32
                : 200,
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(widget.isExpanded ? 20 : 40),
              border: Border.all(
                color: isListening
                    ? _orange.withValues(alpha: 0.8)
                    : _border,
                width: isListening ? 1.5 : 1,
              ),
              boxShadow: isListening
                  ? [
                      BoxShadow(
                        color: _orange.withValues(alpha: 0.18),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: widget.isExpanded
                ? _buildExpandedPill(isListening, isThinking, isSpeaking)
                : _buildCollapsedPill(isListening, isThinking, isSpeaking),
          ),
        );
      },
    );
  }

  // ── Collapsed pill (180×48) ────────────────────────────────────────
  Widget _buildCollapsedPill(bool listening, bool thinking, bool speaking) {
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: status dot + label
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(children: [
              _StatusDot(listening: listening, thinking: thinking, speaking: speaking),
              const SizedBox(width: 8),
              Text(
                _statusLabel(listening, thinking, speaking),
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  color: listening ? _orange : _text.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ]),
          ),
          // Right: waveform (mini) + mic button
          Row(children: [
            if (listening) _buildMiniWaveform(),
            _buildMicButton(listening, thinking, speaking),
          ]),
        ],
      ),
    );
  }

  Widget _buildMiniWaveform() {
    return SizedBox(
      width: 40,
      height: 28,
      child: CustomPaint(
        painter: _OscilloscopePainter(
          samples: _waveform.sublist(0, 16),
          color: _orange,
          strokeWidth: 1.2,
        ),
      ),
    );
  }

  // ── Expanded panel ─────────────────────────────────────────────────
  Widget _buildExpandedPill(bool listening, bool thinking, bool speaking) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top bar ──
          Row(children: [
            _StatusDot(listening: listening, thinking: thinking, speaking: speaking),
            const SizedBox(width: 8),
            Text(
              'ZEN',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 11,
                color: _orange,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: widget.onClose,
              child: const Icon(Icons.close, size: 16, color: _muted),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Waveform ──
          SizedBox(
            width: double.infinity,
            height: 56,
            child: CustomPaint(
              painter: _OscilloscopePainter(
                samples: _waveform,
                color: listening ? _orange : _muted,
                strokeWidth: 1.5,
                filled: true,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Transcript / status text ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _engine.lastTranscript.isNotEmpty
                  ? _engine.lastTranscript
                  : _statusDetailLabel(listening, thinking, speaking),
              key: ValueKey(_engine.lastTranscript + _statusLabel(listening, thinking, speaking)),
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                color: _text.withValues(alpha: 0.8),
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),

          // ── AI response preview ──
          if (_engine.lastResponse.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _orange.withValues(alpha: 0.15)),
              ),
              child: Text(
                _engine.lastResponse,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  color: _text.withValues(alpha: 0.7),
                  height: 1.4,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 14),

          // ── Controls row ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Push-to-talk button
              GestureDetector(
                onTapDown: (_) => _startListening(),
                onTapUp: (_) => _stopListening(),
                onTapCancel: () => _stopListening(),
                child: _buildMicButton(listening, thinking, speaking),
              ),
              const SizedBox(width: 16),
              // Hold mode toggle
              _buildSmallAction(
                icon: Icons.mic_external_on_rounded,
                label: 'HOLD',
                active: false,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              // Wake word toggle
              _buildSmallAction(
                icon: Icons.hearing_rounded,
                label: 'WAKE',
                active: _engine.wakeWordEnabled,
                onTap: () {
                  _engine.toggleWakeWord();
                  setState(() {});
                },
              ),
            ],
          ),

          // ── Tool chips ──
          if (thinking && _engine.activeTools.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: _engine.activeTools.map((t) => _ToolChip(label: t)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMicButton(bool listening, bool thinking, bool speaking) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        if (listening) {
          _stopListening();
        } else {
          _startListening();
        }
      },
      child: ScaleTransition(
        scale: listening ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
        child: Container(
          width: listening ? 52 : 44,
          height: listening ? 52 : 44,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: listening
                ? _orange
                : thinking
                    ? _muted.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: listening ? _orange : _border,
              width: 1,
            ),
          ),
          child: Icon(
            thinking
                ? Icons.hourglass_top_rounded
                : speaking
                    ? Icons.volume_up_rounded
                    : listening
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
            size: 20,
            color: listening
                ? Colors.black
                : _text.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallAction({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _orange.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? _orange.withValues(alpha: 0.5) : _border,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: active ? _orange : _muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 9,
              color: active ? _orange : _muted,
              letterSpacing: 1,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ──
  String _statusLabel(bool l, bool t, bool s) {
    if (l) return 'LISTENING';
    if (t) return 'THINKING';
    if (s) return 'SPEAKING';
    return 'ZEN';
  }

  String _statusDetailLabel(bool l, bool t, bool s) {
    if (l) return 'Say something...';
    if (t) return 'Processing...';
    if (s) return 'Speaking...';
    return _engine.wakeWordEnabled ? 'Say "Hey Zen"' : 'Tap mic to speak';
  }

  Future<void> _startListening() => _engine.startListening();
  Future<void> _stopListening() => _engine.stopListening();
}

// ── Oscilloscope waveform painter ──────────────────────────────────────────
class _OscilloscopePainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final double strokeWidth;
  final bool filled;

  const _OscilloscopePainter({
    required this.samples,
    required this.color,
    this.strokeWidth = 1.5,
    this.filled = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke;

    final path = Path();
    final step = size.width / (samples.length - 1);
    final midY = size.height / 2;

    path.moveTo(0, midY - samples[0] * midY);
    for (int i = 1; i < samples.length; i++) {
      final x = i * step;
      final y = midY - samples[i] * midY;
      final prevX = (i - 1) * step;
      final prevY = midY - samples[i - 1] * midY;
      final cpX = (prevX + x) / 2;
      path.cubicTo(cpX, prevY, cpX, y, x, y);
    }

    if (filled) {
      path.lineTo(size.width, midY);
      path.lineTo(0, midY);
      path.close();
      paint.color = color.withValues(alpha: 0.08);
      canvas.drawPath(path, paint);
      paint.color = color;
      paint.style = PaintingStyle.stroke;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OscilloscopePainter old) =>
      old.samples != samples || old.color != color;
}

// ── Status dot ─────────────────────────────────────────────────────────────
class _StatusDot extends StatelessWidget {
  final bool listening;
  final bool thinking;
  final bool speaking;

  const _StatusDot({
    required this.listening,
    required this.thinking,
    required this.speaking,
  });

  @override
  Widget build(BuildContext context) {
    final Color c = listening
        ? const Color(0xFFFF4500)
        : thinking
            ? const Color(0xFFFF8C00)
            : speaking
                ? const Color(0xFF00C86A)
                : const Color(0xFF333333);
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1),
        ],
      ),
    );
  }
}

// ── Tool chip ──────────────────────────────────────────────────────────────
class _ToolChip extends StatelessWidget {
  final String label;
  const _ToolChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.ibmPlexMono(
          fontSize: 8,
          color: const Color(0xFF888888),
          letterSpacing: 1,
        ),
      ),
    );
  }
}
