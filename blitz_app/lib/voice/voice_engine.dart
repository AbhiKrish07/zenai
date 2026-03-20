import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../core/zen_brain.dart';
import 'voice_state.dart';

/// ── Zen Voice Engine ─────────────────────────────────────────────────
/// Fast-path design:
///   1. On-device STT (speech_to_text) → transcript in ~200ms
///   2. Groq streaming via existing backend WS (sub-second TTFT)
///   3. System TTS for playback with optional ElevenLabs
///   4. Demo mode: canned responses, 100% testable offline
/// ────────────────────────────────────────────────────────────────────────
class VoiceEngine {
  // ── Singleton ──
  static final VoiceEngine _instance = VoiceEngine._internal();
  factory VoiceEngine() => _instance;
  VoiceEngine._internal() { _init(); }


  // ── Core services ──
  final _speech = stt.SpeechToText();
  final _tts    = FlutterTts();
  final _brain  = ZenBrain();

  // ── Demo / test mode ──
  bool _demoMode = false;
  bool get demoMode => _demoMode;
  void setDemoMode(bool v) { _demoMode = v; _addLog('Demo mode: $v'); }

  // ── State ──
  VoiceState _state = VoiceState.idle;
  VoiceState get currentState => _state;

  String _lastTranscript = '';
  String _lastResponse   = '';
  final List<String> _activeTools = [];
  bool _wakeWordEnabled  = false;
  bool _speechReady      = false;
  bool _speakEnabled     = true;

  String get lastTranscript => _lastTranscript;
  String get lastResponse   => _lastResponse;
  List<String> get activeTools => List.from(_activeTools);
  bool get wakeWordEnabled  => _wakeWordEnabled;
  bool get speakEnabled     => _speakEnabled;
  void setSpeakEnabled(bool v) => _speakEnabled = v;

  // ── Debug log (field named _entries to avoid name clash) ──
  final List<String> _entries = [];
  List<String> get debugLog => List.from(_entries);
  void _addLog(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _entries.add('[$ts] $msg');
    if (_entries.length > 50) _entries.removeAt(0);
    _logCtrl.add(List.from(_entries));
  }

  // ── Streams ──
  final _stateCtrl      = StreamController<VoiceState>.broadcast();
  final _transcriptCtrl = StreamController<String>.broadcast();
  final _responseCtrl   = StreamController<String>.broadcast();
  final _toolCtrl       = StreamController<List<String>>.broadcast();
  final _logCtrl        = StreamController<List<String>>.broadcast();

  Stream<VoiceState>    get stateStream      => _stateCtrl.stream;
  Stream<String>        get transcriptStream  => _transcriptCtrl.stream;
  Stream<String>        get responseStream    => _responseCtrl.stream;
  Stream<List<String>>  get toolStream        => _toolCtrl.stream;
  Stream<List<String>>  get logStream         => _logCtrl.stream;

  // Waveform samples (0.0–1.0, 32 bars)
  final List<double> _waveform = List.filled(32, 0.0);
  final _waveCtrl = StreamController<List<double>>.broadcast();
  Stream<List<double>> get waveformStream => _waveCtrl.stream;
  List<double> get waveform => List.from(_waveform);

  Timer? _waveTimer;
  final _rand = math.Random();

  // ── WS to backend ──
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  bool _wsConnected = false;

  // ── Wake word ──
  Timer? _wakeWordTimer;
  bool  _wakeCheckActive = false;

  // ── Intent debounce ──
  Timer? _intentTimer;

  final List<String> _commandKeywords = [
    'search', 'find', 'open', 'play', 'pause', 'stop', 'remind',
    'set timer', 'create task', 'add task', 'navigate',
    'volume', 'brightness', 'screenshot', 'what time', 'weather'
  ];

  // ─────────────────────────────────────────────────────────────────────
  //  Init
  // ─────────────────────────────────────────────────────────────────────
  Future<void> _init() async {
    _addLog('VoiceEngine init');

    _addLog('VoiceEngine initialized (lazy mode)');
    _addLog('Init complete');
  }



