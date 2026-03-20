/// All possible states of the voice assistant
enum VoiceState {
  /// No active listening or processing — base state
  idle,

  /// Wake word detected or button held — microphone open
  listening,

  /// Transcript sent to backend — waiting for LLM + tools
  processing,

  /// TTS audio is being played back
  speaking,

  /// Silent error state — shown for 2 s then returns to idle
  error,
}

extension VoiceStateX on VoiceState {
  bool get isActive => this != VoiceState.idle && this != VoiceState.error;

  String get displayLabel {
    switch (this) {
      case VoiceState.idle:
        return 'IDLE';
      case VoiceState.listening:
        return 'LISTENING';
      case VoiceState.processing:
        return 'THINKING';
      case VoiceState.speaking:
        return 'SPEAKING';
      case VoiceState.error:
        return 'ERROR';
    }
  }
}
