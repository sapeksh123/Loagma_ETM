import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'api_config.dart';

@pragma('vm:entry-point')
void taskAlarmNotificationTapBackground(NotificationResponse response) {
  TaskAlarmService.handleNotificationAction(response);
}

class TaskAlarmService {
  TaskAlarmService._();

  static const String _actionOpen = 'open_task';
  static const String _actionDone = 'mark_done';
  static const String _actionSnooze = 'snooze_10m';
  static const String _actionDismiss = 'dismiss_alarm';
  static const String _androidChannelId = 'task_alarm_channel';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final Map<int, Timer> _foregroundTimers = <int, Timer>{};
  static final Map<int, String> _foregroundTimerTaskIds = <int, String>{};

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: handleNotificationAction,
      onDidReceiveBackgroundNotificationResponse:
          taskAlarmNotificationTapBackground,
    );

    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    _initialized = true;
  }

  static Future<AlarmPermissionStatus> ensureAlarmPermissions({
    bool requestIfNeeded = true,
  }) async {
    await initialize();
    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation == null) {
      return const AlarmPermissionStatus(
        notificationsEnabled: true,
        exactAlarmAllowed: true,
      );
    }

    var notificationsEnabled =
        await androidImplementation.areNotificationsEnabled() ?? false;
    if (!notificationsEnabled && requestIfNeeded) {
      await androidImplementation.requestNotificationsPermission();
      notificationsEnabled =
          await androidImplementation.areNotificationsEnabled() ?? false;
    }

    var exactAlarmAllowed =
        await androidImplementation.canScheduleExactNotifications() ?? false;
    if (!exactAlarmAllowed && requestIfNeeded) {
      await androidImplementation.requestExactAlarmsPermission();
      exactAlarmAllowed =
          await androidImplementation.canScheduleExactNotifications() ?? false;
    }

    return AlarmPermissionStatus(
      notificationsEnabled: notificationsEnabled,
      exactAlarmAllowed: exactAlarmAllowed,
    );
  }

  static Future<int> scheduleFromTaskMap(
    Map<String, dynamic> task, {
    required String actingUserId,
    required String actingUserRole,
  }) async {
    await initialize();

    final isEnabled = _readBool(task['alarm_enabled']);
    if (!isEnabled) return 0;

    final taskId = task['id']?.toString();
    if (taskId == null || taskId.trim().isEmpty) return 0;

    final title = task['title']?.toString().trim();
    if (title == null || title.isEmpty) return 0;

    final alarmTime = _parseAlarmTime(task['alarm_time']?.toString());
    if (alarmTime == null) return 0;

    final pattern = (task['alarm_pattern']?.toString().trim().toLowerCase().isEmpty ?? true)
        ? 'today'
        : task['alarm_pattern'].toString().trim().toLowerCase();

    final now = DateTime.now();
    final dates = _buildAlarmDates(
      pattern: pattern,
      now: now,
      startDateRaw: task['alarm_start_date']?.toString(),
      endDateRaw: task['alarm_end_date']?.toString(),
    );
    if (dates.isEmpty) return 0;

    final androidImplementation =
      _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canUseExact =
      await androidImplementation?.canScheduleExactNotifications() ?? false;
    final scheduleMode = canUseExact
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

    final status = (task['status']?.toString().trim().isEmpty ?? true)
        ? 'assigned'
        : task['status'].toString();

    var scheduledCount = 0;

    for (final day in dates) {
      final localWallClock = DateTime(
        day.year,
        day.month,
        day.day,
        alarmTime.hour,
        alarmTime.minute,
      );
      if (localWallClock.isBefore(DateTime.now())) {
        continue;
      }

      final scheduled = tz.TZDateTime.from(localWallClock, tz.local);

      final notificationId =
          _notificationId(taskId, day, alarmTime.hour, alarmTime.minute);
      await _plugin.cancel(notificationId);
        _cancelForegroundTimer(notificationId);

      final payload = <String, dynamic>{
        'task_id': taskId,
        'task_title': title,
        'task_status': status,
        'user_id': actingUserId,
        'user_role': actingUserRole,
        'alarm_date': _toYmd(day),
        'alarm_time': task['alarm_time']?.toString(),
        'alarm_pattern': pattern,
      };

      await _plugin.zonedSchedule(
        notificationId,
        title,
        'Status: $status',
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            'Task Alarms',
            channelDescription: 'Rings for scheduled task alarms',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            fullScreenIntent: true,
            ticker: 'Task alarm',
            actions: const <AndroidNotificationAction>[
              AndroidNotificationAction(_actionOpen, 'Open'),
              AndroidNotificationAction(_actionDone, 'Mark Done'),
              AndroidNotificationAction(_actionSnooze, 'Snooze 10m'),
              AndroidNotificationAction(_actionDismiss, 'Dismiss', cancelNotification: true),
            ],
          ),
        ),
        payload: jsonEncode(payload),
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      _scheduleForegroundFallback(
        notificationId: notificationId,
        taskId: taskId,
        when: scheduled,
        title: title,
        status: status,
        payload: payload,
      );
      scheduledCount++;
    }

    return scheduledCount;
  }

  static Future<void> cancelTaskAlarms(String taskId) async {
    await initialize();
    final requests = await _plugin.pendingNotificationRequests();
    for (final request in requests) {
      final payload = _decodePayload(request.payload);
      if (payload['task_id']?.toString() == taskId) {
        await _plugin.cancel(request.id);
        _cancelForegroundTimer(request.id);
      }
    }

    final timerIds = _foregroundTimerTaskIds.entries
        .where((entry) => entry.value == taskId)
        .map((entry) => entry.key)
        .toList();
    for (final timerId in timerIds) {
      _cancelForegroundTimer(timerId);
    }
  }

  static Future<void> handleNotificationAction(
    NotificationResponse response,
  ) async {
    final payload = _decodePayload(response.payload);
    final taskId = payload['task_id']?.toString();
    if (taskId == null || taskId.trim().isEmpty) return;

    switch (response.actionId) {
      case _actionDone:
        await _markTaskDone(payload);
        await cancelTaskAlarms(taskId);
        return;
      case _actionSnooze:
        await _scheduleSnooze(payload);
        return;
      case _actionDismiss:
      case _actionOpen:
      default:
        return;
    }
  }

  static Future<void> _markTaskDone(Map<String, dynamic> payload) async {
    final taskId = payload['task_id']?.toString();
    final userId = payload['user_id']?.toString();
    final userRole = payload['user_role']?.toString();
    if (taskId == null || userId == null || userRole == null) return;

    try {
      await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': 'completed',
          'user_id': userId,
          'user_role': userRole,
        }),
      );
    } catch (_) {
      // Keep action handler resilient and non-blocking.
    }
  }

  static Future<void> _scheduleSnooze(Map<String, dynamic> payload) async {
    final taskId = payload['task_id']?.toString();
    final title = payload['task_title']?.toString();
    if (taskId == null || title == null) return;

    final snoozeAt = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
    final snoozeId = _notificationId(taskId, DateTime.now(), snoozeAt.hour, snoozeAt.minute) ^
        0x0055AA;

    await _plugin.zonedSchedule(
      snoozeId,
      title,
      'Snoozed reminder',
      snoozeAt,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          'Task Alarms',
          channelDescription: 'Rings for scheduled task alarms',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          fullScreenIntent: true,
        ),
      ),
      payload: jsonEncode(payload),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static List<DateTime> _buildAlarmDates({
    required String pattern,
    required DateTime now,
    String? startDateRaw,
    String? endDateRaw,
  }) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    if (pattern == 'today') {
      return [startOfToday];
    }
    if (pattern == '2days') {
      return [startOfToday, startOfToday.add(const Duration(days: 1))];
    }
    if (pattern == 'week') {
      return List<DateTime>.generate(
        7,
        (i) => startOfToday.add(Duration(days: i)),
      );
    }

    final parsedStart = _parseDateOnly(startDateRaw) ?? startOfToday;
    final parsedEnd = _parseDateOnly(endDateRaw) ?? parsedStart;
    if (parsedEnd.isBefore(parsedStart)) {
      return [parsedStart];
    }

    final days = parsedEnd.difference(parsedStart).inDays;
    return List<DateTime>.generate(
      days + 1,
      (i) => parsedStart.add(Duration(days: i)),
    );
  }

  static DateTime? _parseDateOnly(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  static TimeOfDayLike? _parseAlarmTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDayLike(hour: hour, minute: minute);
  }

  static int _notificationId(
    String taskId,
    DateTime day,
    int hour,
    int minute,
  ) {
    final key = '$taskId-${_toYmd(day)}-${hour.toString().padLeft(2, '0')}${minute.toString().padLeft(2, '0')}';
    return key.hashCode & 0x7fffffff;
  }

  static String _toYmd(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static Map<String, dynamic> _decodePayload(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Invalid alarm payload: $raw');
      }
    }
    return const {};
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  static void _scheduleForegroundFallback({
    required int notificationId,
    required String taskId,
    required tz.TZDateTime when,
    required String title,
    required String status,
    required Map<String, dynamic> payload,
  }) {
    _cancelForegroundTimer(notificationId);

    final delay = when.toLocal().difference(DateTime.now());
    if (delay.isNegative) {
      return;
    }

    _foregroundTimerTaskIds[notificationId] = taskId;
    _foregroundTimers[notificationId] = Timer(delay, () async {
      _foregroundTimers.remove(notificationId);
      _foregroundTimerTaskIds.remove(notificationId);

      await _plugin.show(
        notificationId,
        title,
        'Status: $status',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            'Task Alarms',
            channelDescription: 'Rings for scheduled task alarms',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            fullScreenIntent: true,
            ticker: 'Task alarm',
            actions: const <AndroidNotificationAction>[
              AndroidNotificationAction(_actionOpen, 'Open'),
              AndroidNotificationAction(_actionDone, 'Mark Done'),
              AndroidNotificationAction(_actionSnooze, 'Snooze 10m'),
              AndroidNotificationAction(_actionDismiss, 'Dismiss', cancelNotification: true),
            ],
          ),
        ),
        payload: jsonEncode(payload),
      );
    });
  }

  static void _cancelForegroundTimer(int notificationId) {
    _foregroundTimers.remove(notificationId)?.cancel();
    _foregroundTimerTaskIds.remove(notificationId);
  }
}

class TimeOfDayLike {
  final int hour;
  final int minute;

  const TimeOfDayLike({required this.hour, required this.minute});
}

class AlarmPermissionStatus {
  final bool notificationsEnabled;
  final bool exactAlarmAllowed;

  const AlarmPermissionStatus({
    required this.notificationsEnabled,
    required this.exactAlarmAllowed,
  });
}