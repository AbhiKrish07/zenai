import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'notifications.dart';
import 'zen_brain.dart';

/// Background task names
const kProactiveCheckTask = 'zen_proactive_check';
const kMorningBriefingTask = 'zen_morning_briefing';
const kTaskReprioritizeTask = 'zen_reprioritize';

/// Background service dispatcher
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case kProactiveCheckTask:
        final notifications = ZenNotifications();
        await notifications.init();
        await notifications.runProactiveChecks();
        break;

      case kMorningBriefingTask:
        final brain = ZenBrain();
        await brain.init();
        final briefing = await brain.generateMorningBriefing();
        final notifications = ZenNotifications();
        await notifications.init();
        await notifications.showMorningBriefing(briefing);
        break;

      case kTaskReprioritizeTask:
        final brain = ZenBrain();
        await brain.init();
        await brain.analyzeAndPrioritizeTasks();
        break;
    }
    return Future.value(true);
  });
}

/// Registers background tasks
class BackgroundService {
  static Future<void> init() async {
    if (kIsWeb) return; // Background tasks not available on Web
    
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Proactive checks every hour
    await Workmanager().registerPeriodicTask(
      'proactive_check',
      kProactiveCheckTask,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.not_required),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    // Morning briefing at system schedule
    await Workmanager().registerPeriodicTask(
      'morning_briefing',
      kMorningBriefingTask,
      frequency: const Duration(hours: 24),
      initialDelay: _timeUntilMorning(),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    // Task reprioritization every 4 hours  
    await Workmanager().registerPeriodicTask(
      'task_reprioritize',
      kTaskReprioritizeTask,
      frequency: const Duration(hours: 4),
      constraints: Constraints(networkType: NetworkType.not_required),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Duration _timeUntilMorning() {
    final now = DateTime.now();
    var morning = DateTime(now.year, now.month, now.day, 7, 0);
    if (morning.isBefore(now)) {
      morning = morning.add(const Duration(days: 1));
    }
    return morning.difference(now);
  }
}
