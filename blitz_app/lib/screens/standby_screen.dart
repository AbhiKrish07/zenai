import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../theme.dart';
import '../services/notification_service.dart';
import '../services/spotify_service.dart';
import '../core/zen_brain.dart';
import '../models/task.dart';
import '../models/event.dart';
import '../core/database.dart';
import 'package:uuid/uuid.dart';

class StandbyScreen extends StatefulWidget {
  const StandbyScreen({super.key});

  @override
  State<StandbyScreen> createState() => _StandbyScreenState();
}

class _StandbyScreenState extends State<StandbyScreen>
    with TickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────
  final _notifService = AppNotificationService();
  final _spotify = SpotifyService();
  final _brain = ZenBrain();
  final _db = ZenDatabase();

  // ── State ─────────────────────────────────────────────────────────
  DateTime _now = DateTime.now();
  List<ServiceNotificationEvent> _notifs = [];
  Map<String, dynamic>? _track;
  bool _showSearch = false;
  bool _spotifyConnected = false;
  String _searchQuery = '';
  String _searchResult = '';
  bool _searching = false;
  ServiceNotificationEvent? _selectedNotif;
  String _replyText = '';
  bool _replying = false;
  final _searchCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();

  // STT & TTS State
  bool _voiceMode = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _speechEnabled = false;
  bool _showSpotify = true;
  bool _isSpeaking = false;
  double _soundLevel = 0.0;

  // Ambient customization
  Color _ambientColor = BlitzTheme.accent;
  String _clockStyle = 'serif'; // serif, mono, minimal
  static const List<Color> _ambientColors = [
    BlitzTheme.accent,
    Color(0xFF7C3AED), // purple
    Color(0xFF0EA5E9), // sky blue
    Color(0xFF10B981), // emerald
    Color(0xFFF59E0B), // amber
    Color(0xFFEC4899), // pink
    Color(0xFFFFFFFF), // white
  ];

  // ── Timers ────────────────────────────────────────────────────────
  Timer? _clockTimer;
  Timer? _spotifyTimer;
  late AnimationController _pulseAnim;
  late AnimationController _discAnim;
  Timer? _silenceTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _initSpeech();

    _loadAmbientPrefs();

    // Pulse animation
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Spotify Disc animation
    _discAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    // Clock tick
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    // Spotify polling
    _spotifyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshSpotify();
    });
    _refreshSpotify();

    // Notification stream
    _notifService.startListening().then((_) {
      _notifService.stream.listen((notifs) {
        if (mounted) setState(() => _notifs = notifs);
      });
      setState(() => _notifs = _notifService.notifications);
    });
  }

  void _initSpeech() async {
    _speechEnabled = await _speech.initialize(
      onError: (val) => debugPrint('STT Error: $val'),
      onStatus: (val) {
        if (val == 'notListening' && _voiceMode) {
          setState(() => _voiceMode = false);
          if (_searchQuery.trim().isNotEmpty) {
            _doSearch();
          }
        }
      },
    );

    // Initialize TTS
    await _tts.setLanguage('en-US');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
    _tts.setErrorHandler((_) => setState(() => _isSpeaking = false));
  }

  void _listen() async {
    if (!_speechEnabled) {
      bool available = await _speech.initialize();
      if (!available) return;
      _speechEnabled = true;
    }
    
    if (_voiceMode) {
      _silenceTimer?.cancel();
      _speech.stop();
      setState(() => _voiceMode = false);
      if (_searchQuery.trim().isNotEmpty) {
        _doSearch();
      }
    } else {
      // Stop AI if it was speaking (Interruption logic)
      if (_isSpeaking) await _tts.stop();

      setState(() {
        _voiceMode = true;
        _showSearch = true; 
        _searchCtrl.text = '';
        _searchQuery = '';
      });
      _speech.listen(
        onResult: (val) {
          if (mounted) {
            setState(() {
              _searchQuery = val.recognizedWords;
              _searchCtrl.text = _searchQuery;
            });
            
            // Neural Interruption: Instantly stop AI speech if user starts talking
            if (_isSpeaking && val.recognizedWords.isNotEmpty) {
              _tts.stop();
              setState(() => _isSpeaking = false);
            }

            // Neural Gap Detection: 2-second silence auto-send
            _silenceTimer?.cancel();
            _silenceTimer = Timer(const Duration(milliseconds: 2000), () {
               if (_voiceMode && _searchQuery.trim().isNotEmpty) {
                  _doSearch();
               }
            });
          }
        },
        onSoundLevelChange: (level) {
          if (mounted) setState(() => _soundLevel = level);
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          onDevice: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _clockTimer?.cancel();
    _spotifyTimer?.cancel();
    _pulseAnim.dispose();
    _discAnim.dispose();
    _searchCtrl.dispose();
    _replyCtrl.dispose();
    _silenceTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshSpotify() async {
    final t = await _spotify.getCurrentTrack();
    if (mounted) {
      setState(() {
        _track = t;
        _spotifyConnected = _spotify.isConnected;
        
        if (t != null && t['is_playing'] == true) {
          if (!_discAnim.isAnimating) _discAnim.repeat();
        } else {
          _discAnim.stop();
        }
      });
    }
  }

  Future<void> _doSearch() async {
    if (_searchQuery.trim().isEmpty) return;
    
    // Neural Stop if speaking
    if (_isSpeaking) await _tts.stop();
    _silenceTimer?.cancel();
    _speech.stop();

    setState(() {
      _searching = true;
      _voiceMode = false;
      _searchResult = '';
      _soundLevel = 0.0;
    });
    
    final result = await _brain.chat(
      'Search/research this briefly and conversationally: ${_searchQuery.trim()}',
    );
    
    if (mounted) {
      String processedResult = result;
      final cmdRegex = RegExp(r'<CMD>(.*?)</CMD>', dotAll: true);
      final matches = cmdRegex.allMatches(result);

      if (matches.isNotEmpty) {
        for (final match in matches) {
          final commandBlock = match.group(1);
          if (commandBlock != null) {
            await _processCommand(commandBlock.trim());
            processedResult = processedResult.replaceAll('<CMD>$commandBlock</CMD>', '').trim();
          }
        }
      }

      setState(() {
        _searching = false;
        _searchResult = processedResult;
      });
      
      // Advanced Voice Mode Lifecycle: Automated completion and re-engagement
      _tts.setCompletionHandler(() {
        if (mounted) {
          setState(() => _isSpeaking = false);
          // Mirror ChatGPT: Automatically start listening for the next query
          _listen();
        }
      });
      _tts.setErrorHandler((_) => setState(() => _isSpeaking = false));

      if (processedResult.isNotEmpty) {
        setState(() => _isSpeaking = true);
        await _tts.speak(processedResult);
      }
    }
  }

  Future<void> _processCommand(String cmd) async {
    const uuid = Uuid();
    if (cmd.startsWith('create_task:')) {
      final payload = cmd.substring('create_task:'.length).trim();
      final components = payload.split('|');
      if (components.isNotEmpty) {
        String pRaw = components.length > 1 ? components[1].toLowerCase().trim() : 'medium';
        String p = 'medium';
        if (pRaw == '3' || pRaw.contains('high')) { p = 'high'; }
        else if (pRaw == '1' || pRaw.contains('low')) { p = 'low'; }
        await _db.insertTask(Task(title: components[0], priority: p, description: components.length > 2 ? components[2] : ''));
      }
    } else if (cmd.startsWith('create_event:')) {
      final components = cmd.substring('create_event:'.length).trim().split('|');
      if (components.isNotEmpty) {
        await _db.insertEvent(CalendarEvent(id: uuid.v4(), title: components[0], startTime: DateTime.tryParse(components[1]) ?? DateTime.now(), endTime: DateTime.tryParse(components[2]) ?? DateTime.now().add(const Duration(hours: 1)), description: components.length > 3 ? components[3] : '', createdAt: DateTime.now()));
      }
    } else if (cmd.startsWith('system:volume:')) {
      // Basic feedback since we don't have direct vol control in pure flutter yet without deps
      debugPrint('[Zen] CMD: Volume Adjust: $cmd');
    } else if (cmd.startsWith('reply_notif:')) {
       final payload = cmd.substring('reply_notif:'.length).trim().split('|');
       if (payload.length == 2) {
         final notif = AppNotificationService().notifications.firstWhere((n) => AppNotificationService().friendlyApp(n.packageName).toLowerCase().contains(payload[0].toLowerCase()), orElse: () => throw 'Notif not found');
         await AppNotificationService().replyTo(notif, payload[1]);
       }
    }
  }

  Future<void> _doReply(ServiceNotificationEvent notif) async {
    if (_replyText.trim().isEmpty) return;
    setState(() => _replying = true);

    String messageToSend = _replyText.trim();

    // If user typed "ai", let Zen draft the reply first
    if (messageToSend.toLowerCase() == 'ai') {
      final draft = await _brain.chat(
        'Draft a short, natural reply to this notification from ${notif.title ?? 'someone'}: "${notif.content}". Just the reply text, nothing else.',
      );
      _replyCtrl.text = draft;
      setState(() {
        _replyText = draft;
        _replying = false;
      });
      return;
    }

    // Attempt real DirectReply
    bool sent = false;
    if (notif.canReply == true) {
      sent = await _notifService.replyTo(notif, messageToSend);
    }

    setState(() {
      _replying = false;
      _selectedNotif = null;
      _replyCtrl.clear();
      _replyText = '';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Reply sent!'
                : notif.canReply == true
                    ? 'Failed to send reply.'
                    : 'This notification doesn\'t support direct reply.',
            style: GoogleFonts.spaceMono(),
          ),
          backgroundColor: sent ? BlitzTheme.green : Colors.orange.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_showSearch) {
            setState(() {
              _showSearch = false;
              _searchResult = '';
              _searchCtrl.clear();
            });
          }
          if (_selectedNotif != null) {
            setState(() => _selectedNotif = null);
          }
        },
        child: Stack(
          children: [
            // ── Background ambient glow ──────────────────────────────
            _buildAmbientBg(),
            // ── Main content ─────────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  // Top bar — close button
                  _buildTopBar(),
                  const Spacer(),
                  // Clock
                  _buildClock(),
                  const SizedBox(height: 8),
                  // Date
                  _buildDate(),
                  const Spacer(),
                  // Notifications
                  if (_notifs.isNotEmpty) _buildNotifStrip(),
                  // Spotify
                  if (_spotifyConnected && _track != null && _showSpotify) _buildSpotifyBar(),
                  // Search bar
                  _buildSearchBar(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            // ── Notification detail overlay ───────────────────────────
            if (_selectedNotif != null) _buildNotifDetail(),
            // ── Search result overlay ─────────────────────────────────
            if (_searchResult.isNotEmpty) _buildSearchResult(),
            // ── Advanced Voice Interface ──────────────────────────────
            if (_voiceMode || _isSpeaking || _searching) _buildAdvancedVoiceOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedVoiceOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.9),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                // Advanced Glow Animation
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: _soundLevel),
                  duration: const Duration(milliseconds: 100),
                  builder: (context, value, child) {
                    return Container(
                      width: 200 + (value * 100),
                      height: 200 + (value * 100),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: _ambientColor.withValues(alpha: 0.2), blurRadius: 40 + (value * 20), spreadRadius: 10 + (value * 10)),
                          BoxShadow(color: Colors.white.withValues(alpha: 0.05), blurRadius: 20, spreadRadius: 0),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Icon(_isSpeaking ? Icons.graphic_eq_rounded : Icons.mic_rounded, color: Colors.white, size: 32),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 60),
                Text(
                  _searching ? 'ZEN IS THINKING…' : _isSpeaking ? 'ZEN IS SPEAKING…' : 'I\'m Listening…',
                  style: GoogleFonts.spaceMono(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 3),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _searchQuery.isEmpty ? 'Talk to me...' : _searchQuery.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(fontSize: 18, color: Colors.white60, height: 1.5, fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 80),
                IconButton(
                  onPressed: () {
                    _tts.stop();
                    _speech.stop();
                    setState(() { _voiceMode = false; _isSpeaking = false; _searching = false; });
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withValues(alpha: 0.1), border: Border.all(color: Colors.red.withValues(alpha: 0.2))),
                    child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 32),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Ambient Background ─────────────────────────────────────────────
  Widget _buildAmbientBg() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.2,
            colors: [
              _ambientColor
                  .withValues(alpha: 0.05 + _pulseAnim.value * 0.04),
              const Color(0xFF020308),
            ],
          ),
        ),
      ),
    );
  }

  // ── Load/save ambient prefs ─────────────────────────────────────────
  Future<void> _loadAmbientPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final colorIdx = prefs.getInt('ambient_color_idx') ?? 0;
    final clock = prefs.getString('ambient_clock_style') ?? 'serif';
    if (mounted) {
      setState(() {
        _ambientColor = _ambientColors[colorIdx.clamp(0, _ambientColors.length - 1)];
        _clockStyle = clock;
      });
    }
  }

  Future<void> _saveAmbientPrefs(int colorIdx, String clockStyle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ambient_color_idx', colorIdx);
    await prefs.setString('ambient_clock_style', clockStyle);
  }

  void _showAmbientSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.white.withValues(alpha: 0.2)),
              )),
              const SizedBox(height: 20),
              Text('AMBIENT MODE', style: GoogleFonts.spaceMono(color: _ambientColor, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              Text('GLOW COLOR', style: GoogleFonts.spaceMono(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              Row(
                children: _ambientColors.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final col = entry.value;
                  final sel = col == _ambientColor;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        ss(() {});
                        setState(() => _ambientColor = col);
                        _saveAmbientPrefs(idx, _clockStyle);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: col.withValues(alpha: sel ? 0.3 : 0.1),
                          border: Border.all(color: col.withValues(alpha: sel ? 0.9 : 0.3), width: sel ? 2 : 1),
                        ),
                        child: sel ? Center(child: Icon(Icons.check_rounded, size: 14, color: col)) : const SizedBox(),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Text('CLOCK STYLE', style: GoogleFonts.spaceMono(color: Colors.white38, fontSize: 9, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  {'id': 'serif', 'label': 'Classic', 'preview': '12:00'},
                  {'id': 'mono', 'label': 'Digital', 'preview': '12:00'},
                  {'id': 'minimal', 'label': 'Minimal', 'preview': '12:00'},
                ].map((style) {
                  final sel = _clockStyle == style['id'];
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        ss(() {});
                        setState(() => _clockStyle = style['id']!);
                        _saveAmbientPrefs(
                          _ambientColors.indexOf(_ambientColor),
                          style['id']!,
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: sel ? _ambientColor.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.04),
                          border: Border.all(color: sel ? _ambientColor.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              style['preview']!,
                              style: style['id'] == 'serif'
                                  ? GoogleFonts.playfairDisplay(fontSize: 18, color: Colors.white)
                                  : style['id'] == 'mono'
                                      ? GoogleFonts.spaceMono(fontSize: 16, color: Colors.white)
                                      : const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w100, letterSpacing: -1),
                            ),
                            const SizedBox(height: 4),
                            Text(style['label']!, style: GoogleFonts.spaceMono(color: sel ? _ambientColor : Colors.white38, fontSize: 8)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Spotify connect button if not connected
          if (!_spotifyConnected)
            GestureDetector(
              onTap: _showSpotifyTokenDialog,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF1DB954).withValues(alpha: 0.5)),
                ),
                child: Row(children: [
                  const Icon(Icons.music_note,
                      size: 14, color: Color(0xFF1DB954)),
                  const SizedBox(width: 6),
                  Text('Connect Spotify',
                      style: GoogleFonts.spaceMono(
                          fontSize: 10, color: const Color(0xFF1DB954))),
                ]),
              ),
            ),
          const Spacer(),
          // Ambient settings button
          GestureDetector(
            onTap: _showAmbientSettings,
            child: Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _ambientColor.withValues(alpha: 0.08),
              ),
              child: Icon(Icons.palette_outlined, size: 16, color: _ambientColor.withValues(alpha: 0.7)),
            ),
          ),
          // Close standby
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 18, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  // ── Clock ──────────────────────────────────────────────────────────
  Widget _buildClock() {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    final second = _now.second.toString().padLeft(2, '0');

    TextStyle mainStyle;
    if (_clockStyle == 'mono') {
      mainStyle = GoogleFonts.spaceMono(
        fontSize: 72,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.92),
        height: 1.0,
        letterSpacing: -2,
      );
    } else if (_clockStyle == 'minimal') {
      mainStyle = TextStyle(
        fontSize: 84,
        fontWeight: FontWeight.w100,
        color: Colors.white.withValues(alpha: 0.88),
        height: 1.0,
        letterSpacing: -6,
      );
    } else {
      mainStyle = GoogleFonts.playfairDisplay(
        fontSize: 96,
        fontWeight: FontWeight.w400,
        color: Colors.white.withValues(alpha: 0.92),
        height: 1.0,
        letterSpacing: -4,
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$hour:$minute',
              style: mainStyle,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14, left: 4),
              child: Text(
                second,
                style: GoogleFonts.spaceMono(
                  fontSize: 18,
                  color: _ambientColor.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Date ───────────────────────────────────────────────────────────
  Widget _buildDate() {
    final days = [
      'Sunday', 'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday'
    ];
    final months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final label =
        '${days[_now.weekday % 7]}, ${months[_now.month]} ${_now.day}';

    return Text(
      label,
      style: GoogleFonts.syne(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: Colors.white.withValues(alpha: 0.35),
        letterSpacing: 2,
      ),
    );
  }

  // ── Notification Strip ─────────────────────────────────────────────
  Widget _buildNotifStrip() {
    final visible = _notifs.take(5).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '${_notifs.length} NOTIFICATION${_notifs.length > 1 ? 'S' : ''}',
              style: GoogleFonts.spaceMono(
                fontSize: 9,
                color: Colors.white30,
                letterSpacing: 2,
              ),
            ),
          ),
          ...visible.map((n) => _buildNotifCard(n)),
        ],
      ),
    );
  }

  Widget _buildNotifCard(ServiceNotificationEvent n) {
    final app = _notifService.friendlyApp(n.packageName);
    final icon = _appIcon(n.packageName);

    return GestureDetector(
      onTap: () => setState(() => _selectedNotif = n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: icon.$2.withValues(alpha: 0.12),
              ),
              child: Icon(icon.$1, size: 16, color: icon.$2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title ?? app,
                    style: GoogleFonts.syne(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    n.content ?? '',
                    style: GoogleFonts.spaceMono(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              app,
              style: GoogleFonts.spaceMono(
                fontSize: 8,
                color: icon.$2.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Spotify Widget ───────────────────────────────────────────────────
  Widget _buildSpotifyBar() {
    final t = _track!;
    final isPlaying = t['is_playing'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF090909),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: Drag dots & close
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 20), // Balance the close icon
              // Drag Handle dots 4x2
              Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(4, (i) => _dot()),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(4, (i) => _dot()),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _showSpotify = false);
                },
                child: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Middle row: Album Art + Track Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.grey.shade900,
                  image: t['album_art'] != null
                      ? DecorationImage(
                          image: NetworkImage(t['album_art']),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t['title'] ?? 'Unknown',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t['artist'] ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Bottom row: Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _spotifyIconBtn(Icons.add_circle_outline_rounded, () {}),
              _spotifyIconBtn(Icons.shuffle_rounded, () {}),
              _spotifyIconBtn(Icons.skip_previous_rounded, () => _spotify.previous()),
              // Play/pause button (White circle)
              GestureDetector(
                onTap: () async {
                  isPlaying ? await _spotify.pause() : await _spotify.play();
                  _refreshSpotify();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 26,
                  ),
                ),
              ),
              _spotifyIconBtn(Icons.skip_next_rounded, () => _spotify.next()),
              _spotifyIconBtn(Icons.repeat_rounded, () {}),
              _spotifyIconBtn(Icons.volume_up_rounded, () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot() {
    return Container(
      width: 2.5,
      height: 2.5,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _spotifyIconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.65)),
      ),
    );
  }

  // ── Search / Input Bar ─────────────────────────────────────────────
  Widget _buildSearchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: const Color(0xFF0A0A0F),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          // Voice Button
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              _listen();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _voiceMode
                    ? BlitzTheme.red.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.04),
                border: Border.all(
                  color: _voiceMode ? BlitzTheme.red : Colors.transparent,
                ),
              ),
              child: Icon(
                _voiceMode ? Icons.mic_rounded : Icons.mic_none_rounded,
                size: 20,
                color: _voiceMode ? BlitzTheme.red : Colors.white54,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Expanded Text Field
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.syne(fontSize: 14, color: Colors.white.withValues(alpha: 0.9)),
              decoration: InputDecoration(
                hintText: 'Ask Zen, Voice, or Search...',
                hintStyle: GoogleFonts.syne(fontSize: 14, color: Colors.white.withValues(alpha: 0.3)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) => _searchQuery = v,
              onSubmitted: (_) {
                _doSearch();
                FocusScope.of(context).unfocus();
              },
            ),
          ),
          // Send / Action Arrow
          if (_searching || _voiceMode)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: BlitzTheme.accent),
              ),
            )
          else
            GestureDetector(
              onTap: () {
                if (_searchQuery.trim().isNotEmpty) {
                  _doSearch();
                  FocusScope.of(context).unfocus();
                } else {
                  FocusScope.of(context).requestFocus();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _searchQuery.trim().isNotEmpty
                      ? BlitzTheme.accent
                      : Colors.white.withValues(alpha: 0.04),
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 16,
                  color: _searchQuery.trim().isNotEmpty ? Colors.white : Colors.white30,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Search Result Overlay ──────────────────────────────────────────
  Widget _buildSearchResult() {
    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () {}, // stop tap-through
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF0D0E1A),
            border: Border.all(color: BlitzTheme.accent.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 14, color: BlitzTheme.accent),
                  const SizedBox(width: 6),
                  Text(
                    _searchQuery,
                    style: GoogleFonts.spaceMono(
                        fontSize: 10,
                        color: BlitzTheme.accent.withValues(alpha: 0.7)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _searchResult = ''),
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.white30),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _searchResult,
                style: GoogleFonts.syne(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Notification Detail Overlay ────────────────────────────────────
  Widget _buildNotifDetail() {
    final n = _selectedNotif!;
    final app = _notifService.friendlyApp(n.packageName);

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _selectedNotif = null),
        child: Container(
          color: Colors.black54,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // stop close
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: const Color(0xFF0D0E1A),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App name + icon
                    Row(
                      children: [
                        Icon(
                          _appIcon(n.packageName).$1,
                          size: 18,
                          color: _appIcon(n.packageName).$2,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          app.toUpperCase(),
                          style: GoogleFonts.spaceMono(
                            fontSize: 10,
                            color: _appIcon(n.packageName)
                                .$2
                                .withValues(alpha: 0.8),
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _selectedNotif = null),
                          child: const Icon(Icons.close,
                              size: 18, color: Colors.white30),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      n.title ?? 'Notification',
                      style: GoogleFonts.syne(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      n.content ?? '',
                      style: GoogleFonts.spaceMono(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Reply box
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyCtrl,
                              style: GoogleFonts.syne(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.9)),
                              decoration: InputDecoration(
                                hintText:
                                    'Type reply or "ai" for AI draft…',
                                hintStyle: GoogleFonts.syne(
                                    fontSize: 12,
                                    color:
                                        Colors.white.withValues(alpha: 0.3)),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (v) => _replyText = v,
                            ),
                          ),
                          _replying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: BlitzTheme.accent))
                              : GestureDetector(
                                  onTap: () => _doReply(n),
                                  child: const Icon(
                                      Icons.send_rounded,
                                      size: 18,
                                      color: BlitzTheme.accent),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tip: type "ai" to have Zen draft the reply',
                      style: GoogleFonts.spaceMono(
                          fontSize: 9,
                          color: BlitzTheme.accent.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Spotify Token Dialog ───────────────────────────────────────────
  void _showSpotifyTokenDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: BlitzTheme.surface,
        title: Text('Spotify Access Token',
            style: GoogleFonts.syne(
                color: Colors.white, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Go to open.spotify.com/get_access_token, copy the access token and paste it here.',
              style: GoogleFonts.spaceMono(
                  fontSize: 10, color: Colors.white54, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: GoogleFonts.spaceMono(
                  fontSize: 11, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'BQA...',
                hintStyle: GoogleFonts.spaceMono(
                    color: Colors.white24, fontSize: 11),
                filled: true,
                fillColor: const Color(0xFF04050A),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _spotify.setToken(ctrl.text.trim());
              setState(() => _spotifyConnected = true);
              Navigator.pop(c);
              _refreshSpotify();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954)),
            child: const Text('Connect',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── App Icon Mapping ───────────────────────────────────────────────
  (IconData, Color) _appIcon(String? pkg) {
    final map = <String, (IconData, Color)>{
      'com.whatsapp': (Icons.chat_bubble_rounded, const Color(0xFF25D366)),
      'com.instagram.android': (Icons.camera_alt_rounded, const Color(0xFFE1306C)),
      'com.google.android.gm': (Icons.email_rounded, const Color(0xFFEA4335)),
      'com.twitter.android': (Icons.alternate_email, const Color(0xFF1DA1F2)),
      'com.snapchat.android': (Icons.camera_rounded, const Color(0xFFFFFC00)),
      'com.discord': (Icons.headset_mic_rounded, const Color(0xFF5865F2)),
      'com.slack': (Icons.tag, const Color(0xFF4A154B)),
      'com.spotify.music': (Icons.music_note, const Color(0xFF1DB954)),
    };
    return map[pkg] ??
        (Icons.notifications_rounded, BlitzTheme.accent);
  }
}
