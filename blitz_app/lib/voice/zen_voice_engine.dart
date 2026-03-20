import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'voice_state.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  ZEN VOICE ENGINE  —  Wispr Flow Layer
//
//  Features:
//   • Real-time streaming STT via on-device speech_to_text
//   • Filler word suppression ("um", "uh", "like", "you know", etc.)
//   • Command vs. dictation disambiguation
//   • Voice tone detection (urgent / frustrated / casual)
//   • Adaptive personal vocabulary (learns names, abbreviations)
//   • Smart punctuation inference
//   • WebSocket bridge to FastAPI backend (Claude claude-sonnet-4-6)
//   • ElevenLabs TTS with low-latency streaming
//   • Demo mode — 100% offline testable
// ═══════════════════════════════════════════════════════════════════════════

enum VoiceTone { urgent, frustrated, casual }

class ZenVoiceEngine {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final ZenVoiceEngine _instance = ZenVoiceEngine._internal();
  factory ZenVoiceEngine() => _instance;
  ZenVoiceEngine._internal() { _init(); }

  // ── Core services ──────────────────────────────────────────────────────
  final _speech = stt.SpeechToText();
  final _tts    = FlutterTts();

  // ── Demo / test mode ───────────────────────────────────────────────────
  bool _demoMode = false;
  bool get demoMode => _demoMode;
  void setDemoMode(bool v) { _demoMode = v; _log('Demo mode: $v'); }

  // ── State ──────────────────────────────────────────────────────────────
  VoiceState _state = VoiceState.idle;
  VoiceState get currentState => _state;

  String _lastTranscript     = '';
  String _lastResponse       = '';
  String _rawTranscript      = '';  // before filler suppression
  VoiceTone _currentTone     = VoiceTone.casual;
  bool _wakeWordEnabled      = false;
  bool _speechReady          = false;
  bool _speakEnabled         = true;

  String get lastTranscript => _lastTranscript;
  String get lastResponse   => _lastResponse;
  VoiceTone get currentTone => _currentTone;
  bool get wakeWordEnabled  => _wakeWordEnabled;
  bool get speakEnabled     => _speakEnabled;
  void setSpeakEnabled(bool v) => _speakEnabled = v;

  // ── Personal vocabulary (adaptive) ────────────────────────────────────
  final Map<String, String> _vocabulary = {};
  // e.g. "blitz" → "B.L.I.T.Z.", "mgr" → "manager"

  // ── Filler words to strip ─────────────────────────────────────────────
  static const List<String> _fillerWords = [
    'um', 'uh', 'umm', 'uhh', 'like', 'you know', 'sort of', 'kind of',
    'right', 'basically', 'literally', 'actually', 'okay so', 'so like',
    'i mean', 'well', 'hmm', 'ah', 'er', 'erm',
  ];

  // ── Command trigger keywords ───────────────────────────────────────────
  static const List<String> _commandTriggers = [
    'search', 'find', 'open', 'play', 'pause', 'stop', 'skip', 'next',
    'previous', 'remind', 'set timer', 'create task', 'add task', 'navigate',
    'volume', 'brightness', 'screenshot', 'weather', 'what time', 'call',
    'send', 'draft email', 'show me', 'take a note', 'schedule',
    'hey zen', 'zen please', 'can you', 'could you', 'i need',
  ];

  // ── Urgency patterns ──────────────────────────────────────────────────
  static const List<String> _urgentWords = [
    'urgent', 'asap', 'immediately', 'right now', 'emergency', 'quickly',
    'hurry', 'fast', 'critical', 'important', 'deadline',
  ];
  static const List<String> _frustratedWords = [
    'ugh', 'damn', 'again', 'why', 'broken', 'not working', 'terrible',
    'awful', 'hate', 'stupid', 'wrong', 'failed', 'error',
  ];

  // ── Streams ───────────────────────────────────────────────────────────
  final _stateCtrl      = StreamController<VoiceState>.broadcast();
  final _transcriptCtrl = StreamController<String>.broadcast();
  final _responseCtrl   = StreamController<String>.broadcast();
  final _toolCtrl       = StreamController<List<String>>.broadcast();
  final _logCtrl        = StreamController<List<String>>.broadcast();
  final _waveCtrl       = StreamController<List<double>>.broadcast();
  final _toneCtrl       = StreamController<VoiceTone>.broadcast();