  // ─────────────────────────────────────────────────────────────────────
  //  WebSocket (fast Groq streaming via /ws/voice)
  // ─────────────────────────────────────────────────────────────────────
  void _connectWs() {
    if (_wsConnected) return;
    try {
      final uri = Uri.parse('${BlitzConfig.wsUrl}/ws/voice');
      _ws = WebSocketChannel.connect(uri);
      _wsConnected = true;
      _addLog('WS connected: $uri');
      _wsSub = _ws!.stream.listen(
        _onWsMessage,
        onError: (e) { _addLog('WS error: $e'); _wsConnected = false; _retryWs(); },
        onDone:  ()  { _addLog('WS closed');    _wsConnected = false; _retryWs(); },
      );
    } catch (e) {
      _addLog('WS connect failed: $e');
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
      final type = data['type'] as String?;
      switch (type) {
        case 'tool_start':
          final tool = data['tool'] as String? ?? 'tool';
          if (!_activeTools.contains(tool)) _activeTools.add(tool);
          _toolCtrl.add(List.from(_activeTools));
          _addLog('Tool start: $tool');
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
          if (_speakEnabled) speak(text);
          _addLog('Response done (${text.length} chars)');
          break;
        case 'error':
          _addLog('Backend error: ${data['message']}');
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
    _addLog('startListening');
    _connectWs(); // Connect on demand
    await _tts.stop();

    _lastTranscript = '';
    _lastResponse   = '';
    _activeTools.clear();
    _toolCtrl.add([]);
    _startWaveform();

    if (_demoMode) {
      _setState(VoiceState.listening);
      _addLog('[DEMO] Listening simulation started');
      return;
    }

    if (!_speechReady) {
       _addLog('Initializing STT/TTS hardware...');
       await _tts.setLanguage('en-US');
       _speechReady = await _speech.initialize(
         onError: (e) => _addLog('STT error: ${e.errorMsg}'),
         onStatus: (s) {
           if (s == 'notListening' && _state == VoiceState.listening) _onSpeechDone();
         },
       );
    }
    
    if (!_speechReady) {
      _addLog('STT hardware failure');
      _setState(VoiceState.error);
      Future.delayed(const Duration(seconds: 2), () => _setState(VoiceState.idle));
      return;
    }


    _speech.listen(
      onResult: (result) {
        _lastTranscript = result.recognizedWords;
        _transcriptCtrl.add(_lastTranscript);
        
        // Advanced Gap Detection: Deep-brain intent timer
        _intentTimer?.cancel();
        _intentTimer = Timer(const Duration(milliseconds: 2000), () {
          if (_state == VoiceState.listening) {
            _addLog('Natural pause detected (2s). Triggering auto-send.');
            _speech.stop();
            _onSpeechDone();
          }
        });

        if (result.finalResult) {
          _intentTimer?.cancel();
          _intentTimer = Timer(const Duration(milliseconds: 300), _onSpeechDone);
        }
      },
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 5), // Increased plugin-level pause to allow manual timer control
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onDevice: true,
        cancelOnError: false,
      ),
    );
    _setState(VoiceState.listening);
  }

  Future<void> stopListening() async {
    if (_state != VoiceState.listening) return;
    _addLog('stopListening');
    if (!_demoMode) await _speech.stop();
    _stopWaveform();
    _onSpeechDone();
  }

  /// Submit text directly — keyboard input or programmatic testing
  Future<void> submitText(String text) async {
    if (text.trim().isEmpty) return;
    _lastTranscript = text.trim();
    _lastResponse   = '';
    _transcriptCtrl.add(_lastTranscript);
    _connectWs(); // Connect on demand
    _setState(VoiceState.processing);
    _addLog('submitText: $text');

    if (_demoMode) {
      await _demoResponse(text.trim());
    } else {
      await _routeIntent(text.trim());
    }
  }

