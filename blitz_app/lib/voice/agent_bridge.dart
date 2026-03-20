import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import 'zen_voice_engine.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  AGENT BRIDGE  —  ClawdBot Layer
//
//  WebSocket client connecting the Flutter app to the FastAPI + LangGraph
//  backend running Claude claude-sonnet-4-6.
//
//  Features:
//   • Persistent WS connection with exponential backoff reconnect
//   • Streaming response chunks (token-by-token)
//   • Tool call lifecycle events (start / progress / done)
//   • Agentic task dispatch — sends goal, backend breaks into subtasks
//   • Self-correction signals — backend retries are surfaced here
//   • Memory sync (short-term session + long-term signals)
//   • Screen context injection — app + route info sent with each query
//   • Proactive suggestion stream — backend pushes suggestions unprompted
// ═══════════════════════════════════════════════════════════════════════════

enum AgentTaskStatus { pending, running, done, failed }

class AgentTask {
  final String id;
  final String goal;
  final List<String> subtasks;
  AgentTaskStatus status;
  String? result;
  int retryCount;

  AgentTask({
    required this.id,
    required this.goal,
    required this.subtasks,
    this.status = AgentTaskStatus.pending,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'goal': goal,
    'subtasks': subtasks,
    'status': status.name,
    'retry_count': retryCount,
  };
}

class AgentBridge with ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final AgentBridge _instance = AgentBridge._internal();
  factory AgentBridge() => _instance;
  AgentBridge._internal();

  // ── WS connection ──────────────────────────────────────────────────────
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  bool _connected  = false;
  int  _retryDelay = 2;   // seconds, exponential backoff
  Timer? _retryTimer;
  Timer? _pingTimer;

  bool get isConnected => _connected;

  // ── State ──────────────────────────────────────────────────────────────
  final String _sessionId  = _generateSessionId();
  final List<AgentTask> _tasks = [];
  final List<String> _proactiveSuggestions = [];

  List<AgentTask> get activeTasks => _tasks
      .where((t) => t.status == AgentTaskStatus.running ||
                    t.status == AgentTaskStatus.pending)
      .toList();
  List<String> get suggestions => List.from(_proactiveSuggestions);

  // ── Screen context ─────────────────────────────────────────────────────
  Map<String, dynamic> _screenContext = {};

  // ── Streams ───────────────────────────────────────────────────────────
  final _responseCtrl    = StreamController<String>.broadcast();
  final _toolCtrl        = StreamController<Map<String, dynamic>>.broadcast();
  final _taskCtrl        = StreamController<AgentTask>.broadcast();
  final _suggestionCtrl  = StreamController<String>.broadcast();
  final _connectionCtrl  = StreamController<bool>.broadcast();
  final _errorCtrl       = StreamController<String>.broadcast();

  Stream<String>             get responseStream   => _responseCtrl.stream;
  Stream<Map<String, dynamic>> get toolStream     => _toolCtrl.stream;
  Stream<AgentTask>          get taskStream        => _taskCtrl.stream;
  Stream<String>             get suggestionStream  => _suggestionCtrl.stream;
  Stream<bool>               get connectionStream  => _connectionCtrl.stream;
  Stream<String>             get errorStream       => _errorCtrl.stream;

  // ── Debug ──────────────────────────────────────────────────────────────
  final List<String> _log = [];
  List<String> get debugLog => List.from(_log);
  void _addLog(String s) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _log.add('[$ts] $s');
    if (_log.length > 80) _log.removeAt(0);
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Connect / Disconnect
  // ─────────────────────────────────────────────────────────────────────
  void connect() {
    if (_connected) return;
    _tryConnect();
  }

