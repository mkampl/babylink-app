import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Runs an Android foreground service while monitoring so the process (and thus
/// the Socket.IO connection + PCM playback + disconnect alarm) keeps running
/// with the app backgrounded or the screen off — the difference between a toy
/// and an actual baby monitor.
class MonitorService {
  MonitorService._();

  static void configure() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'babylink_monitor',
        channelName: 'BabyLink monitoring',
        channelDescription: 'Keeps listening to your BabyLink in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> start(String babyName) async {
    await FlutterForegroundTask.requestNotificationPermission();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.mediaPlayback],
      notificationTitle: 'Listening to $babyName',
      notificationText: 'BabyLink is monitoring',
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
