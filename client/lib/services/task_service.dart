import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'local_cache_service.dart';

class TaskService {
  static const Duration _tasksCacheTtl = Duration(seconds: 45);
  static final Map<String, Future<Map<String, dynamic>>> _pendingGets = {};

  static String _errorMessageFromResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {
      // Ignore parse issues and fall back to status code message.
    }
    return 'Server error: ${response.statusCode}';
  }

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

  static String _appendTaskQuery(
    String baseApiUrl,
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
  }) {
    final query = StringBuffer(
      '$baseApiUrl/tasks?user_id=$userId&user_role=$userRole',
    );
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
    return query.toString();
  }

  static Map<String, dynamic>? _tryParseJsonMapLenient(String body) {
    var normalized = body.trim();
    if (normalized.startsWith('\ufeff')) {
      normalized = normalized.substring(1);
    }
    normalized = normalized.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

    normalized = _repairBrokenSubtasksJson(normalized);

    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Try to salvage JSON if server prepends warnings/noise.
    }

    final candidate = _extractFirstJsonObject(normalized);
    if (candidate != null) {
      final repairedCandidate = _repairBrokenSubtasksJson(candidate);
      try {
        final decoded = jsonDecode(repairedCandidate);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        final dropped = _dropMalformedSubtasksSegments(repairedCandidate);
        try {
          final decoded = jsonDecode(dropped);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {
          return null;
        }
      }
    }

    final dropped = _dropMalformedSubtasksSegments(normalized);
    try {
      final decoded = jsonDecode(dropped);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Give up after all repairs.
    }

    return null;
  }

  static String? _extractFirstJsonObject(String input) {
    final start = input.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < input.length; i++) {
      final ch = input[i];

      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          return input.substring(start, i + 1);
        }
      }
    }

    return null;
  }

  static String _repairBrokenSubtasksJson(String input) {
    var output = input;

    // Fix payloads shaped like: "subtasks":"[{"text":"a"}]"
    // by unwrapping the quoted JSON array into a real array.
    final malformedSubtasksPattern = RegExp(
      r'"subtasks"\s*:\s*"(\[[\s\S]*?\])"',
      multiLine: true,
    );

    output = output.replaceAllMapped(malformedSubtasksPattern, (match) {
      final inner = match.group(1);
      if (inner == null || inner.isEmpty) {
        return '"subtasks":[]';
      }
      return '"subtasks":$inner';
    });

    return output;
  }

  static String _dropMalformedSubtasksSegments(String input) {
    var output = input;
    var searchFrom = 0;

    while (true) {
      final keyIndex = output.indexOf('"subtasks"', searchFrom);
      if (keyIndex < 0) break;

      final colonIndex = output.indexOf(':', keyIndex);
      if (colonIndex < 0) break;

      final nextCandidates = <int>[];
      for (final marker in [
        ',"category"',
        ',"priority"',
        ',"status"',
        ',"deadline_date"',
        ',"created_by"',
        ',"assigned_to"',
        '}',
      ]) {
        final idx = output.indexOf(marker, colonIndex + 1);
        if (idx >= 0) nextCandidates.add(idx);
      }

      if (nextCandidates.isEmpty) {
        searchFrom = colonIndex + 1;
        continue;
      }

      nextCandidates.sort();
      final endIndex = nextCandidates.first;

      output =
          '${output.substring(0, keyIndex)}"subtasks":[]${output.substring(endIndex)}';
      searchFrom = keyIndex + '"subtasks":[]'.length;
    }

    return output;
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
        final baseCandidates = ApiConfig.localDevBaseUrlCandidates;
        final seen = <String>{};
        final candidates = <String>[];
        for (final base in [ApiConfig.baseUrl, ...baseCandidates]) {
          final trimmed = base.trim();
          if (trimmed.isEmpty) continue;
          if (seen.add(trimmed)) {
            candidates.add(trimmed);
          }
        }

        String? lastError;

        for (final baseApiUrl in candidates) {
          final url = _appendTaskQuery(
            baseApiUrl,
            userId,
            userRole,
            needHelpOnly: needHelpOnly,
            targetUserId: targetUserId,
            currentOnly: currentOnly,
            perPage: perPage,
            page: page,
            useCursorPagination: useCursorPagination,
            cursorCreatedAt: cursorCreatedAt,
            cursorId: cursorId,
            view: view,
            includeHistory: includeHistory,
          );

          try {
            final response = await http.get(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
            );

            if (response.statusCode != 200) {
              lastError = _errorMessageFromResponse(response);
              continue;
            }

            final rawBody = utf8.decode(response.bodyBytes, allowMalformed: true);
            final decoded = _tryParseJsonMapLenient(rawBody);
            if (decoded == null) {
              final normalizedRaw = rawBody.toLowerCase();
              if (normalizedRaw.contains('"status":"success"') ||
                  normalizedRaw.contains('"status": "success"')) {
                final safeFallback = <String, dynamic>{
                  'status': 'success',
                  'data': <dynamic>[],
                };
                await LocalCacheService.putJson(
                  cacheKey,
                  safeFallback,
                  ttl: _tasksCacheTtl,
                );
                return safeFallback;
              }

              final preview = rawBody.length > 180
                  ? '${rawBody.substring(0, 180)}...'
                  : rawBody;
              lastError =
                  'Server returned non-JSON task payload. Preview: ${preview.replaceAll('\n', ' ')}';
              continue;
            }

            await LocalCacheService.putJson(
              cacheKey,
              decoded,
              ttl: _tasksCacheTtl,
            );
            return decoded;
          } catch (e) {
            lastError = e.toString();
          }
        }

        throw Exception(lastError ?? 'Failed to load tasks from all API endpoints.');
      } catch (e) {
        if (e is Exception) rethrow;
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
        throw Exception(_errorMessageFromResponse(response));
      }
    } catch (e) {
      if (e is Exception) rethrow;
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
        throw Exception(_errorMessageFromResponse(response));
      }
    } catch (e) {
      if (e is Exception) rethrow;
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