  void _tryConnect() {
    try {
      final uri = Uri.parse('${BlitzConfig.wsUrl}/ws/agent');
      _ws = IOWebSocketChannel.connect(uri,
        connectTimeout: const Duration(seconds: 8),
        headers: {
          'X-Session-Id': _sessionId,
          'X-App-Version': '4.0.0',
        },
      );
      _wsSub = _ws!.stream.listen(
        _onMessage,
        onError: (e) {
          _addLog('WS error: $e');
          _setConnected(false);
          _scheduleReconnect();
        },
        onDone: () {
          _addLog('WS closed');
          _setConnected(false);
          _scheduleReconnect();
        },
      );
      _setConnected(true);
      _retryDelay = 2;
      _startPing();
      // Send initial context
      _sendScreenContext();
      _addLog('Connected to agent @ ${uri.host}');
    } catch (e) {
      _addLog('Connect failed: $e');
      _setConnected(false);
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    _wsSub?.cancel();
    _ws?.sink.close();
    _setConnected(false);
  }

  void _scheduleReconnect() {
    _retryTimer?.cancel();
    _addLog('Reconnect in ${_retryDelay}s');
    _retryTimer = Timer(Duration(seconds: _retryDelay), _tryConnect);
    _retryDelay = (_retryDelay * 2).clamp(2, 60);
  }

  void _setConnected(bool v) {
    _connected = v;
    _connectionCtrl.add(v);
    notifyListeners();
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connected && _ws != null) {
        _send({'type': 'ping'});
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Message routing
  // ─────────────────────────────────────────────────────────────────────
  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map;
      final type = data['type'] as String? ?? '';

      switch (type) {
        case 'pong':
          break;

        case 'response_chunk':
          _responseCtrl.add(data['text'] as String? ?? '');
          break;

        case 'response_done':
          _responseCtrl.add(data['text'] as String? ?? '');
          break;

        case 'tool_start':
          _toolCtrl.add({'action': 'start', 'tool': data['tool'], 'input': data['input']});
          break;

        case 'tool_done':
          _toolCtrl.add({'action': 'done', 'tool': data['tool'], 'output': data['output']});
          break;

        case 'task_created':
          final task = AgentTask(
            id: data['task_id'] as String? ?? _generateId(),
            goal: data['goal'] as String? ?? '',
            subtasks: (data['subtasks'] as List<dynamic>?)
                ?.map((s) => s.toString())
                .toList() ?? [],
            status: AgentTaskStatus.running,
          );
          _tasks.add(task);
          _taskCtrl.add(task);
          notifyListeners();
          break;

        case 'task_progress':
          final taskId = data['task_id'] as String? ?? '';
          final t = _tasks.firstWhere((t) => t.id == taskId, orElse: () =>
            AgentTask(id: taskId, goal: '', subtasks: []));
          _taskCtrl.add(t);
          break;

        case 'task_done':
          final taskId = data['task_id'] as String? ?? '';
          for (final t in _tasks) {
            if (t.id == taskId) {
              t.status = AgentTaskStatus.done;
              t.result = data['result'] as String?;
              _taskCtrl.add(t);
              break;
            }
          }
          notifyListeners();
          break;

        case 'task_retry':
          final taskId = data['task_id'] as String? ?? '';
          for (final t in _tasks) {
            if (t.id == taskId) {
              t.retryCount++;
              _taskCtrl.add(t);
              break;
            }
          }
          _addLog('Task retry: $taskId attempt ${data['attempt']}');
          break;

        case 'task_failed':
          final taskId = data['task_id'] as String? ?? '';
          for (final t in _tasks) {
            if (t.id == taskId) {
              t.status = AgentTaskStatus.failed;
              _taskCtrl.add(t);
              break;
            }
          }
          _errorCtrl.add('Task failed: ${data['reason']}');
          break;

        case 'suggestion':
          final s = data['text'] as String? ?? '';
          if (s.isNotEmpty) {
            _proactiveSuggestions.insert(0, s);
            if (_proactiveSuggestions.length > 10) _proactiveSuggestions.removeLast();
            _suggestionCtrl.add(s);
            notifyListeners();
          }
          break;

        case 'memory_saved':
          _addLog('Memory: ${data['key']}');
          break;

        case 'error':
          final msg = data['message'] as String? ?? 'Unknown error';
          _errorCtrl.add(msg);
          _addLog('Error: $msg');
          break;
      }
    } catch (e) {
      _addLog('Parse error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Public API — sending to backend
  // ─────────────────────────────────────────────────────────────────────

  /// Send a voice query with full context
  void sendVoiceQuery({
    required String text,
    required bool isCommand,
    required String intent,
    required VoiceTone tone,
    String? rawTranscript,
  }) {
    _send({
      'type':       'zen_query',
      'session_id': _sessionId,
      'text':       text,
      'is_command': isCommand,
      'intent':     intent,
      'tone':       tone.name,
      'raw':        rawTranscript ?? text,
      'context':    _screenContext,
    });
  }

  /// Dispatch an autonomous multi-step goal to the LangGraph agent
  Future<String> dispatchGoal(String goal) async {
    final taskId = _generateId();
    _send({
      'type':       'dispatch_goal',
      'session_id': _sessionId,
      'task_id':    taskId,
      'goal':       goal,
      'context':    _screenContext,
    });
    _addLog('Goal dispatched: $goal');
    return taskId;
  }

  /// Cancel an in-progress task
  void cancelTask(String taskId) {
    _send({'type': 'cancel_task', 'task_id': taskId});
    for (final t in _tasks) {
      if (t.id == taskId) {
        t.status = AgentTaskStatus.failed;
        _taskCtrl.add(t);
        break;
      }
    }
    notifyListeners();
  }

  /// Update screen context (called by ScreenContextReader)
  void updateScreenContext({
    required String appName,
    required String routeName,
    Map<String, dynamic>? extra,
  }) {
    _screenContext = {
      'app':       appName,
      'route':     routeName,
      'time':      DateTime.now().toIso8601String(),
      'day':       _dayName(DateTime.now().weekday),
      ...?extra,
    };
    _sendScreenContext();
  }

  void _sendScreenContext() {
    if (!_connected || _screenContext.isEmpty) return;
    _send({
      'type':    'context_update',
      'context': _screenContext,
    });
  }

  /// Send a text message directly (typed or programmatic)
  void sendText(String text) {
    _send({
      'type':       'chat_message',
      'session_id': _sessionId,
      'text':       text,
      'context':    _screenContext,
    });
  }

  /// Ask backend to generate proactive suggestions
  void requestSuggestions() {
    _send({
      'type':    'get_suggestions',
      'context': _screenContext,
    });
  }

  void _send(Map<String, dynamic> data) {
    if (!_connected || _ws == null) return;
    try {
      _ws!.sink.add(jsonEncode(data));
    } catch (e) {
      _addLog('Send error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────────────────────────────
  static String _generateSessionId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'zen_${now.toRadixString(16)}';
  }

  static String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now.toRadixString(16);
  }

  static String _dayName(int weekday) => const [
    '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ][weekday];

  @override
  void dispose() {
    disconnect();
    _responseCtrl.close();
    _toolCtrl.close();
    _taskCtrl.close();
    _suggestionCtrl.close();
    _connectionCtrl.close();
    _errorCtrl.close();
    super.dispose();
  }
}
