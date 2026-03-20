import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../models/chat_thread_model.dart';
import '../models/chat_message_model.dart';
import '../models/chat_user_model.dart';

class _MemoryCacheEntry<T> {
  final T data;
  final DateTime createdAt;

  _MemoryCacheEntry(this.data) : createdAt = DateTime.now();

  bool isFresh(Duration ttl) => DateTime.now().difference(createdAt) <= ttl;
}

class ChatService {
  static const Duration _requestTimeout = ApiConfig.chatRequestTimeout;
  static const Duration _sendMessageTimeout = ApiConfig.chatSendTimeout;
  static const Duration _retryDelay = Duration(milliseconds: 700);
  static const int _maxRequestAttempts = 2;
  static const int _maxSendAttempts = 2;
  static const Duration _threadsCacheTtl = Duration(seconds: 20);
  static const Duration _usersCacheTtl = Duration(seconds: 60);

  static final Map<String, _MemoryCacheEntry<List<ChatThread>>> _threadsCache =
      {};
  static final Map<String, _MemoryCacheEntry<List<ChatUser>>> _usersCache = {};

  static List<ChatThread>? getCachedThreads({
    required String userId,
    required String role,
  }) {
    final key = '$userId|$role';
    final cached = _threadsCache[key];
    if (cached == null || !cached.isFresh(_threadsCacheTtl)) {
      return null;
    }
    return cached.data;
  }

  static List<ChatUser>? getCachedUsers({
    required String currentUserId,
    int perPage = 100,
  }) {
    final key = '$currentUserId|$perPage';
    final cached = _usersCache[key];
    if (cached == null || !cached.isFresh(_usersCacheTtl)) {
      return null;
    }
    return cached.data;
  }

