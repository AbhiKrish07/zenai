import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';
import 'package:uuid/uuid.dart';
import '../services/zilliz_service.dart';
import 'database.dart';

class ZenBrain {
  static final ZenBrain _instance = ZenBrain._internal();
  factory ZenBrain() => _instance;

  final _db = ZenDatabase();
  late final FlutterSecureStorage _secureStorage;
  final _uuid = const Uuid();
  final _zilliz = ZillizService();
  bool _initialized = false;
  Completer<void>? _initCompleter;

  ZenBrain._internal() {
    _secureStorage = const FlutterSecureStorage();
  }

  String _apiKey = '';
  String _geminiApiKey = '';
  String _zillizEndpoint = '';
  String _zillizUser = '';
  String _zillizKey = '';
  String _model = 'llama3-70b-8192';

  // Getters for external modules
  String get apiKey => _apiKey;
  String get currentModel => _model;
  String get currentModelName => _model;
  String get zillizUser => _zillizUser;
  String get zillizPassword => _zillizKey;
  String get zillizEndpoint => _zillizEndpoint;
  
  List<Map<String, String>> get availableModels => [
    {'id': 'llama3-70b-8192', 'name': 'Llama 3 70B'},
    {'id': 'llama3-8b-8192', 'name': 'Llama 3 8B'},
    {'id': 'mixtral-8x7b-32768', 'name': 'Mixtral 8x7B'},
    {'id': 'gemini-pro', 'name': 'Gemini Pro'},
  ];

  Future<void> init() async {
    if (_initialized) return;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    try {
      _apiKey = await _secureStorage.read(key: 'groq_api_key') ?? '';
      _geminiApiKey = await _secureStorage.read(key: 'gemini_api_key') ?? '';
      _zillizEndpoint = await _secureStorage.read(key: 'zilliz_endpoint') ?? '';
      _zillizUser = await _secureStorage.read(key: 'zilliz_user') ?? '';
      _zillizKey = await _secureStorage.read(key: 'zilliz_key') ?? '';
      _model = await _secureStorage.read(key: 'groq_model') ?? BlitzConfig.groqModel;
      
      // If user key is missing, try fallback to pool
      if (_apiKey.isEmpty && BlitzConfig.groqKeyPool.isNotEmpty) {
        debugPrint('[ZenBrain] Using key from fallback pool...');
        _apiKey = BlitzConfig.groqKeyPool[Random().nextInt(BlitzConfig.groqKeyPool.length)];
      }
    } catch (_) {}
    _initialized = true;
    _initCompleter?.complete();
    _initCompleter = null;
  }

  Future<void> setApiKey(String key) async { _apiKey = key; await _secureStorage.write(key: 'groq_api_key', value: key); }
  Future<void> setGeminiApiKey(String key) async { _geminiApiKey = key; await _secureStorage.write(key: 'gemini_api_key', value: key); }
  Future<void> setElevenLabsKey(String key) async { await _secureStorage.write(key: 'elevenlabs_api_key', value: key); }
  Future<void> setSpotifyToken(String token) async { await _secureStorage.write(key: 'spotify_token', value: token); }
  Future<void> setZillizConfig(String endpoint, String user, String key) async {
    _zillizEndpoint = endpoint; _zillizUser = user; _zillizKey = key;
    await _secureStorage.write(key: 'zilliz_endpoint', value: endpoint);
    await _secureStorage.write(key: 'zilliz_user', value: user);
    await _secureStorage.write(key: 'zilliz_key', value: key);
  }
  Future<void> setModel(String modelId) async { _model = modelId; await _secureStorage.write(key: 'groq_model', value: modelId); }

  Future<String> _buildSystemPrompt({String? userMessage}) async {
    final snapshot = await _db.getFullSnapshot();
    final memoriesRaw = snapshot['memories'] ?? [];
    final sqliteMemories = memoriesRaw.join('\n');
    String semanticMemories = '';
    if (userMessage != null && _zillizUser.isNotEmpty) {
      try {
        final matches = await _zilliz.searchMemories(userMessage, topK: 3);
        if (matches.isNotEmpty) semanticMemories = '\n[Relevant Memories]:\n${matches.join('\n')}';
      } catch (_) {}
    }
    return 'You are Zen AI assistant.\nContext:\n$sqliteMemories$semanticMemories';
  }

  Future<String> chat(String message, {bool persistHistory = true, String? sessionId}) async {
    await init();
    if (_apiKey.isEmpty) return "Neural link missing.";
    try {
      final systemPrompt = await _buildSystemPrompt(userMessage: message);
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _model,
          'messages': [{'role': 'system', 'content': systemPrompt}, {'role': 'user', 'content': message}],
        }),
      );
      if (response.statusCode == 200) {
        final reply = jsonDecode(response.body)['choices'][0]['message']['content'];
        if (persistHistory) {
          await _db.setMemory(_uuid.v4(), "User: $message\nAI: $reply");
        }
        return reply;
      }
    } catch (e) { return "Link failed: $e"; }
    return "Error.";
  }

  Stream<String> chatStream(String message, {String? sessionId, bool? persistHistory}) async* {
    yield await chat(message, persistHistory: persistHistory ?? true, sessionId: sessionId);
  }

  Future<String> analyze(String data) async {
    await init();
    if (_apiKey.isEmpty) return "Missing link.";
    try {
      final resp = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'llama3-70b-8192',
          'messages': [{'role': 'system', 'content': 'Analyze.'}, {'role': 'user', 'content': data}],
        }),
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body)['choices'][0]['message']['content'];
    } catch (_) {}
    return "Failed.";
  }

  Future<String> generateMorningBriefing() async => "Briefing ready.";
  Future<String> analyzeAndPrioritizeTasks([List<dynamic>? tasks]) async => "Prioritized.";
  Future<Map<String, dynamic>> defaultAliveCalculation() async => {'message': 'Functional.'};

  Future<List<double>> getEmbedding(String text) async {
    if (_geminiApiKey.isNotEmpty) {
       final url = 'https://generativelanguage.googleapis.com/v1beta/models/embedding-001:embedContent?key=$_geminiApiKey';
       try {
         final resp = await http.post(Uri.parse(url), body: jsonEncode({'model': 'models/embedding-001', 'content': {'parts': [{'text': text}]}}));
         if (resp.statusCode == 200) return List<double>.from(jsonDecode(resp.body)['embedding']['values']);
       } catch (_) {}
    }
    return [];
  }

  Future<void> saveToBrain(String text) async {
    await init();
    await _db.setMemory(_uuid.v4(), text);
    if (_zillizUser.isNotEmpty) {
      try {
        await _zilliz.upsertMemory(id: _uuid.v4(), text: text);
      } catch (_) {}
    }
  }

  Future<void> clearBrain() async { await init(); }
}
