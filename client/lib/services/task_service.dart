import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'local_cache_service.dart';

class TaskService {
  static const Duration _tasksCacheTtl = Duration(seconds: 45);
  static final Map<String, Future<Map<String, dynamic>>> _pendingGets = {};

  static String _tasksCacheKey(
    String userId,
    String userRole, {
    bool needHelpOnly = false,
    String? targetUserId,
    bool currentOnly = false,
  }) {
    return [
      'tasks',
      userId,
      userRole,
      targetUserId ?? '',
      needHelpOnly ? '1' : '0',
      currentOnly ? '1' : '0',
    ].join('|');
  }

  static Future<void> _invalidateTaskCache() {
    return LocalCacheService.invalidatePrefix('tasks|');
  }

  // Get all tasks
  static Future<Map<String, dynamic>> getTasks(
    String userId,
    String userRole, {
    bool needHelpOnly = false,
    String? targetUserId,
    bool currentOnly = false,
    int? perPage,
    int? page,
    bool useCursorPagination = false,
    String? cursorCreatedAt,
    String? cursorId,
    String view = 'full',
    bool includeHistory = true,
  }) async {
    final cacheKey = _tasksCacheKey(
      userId,
      userRole,
      needHelpOnly: needHelpOnly,
      targetUserId: targetUserId,
      currentOnly: currentOnly,
    );

    final cached = await LocalCacheService.getJsonMap(
      cacheKey,
      ttl: _tasksCacheTtl,
    );
    if (cached != null) {
      return cached;
    }

    final inflight = _pendingGets[cacheKey];
    if (inflight != null) {
      return inflight;
    }

    final future = () async {
      try {
        final query = StringBuffer(
            '${ApiConfig.baseUrl}/tasks?user_id=$userId&user_role=$userRole');
        if (targetUserId != null && targetUserId.trim().isNotEmpty) {
          query.write('&target_user_id=${Uri.encodeQueryComponent(targetUserId.trim())}');
        }
        if (needHelpOnly) {
          query.write('&need_help=1');
        }
        if (currentOnly) {
          query.write('&current_only=1');
        }
        if (perPage != null && perPage > 0) {
          query.write('&per_page=$perPage');
        }
        if (page != null && page > 0) {
          query.write('&page=$page');
        }
        if (useCursorPagination) {
          query.write('&pagination_mode=cursor');
          if (cursorCreatedAt != null && cursorCreatedAt.trim().isNotEmpty) {
            query.write('&cursor_created_at=${Uri.encodeQueryComponent(cursorCreatedAt.trim())}');
          }
          if (cursorId != null && cursorId.trim().isNotEmpty) {
            query.write('&cursor_id=${Uri.encodeQueryComponent(cursorId.trim())}');
          }
        }
        if (view.trim().isNotEmpty) {
          query.write('&view=${Uri.encodeQueryComponent(view.trim().toLowerCase())}');
        }
        query.write('&include_history=${includeHistory ? '1' : '0'}');

        final response = await http.get(
          Uri.parse(query.toString()),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          await LocalCacheService.putJson(
            cacheKey,
            decoded,
            ttl: _tasksCacheTtl,
          );
          return decoded;
        } else {
          throw Exception('Server error: ${response.statusCode}');
        }
      } catch (e) {
        throw Exception('Network error: $e');
      } finally {
        _pendingGets.remove(cacheKey);
      }
    }();

    _pendingGets[cacheKey] = future;

    return future;
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
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _invalidateTaskCache();
        return decoded;
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
    String userId,
    String userRole,
  ) async {
    try {
      final payload = <String, dynamic>{
        ...taskData,
        'user_id': userId,
        'user_role': userRole,
      };
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _invalidateTaskCache();
        return decoded;
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
    required String userId,
    required String userRole,
  }) async {
    try {
      final payload = <String, dynamic>{
        'status': status,
        'user_id': userId,
        'user_role': userRole,
      };
      if (needHelpNote != null && needHelpNote.trim().isNotEmpty) {
        payload['need_help_note'] = needHelpNote.trim();
      }
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _invalidateTaskCache();
        return decoded;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Mark a task as current work for its assignee.
  static Future<Map<String, dynamic>> moveToCurrentTask(
    String taskId, {
    required String userId,
    required String userRole,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId/current'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_role': userRole,
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _invalidateTaskCache();
        return decoded;
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Delete task
  static Future<Map<String, dynamic>> deleteTask(
    String taskId,
    String userId,
    String userRole,
  ) async {
    try {
      final query =
          '${ApiConfig.baseUrl}/tasks/$taskId?user_id=${Uri.encodeQueryComponent(userId)}&user_role=${Uri.encodeQueryComponent(userRole)}';
      final response = await http.delete(
        Uri.parse(query),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _invalidateTaskCache();
        return decoded;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Get hidden tasks for current user
  static Future<Map<String, dynamic>> getHiddenTasks(
    String userId,
    String userRole,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/tasks/hidden?user_id=${Uri.encodeQueryComponent(userId)}&user_role=${Uri.encodeQueryComponent(userRole)}',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _invalidateTaskCache();
        return decoded;
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Hide task for current user
  static Future<Map<String, dynamic>> hideTask(
    String taskId,
    String userId,
    String userRole,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId/hide'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'user_role': userRole}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _invalidateTaskCache();
        return decoded;
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Restore hidden task for current user
  static Future<Map<String, dynamic>> unhideTask(
    String taskId,
    String userId,
    String userRole,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/tasks/$taskId/unhide'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'user_role': userRole}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}