  static Future<http.Response> _performRequest({
    required Future<http.Response> Function() request,
    required String actionLabel,
    Duration timeout = _requestTimeout,
    int attempts = _maxRequestAttempts,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await request().timeout(timeout);
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt < attempts) {
          await Future.delayed(_retryDelay);
          continue;
        }
      } on SocketException catch (e) {
        lastError = e;
        if (attempt < attempts) {
          await Future.delayed(_retryDelay);
          continue;
        }
      }
    }

    if (lastError is TimeoutException) {
      throw Exception(
        'Request timed out after ${timeout.inSeconds}s while trying to $actionLabel. Please retry.',
      );
    }

    throw Exception(
      'Unable to reach server while trying to $actionLabel. Check internet and retry.',
    );
  }

  static Map<String, String> _chatHeaders({
    required String userId,
    required String userRole,
  }) {
    return {
      'Content-Type': 'application/json',
      'X-User-Id': userId,
      'X-User-Role': userRole,
      'X-Skip-Broadcast': '0',
    };
  }

  static Future<List<ChatUser>> getChatUsers({
    required String currentUserId,
    int perPage = 100,
    bool forceRefresh = false,
  }) async {
    final usersCacheKey = '$currentUserId|$perPage';
    final cachedUsers = _usersCache[usersCacheKey];
    if (!forceRefresh && cachedUsers != null && cachedUsers.isFresh(_usersCacheTtl)) {
      return cachedUsers.data;
    }

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/users?per_page=$perPage&page=1',
    );

    final response = await _performRequest(
      request: () =>
          http.get(uri, headers: {'Content-Type': 'application/json'}),
      actionLabel: 'load users for chat',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load users for chat');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      final users = list
          .whereType<Map>()
          .map((e) => ChatUser.fromJson(Map<String, dynamic>.from(e)))
          .where((u) => u.id.isNotEmpty && u.id != currentUserId)
          .toList();
      _usersCache[usersCacheKey] = _MemoryCacheEntry(users);
      return users;
    }
    return [];
  }

  static Future<ChatThread> openDirectThread({
    required String userAId,
    required String userBId,
    required String userRole,
    String? title,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads/direct');

    final payload = <String, dynamic>{
      'user_a_id': userAId,
      'user_b_id': userBId,
    };
    if (title != null && title.trim().isNotEmpty) {
      payload['title'] = title.trim();
    }

    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: _chatHeaders(userId: userAId, userRole: userRole),
        body: jsonEncode(payload),
      ),
      actionLabel: 'open direct chat',
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to open direct chat');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final thread = data?['data'];
    if (thread is Map<String, dynamic>) {
      return ChatThread.fromJson(thread);
    }
    throw Exception('Invalid direct chat response');
  }

  static Future<List<ChatThread>> getThreads({
    required String userId,
    required String role,
    bool forceRefresh = false,
  }) async {
    final threadsCacheKey = '$userId|$role';
    final cachedThreads = _threadsCache[threadsCacheKey];
    if (!forceRefresh && cachedThreads != null && cachedThreads.isFresh(_threadsCacheTtl)) {
      return cachedThreads.data;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads');
    final response = await _performRequest(
      request: () => http.get(
        uri,
        headers: _chatHeaders(userId: userId, userRole: role),
      ),
      actionLabel: 'load chat threads',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load chat threads');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      final threads = list
          .whereType<Map>()
          .map((e) => ChatThread.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _threadsCache[threadsCacheKey] = _MemoryCacheEntry(threads);
      return threads;
    }
    return [];
  }

  static Future<List<ChatMessage>> getMessages({
    required String threadId,
    required String userId,
    required String userRole,
    String? sinceMessageId,
    bool includeReactions = false,
    int limit = 80,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'include_reactions': includeReactions ? '1' : '0',
    };
    if (sinceMessageId != null) {
      queryParams['since_id'] = sinceMessageId;
    }

    final query = Uri(queryParameters: queryParams).query;
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages?$query',
    );

    final response = await _performRequest(
      request: () => http.get(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
      ),
      actionLabel: 'load chat messages',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load chat messages');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  static Future<ChatMessage> sendMessage({
    required String threadId,
    required String senderId,
    required String senderRole,
    required String body,
    String? clientMessageId,
    String? taskId,
    int? subtaskIndex,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages',
    );

    final payload = <String, dynamic>{'body': body};
    if (clientMessageId != null && clientMessageId.trim().isNotEmpty) {
      payload['client_message_id'] = clientMessageId.trim();
    }
    if (taskId != null) {
      payload['task_id'] = taskId;
    }
    if (subtaskIndex != null) {
      payload['subtask_index'] = subtaskIndex;
    }

    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: _chatHeaders(userId: senderId, userRole: senderRole),
        body: jsonEncode(payload),
      ),
      actionLabel: 'send message',
      timeout: _sendMessageTimeout,
      attempts: _maxSendAttempts,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        final message =
            data?['message'] ??
            (data?['errors'] != null ? data!['errors'].toString() : null);
        if (message != null && message.toString().trim().isNotEmpty) {
          throw Exception(message.toString().trim());
        }
      } on FormatException {
        // Ignore invalid JSON body and fallback to generic status message.
      }
      throw Exception('Failed to send message (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final msgJson = data?['data'] as Map<String, dynamic>?;
    if (msgJson == null) {
      throw Exception('Invalid response from server');
    }
    return ChatMessage.fromJson(msgJson);
  }

  static Future<void> markThreadRead({
    required String threadId,
    required String userId,
    required String userRole,
    required String lastReadMessageId,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads/$threadId/read');

    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({'last_read_message_id': lastReadMessageId}),
      ),
      actionLabel: 'mark thread as read',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark thread as read');
    }
  }

  static Future<void> markMessageDelivered({
    required String threadId,
    required String messageId,
    required String userId,
    required String userRole,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages/$messageId/delivered',
    );

    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
      ),
      actionLabel: 'mark message as delivered',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark message as delivered');
    }
  }

  static Future<void> markMessageSeen({
    required String threadId,
    required String messageId,
    required String userId,
    required String userRole,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages/$messageId/seen',
    );

    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
      ),
      actionLabel: 'mark message as seen',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark message as seen');
    }
  }

  static Future<List<ChatMessageReaction>> getReactions({
    required String threadId,
    required String messageId,
    required String userId,
    required String userRole,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages/$messageId/reactions',
    );

    final response = await _performRequest(
      request: () => http.get(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
      ),
      actionLabel: 'load reactions',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load reactions');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map(
            (e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    }
    return [];
  }

  static Future<List<ChatMessageReaction>> addReaction({
    required String threadId,
    required String messageId,
    required String userId,
    required String userRole,
    required String emoji,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages/$messageId/reactions',
    );

    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({'emoji': emoji}),
      ),
      actionLabel: 'add reaction',
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to add reaction');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map(
            (e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    }
    return [];
  }

  static Future<List<ChatMessageReaction>> removeReaction({
    required String threadId,
    required String messageId,
    required String userId,
    required String userRole,
    required String emoji,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages/$messageId/reactions',
    );

    final response = await _performRequest(
      request: () => http.delete(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({'emoji': emoji}),
      ),
      actionLabel: 'remove reaction',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove reaction');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map(
            (e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    }
    return [];
  }

  static Future<void> setTyping({
    required String threadId,
    required String userId,
    required String userRole,
    required bool isTyping,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads/$threadId/typing');

    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({'is_typing': isTyping}),
      ),
      actionLabel: 'update typing state',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update typing state');
    }
  }

  static Future<void> setPresence({
    required String userId,
    required String userRole,
    required bool isOnline,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/presence');

    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: _chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({'is_online': isOnline}),
      ),
      actionLabel: 'update presence',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update presence');
    }
  }

  static Stream<List<ChatMessage>> watchThreadMessages({
    required String threadId,
    required String userId,
    required String userRole,
    String? initialSinceMessageId,
    Duration interval = const Duration(seconds: 2),
    int limit = 30,
  }) async* {
    var sinceId = initialSinceMessageId;

    while (true) {
      try {
        final updates = await getMessages(
          threadId: threadId,
          userId: userId,
          userRole: userRole,
          sinceMessageId: sinceId,
          limit: limit,
        );

        if (updates.isNotEmpty) {
          sinceId = updates.last.id;
          yield updates;
        }
      } catch (_) {
        // Swallow transient network failures and keep stream alive.
      }

      await Future.delayed(interval);
    }
  }

  static Stream<List<ChatThread>> watchThreads({
    required String userId,
    required String role,
    Duration interval = const Duration(seconds: 5),
  }) async* {
    while (true) {
      try {
        final threads = await getThreads(
          userId: userId,
          role: role,
          forceRefresh: true,
        );
        yield threads;
      } catch (_) {
        // Keep watcher alive on transient failures.
      }
      await Future.delayed(interval);
    }
  }
}