  void toggleWakeWord() {
    _wakeWordEnabled = !_wakeWordEnabled;
    _wakeWordEnabled ? _startWakeWordLoop() : _stopWakeWordLoop();
    _addLog('Wake word: $_wakeWordEnabled');
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Demo mode — simulated streaming responses (zero network required)
  // ─────────────────────────────────────────────────────────────────────
  static const List<String> _demoReplies = [
    "On it. Volume set to 50 percent.",
    "Done — Spotify paused.",
    "Reminder set for 10 minutes from now.",
    "Here's what I found: according to recent data, the answer is 42.",
    "Task created and added to your list.",
    "Brightness adjusted to 70 percent.",
    "Opening Chrome for you now.",
    "I don't have that data right now, but I can look it up — want me to search?",
    "Memory saved. I'll remember that.",
    "Short answer: it depends on context, but most likely yes.",
  ];

  Future<void> _demoResponse(String text) async {
    _addLog('[DEMO] Processing: $text');
    await Future.delayed(const Duration(milliseconds: 350)); // Simulate LLM latency

    final reply = _demoReplies[_rand.nextInt(_demoReplies.length)];
    final words = reply.split(' ');
    _lastResponse = '';

    for (int i = 0; i < words.length; i++) {
      await Future.delayed(const Duration(milliseconds: 55));
      _lastResponse += (i == 0 ? '' : ' ') + words[i];
      _responseCtrl.add(_lastResponse);
    }

    _setState(VoiceState.idle);
    _addLog('[DEMO] Response complete');
    if (_speakEnabled) speak(reply);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Intent routing (fast path: WS → ZenBrain fallback)
  // ─────────────────────────────────────────────────────────────────────
  void _onSpeechDone() {
    _stopWaveform();
    final text = _lastTranscript.trim();
    _addLog('Speech done: "$text"');
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
    final clean = lower
        .replaceFirst('hey zen', '')
        .replaceFirst('hi zen', '')
        .replaceFirst('okay zen', '')
        .trim();
    final query  = clean.isNotEmpty ? clean : text;
    final intent = _classifyIntent(lower);
    final isCmd  = _commandKeywords.any((kw) => lower.startsWith(kw));

    if (_wsConnected && _ws != null) {
      _addLog('Route → WS (intent=$intent)');
      _ws!.sink.add(jsonEncode({
        'type': 'voice_query',
        'text': query,
        'is_command': isCmd,
        'intent': intent,
      }));
    } else {
      _addLog('Route → ZenBrain (no WS)');
      try {
        final response = await _brain.chat(query);
        _lastResponse = response;
        _responseCtrl.add(response);
        _setState(VoiceState.idle);
        if (_speakEnabled) speak(response);
      } catch (e) {
        _addLog('ZenBrain error: $e');
        _setState(VoiceState.error);
        Future.delayed(const Duration(seconds: 2), () => _setState(VoiceState.idle));
      }
    }
  }

  String _classifyIntent(String text) {
    if (text.contains('remind') || text.contains('timer') || text.contains('alarm')) {
      return 'reminder';
    }
    if (text.contains('search') || text.contains('find') || text.contains('look up') ||
        text.contains('what is') || text.contains('who is')) {
      return 'search';
    }
    if (text.contains('play') || text.contains('pause') || text.contains('music') ||
        text.contains('spotify') || text.contains('skip')) {
      return 'media_control';
    }
    if (text.contains('create task') || text.contains('add task') || text.contains('todo')) {
      return 'task_create';
    }
    if (text.contains('open') || text.contains('launch')) {
      return 'open_app';
    }
    if (text.contains('volume') || text.contains('louder') || text.contains('quieter')) {
      return 'volume';
    }
    if (text.contains('brightness') || text.contains('dim') || text.contains('brighter')) {
      return 'brightness';
    }
    if (text.contains('screenshot')) {
      return 'screenshot';
    }
    if (text.contains('weather') || text.contains('temperature')) {
      return 'weather';
    }
    return 'conversation';
  }

  // ─────────────────────────────────────────────────────────────────────
  //  TTS playback
  // ─────────────────────────────────────────────────────────────────────
  Future<void> speak(String text) async {
    if (text.isEmpty || !_speakEnabled) return;
    final clean = text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'\1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'\1')
        .replaceAll(RegExp(r'#{1,6}\s'), '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'\1')
        .replaceAll('\\', ' backslash ')
        .replaceAll('/', ' slash ')
        .replaceAll('_', ' underscore ')
        .replaceAll(RegExp(r'\n+'), '. ')
        .trim();
    if (clean.isEmpty) return;
    final capped = clean.length > 400 ? '${clean.substring(0, 400)}...' : clean;
    _setState(VoiceState.speaking);
    await _tts.speak(capped);
    _setState(VoiceState.idle);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Waveform (animated amplitude bars)
  // ─────────────────────────────────────────────────────────────────────
  void _startWaveform() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      for (int i = 0; i < _waveform.length; i++) {
        final target = 0.05 + _rand.nextDouble() * 0.9;
        _waveform[i] = _waveform[i] * 0.5 + target * 0.5;
      }
      _waveCtrl.add(List.from(_waveform));
    });
  }

  void _stopWaveform() {
    _waveTimer?.cancel();
    Timer.periodic(const Duration(milliseconds: 30), (t) {
      bool done = true;
      for (int i = 0; i < _waveform.length; i++) {
        _waveform[i] *= 0.7;
        if (_waveform[i] > 0.005) done = false;
      }
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
    if (['hey zen', 'hi zen', 'okay zen'].any((kw) => heard.contains(kw))) {
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
  }
}
