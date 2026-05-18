import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/weather_alert.dart';

const _channelId = 'weather_alerts';
const _channelName = 'Severe Weather Alerts';

final _plugin = FlutterLocalNotificationsPlugin();

class NotificationService {
  static Future<void> initialize() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> postAlertNotification(
    String locationName,
    List<WeatherAlert> alerts,
  ) async {
    final now = DateTime.now();
    final active = alerts.where((a) {
      final severityMatch = a.severity == 'Extreme' ||
          a.severity == 'Severe' ||
          a.severity == 'Moderate';
      return severityMatch && a.expires.isAfter(now);
    }).toList();

    if (active.isEmpty) return;

    final count = active.length;
    final names = active.map((a) => a.event).join(', ');
    final body = '$count active ${count == 1 ? 'alert' : 'alerts'}: $names';

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    final id = locationName.hashCode.abs() % 100000;
    await _plugin.show(id, locationName, body, details);
  }
}
