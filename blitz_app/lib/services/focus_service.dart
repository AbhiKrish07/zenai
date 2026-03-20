import 'dart:async';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../core/notifications.dart';
import '../core/database.dart';
import '../models/study_session.dart';

class FocusService {
  static final FocusService _instance = FocusService._internal();
  factory FocusService() => _instance;
  FocusService._internal() {
    ZenNotifications().onStopFocus = stopFocus;
  }

  static const _focusChannel = MethodChannel('com.zen/focus');

  bool _isRunning = false;
  int _secondsRemaining = 0;
  String _subject = 'Deep Work';
  Timer? _timer;
  DateTime? _startTime;

  final _updateController = StreamController<void>.broadcast();
  Stream<void> get onUpdate => _updateController.stream;

  final _completeController = StreamController<void>.broadcast();
  Stream<void> get onComplete => _completeController.stream;

  bool get isRunning => _isRunning;
  int get secondsRemaining => _secondsRemaining;
  String get subject => _subject;

  final Map<String, String> _socialNames = {
    'com.instagram.android': 'Instagram',
    'com.twitter.android': 'X (Twitter)',
    'com.zhiliaoapp.musically': 'TikTok',
    'com.facebook.katana': 'Facebook',
    'com.snapchat.android': 'Snapchat',
    'com.reddit.frontpage': 'Reddit',
    'com.linkedin.android': 'LinkedIn',
    'com.pinterest': 'Pinterest',
    'com.whatsapp': 'WhatsApp',
    'org.telegram.messenger': 'Telegram',
    'com.discord': 'Discord',
  };

  void startFocus(int minutes, String subject) {
    _isRunning = true;
    _subject = subject;
    _secondsRemaining = minutes * 60;
    _startTime = DateTime.now();
    
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
        _updateController.add(null);
        
        // Push update to system notification every second for "Live Activity" feel
        _updateNotification();
      } else {
        _completeController.add(null);
        stopFocus();
      }
    });

    _focusChannel.invokeMethod('setFocusMode', {
      'active': true,
      'blocked': _socialNames.keys.toList(),
    });

    _updateNotification();
    _updateController.add(null);
  }

  void _updateNotification() {
    ZenNotifications().showFocusNotification(
      secondsRemaining: _secondsRemaining,
      subject: _subject,
    );
  }

  void stopFocus() async {
    if (!_isRunning) return;
    
    // Calculate elapsed time and save session
    if (_startTime != null) {
      final elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
      final durationMinutes = (elapsedSeconds / 60).round();
      if (durationMinutes >= 1) {
        final session = StudySession(
          id: const Uuid().v4(),
          subject: _subject,
          durationMinutes: durationMinutes,
          startedAt: _startTime!,
          endedAt: DateTime.now(),
        );
        await ZenDatabase().insertStudySession(session);
      }
    }

    _isRunning = false;
    _startTime = null;
    _timer?.cancel();
    _focusChannel.invokeMethod('setFocusMode', {'active': false});
    ZenNotifications().cancelFocusNotification();
    _updateController.add(null);
  }
}
