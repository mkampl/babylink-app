import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Foreground service (microphone type) that keeps the phone-as-baby streaming
/// its mic while backgrounded or screen-off. Mirrors MonitorService but with
/// the microphone service type Android 14+ requires for background capture.
class BabyService {
  BabyService._();

  static void configure() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'babylink_baby',
        channelName: 'BabyLink streaming',
        channelDescription: 'Streams this phone’s microphone to your room.',
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

  static Future<void> start(String roomName) async {
    await FlutterForegroundTask.requestNotificationPermission();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: 'Streaming to $roomName',
      notificationText: 'This phone is acting as a baby unit',
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
