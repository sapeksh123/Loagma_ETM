import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../models/chat_thread_model.dart';
import '../models/chat_message_model.dart';

class ChatService {
  static Future<List<ChatThread>> getThreads({
    required String userId,
    required String role,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads?user_id=$userId&role=$role',
    );
    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

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
    String? sinceMessageId,
  }) async {
    final query =
        sinceMessageId != null ? '?since_id=$sinceMessageId' : '';
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/messages$query',
    );

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
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
      'sender_id': senderId,
      'sender_role': senderRole,
      'body': body,
    };
    if (taskId != null) {
      payload['task_id'] = taskId;
    }
    if (subtaskIndex != null) {
      payload['subtask_index'] = subtaskIndex;
    }

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

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
    required String lastReadMessageId,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/chat/threads/$threadId/read',
    );

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'last_read_message_id': lastReadMessageId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark thread as read');
    }
  }
}

