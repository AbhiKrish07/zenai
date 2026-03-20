import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'voice_controller.dart';
import 'voice_state.dart';
import 'ipad_voice_panel.dart';
import 'desktop_voice_bar.dart';
import 'voice_engine.dart';

/// Detects the current platform and wraps the app in the correct
/// voice shell:
///
///   📱 Phone (Android/iOS)  → Bottom floating draggable pill
///   📟 iPad                 → Right-docked side panel (split-view compatible)
///   💻 Desktop (macOS/Win)  → Always-on-top top bar with global hotkey
///   🌐 Web                  → Floating pill (same as phone)
class AdaptiveVoiceShell extends StatefulWidget {
  final Widget child;
  const AdaptiveVoiceShell({super.key, required this.child});

  @override
  State<AdaptiveVoiceShell> createState() => _AdaptiveVoiceShellState();
}

class _AdaptiveVoiceShellState extends State<AdaptiveVoiceShell> {
  final _engine = VoiceEngine();

  @override
  Widget build(BuildContext context) {
    final platform = _detectPlatform(context);

    switch (platform) {
      case _Platform.desktop:
        return _withKeyboardShortcut(
          DesktopVoiceBar(child: widget.child),
        );

      case _Platform.ipad:
        return IpadVoicePanel(content: widget.child);

      case _Platform.phone:
      case _Platform.web:
        return ZenVoiceController(child: widget.child);
    }
  }

  /// Wraps desktop bar with global hotkey handler (⌘⇧Space / Ctrl+Shift+Space)
  Widget _withKeyboardShortcut(Widget child) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final pressed = HardwareKeyboard.instance.logicalKeysPressed;
          final isCtrlOrCmd =
              pressed.contains(LogicalKeyboardKey.controlLeft) ||
              pressed.contains(LogicalKeyboardKey.controlRight) ||
              pressed.contains(LogicalKeyboardKey.metaLeft) ||
              pressed.contains(LogicalKeyboardKey.metaRight);
          final isShift =
              pressed.contains(LogicalKeyboardKey.shiftLeft) ||
              pressed.contains(LogicalKeyboardKey.shiftRight);
          final isSpace = event.logicalKey == LogicalKeyboardKey.space;

          if (isCtrlOrCmd && isShift && isSpace) {
            final active = _engine.currentState != VoiceState.idle &&
                _engine.currentState != VoiceState.error;
            if (active) {
              _engine.stopListening();
            } else {
              _engine.startListening();
            }
            return KeyEventResult.handled;
          }

          final curActive = _engine.currentState != VoiceState.idle &&
              _engine.currentState != VoiceState.error;
          if (event.logicalKey == LogicalKeyboardKey.escape && curActive) {
            _engine.stopListening();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  _Platform _detectPlatform(BuildContext context) {
    if (kIsWeb) return _Platform.web;

    final platform = defaultTargetPlatform;

    // iPad detection: iOS + large short axis
    if (platform == TargetPlatform.iOS) {
      final shortSide = MediaQuery.of(context).size.shortestSide;
      if (shortSide >= 600) return _Platform.ipad;
      return _Platform.phone;
    }

    if (platform == TargetPlatform.android) {
      final shortSide = MediaQuery.of(context).size.shortestSide;
      if (shortSide >= 600) return _Platform.ipad; // Android tablet
      return _Platform.phone;
    }

    if (platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux) {
      return _Platform.desktop;
    }

    return _Platform.phone;
  }
}

enum _Platform { phone, ipad, desktop, web }
