import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/event.dart';
import '../models/task.dart';

class ZenNotifier {
  static final ZenNotifier _i = ZenNotifier._();
  factory ZenNotifier() => _i;
  ZenNotifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }
    
    tz.initializeTimeZones();
    
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle tap if needed
      },
    );
    
    _initialized = true;
  }

  Future<void> scheduleEventReminder(CalendarEvent event) async {
    if (kIsWeb) return;
    await init();
    
    final remTime = event.startTime.subtract(const Duration(minutes: 10));
    if (remTime.isBefore(DateTime.now())) return;

    final id = event.id.hashCode.abs();
    
    await _plugin.zonedSchedule(
      id,
      'Zen Reminder: ${event.title}',
      'Starting at ${event.startTime.hour.toString().padLeft(2, '0')}:${event.startTime.minute.toString().padLeft(2, '0')}',
      tz.TZDateTime.from(remTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'zen_calendar', 'Calendar Reminders',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> scheduleTaskReminder(Task task) async {
    if (kIsWeb || task.dueDate == null) return;
    await init();
    
    final remTime = task.dueDate!.subtract(const Duration(hours: 1)); // 1 hour reminder
    if (remTime.isBefore(DateTime.now())) return;

    final id = task.id.hashCode.abs() + 10000; // Offset from event ids
    
    await _plugin.zonedSchedule(
      id,
      'Zen Task Reminder',
      'Don\'t forget: ${task.title}',
      tz.TZDateTime.from(remTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'zen_tasks', 'Task Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelReminder(String id) async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancel(id.hashCode.abs());
    await _plugin.cancel(id.hashCode.abs() + 10000);
  }

  Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      999,
      'Zen is Active',
      'I will remind you about your schedule.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'zen_test', 'Zen Core',
          importance: Importance.low,
        ),
      ),
    );
  }
}
