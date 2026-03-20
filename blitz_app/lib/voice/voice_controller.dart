import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'voice_engine.dart';
import 'voice_state.dart';
import 'voice_overlay_widget.dart';

/// The Zen Voice Controller — manages the floating pill overlay
/// and is mounted once at the app root via [ZenVoiceController].
///
/// Usage (in HomeScreen or shell widget):
///   ZenVoiceController(child: YourMainContent())
class ZenVoiceController extends StatefulWidget {
  final Widget child;
  const ZenVoiceController({super.key, required this.child});

  @override
  State<ZenVoiceController> createState() => _ZenVoiceControllerState();
}

class _ZenVoiceControllerState extends State<ZenVoiceController>
    with TickerProviderStateMixin {
  final _engine = VoiceEngine();
  final bool _pillVisible = true;
  bool _pillExpanded = false;

  // Drag position — phone default: bottom-center
  double _pillBottom = 100;
  double _pillRight = 16;

  @override
  void initState() {
    super.initState();
    // Auto-collapse when engine returns to idle
    _engine.stateStream.listen((s) {
      if (s == VoiceState.idle && _pillExpanded) {
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted && _engine.currentState == VoiceState.idle) {
            setState(() => _pillExpanded = false);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Main app content ──
          widget.child,

          // ── Floating pill ──
          if (_pillVisible)
            _buildDraggablePill(context),
        ],
      ),
    );
  }

  Widget _buildDraggablePill(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      bottom: _pillBottom,
      right: _pillExpanded ? 16 : _pillRight,
      child: GestureDetector(
        onPanUpdate: !_pillExpanded
            ? (details) {
                setState(() {
                  _pillBottom =
                      (_pillBottom - details.delta.dy).clamp(40.0, MediaQuery.of(context).size.height - 120);
                  _pillRight =
                      (_pillRight - details.delta.dx).clamp(8.0, MediaQuery.of(context).size.width - 220);
                });
              }
            : null,
        child: VoiceOverlayWidget(
          isExpanded: _pillExpanded,
          onToggle: () {
            HapticFeedback.selectionClick();
            setState(() => _pillExpanded = !_pillExpanded);
          },
          onClose: () {
            setState(() {
              _pillExpanded = false;
            });
          },
        ),
      ),
    );
  }
}
