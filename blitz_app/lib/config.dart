import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';

/// Zen App Configuration — Safely handles cross-platform logic
class BlitzConfig {
  // ── Server Connection ──
  static String get baseHost {
    if (kIsWeb) return '127.0.0.1';
    try {
      if (Platform.isAndroid) return '10.0.2.2';
      if (Platform.isIOS) return '127.0.0.1';
    } catch (_) {}
    return '127.0.0.1';
  }

  static String get serverUrl => 'http://$baseHost:8000';
  static String get wsUrl => 'ws://$baseHost:8000';

  // Passphrase for auth
  static const String defaultPassphrase = 'blitz-jarvis-2025';

  // ── API Endpoints ──
  static String get loginUrl => '$serverUrl/api/login';
  static String get statusUrl => '$serverUrl/api/status';
  static String get meUrl => '$serverUrl/api/me';
  static String get briefingUrl => '$serverUrl/api/briefing';
  static String get tasksUrl => '$serverUrl/api/tasks';
  static String get metricsUrl => '$serverUrl/api/metrics';
  static String get sttUrl => '$serverUrl/api/stt';
  static String get ttsUrl => '$serverUrl/api/tts';
  static String get chatWsUrl => '$wsUrl/ws/chat';

  // ── AI Configuration (Supports Key Pooling for Throughput) ──
  static const List<String> groqKeyPool = [
    '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',
    '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',
    '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',
    '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',
    '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'
  ];
  static const String groqApiKey = ''; 
  static const String geminiApiKey = ''; 
  static const String groqModel = 'llama-3.3-70b-versatile';
  static const String groqEmbedModel = 'nomic-embed-text';
  static const String groqSwarmModel = 'llama-3.1-8b-instant';
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';

  // ── Zilliz (Vector Memory - User should provide their own cluster) ──
  static const String zillizUser = ''; 
  static const String zillizPassword = ''; 
  static const String zillizEndpoint = 'https://in03-xxxxxx.api.gcp-us-west1.zillizcloud.com';
  static const String zillizCollection = 'zen_memories';

  // ── ElevenLabs TTS (User provided) ──
  static const String elevenLabsApiKey = ''; 
  static const String elevenLabsVoiceId = '21m00Tcm4TlvDq8ikWAM';

  // ── Theme ──
  static const double borderRadius = 16.0;
  static const double cardRadius = 20.0;
}
