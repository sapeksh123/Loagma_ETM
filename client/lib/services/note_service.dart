import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class NoteService {
  static Future<String> getMyNote(String userId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/notes/me?user_id=$userId',
      );
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] == 'success') {
          final data = body['data'] as Map<String, dynamic>? ?? {};
          final content = data['content'];
          return content?.toString() ?? '';
        }
        throw Exception(body['message']?.toString() ?? 'Failed to load note');
      }

      if (response.statusCode == 404) {
        return '';
      }

      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<void> saveMyNote(String userId, String content) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/notes/me');
      final payload = jsonEncode({
        'user_id': userId,
        'content': content,
      });
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] == 'success') {
          return;
        }
        throw Exception(body['message']?.toString() ?? 'Failed to save note');
      }

      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}

