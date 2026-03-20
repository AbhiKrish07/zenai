import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

/// Manages authentication, REST API calls, and WebSocket chat
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;
  WebSocketChannel? _ws;
  bool _wsConnected = false;

  // ── Stream controllers for WebSocket messages ──
  final _messageController = StreamController<Map>.broadcast();
  Stream<Map> get messageStream => _messageController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => _wsConnected;
  String? get token => _token;

  // ── AUTH ──
  Future<bool> login(String passphrase) async {
    try {
      final resp = await http.post(
        Uri.parse(BlitzConfig.loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'passphrase': passphrase}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _token = data['token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('blitz_token', _token!);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[API] Login error: $e');
      return false;
    }
  }

  Future<bool> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('blitz_token');
    if (_token == null) return false;
    try {
      final resp = await http.get(
        Uri.parse(BlitzConfig.meUrl),
        headers: _authHeaders,
      );
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('blitz_token');
    disconnectWs();
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
        'Cookie': 'blitz_token=$_token',
      };

  // ── STATUS ──
  Future<Map?> getStatus() async {
    try {
      final resp = await http.get(Uri.parse(BlitzConfig.statusUrl));
      if (resp.statusCode == 200) return jsonDecode(resp.body);
    } catch (e) {
      debugPrint('[API] Status error: $e');
    }
    return null;
  }

  // ── BRIEFING ──
  Future<Map?> getBriefing() async {
    try {
      final resp = await http.get(
        Uri.parse(BlitzConfig.briefingUrl),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body);
    } catch (e) {
      debugPrint('[API] Briefing error: $e');
    }
    return null;
  }

  // ── TASKS ──
  Future<Map?> getTasks() async {
    try {
      final resp = await http.get(
        Uri.parse(BlitzConfig.tasksUrl),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body);
    } catch (e) {
      debugPrint('[API] Tasks error: $e');
    }
    return null;
  }

  Future<bool> addTask(String title, {String due = '', String priority = 'medium'}) async {
    try {
      final resp = await http.post(
        Uri.parse(BlitzConfig.tasksUrl),
        headers: _authHeaders,
        body: jsonEncode({'title': title, 'due': due, 'priority': priority}),
      );
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> completeTask(String taskId) async {
    try {
      final resp = await http.post(
        Uri.parse('${BlitzConfig.tasksUrl}/complete'),
        headers: _authHeaders,
        body: jsonEncode({'task_id': taskId}),
      );
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ── METRICS ──
  Future<Map?> getMetrics() async {
    try {
      final resp = await http.get(
        Uri.parse(BlitzConfig.metricsUrl),
        headers: _authHeaders,
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body);
    } catch (e) {
      debugPrint('[API] Metrics error: $e');
    }
    return null;
  }

  // ── TTS ──
  Future<String?> tts(String text) async {
    try {
      final resp = await http.post(
        Uri.parse(BlitzConfig.ttsUrl),
        headers: _authHeaders,
        body: jsonEncode({'text': text}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['audio_b64'];
      }
    } catch (e) {
      debugPrint('[API] TTS error: $e');
    }
    return null;
  }

  // ── STT ──
  Future<String?> stt(String audioBase64) async {
    try {
      final resp = await http.post(
        Uri.parse(BlitzConfig.sttUrl),
        headers: _authHeaders,
        body: jsonEncode({'audio_b64': audioBase64, 'language': 'en'}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['text'];
      }
    } catch (e) {
      debugPrint('[API] STT error: $e');
    }
    return null;
  }

  // ── GROQ DIRECT (local AI fallback) ──
  Future<String> chatWithGroq(String message, {List? history}) async {
    try {
      final messages = <Map<String, String>>[
        {
          'role': 'system',
          'content': 'You are Zen, an advanced Zen-level AI assistant. '
              'You are fast, precise, confident, and proactive. '
              'Respond in a helpful, conversational manner. Use markdown when helpful.'
        },
        if (history != null) ...history,
        {'role': 'user', 'content': message},
      ];

      final resp = await http.post(
        Uri.parse('${BlitzConfig.groqBaseUrl}/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${BlitzConfig.groqApiKey}',
        },
        body: jsonEncode({
          'model': BlitzConfig.groqModel,
          'messages': messages,
          'max_tokens': 2048,
          'temperature': 0.7,
        }),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['choices'][0]['message']['content'] ?? 'No response.';
      }
      return 'Error: ${resp.statusCode} — ${resp.body}';
    } catch (e) {
      return 'Error connecting to Groq: $e';
    }
  }

  // ── WEBSOCKET CHAT ──
  void connectWs() {
    if (_wsConnected || _token == null) return;
    try {
      _ws = WebSocketChannel.connect(Uri.parse(BlitzConfig.chatWsUrl));
      _wsConnected = true;
      _connectionController.add(true);

      // Send auth token as first message
      _ws!.sink.add(jsonEncode({'token': _token}));

      _ws!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map;
            _messageController.add(msg);
          } catch (e) {
            debugPrint('[WS] Parse error: $e');
          }
        },
        onError: (e) {
          debugPrint('[WS] Error: $e');
          _wsConnected = false;
          _connectionController.add(false);
          // Auto-reconnect after 3 seconds
          Future.delayed(const Duration(seconds: 3), connectWs);
        },
        onDone: () {
          _wsConnected = false;
          _connectionController.add(false);
          // Auto-reconnect after 3 seconds
          Future.delayed(const Duration(seconds: 3), connectWs);
        },
      );
    } catch (e) {
      debugPrint('[WS] Connection error: $e');
      _wsConnected = false;
      _connectionController.add(false);
    }
  }

  void sendMessage(String text, {
    List<String>? activeModules,
    bool useSwarm = false,
    bool useTools = true,
    bool voiceMode = false,
  }) {
    if (!_wsConnected || _ws == null) return;
    _ws!.sink.add(jsonEncode({
      'text': text,
      'active_modules': activeModules ?? [],
      'use_swarm': useSwarm,
      'use_tools': useTools,
      'voice_mode': voiceMode,
    }));
  }

  void disconnectWs() {
    _ws?.sink.close();
    _ws = null;
    _wsConnected = false;
    _connectionController.add(false);
  }

  void dispose() {
    disconnectWs();
    _messageController.close();
    _connectionController.close();
  }
}