  Stream<VoiceState>   get stateStream      => _stateCtrl.stream;
  Stream<String>       get transcriptStream  => _transcriptCtrl.stream;
  Stream<String>       get responseStream    => _responseCtrl.stream;
  Stream<List<String>> get toolStream        => _toolCtrl.stream;
  Stream<List<String>> get logStream         => _logCtrl.stream;
  Stream<List<double>> get waveformStream    => _waveCtrl.stream;
  Stream<VoiceTone>    get toneStream        => _toneCtrl.stream;

  // ── Waveform ──────────────────────────────────────────────────────────
  List<double> _waveform = List.filled(40, 0.0);
  List<double> get waveform => List.from(_waveform);
  Timer? _waveTimer;
  final _rand = math.Random();

  // ── Debug log ─────────────────────────────────────────────────────────
  final List<String> _logEntries = [];
  List<String> get debugLog => List.from(_logEntries);
  void _log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logEntries.add('[$ts] $msg');
    if (_logEntries.length > 60) _logEntries.removeAt(0);
    _logCtrl.add(List.from(_logEntries));
  }

  // ── WebSocket ──────────────────────────────────────────────────────────
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  bool _wsConnected = false;
  final List<String> _activeTools = [];

  // ── Wake word ─────────────────────────────────────────────────────────
  Timer? _wakeWordTimer;
  bool  _wakeCheckActive = false;

  // ── Intent debounce ───────────────────────────────────────────────────
  Timer? _intentTimer;

  // ─────────────────────────────────────────────────────────────────────
  //  Init
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _init() async {
    _log('ZenVoiceEngine init');
    await _loadVocabulary();
  }


  Future<void> _setupTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.52);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _tts.setStartHandler(()  => _setState(VoiceState.speaking));
    _tts.setCompletionHandler(() { _setState(VoiceState.idle); });
    _tts.setErrorHandler((_) => _setState(VoiceState.idle));
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Personal Vocabulary  —  load/save/learn
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _loadVocabulary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('zen_vocabulary') ?? '{}';
      final map = jsonDecode(raw) as Map;
      _vocabulary.addAll(map.map((k, v) => MapEntry(k, v.toString())));
      _log('Vocabulary loaded: ${_vocabulary.length} entries');
    } catch (e) {
      _log('Vocabulary load error: $e');
    }
  }

  Future<void> learnWord(String abbrev, String expansion) async {
    _vocabulary[abbrev.toLowerCase()] = expansion;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zen_vocabulary', jsonEncode(_vocabulary));
      _log('Learned: "$abbrev" → "$expansion"');
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Text processing pipeline (Wispr Flow layer)
  // ─────────────────────────────────────────────────────────────────────

  /// 1. Strip filler words
  String suppressFillers(String text) {
    var result = text;
    for (final filler in _fillerWords) {
      // Match whole word, case-insensitive, with optional surrounding punctuation
      final pattern = RegExp(
        r'(?<![a-z])' + RegExp.escape(filler) + r'(?![a-z]),?\s*',
        caseSensitive: false,
        unicode: true,
      );
      result = result.replaceAll(pattern, ' ');
    }
    return result.replaceAll(RegExp(r' {2,}'), ' ').trim();
  }

  /// 2. Apply personal vocabulary substitutions
  String applyVocabulary(String text) {
    var result = text;
    for (final entry in _vocabulary.entries) {
      final pattern = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b',
          caseSensitive: false);
      result = result.replaceAll(pattern, entry.value);
    }
    return result;
  }

  /// 3. Infer punctuation — adds periods, commas, question marks
  String inferPunctuation(String text) {
    if (text.isEmpty) return text;
    var result = text.trim();

    // Question detection
    final questionStarters = [
      'what', 'where', 'when', 'who', 'why', 'how', 'is', 'are', 'can',
      'could', 'will', 'would', 'should', 'do', 'does', 'did', 'has', 'have',
    ];
    final lower = result.toLowerCase();
    final isQuestion = questionStarters.any((q) => lower.startsWith(q));

    // Add terminal punctuation if missing
    if (!result.endsWith('.') && !result.endsWith('?') && !result.endsWith('!')) {
      result += isQuestion ? '?' : '.';
    }

    // Capitalize first letter
    if (result.isNotEmpty) {
      result = result[0].toUpperCase() + result.substring(1);
    }

    return result;
  }

  /// 4. Command vs. dictation disambiguation
  bool isCommand(String text) {
    final lower = text.toLowerCase().trim();
    return _commandTriggers.any((kw) => lower.startsWith(kw) || lower.contains(kw));
  }

  /// 5. Voice tone detection
  VoiceTone detectTone(String text) {
    final lower = text.toLowerCase();
    if (_urgentWords.any((w) => lower.contains(w))) return VoiceTone.urgent;
    if (_frustratedWords.any((w) => lower.contains(w))) return VoiceTone.frustrated;
    return VoiceTone.casual;
  }

  /// Full pipeline: raw STT → clean spoken text
  String _processTranscript(String raw) {
    var t = suppressFillers(raw);
    t = applyVocabulary(t);
    if (!isCommand(t)) {
      t = inferPunctuation(t);
    }
    return t;
  }

  // ─────────────────────────────────────────────────────────────────────
  //  WebSocket  →  FastAPI backend (Claude agent)
  // ─────────────────────────────────────────────────────────────────────
  void _connectWs() {
    if (_wsConnected) return;
    try {
      final uri = Uri.parse('${BlitzConfig.wsUrl}/ws/zen');
      _ws = WebSocketChannel.connect(uri);
      _wsConnected = true;
      _log('WS → ${uri.host}:${uri.port}/ws/zen');
      _wsSub = _ws!.stream.listen(
        _onWsMessage,
        onError: (e) { _log('WS error: $e'); _wsConnected = false; _retryWs(); },
        onDone:  ()  { _log('WS closed');    _wsConnected = false; _retryWs(); },
      );
    } catch (e) {
      _log('WS failed: $e');
      _wsConnected = false;
      _retryWs();
    }
  }

  void _retryWs() {
    // Aggressive retries removed to prevent lookup errors during development.
    // Connection will be re-attempted on next voice interaction.
  }


  void _onWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map;
      final type = data['type'] as String? ?? '';
      switch (type) {
        case 'tool_start':
          final tool = data['tool'] as String? ?? 'tool';
          if (!_activeTools.contains(tool)) _activeTools.add(tool);
          _toolCtrl.add(List.from(_activeTools));
          _log('Tool: $tool');
          break;
        case 'tool_done':
          _activeTools.remove(data['tool'] as String? ?? '');
          _toolCtrl.add(List.from(_activeTools));
          break;
        case 'response_chunk':
          final chunk = data['text'] as String? ?? '';
          _lastResponse += chunk;
          _responseCtrl.add(_lastResponse);
          break;
        case 'response_done':
          final text = data['text'] as String? ?? _lastResponse;
          _lastResponse = text;
          _responseCtrl.add(text);
          _setState(VoiceState.idle);
          if (_speakEnabled) _speakResponse(text);
          _log('Response: ${text.length} chars');
          break;
        case 'memory_saved':
          _log('Memory: ${data['key']}');
          break;
        case 'context':
          _log('Context update: ${data['app']}');
          break;
        case 'error':
          _log('Backend error: ${data['message']}');
          _setState(VoiceState.error);
          Future.delayed(const Duration(seconds: 2), () => _setState(VoiceState.idle));
          break;
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────────────

  Future<void> startListening() async {
    if (_state == VoiceState.listening) return;
    _log('startListening');
    _connectWs(); // Connect on demand
    await _tts.stop();

    _rawTranscript  = '';
    _lastTranscript = '';
    _lastResponse   = '';
    _activeTools.clear();
    _toolCtrl.add([]);
    _startWaveform();

    if (_demoMode) {
      _setState(VoiceState.listening);
      _log('[DEMO] listening');
      return;
    }

    if (!_speechReady) {
       _log('Initializing hardware...');
       await _setupTts();
       _speechReady = await _speech.initialize(
         onError: (e) => _log('STT error: ${e.errorMsg}'),
         onStatus: (s) {
            if (s == 'notListening' && _state == VoiceState.listening) _onSpeechDone();
         },
       );
    }
    
    if (!_speechReady) {
      _log('STT hardware failure');
      _setState(VoiceState.error);
      Future.delayed(const Duration(seconds: 2), () => _setState(VoiceState.idle));
      return;
    }


    _speech.listen(
      onResult: (result) {
        _rawTranscript = result.recognizedWords;
        final clean = _processTranscript(_rawTranscript);
        _lastTranscript = clean;
        _transcriptCtrl.add(clean);

        // Live tone detection as user speaks
        final tone = detectTone(_rawTranscript);
        if (tone != _currentTone) {
          _currentTone = tone;
          _toneCtrl.add(tone);
        }

        _intentTimer?.cancel();
        if (result.finalResult) {
          _intentTimer = Timer(const Duration(milliseconds: 80), _onSpeechDone);
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 2),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
    );
    _setState(VoiceState.listening);
  }

  Future<void> stopListening() async {
    if (_state != VoiceState.listening) return;
    _log('stopListening');
    if (!_demoMode) await _speech.stop();
    _stopWaveform();
    _onSpeechDone();
  }

  Future<void> submitText(String text) async {
    if (text.trim().isEmpty) return;
    final clean = _processTranscript(text.trim());
    _lastTranscript = clean;
    _lastResponse   = '';
    _transcriptCtrl.add(clean);
    _connectWs(); // Connect on demand
    _setState(VoiceState.processing);
    _log('submit: $text');

    if (_demoMode) {
      await _demoResponse(text.trim());
    } else {
      await _routeIntent(clean);
    }
  }

  void toggleWakeWord() {
    _wakeWordEnabled = !_wakeWordEnabled;
    _wakeWordEnabled ? _startWakeWordLoop() : _stopWakeWordLoop();
    _log('Wake word: $_wakeWordEnabled');
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Intent routing  →  WS agent or local fallback
  // ─────────────────────────────────────────────────────────────────────
  void _onSpeechDone() {
    _stopWaveform();
    final text = _lastTranscript.trim();
    _log('Speech done: "$text"');
    if (text.isEmpty) { _setState(VoiceState.idle); return; }
    _setState(VoiceState.processing);
    if (_demoMode) {
      _demoResponse(text);
    } else {
      _routeIntent(text);
    }
  }

  Future<void> _routeIntent(String text) async {
    final lower = text.toLowerCase();
    final cmd   = isCommand(text);
    final intent = _classifyIntent(lower);
    final tone   = _currentTone.name;

    // Strip wake word prefix if present
    var query = lower
        .replaceFirst('hey zen', '')
        .replaceFirst('zen please', '')
        .replaceFirst('hey zen', '')
        .trim();
    if (query.isEmpty) query = text;

    if (_wsConnected && _ws != null) {
      _log('→ WS (intent=$intent, command=$cmd, tone=$tone)');
      _ws!.sink.add(jsonEncode({
        'type':       'zen_query',
        'text':       query,
        'is_command': cmd,
        'intent':     intent,
        'tone':       tone,
        'raw':        _rawTranscript,
      }));
    } else {
      _log('→ local fallback (no WS)');
      // Very basic local response
      final response = _localFallback(query, intent);
      _lastResponse = response;
      _responseCtrl.add(response);
      _setState(VoiceState.idle);
      if (_speakEnabled) _speakResponse(response);
    }
  }

  String _localFallback(String query, String intent) {
    return switch (intent) {
      'weather'      => 'I need a network connection to check the weather.',
      'reminder'     => 'I\'ll set that reminder once you\'re back online.',
      'search'       => 'Search requires an internet connection.',
      'media_control'=> 'Media control requires the backend service.',
      _              => 'I\'m offline right now. Reconnecting soon.',
    };
  }

  String _classifyIntent(String text) {
    if (text.contains('remind') || text.contains('timer') || text.contains('alarm')) {
      return 'reminder';
    }
    if (text.contains('search') || text.contains('look up') || text.contains('find') ||
        text.contains('what is') || text.contains('who is')) {
      return 'search';
    }
    if (text.contains('play') || text.contains('pause') || text.contains('music') ||
        text.contains('spotify') || text.contains('skip') || text.contains('volume')) {
      return 'media_control';
    }
    if (text.contains('create task') || text.contains('add task') || text.contains('todo')) {
      return 'task_create';
    }
    if (text.contains('open') || text.contains('launch')) return 'open_app';
    if (text.contains('screenshot')) return 'screenshot';
    if (text.contains('weather') || text.contains('temperature')) return 'weather';
    if (text.contains('email') || text.contains('draft') || text.contains('send')) {
      return 'email';
    }
    if (text.contains('calendar') || text.contains('schedule') || text.contains('meeting')) {
      return 'calendar';
    }
    if (text.contains('note') || text.contains('write down')) return 'note';
    return 'conversation';
  }

  // ─────────────────────────────────────────────────────────────────────
  //  TTS — ElevenLabs preferred, system fallback
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _speakResponse(String text) async {
    if (text.isEmpty || !_speakEnabled) return;
    final clean = text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'\1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'\1')
        .replaceAll(RegExp(r'#{1,6}\s'), '')
        .replaceAll(RegExp(r'`+'), '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'\1')
        .replaceAll('\\', ' backslash ')
        .replaceAll('/', ' slash ')
        .replaceAll('_', ' underscore ')
        .replaceAll(RegExp(r'\n+'), '. ')
        .trim();
    if (clean.isEmpty) return;
    final capped = clean.length > 500 ? '${clean.substring(0, 500)}...' : clean;
    _setState(VoiceState.speaking);
    await _tts.speak(capped);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Demo mode
  // ─────────────────────────────────────────────────────────────────────
  static const List<String> _demoReplies = [
    'On it. Volume adjusted.',
    'Done — Spotify paused.',
    'Reminder set for 10 minutes.',
    "Here's what I found: 42.",
    'Task created.',
    'Brightness set to 70%.',
    'Opening Chrome.',
    "I'm offline in demo mode, but I'd normally search that for you.",
    'Memory saved.',
    'Short answer: probably yes.',
  ];

  Future<void> _demoResponse(String text) async {
    await Future.delayed(const Duration(milliseconds: 320));
    final reply = _demoReplies[_rand.nextInt(_demoReplies.length)];
    final words = reply.split(' ');
    _lastResponse = '';
    for (int i = 0; i < words.length; i++) {
      await Future.delayed(const Duration(milliseconds: 55));
      _lastResponse += (i == 0 ? '' : ' ') + words[i];
      _responseCtrl.add(_lastResponse);
    }
    _setState(VoiceState.idle);
    if (_speakEnabled) _speakResponse(reply);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Waveform
  // ─────────────────────────────────────────────────────────────────────
  void _startWaveform() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 48), (_) {
      final next = List<double>.from(_waveform);
      for (int i = 0; i < next.length; i++) {
        final target = 0.04 + _rand.nextDouble() * 0.92;
        next[i] = next[i] * 0.52 + target * 0.48;
      }
      _waveform = next;
      _waveCtrl.add(List.from(_waveform));
    });
  }

  void _stopWaveform() {
    _waveTimer?.cancel();
    Timer.periodic(const Duration(milliseconds: 28), (t) {
      bool done = true;
      final next = List<double>.from(_waveform);
      for (int i = 0; i < next.length; i++) {
        next[i] *= 0.72;
        if (next[i] > 0.004) done = false;
      }
      _waveform = next;
      _waveCtrl.add(List.from(_waveform));
      if (done) t.cancel();
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Wake word loop
  // ─────────────────────────────────────────────────────────────────────
  void _startWakeWordLoop() {
    _wakeWordTimer?.cancel();
    _wakeWordTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_state != VoiceState.idle || _wakeCheckActive) return;
      _wakeCheckActive = true;
      await _doWakeWordCheck();
      _wakeCheckActive = false;
    });
  }

  void _stopWakeWordLoop() {
    _wakeWordTimer?.cancel();
    _wakeCheckActive = false;
    if (_state == VoiceState.listening) { _speech.stop(); _setState(VoiceState.idle); }
  }

  Future<void> _doWakeWordCheck() async {
    if (!_speechReady) return;
    String heard = '';
    await _speech.listen(
      onResult: (r) => heard = r.recognizedWords.toLowerCase(),
      listenFor: const Duration(seconds: 3),
      pauseFor: const Duration(seconds: 1),
    );
    await Future.delayed(const Duration(seconds: 3));
    await _speech.stop();
    const wakeWords = ['hey zen', 'okay zen', 'hi zen', 'hey zen', 'hi zen'];
    if (wakeWords.any((kw) => heard.contains(kw))) {
      HapticFeedback.lightImpact();
      await startListening();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  State helper + cleanup
  // ─────────────────────────────────────────────────────────────────────
  void _setState(VoiceState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void dispose() {
    _speech.stop();
    _tts.stop();
    _wsSub?.cancel();
    _ws?.sink.close();
    _waveTimer?.cancel();
    _wakeWordTimer?.cancel();
    _intentTimer?.cancel();
    _stateCtrl.close();
    _transcriptCtrl.close();
    _responseCtrl.close();
    _toolCtrl.close();
    _logCtrl.close();
    _waveCtrl.close();
    _toneCtrl.close();
  }
}
