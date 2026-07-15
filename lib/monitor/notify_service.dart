import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // A high-importance channel so alerts pop as a heads-up with sound even when
    // the phone is in a pocket with the screen off — this is a baby monitor.
    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      'BabyLink alerts',
      description: 'Cry and connection alerts from the monitor.',
      importance: Importance.max,
    ));
    await impl?.requestNotificationsPermission();
  }

  static const _cryDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'BabyLink alerts',
      channelDescription: 'Cry and connection alerts from the monitor.',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      icon: '@mipmap/ic_launcher',
    ),
  );

  static const _lostDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'BabyLink alerts',
      channelDescription: 'Cry and connection alerts from the monitor.',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      ongoing: true, // a lost device is a standing problem — keep it visible
      icon: '@mipmap/ic_launcher',
    ),
  );

  static int _cryId(String id) => id.hashCode & 0x3fffffff;
  static int _lostId(String id) => ('lost:$id').hashCode & 0x3fffffff;

  static Future<void> crying(String babyId, String babyName) =>
      _plugin.show(_cryId(babyId), '$babyName is crying', 'Loud sound detected', _cryDetails);

  static Future<void> disconnected(String babyId, String babyName) =>
      _plugin.show(_lostId(babyId), '$babyName went offline', 'No audio — the device dropped', _lostDetails);

  static Future<void> clearCry(String babyId) => _plugin.cancel(_cryId(babyId));
  static Future<void> clearDisconnected(String babyId) => _plugin.cancel(_lostId(babyId));

  static Future<void> clearAll() => _plugin.cancelAll();
}
