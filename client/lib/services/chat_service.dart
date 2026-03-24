import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../models/chat_message_model.dart';
import '../models/chat_thread_model.dart';
import '../models/chat_user_model.dart';
import 'api_config.dart';

class ChatMessagesPage {
  final List<ChatMessage> messages;
  final bool hasMoreBefore;
  final int? firstSortKey;
  final int? lastSortKey;

  const ChatMessagesPage({
    required this.messages,
    required this.hasMoreBefore,
    this.firstSortKey,
    this.lastSortKey,
  });
}

class ChatService {
  static const Duration _requestTimeout = ApiConfig.chatRequestTimeout;
  static const Duration _sendMessageTimeout = ApiConfig.chatSendTimeout;
  static const Duration _retryDelay = Duration(milliseconds: 400);
  static const Duration _realtimeAuthTimeout = Duration(seconds: 10);
  static const Duration _typingTimeout = Duration(seconds: 3);
  static const Duration _receiptsTimeout = Duration(seconds: 4);
  static const Duration _presenceTimeout = Duration(seconds: 4);

  static Future<http.Response> _performRequest({
    required Future<http.Response> Function() request,
    required String actionLabel,
    Duration timeout = _requestTimeout,
    int attempts = 2,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await request().timeout(timeout);
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      }

      if (attempt < attempts) {
        await Future.delayed(_retryDelay);
      }
    }

    if (lastError is TimeoutException) {
      throw Exception('Request timed out while trying to $actionLabel.');
    }

    throw Exception('Unable to reach server while trying to $actionLabel.');
  }

  static Map<String, String> chatHeaders({
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

  static Future<Map<String, dynamic>> authorizeRealtime({
    required String userId,
    required String userRole,
    required String socketId,
    required String channelName,
  }) async {
    final uri = Uri.parse(ApiConfig.realtimeAuthUrl);
    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({
          'socket_id': socketId,
          'channel_name': channelName,
        }),
      ),
      actionLabel: 'authorize realtime channel',
      timeout: _realtimeAuthTimeout,
      attempts: 1,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to authorize realtime channel');
    }

    return Map<String, dynamic>.from(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<List<ChatUser>> getChatUsers({
    required String currentUserId,
    int perPage = 100,
    int page = 1,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/users?per_page=$perPage&page=$page');
    final response = await _performRequest(
      request: () =>
          http.get(uri, headers: {'Content-Type': 'application/json'}),
      actionLabel: 'load users for chat',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load users for chat');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['data'];
    if (list is! List) return [];

    return list
        .whereType<Map>()
        .map((item) => ChatUser.fromJson(Map<String, dynamic>.from(item)))
        .where((user) => user.id.isNotEmpty && user.id != currentUserId)
        .toList();
  }

  static Future<List<ChatThread>> getThreads({
    required String userId,
    required String role,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads');
    final response = await _performRequest(
      request: () =>
          http.get(uri, headers: chatHeaders(userId: userId, userRole: role)),
      actionLabel: 'load chat threads',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load chat threads');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['data'];
    if (list is! List) return [];

    return list
        .whereType<Map>()
        .map((item) => ChatThread.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<ChatMessagesPage> getMessages({
    required String threadId,
    required String userId,
    required String userRole,
    int? afterSortKey,
    int? beforeSortKey,
    int limit = 80,
    bool includeReactions = false,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'include_reactions': includeReactions ? '1' : '0',
    };
    if (afterSortKey != null) queryParams['after_sort_key'] = '$afterSortKey';
    if (beforeSortKey != null) queryParams['before_sort_key'] = '$beforeSortKey';

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages',
    ).replace(queryParameters: queryParams);

    final response = await _performRequest(
      request: () =>
          http.get(uri, headers: chatHeaders(userId: userId, userRole: userRole)),
      actionLabel: 'load chat messages',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load chat messages');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['data'];
    final meta = data['meta'] is Map<String, dynamic>
        ? data['meta'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final cursor = meta['cursor'] is Map<String, dynamic>
        ? meta['cursor'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final messages = list is List
        ? list
              .whereType<Map>()
              .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
              .toList()
        : <ChatMessage>[];

    return ChatMessagesPage(
      messages: messages,
      hasMoreBefore: meta['has_more_before'] == true,
      firstSortKey: cursor['first_sort_key'] != null
          ? int.tryParse(cursor['first_sort_key'].toString())
          : null,
      lastSortKey: cursor['last_sort_key'] != null
          ? int.tryParse(cursor['last_sort_key'].toString())
          : null,
    );
  }

  static Future<ChatThread> openDirectThread({
    required String userAId,
    required String userBId,
    required String userRole,
    String? title,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads/direct');
    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: chatHeaders(userId: userAId, userRole: userRole),
        body: jsonEncode({
          'user_a_id': userAId,
          'user_b_id': userBId,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        }),
      ),
      actionLabel: 'open direct chat',
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to open direct chat');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatThread.fromJson(Map<String, dynamic>.from(data['data'] as Map));
  }

  static Future<ChatMessage> sendMessage({
    required String threadId,
    required String senderId,
    required String senderRole,
    required String body,
    String? clientMessageId,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads/$threadId/messages');
    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: chatHeaders(userId: senderId, userRole: senderRole),
        body: jsonEncode({
          'body': body,
          if (clientMessageId != null && clientMessageId.trim().isNotEmpty)
            'client_message_id': clientMessageId.trim(),
        }),
      ),
      actionLabel: 'send message',
      timeout: _sendMessageTimeout,
      attempts: 1,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      String message = 'Failed to send message';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final apiMessage = payload['message']?.toString().trim();
        if (apiMessage != null && apiMessage.isNotEmpty) {
          message = apiMessage;
        }
      } catch (_) {
        // Keep fallback message when response is not JSON.
      }
      throw Exception(message);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ChatMessage.fromJson(Map<String, dynamic>.from(data['data'] as Map));
  }

  static Future<void> updateReceipts({
    required String threadId,
    required String userId,
    required String userRole,
    String? deliveredMessageId,
    String? seenMessageId,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads/$threadId/receipts');
    final response = await _performRequest(
      request: () => http.post(
        uri,
        headers: chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({
          if (deliveredMessageId != null) 'delivered_message_id': deliveredMessageId,
          if (seenMessageId != null) 'seen_message_id': seenMessageId,
        }),
      ),
      actionLabel: 'update message receipts',
      timeout: _receiptsTimeout,
      attempts: 1,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update receipts');
    }
  }

  static Future<void> setTyping({
    required String threadId,
    required String userId,
    required String userRole,
    required bool isTyping,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads/$threadId/typing');
    await _performRequest(
      request: () => http.post(
        uri,
        headers: chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({'is_typing': isTyping}),
      ),
      actionLabel: 'update typing state',
      timeout: _typingTimeout,
      attempts: 1,
    );
  }

  static Future<void> setPresence({
    required String userId,
    required String userRole,
    required bool isOnline,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/presence');
    await _performRequest(
      request: () => http.post(
        uri,
        headers: chatHeaders(userId: userId, userRole: userRole),
        body: jsonEncode({'is_online': isOnline}),
      ),
      actionLabel: 'update presence',
      timeout: _presenceTimeout,
      attempts: 1,
    );
  }
}
