import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../models/notification_model.dart';

class NotificationService {
  static Future<void> sendTaskReminder({
    required String senderRole,
    required String employeeId,
    required String taskId,
    int? subtaskIndex,
    required String type,
    required String message,
  }) async {
    final uri = Uri.parse(ApiConfig.notificationsUrl);

    final body = <String, dynamic>{
      'sender_role': senderRole,
      'employee_id': employeeId,
      'task_id': taskId,
      'type': type,
      'message': message,
    };
    if (subtaskIndex != null) {
      body['subtask_index'] = subtaskIndex;
    }

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      String? apiMessage;
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        final message = data?['message'] ??
            (data?['errors'] != null ? data!['errors'].toString() : null);
        if (message != null && message.toString().trim().isNotEmpty) {
          apiMessage = message.toString().trim();
        }
      } catch (_) {
        // Ignore parse errors and fall back to status code message.
      }

      throw Exception(
        apiMessage ?? 'Failed to send notification (${response.statusCode})',
      );
    }
  }

  static Future<List<NotificationModel>> fetchNotifications(
    String employeeId,
  ) async {
    final uri = Uri.parse(
      '${ApiConfig.notificationsUrl}?employee_id=$employeeId',
    );

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load notifications');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => NotificationModel.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .toList();
    }
    return [];
  }

  static Future<void> markNotificationRead({
    required String notificationId,
    required String employeeId,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.notificationsUrl}/$notificationId/read',
    );

    final response = await http.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'employee_id': employeeId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update notification');
    }
  }
}

