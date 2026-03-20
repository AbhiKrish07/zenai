import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../voice/voice_engine.dart';
import '../voice/voice_state.dart';
import '../voice/voice_overlay_widget.dart';

/// iPad-specific side-docked voice panel.
/// Docks to the right edge, collapsible via a tab.
class IpadVoicePanel extends StatefulWidget {
  final Widget content;
  const IpadVoicePanel({super.key, required this.content});

  @override
  State<IpadVoicePanel> createState() => _IpadVoicePanelState();
}

class _IpadVoicePanelState extends State<IpadVoicePanel>
    with SingleTickerProviderStateMixin {
  final _engine = VoiceEngine();
  bool _panelOpen = false;
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;

  static const double _panelWidth = 300.0;
  static const Color _bg = Color(0xFF000000);
  static const Color _orange = Color(0xFFFF4500);
  static const Color _border = Color(0xFF1A1A1A);


  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    if (_panelOpen) {
      _slideCtrl.reverse().then((_) => setState(() => _panelOpen = false));
    } else {
      setState(() => _panelOpen = true);
      _slideCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Main content area ──
        Expanded(child: widget.content),

        // ── Slide-out voice panel ──
        AnimatedBuilder(
          animation: _slideAnim,
          builder: (context, _) {
            final w = _panelWidth * _slideAnim.value;
            return SizedBox(
              width: w + 28, // tab always visible
              child: Stack(
                children: [
                  // Panel body
                  if (_panelOpen)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: w,
                      child: _buildPanelBody(),
                    ),
                  // Tab
                  Positioned(
                    right: w,
                    top: 0,
                    bottom: 0,
                    width: 28,
                    child: _buildTab(),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTab() {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          border: Border(
            left: BorderSide(color: _border),
            top: BorderSide(color: _border),
            bottom: BorderSide(color: _border),
          ),
          borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StreamBuilder<VoiceState>(
              stream: _engine.stateStream,
              initialData: _engine.currentState,
              builder: (_, snap) {
                final listening = snap.data == VoiceState.listening;
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: listening ? _orange : const Color(0xFF333333),
                    boxShadow: listening
                        ? [BoxShadow(color: _orange.withValues(alpha: 0.5), blurRadius: 8)]
                        : [],
                  ),
                );
              },
            ),
            RotatedBox(
              quarterTurns: 3,
              child: Text(
                'ZEN',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 9,
                  color: _orange,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Icon(
              _panelOpen ? Icons.chevron_right : Icons.chevron_left,
              color: const Color(0xFF555555),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelBody() {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(left: BorderSide(color: _border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(children: [
              Text(
                'ZEN',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 12,
                  color: _orange,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'VOICE',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 9,
                  color: const Color(0xFF444444),
                  letterSpacing: 2,
                ),
              ),
            ]),
          ),
          // Expanded voice overlay (no pill — full-panel mode)
          Expanded(
            child: VoiceOverlayWidget(
              isExpanded: true,
              onToggle: () => _engine.currentState == VoiceState.listening
                  ? _engine.stopListening()
                  : _engine.startListening(),
              onClose: _toggle,
            ),
          ),
        ],
      ),
    );
  }
}
