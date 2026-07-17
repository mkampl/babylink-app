import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/l10n_sync.dart';

/// Fires LOCAL notifications straight from the monitor — no server, no ntfy, no
/// cloud. Because the monitor runs inside a foreground service, the app itself
/// detects a cry / a dropped device and posts a heads-up alert, working fully
/// offline on the LAN. This is the native counterpart to the web app's push.
class NotifyService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static const _channelId = 'babylink_alerts';

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    final l10n = await l10nSync();
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // A high-importance channel so alerts pop as a heads-up with sound even when
    // the phone is in a pocket with the screen off — this is a baby monitor.
    await impl?.createNotificationChannel(AndroidNotificationChannel(
      _channelId,
      l10n.svcAlertsChannel,
      description: l10n.svcAlertsChannelDesc,
      importance: Importance.max,
    ));
    await impl?.requestNotificationsPermission();
  }

  static NotificationDetails _cryDetails(String channelName, String channelDesc) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          icon: '@mipmap/ic_launcher',
        ),
      );

  static NotificationDetails _lostDetails(String channelName, String channelDesc) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          ongoing: true, // a lost device is a standing problem — keep it visible
          icon: '@mipmap/ic_launcher',
        ),
      );

  static int _cryId(String id) => id.hashCode & 0x3fffffff;
  static int _lostId(String id) => ('lost:$id').hashCode & 0x3fffffff;

  static Future<void> crying(String babyId, String babyName) async {
    final l10n = await l10nSync();
    await _plugin.show(
      _cryId(babyId),
      l10n.alertCryingTitle(babyName),
      l10n.alertCryingBody,
      _cryDetails(l10n.svcAlertsChannel, l10n.svcAlertsChannelDesc),
    );
  }

  static Future<void> disconnected(String babyId, String babyName) async {
    final l10n = await l10nSync();
    await _plugin.show(
      _lostId(babyId),
      l10n.alertOfflineTitle(babyName),
      l10n.alertOfflineBody,
      _lostDetails(l10n.svcAlertsChannel, l10n.svcAlertsChannelDesc),
    );
  }

  static Future<void> clearCry(String babyId) => _plugin.cancel(_cryId(babyId));
  static Future<void> clearDisconnected(String babyId) => _plugin.cancel(_lostId(babyId));

  static Future<void> clearAll() => _plugin.cancelAll();
}
