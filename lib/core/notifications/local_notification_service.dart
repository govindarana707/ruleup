import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

abstract interface class LocalNotificationService {
  Future<void> initialize();

  Future<bool> requestPermission();

  Future<void> cancelHabit(String habitId);

  Future<void> scheduleHabit({
    required int notificationId,
    required String habitId,
    required String habitName,
    required DateTime scheduledAt,
  });
}

class AndroidLocalNotificationService implements LocalNotificationService {
  AndroidLocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _payloadPrefix = 'habit:';
  static const _channelId = 'habit_reminders';
  static const _channelName = 'Habit reminders';
  static const _timeZoneChannel = MethodChannel('ruleup/timezone');

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Habit notifications are Android-only');
    }
    tz.initializeTimeZones();
    final timeZone = await _timeZoneChannel.invokeMethod<String>(
      'getLocalTimezone',
    );
    if (timeZone == null) throw StateError('Android timezone unavailable');
    tz.setLocalLocation(tz.getLocation(timeZone));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> cancelHabit(String habitId) async {
    final payload = '$_payloadPrefix$habitId';
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.payload == payload) {
        await _plugin.cancel(id: notification.id);
      }
    }
  }

  @override
  Future<void> scheduleHabit({
    required int notificationId,
    required String habitId,
    required String habitName,
    required DateTime scheduledAt,
  }) async {
    final zonedDate = tz.TZDateTime(
      tz.local,
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
      scheduledAt.hour,
      scheduledAt.minute,
    );
    await _plugin.zonedSchedule(
      id: notificationId,
      title: 'RuleUp',
      body: 'Time for $habitName',
      scheduledDate: zonedDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Reminders for scheduled habits',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '$_payloadPrefix$habitId',
    );
  }
}
