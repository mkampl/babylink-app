import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../l10n/l10n_sync.dart';

/// Runs an Android foreground service while monitoring so the process (and thus
/// the Socket.IO connection + PCM playback + disconnect alarm) keeps running
/// with the app backgrounded or the screen off — the difference between a toy
/// and an actual baby monitor.
class MonitorService {
  MonitorService._();

  static Future<void> configure() async {
    final l10n = await l10nSync();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'babylink_monitor',
        channelName: l10n.svcMonitorChannel,
        channelDescription: l10n.svcMonitorChannelDesc,
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
    final l10n = await l10nSync();
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.mediaPlayback],
      notificationTitle: l10n.svcListeningTo(babyName),
      notificationText: l10n.svcMonitorRunning,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// True once the OS has exempted us from battery optimization (Doze). Without
  /// this the system can freeze a backgrounded monitor and a cry goes unheard.
  static Future<bool> isBatteryUnrestricted() =>
      FlutterForegroundTask.isIgnoringBatteryOptimizations;

  /// Ask for the exemption if we don't have it. The system dialog only appears
  /// while it isn't granted, so this is safe to call on every monitor start.
  static Future<void> ensureBatteryExemption() async {
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  /// Open the system battery-optimization screen (fallback when the user
  /// dismissed the dialog, and the route to OEM "unrestricted" settings).
  static Future<void> openBatterySettings() =>
      FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
}
