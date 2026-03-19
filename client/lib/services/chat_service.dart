import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../models/chat_thread_model.dart';
import '../models/chat_message_model.dart';
import '../models/chat_user_model.dart';

class ChatService {
  static Map<String, String> _chatHeaders({
    required String userId,
    required String userRole,
  }) {
    return {
      'Content-Type': 'application/json',
      'X-User-Id': userId,
      'X-User-Role': userRole,
    };
  }

  static Future<List<ChatUser>> getChatUsers({
    required String currentUserId,
    int perPage = 100,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/users?per_page=$perPage&page=1',
    );

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Failed to load users for chat');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => ChatUser.fromJson(Map<String, dynamic>.from(e)))
          .where((u) => u.id.isNotEmpty && u.id != currentUserId)
          .toList();
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

    final response = await http.post(
      uri,
      headers: _chatHeaders(userId: userAId, userRole: userRole),
      body: jsonEncode(payload),
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
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/threads');
    final response = await http.get(
      uri,
      headers: _chatHeaders(userId: userId, userRole: role),
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Failed to load chat threads');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => ChatThread.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  static Future<List<ChatMessage>> getMessages({
    required String threadId,
    required String userId,
    required String userRole,
    String? sinceMessageId,
  }) async {
    final queryParams = <String, String>{};
    if (sinceMessageId != null) {
      queryParams['since_id'] = sinceMessageId;
    }

    final query = Uri(queryParameters: queryParams).query;
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages?$query',
    );

    final response = await http.get(
      uri,
      headers: _chatHeaders(userId: userId, userRole: userRole),
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
    String? taskId,
    int? subtaskIndex,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages',
    );

    final payload = <String, dynamic>{
      'body': body,
    };
    if (taskId != null) {
      payload['task_id'] = taskId;
    }
    if (subtaskIndex != null) {
      payload['subtask_index'] = subtaskIndex;
    }

    late http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: _chatHeaders(userId: senderId, userRole: senderRole),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw Exception('Message sending timed out. Please try again.');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>?;
        final message = data?['message'] ??
            (data?['errors'] != null ? data!['errors'].toString() : null);
        if (message != null && message.toString().trim().isNotEmpty) {
          throw Exception(message.toString().trim());
        }
      } catch (_) {}
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
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/read',
    );

    final response = await http
        .post(
          uri,
          headers: _chatHeaders(userId: userId, userRole: userRole),
          body: jsonEncode({
            'last_read_message_id': lastReadMessageId,
          }),
        )
        .timeout(const Duration(seconds: 10));

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

    final response = await http.post(
      uri,
      headers: _chatHeaders(userId: userId, userRole: userRole),
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

    final response = await http.post(
      uri,
      headers: _chatHeaders(userId: userId, userRole: userRole),
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

    final response = await http.get(
      uri,
      headers: _chatHeaders(userId: userId, userRole: userRole),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load reactions');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e)))
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

    final response = await http.post(
      uri,
      headers: _chatHeaders(userId: userId, userRole: userRole),
      body: jsonEncode({'emoji': emoji}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to add reaction');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e)))
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

    final response = await http.delete(
      uri,
      headers: _chatHeaders(userId: userId, userRole: userRole),
      body: jsonEncode({'emoji': emoji}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove reaction');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    final list = data?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => ChatMessageReaction.fromJson(Map<String, dynamic>.from(e)))
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

    final response = await http.post(
      uri,
      headers: _chatHeaders(userId: userId, userRole: userRole),
      body: jsonEncode({'is_typing': isTyping}),
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

    final response = await http.post(
      uri,
      headers: _chatHeaders(userId: userId, userRole: userRole),
      body: jsonEncode({'is_online': isOnline}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update presence');
    }
  }
}

