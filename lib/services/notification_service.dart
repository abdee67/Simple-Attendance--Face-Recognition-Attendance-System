import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_attendance/screens/login.dart';
import 'package:simple_attendance/services/api_service.dart';
import 'package:simple_attendance/utils/notification_texts.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  // Singleton instance
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Notification channel constants
  static const String channelId = 'attendance_reminders';
  static const String channelName = 'Attendance Reminders';
  static const String channelDesc =
      'Reminders for attendance submission (Weekdays only)';
  static const String errorChannelId = 'error_channel';
  static const String errorChannelName = 'Error Notifications';

  // Notification IDs
  static const int errorNotificationId = 997;
  static const int testNotificationId = 998;
  static const int scheduledTestId = 999;
  static const int morningReminderId = 1000;
  static const int lunchReminderId = 1002;
  static const int afternoonReminderId = 1003;
  static const int nightReminderId = 1004;

  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  late tz.Location _timezoneLocation;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  Timer? _monitoringTimer;

  /// Initialize the notification service
  Future<void> initialize() async {
    try {
      _log('Initializing notification service...');

      // Initialize timezone
      tz.initializeTimeZones();
      _notificationsPlugin = FlutterLocalNotificationsPlugin();

      // Set timezone location
      try {
        final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
        _timezoneLocation = tz.getLocation(currentTimeZone);
        tz.setLocalLocation(_timezoneLocation);
        _log('Current Timezone: $currentTimeZone');
      } catch (e) {
        _log('Error getting timezone, using default: $e');
        _timezoneLocation = tz.getLocation('Africa/Addis_Ababa');
      }

      // Request permissions
      await _requestPermissions();

      // Initialize notification plugin
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );

      // Create notification channels
      await _createNotificationChannels();

      // Show immediate test notification
      await showImmediateTestNotification();

      // Schedule daily reminders
      await scheduleDailyReminders();

      // Start monitoring for debugging
      _startMonitoring();

      _log('Notification service initialized successfully');
    } catch (e, stackTrace) {
      _log(
        'Error initializing notification service: $e\n$stackTrace',
        isError: true,
      );
      await _showErrorNotification('Initialization Error', e.toString());
    }
  }

  /// Handle notification response when app is in foreground
  void _handleNotificationResponse(NotificationResponse details) {
    _log('Notification tapped: ${details.payload}');
    _navigateToLogin();
  }

  /// Navigate to login screen
  void _navigateToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => LoginScreen(apiService: ApiService()),
        ),
      );
    });
  }

  /// Request all necessary permissions
  Future<void> _requestPermissions() async {
    try {
      // Request notification permission
      final notificationStatus = await Permission.notification.request();
      _log('Notification permission: ${notificationStatus.toString()}');

      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;

        // Request exact alarm permission for Android 12+
        if (androidInfo.version.sdkInt >= 31) {
          final exactAlarmStatus =
              await Permission.scheduleExactAlarm.request();
          _log('Exact alarm permission: ${exactAlarmStatus.toString()}');
        }

        // Request battery optimization ignore
        await _handleBatteryOptimization();
      }
    } catch (e) {
      _log('Error requesting permissions: $e', isError: true);
    }
  }

  /// Handle battery optimization settings
  Future<void> _handleBatteryOptimization() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      _log('Battery optimization status: ${status.toString()}');

      if (status.isDenied || status.isRestricted) {
        _log('Requesting battery optimization ignore...');
        final result = await Permission.ignoreBatteryOptimizations.request();

        if (!result.isGranted) {
          await _showBatteryOptimizationWarning();
        }
      }
    } catch (e) {
      _log('Error handling battery optimization: $e', isError: true);
    }
  }

  /// Show battery optimization warning
  Future<void> _showBatteryOptimizationWarning() async {
    try {
      await _notificationsPlugin.show(
        errorNotificationId + 1,
        'Battery Optimization',
        'Please disable battery optimization for reliable notifications',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            errorChannelId,
            errorChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      _log('Error showing battery warning: $e', isError: true);
    }
  }

  /// Create all notification channels
  Future<void> _createNotificationChannels() async {
    try {
      // Main notification channel
      final mainChannel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDesc,
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
        showBadge: true,
        enableLights: true,
        ledColor: const Color(0xFF2196F3),
      );

      // Error notification channel
      final errorChannel = AndroidNotificationChannel(
        errorChannelId,
        errorChannelName,
        description: 'Error and warning notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin =
          _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      await androidPlugin?.createNotificationChannel(mainChannel);
      await androidPlugin?.createNotificationChannel(errorChannel);

      _log('Notification channels created successfully');
    } catch (e) {
      _log('Error creating notification channels: $e', isError: true);
    }
  }

  /// Show immediate test notification
  Future<void> showImmediateTestNotification() async {
    try {
      await _notificationsPlugin.show(
        testNotificationId,
        'Attendance App',
        'Notifications are working correctly!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
      _log('Test notification shown successfully');
    } catch (e) {
      _log('Error showing test notification: $e', isError: true);
    }
  }

  /// Check if a given date is a weekend
  bool _isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  /// Get the next weekday from a given date
  DateTime _getNextWeekday(DateTime date) {
    DateTime nextDate = date;
    while (_isWeekend(nextDate)) {
      nextDate = nextDate.add(const Duration(days: 1));
    }
    return nextDate;
  }

  /// Calculate next occurrence of a specific time on a weekday
  tz.TZDateTime _calculateNextWeekdayTime({
    required int hour,
    required int minute,
  }) {
    final now = tz.TZDateTime.now(_timezoneLocation);
    var scheduledTime = tz.TZDateTime(
      _timezoneLocation,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the time today has passed, move to tomorrow
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    // Skip weekends
    while (_isWeekend(scheduledTime)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    _log('Next weekday scheduled time: $scheduledTime (current: $now)');
    return scheduledTime;
  }

  /// Schedule all daily reminders (weekdays only)
  Future<void> scheduleDailyReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool remindersSet = prefs.getBool('reminders_set') ?? false;

      if (!remindersSet) {
        _log('Setting up daily reminders (weekdays only)...');

        // Clear any existing notifications
        await _notificationsPlugin.cancelAll();

        // Schedule test notification (immediate, not affected by weekend check)
        await _scheduleSingleReminder(
          tz.TZDateTime.now(_timezoneLocation).add(const Duration(seconds: 10)),
          NotificationTexts().getContexualMessage(),
          id: scheduledTestId,
          skipWeekendCheck: true, // Test notification should show regardless
        );

        // Get next weekday times
        final morningTime = _calculateNextWeekdayTime(hour: 8, minute: 30);
        final lunchTime = _calculateNextWeekdayTime(hour: 12, minute: 30);
        final afternoonTime = _calculateNextWeekdayTime(hour: 14, minute: 30);
        final nightTime = _calculateNextWeekdayTime(hour: 17, minute: 30);

        // Schedule daily attendance reminders (weekdays only)
        await _scheduleSingleReminder(
          morningTime,
          '🌅 Good Morning! Please submit your morning attendance. Have a great day!',
          id: morningReminderId,
          isDaily: true,
        );

        await _scheduleSingleReminder(
          lunchTime,
          '🍽️ Good Afternoon! Please submit your lunch break attendance. Enjoy your meal!',
          id: lunchReminderId,
          isDaily: true,
        );

        await _scheduleSingleReminder(
          afternoonTime,
          '☀️ Hope you are having a good meal! Please submit your after-lunch attendance.',
          id: afternoonReminderId,
          isDaily: true,
        );

        await _scheduleSingleReminder(
          nightTime,
          '🌙 Hope you are having a good day! Please submit your night attendance. Have a good time!',
          id: nightReminderId,
          isDaily: true,
        );

        // Store the last schedule date to detect day changes
        await prefs.setString(
          'last_schedule_date',
          DateTime.now().toIso8601String(),
        );
        await prefs.setBool('reminders_set', true);

        _log(
          'Weekday reminders scheduled successfully. Next reminders on: ${morningTime.weekday}',
        );
      } else {
        _log('Reminders already scheduled');
        // Check if we need to reschedule for the next day
        await _checkAndRescheduleForNewDay();
      }
    } catch (e, stackTrace) {
      _log('Error scheduling daily reminders: $e\n$stackTrace', isError: true);
      await _showErrorNotification('Scheduling Error', e.toString());
    }
  }

  /// Check if we need to reschedule for a new day
  Future<void> _checkAndRescheduleForNewDay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastDateString = prefs.getString('last_schedule_date');

      if (lastDateString != null) {
        final lastDate = DateTime.parse(lastDateString);
        final now = DateTime.now();

        // If it's a new day and it's a weekday, reschedule
        if (now.day != lastDate.day && !_isWeekend(now)) {
          _log('New weekday detected, rescheduling reminders...');
          await resetAndReschedule();
        }
      }
    } catch (e) {
      _log('Error checking for new day: $e', isError: true);
    }
  }

  /// Schedule a single reminder with weekend skipping
  Future<void> _scheduleSingleReminder(
    tz.TZDateTime scheduledDate,
    String message, {
    required int id,
    bool isDaily = false,
    bool skipWeekendCheck = false,
  }) async {
    try {
      final now = tz.TZDateTime.now(_timezoneLocation);

      // Skip if it's a weekend (unless explicitly bypassed for tests)
      if (!skipWeekendCheck && _isWeekend(scheduledDate)) {
        _log(
          'Skipping weekend notification: $scheduledDate (${scheduledDate.weekday})',
        );
        return;
      }

      if (scheduledDate.isBefore(now)) {
        _log('Skipping past notification: $scheduledDate');
        return;
      }

      _log(
        'Scheduling notification ID $id for $scheduledDate (Weekday: ${scheduledDate.weekday})',
      );

      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('notification'),
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 500, 500]),
          autoCancel: true,
          styleInformation: BigTextStyleInformation(message),
          fullScreenIntent: true,
          showWhen: true,
          when: scheduledDate.millisecondsSinceEpoch,
          ticker: 'Attendance Reminder',
          visibility: NotificationVisibility.public,
          timeoutAfter: 3600000, // 1 hour
          category: AndroidNotificationCategory.reminder,
          channelShowBadge: true,
          enableLights: true,
          ledColor: const Color(0xFF2196F3),
          ledOnMs: 1000,
          ledOffMs: 500,
          colorized: true,
          color: const Color(0xFF2196F3),
          actions: [
            AndroidNotificationAction(
              'submit_action',
              'Submit Now',
              showsUserInterface: true,
            ),
          ],
        ),
      );

      if (isDaily) {
        // For daily reminders, use time components to repeat daily but skip weekends
        await _notificationsPlugin.zonedSchedule(
          id,
          'Attendance Reminder',
          message,
          scheduledDate,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'attendance_reminder_$id',
        );
      } else {
        // For one-time reminders
        await _notificationsPlugin.zonedSchedule(
          id,
          'Attendance Reminder',
          message,
          scheduledDate,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'attendance_reminder_$id',
        );
      }

      _log(
        'Successfully scheduled notification ID $id for ${scheduledDate.weekday}',
      );
    } catch (e, stackTrace) {
      _log('Error scheduling reminder ID $id: $e\n$stackTrace', isError: true);
    }
  }

  /// Show error notification
  Future<void> _showErrorNotification(String title, String message) async {
    try {
      await _notificationsPlugin.show(
        errorNotificationId,
        title,
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            errorChannelId,
            errorChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      _log('Failed to show error notification: $e', isError: true);
    }
  }

  /// Cancel all reminders
  Future<void> cancelAllReminders() async {
    try {
      await _notificationsPlugin.cancelAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('reminders_set');
      await prefs.remove('last_schedule_date');
      _stopMonitoring();
      _log('All reminders cancelled');
    } catch (e) {
      _log('Error cancelling reminders: $e', isError: true);
    }
  }

  /// Reset and reschedule all reminders
  Future<void> resetAndReschedule() async {
    try {
      await cancelAllReminders();
      await scheduleDailyReminders();
      _log('Reminders reset and rescheduled');
    } catch (e) {
      _log('Error resetting reminders: $e', isError: true);
    }
  }

  /// Check notification permissions
  Future<bool> checkPermissions() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.notification.status;
        return status.isGranted;
      }
      return true;
    } catch (e) {
      _log('Error checking permissions: $e', isError: true);
      return false;
    }
  }

  /// Start monitoring for debugging
  void _startMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(const Duration(minutes: 5), (
      timer,
    ) async {
      await _logPendingNotifications();
      await _checkAndRescheduleForNewDay();
    });
  }

  /// Stop monitoring
  void _stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  /// Log pending notifications for debugging
  Future<void> _logPendingNotifications() async {
    try {
      final pending = await _notificationsPlugin.pendingNotificationRequests();
      _log('Pending notifications: ${pending.length}');
      for (final notification in pending) {
        final date = DateTime.fromMillisecondsSinceEpoch(notification.id);
        _log(
          '  ID: ${notification.id}, Title: ${notification.title}, Date: $date (Weekday: ${date.weekday})',
        );
      }
    } catch (e) {
      _log('Error logging pending notifications: $e', isError: true);
    }
  }

  /// Get weekday name from number with validation
  String _getWeekdayName(int weekday) {
    if (weekday < 1 || weekday > 7) {
      return 'Invalid weekday ($weekday)';
    }

    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Unknown weekday ($weekday)';
    }
  }

  /// Log message with timestamp and error flag
  void _log(String message, {bool isError = false}) {
    final timestamp = DateTime.now().toIso8601String();
    final prefix = isError ? '❌ ERROR' : '✅ INFO';
    debugPrint('$prefix [$timestamp] $message');
  }

  /// Dispose resources
  void dispose() {
    _stopMonitoring();
  }

  /// Handle app lifecycle events
  void onAppPaused() {
    _log('App paused - monitoring notifications');
  }

  void onAppResumed() {
    _log('App resumed - checking notification status');
    _logPendingNotifications();
    _checkAndRescheduleForNewDay();
  }

  /// Check if notifications are enabled at system level
  Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlugin =
          _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      return await androidPlugin?.areNotificationsEnabled() ?? false;
    } catch (e) {
      _log('Error checking notification status: $e', isError: true);
      return false;
    }
  }
}
