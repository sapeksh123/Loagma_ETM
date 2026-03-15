import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../models/note_model.dart';

class NoteService {
  static Future<List<Note>> listNotes(String userId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/notes?user_id=$userId',
      );
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] == 'success') {
          final data = body['data'] as List<dynamic>? ?? [];
          return data
              .map((e) => Note.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        throw Exception(body['message']?.toString() ?? 'Failed to list notes');
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Note> getNote(String userId, String noteId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/notes/${Uri.encodeComponent(noteId)}?user_id=$userId',
      );
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] == 'success') {
          final data = body['data'] as Map<String, dynamic>? ?? {};
          return Note.fromJson(data);
        }
        throw Exception(body['message']?.toString() ?? 'Failed to load note');
      }
      if (response.statusCode == 404) {
        throw Exception('Note not found');
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Note> createNote(
    String userId, {
    required String folderName,
    required String title,
    String? content,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/notes');
      final payload = jsonEncode({
        'user_id': userId,
        'folder_name': folderName,
        'title': title,
        if (content != null) 'content': content,
      });
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] == 'success') {
          final data = body['data'] as Map<String, dynamic>? ?? {};
          return Note.fromJson(data);
        }
        throw Exception(body['message']?.toString() ?? 'Failed to create note');
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<void> updateNote(
    String userId,
    String noteId, {
    String? folderName,
    String? title,
    String? content,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/notes/${Uri.encodeComponent(noteId)}?user_id=$userId',
      );
      final payload = <String, dynamic>{};
      if (folderName != null) payload['folder_name'] = folderName;
      if (title != null) payload['title'] = title;
      if (content != null) payload['content'] = content;

      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] == 'success') return;
        throw Exception(body['message']?.toString() ?? 'Failed to update note');
      }
      if (response.statusCode == 404) {
        throw Exception('Note not found');
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<void> deleteNote(String userId, String noteId) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/notes/${Uri.encodeComponent(noteId)}?user_id=$userId',
      );
      final response = await http.delete(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] == 'success') return;
        throw Exception(body['message']?.toString() ?? 'Failed to delete note');
      }
      if (response.statusCode == 404) {
        throw Exception('Note not found');
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

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

