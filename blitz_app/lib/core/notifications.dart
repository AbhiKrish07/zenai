import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'database.dart';
import 'zen_brain.dart';

/// Notification engine for Zen alerts
class ZenNotifications {
  static final ZenNotifications _instance = ZenNotifications._internal();
  factory ZenNotifications() => _instance;
  ZenNotifications._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _db = ZenDatabase();
  bool _initialized = false;
  Completer<void>? _initCompleter;
  VoidCallback? onStopFocus;

  Future<void> init() async {
    if (kIsWeb) return; // Native notifications not supported on Web in this bundle
    if (_initialized) return;
    if (_initCompleter != null) return _initCompleter!.future;
    
    _initCompleter = Completer<void>();
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        macOS: iosSettings,
      );

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      _initialized = true;
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('[Notifications] Init failed: $e');
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    // Handle notification tap — deep linking
    debugPrint('[Notifications] Tapped: ${response.payload}');
    
    if (response.actionId == 'stop_focus' && onStopFocus != null) {
      onStopFocus!();
    }
  }

  // ═══════════════════════════════════════
  // NOTIFICATION TYPES
  // ═══════════════════════════════════════

  Future<void> showAlert({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'zen_alerts',
      'Zen Alerts',
      channelDescription: 'Proactive alerts from Zen',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFA78BFA),
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> showMorningBriefing(String briefingText) async {
    await showAlert(
      id: 100,
      title: '☀️ Good Morning — Zen Briefing',
      body: briefingText,
      payload: 'jarvis://briefing',
    );
  }

  Future<void> showDeadlineAlert(String taskTitle, Duration timeUntil) async {
    final hours = timeUntil.inHours;
    final label = hours > 1 ? '$hours hours' : '${timeUntil.inMinutes} minutes';
    await showAlert(
      id: taskTitle.hashCode,
      title: '⏰ Deadline Alert',
      body: '"$taskTitle" is due in $label',
      payload: 'jarvis://task',
    );
  }

  Future<void> showStudyStreakReminder(int currentStreak) async {
    await showAlert(
      id: 200,
      title: '📚 Study Streak at Risk!',
      body: 'Your $currentStreak-day streak needs a session today. Even 15 minutes counts!',
      payload: 'jarvis://study',
    );
  }

  Future<void> showRunwayAlert(double months) async {
    await showAlert(
      id: 300,
      title: '🚨 Runway Warning',
      body: 'Only ${months.toStringAsFixed(1)} months of runway remaining. Review your burn rate.',
      payload: 'jarvis://startup',
    );
  }

  Future<void> showPreMeetingBriefing(String eventTitle, String briefing) async {
    await showAlert(
      id: eventTitle.hashCode,
      title: '📅 Upcoming: $eventTitle',
      body: briefing,
      payload: 'jarvis://calendar',
    );
  }
  
  // Refined Focus Timer Notification implementation

  Future<void> showFocusNotification({
    required int secondsRemaining,
    required String subject,
  }) async {
    // Local path to the generated lamp icon
    const iconPath = 'C:\\Users\\abhin\\.gemini\\antigravity\\brain\\6004ac21-7119-497d-bc64-8c861d50e22e\\focus_lamp_icon_1773986086890.png';

    final minutes = secondsRemaining ~/ 60;
    final seconds = secondsRemaining % 60;
    final timeStr = "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";

    const androidDetails = AndroidNotificationDetails(
      'focus_mode',
      'Focus Mode',
      channelDescription: 'Active focus session timer',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      onlyAlertOnce: true,
      largeIcon: FilePathAndroidBitmap(iconPath),
      color: Colors.white,
      colorized: true,
      styleInformation: MediaStyleInformation(
        htmlFormatTitle: true,
        htmlFormatContent: true,
      ),
      category: AndroidNotificationCategory.status,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'stop_focus',
          'Pause Session', 
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
      interruptionLevel: InterruptionLevel.active,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      888,
      '<b><big>$timeStr</big></b>',
      'Focusing • $subject', 
      details,
      payload: 'jarvis://focus',
    );
  }

  Future<void> cancelFocusNotification() async {
    await _plugin.cancel(888);
  }

  Future<void> showEnergyAlert() async {
    await showAlert(
      id: 400,
      title: '🧠 How are you feeling?',
      body: 'Check in with your energy level so Zen can optimize your task list.',
      payload: 'jarvis://mood',
    );
  }

  // ═══════════════════════════════════════
  // PROACTIVE CHECK (called by background service)
  // ═══════════════════════════════════════

  Future<void> testProactiveAlert() async {
    // A 5-second simulated background delay so the user can background the app
    await Future.delayed(const Duration(seconds: 5));
    
    // Have the AI generate a context-aware push notification content natively
    final brain = ZenBrain();
    await brain.init();
    final alertText = await brain.chat(
      "Generate a single, punchy, proactive push notification (1-2 sentences max) as if you are spontaneously checking in on my progress today. Do not use quotes or markdown.",
    );

    await showAlert(
      id: 999,
      title: '🔵 Zen Context Alert',
      body: alertText.replaceAll('"', ''),
      payload: 'jarvis://home',
    );
  }

  Future<void> runProactiveChecks() async {
    final now = DateTime.now();

    // Check deadlines
    final tasks = await _db.getTasks();
    for (final task in tasks) {
      if (task.dueDate != null && !task.completed) {
        final timeUntil = task.dueDate!.difference(now);
        if (timeUntil.inHours <= 2 && timeUntil.inHours > 0) {
          await showDeadlineAlert(task.title, timeUntil);
        } else if (timeUntil.inHours <= 24 && timeUntil.inHours > 22) {
          await showDeadlineAlert(task.title, timeUntil);
        }
      }
    }

    // Study streak
    if (now.hour >= 21 && !(await _db.hasStudiedToday())) {
      final streak = await _db.getStudyStreak();
      if (streak > 0) {
        await showStudyStreakReminder(streak);
      }
    }

    // Startup runway
    final metrics = await _db.getLatestStartupMetrics();
    if (metrics != null && metrics.runwayMonths < 3) {
      await showRunwayAlert(metrics.runwayMonths);
    }

    // Upcoming events (15 min briefing)
    final events = await _db.getUpcomingEvents(hours: 1);
    for (final event in events) {
      final minutesUntil = event.startTime.difference(now).inMinutes;
      if (minutesUntil >= 13 && minutesUntil <= 17) {
        await showPreMeetingBriefing(
          event.title,
          event.briefing ?? 'Meeting starting soon. Review your notes.',
        );
      }
    }

    // Mood check-in reminder
    if (now.hour >= 10 && now.hour <= 11) {
      final mood = await _db.getTodaysMood();
      if (mood == null) {
        await showEnergyAlert();
      }
    }
  }
}

/// Backward-compat alias — old code used JarvisNotifications
typedef JarvisNotifications = ZenNotifications;
