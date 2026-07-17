import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../l10n/l10n_sync.dart';

/// Foreground service (microphone type) that keeps the phone-as-baby streaming
/// its mic while backgrounded or screen-off. Mirrors MonitorService but with
/// the microphone service type Android 14+ requires for background capture.
class BabyService {
  BabyService._();

  static Future<void> configure() async {
    final l10n = await l10nSync();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'babylink_baby',
        channelName: l10n.svcBabyChannel,
        channelDescription: l10n.svcBabyChannelDesc,
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
    final l10n = await l10nSync();
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: l10n.svcStreamingTo(roomName),
      notificationText: l10n.svcBabyRunning,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
