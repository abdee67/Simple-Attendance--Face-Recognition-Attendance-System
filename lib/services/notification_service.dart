import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_attendance/screens/login.dart';
import 'package:simple_attendance/services/api_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const channelId = 'attendance_reminders';
  static const channelName = 'Attendance Reminders';
  static const channelDesc = 'Reminders for attendance submission';

  late FlutterLocalNotificationsPlugin _notificationsPlugin;

  Future<void> initialize() async {
    tz.initializeTimeZones();
    final location = tz.getLocation('Africa/Addis_Ababa',); // Adjust timezone as needed

    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _notificationsPlugin.initialize(
      const InitializationSettings(android: initializationSettingsAndroid),
      onDidReceiveNotificationResponse: (details) {
        // Navigate to attendance screen when notification is tapped
        Navigator.of(context as BuildContext).push(
          MaterialPageRoute(
            builder:
                (context) => LoginScreen(
                  apiService: ApiService(),
                ), // Replace with your attendance screen
          ),
        );
      },
    );

    await _createNotificationChannel();
    await _scheduleDailyReminders(location);
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> _scheduleDailyReminders(tz.Location location) async {
    final prefs = await SharedPreferences.getInstance();
    final remindersSet = prefs.getBool('reminders_set') ?? false;

    if (!remindersSet) {
      // Schedule all 4 daily reminders
      await _scheduleSingleReminder(8, 30, location);
      await _scheduleSingleReminder(12, 30, location);
      await _scheduleSingleReminder(17, 30, location); // 5:30 PM
      await _scheduleSingleReminder(19, 30, location); // 7:30 PM

      await prefs.setBool('reminders_set', true);
    }
  }

  Future<void> _scheduleSingleReminder(
    int hour,
    int minute,
    tz.Location location,
  ) async {
    final now = tz.TZDateTime.now(location);
    var scheduledDate = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the time has already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notificationsPlugin.zonedSchedule(
      hour * 100 + minute, // Unique ID based on time
      'Attendance Reminder',
      'Time to submit your attendance!',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelAllReminders() async {
    await _notificationsPlugin.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('reminders_set');
  }
}
