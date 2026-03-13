import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class TaskService {
  // Get all tasks
  static Future<Map<String, dynamic>> getTasks(
    String userId,
    String userRole, {
    bool needHelpOnly = false,
  }) async {
    try {
      final query = StringBuffer(
          '${ApiConfig.baseUrl}/tasks?user_id=$userId&user_role=$userRole');
      if (needHelpOnly) {
        query.write('&need_help=1');
      }
      final response = await http.get(
        Uri.parse(query.toString()),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Create a new task
  static Future<Map<String, dynamic>> createTask(
    Map<String, dynamic> taskData,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(taskData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      if (response.statusCode == 422) {
        final body = jsonDecode(response.body);
        final errors = body['errors'] as Map<String, dynamic>?;
        final message = body['message'] as String?;
        if (errors != null && errors.isNotEmpty) {
          final first = errors.values.first;
          final msg = first is List ? first.join(' ') : first.toString();
          throw Exception(msg);
        }
        throw Exception(message ?? 'Validation failed');
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Update task
  static Future<Map<String, dynamic>> updateTask(
    String taskId,
    Map<String, dynamic> taskData,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(taskData),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Update task status (optional need_help_note when status is need_help)
  static Future<Map<String, dynamic>> updateTaskStatus(
    String taskId,
    String status, {
    String? needHelpNote,
  }) async {
    try {
      final payload = <String, dynamic>{'status': status};
      if (needHelpNote != null && needHelpNote.trim().isNotEmpty) {
        payload['need_help_note'] = needHelpNote.trim();
      }
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Delete task
  static Future<Map<String, dynamic>> deleteTask(String taskId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}
