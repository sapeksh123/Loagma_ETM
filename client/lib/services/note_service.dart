import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import '../models/note_model.dart';

class NoteService {
  static const Duration _notesCacheTtl = Duration(seconds: 45);
  static final Map<String, _NotesCacheEntry> _notesCache = {};

  static Map<String, String> _headers({
    required String userId,
    required String userRole,
  }) {
    return {
      'Content-Type': 'application/json',
      'X-User-Id': userId,
      'X-User-Role': userRole,
    };
  }

  static Future<List<Note>> listNotes(
    String userId,
    String userRole, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$userRole:$userId';
    final cached = _notesCache[cacheKey];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _notesCacheTtl) {
      return List<Note>.from(cached.notes);
    }

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/notes');
      final response = await http.get(
        uri,
        headers: _headers(userId: userId, userRole: userRole),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] == 'success') {
          final data = body['data'] as List<dynamic>? ?? [];
          final notes = data
              .map((e) => Note.fromJson(e as Map<String, dynamic>))
              .toList();
          _notesCache[cacheKey] = _NotesCacheEntry(
            notes: List<Note>.from(notes),
            fetchedAt: DateTime.now(),
          );
          return notes;
        }
        throw Exception(body['message']?.toString() ?? 'Failed to list notes');
      }
      throw Exception('Server error: ${response.statusCode}');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static void invalidateNotesCache(String userId, String userRole) {
    _notesCache.remove('$userRole:$userId');
  }

  static Future<Note> getNote(
    String userId,
    String userRole,
    String noteId,
  ) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/notes/${Uri.encodeComponent(noteId)}',
      );
      final response = await http.get(
        uri,
        headers: _headers(userId: userId, userRole: userRole),
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
    required String userRole,
    required String folderName,
    required String title,
    String? content,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/notes');
      final payload = jsonEncode({
        'folder_name': folderName,
        'title': title,
        if (content != null) 'content': content,
      });
      final response = await http.post(
        uri,
        headers: _headers(userId: userId, userRole: userRole),
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
    String userRole,
    String noteId, {
    String? folderName,
    String? title,
    String? content,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/notes/${Uri.encodeComponent(noteId)}',
      );
      final payload = <String, dynamic>{};
      if (folderName != null) payload['folder_name'] = folderName;
      if (title != null) payload['title'] = title;
      if (content != null) payload['content'] = content;

      final response = await http.put(
        uri,
        headers: _headers(userId: userId, userRole: userRole),
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

  static Future<void> deleteNote(
    String userId,
    String userRole,
    String noteId,
  ) async {
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/notes/${Uri.encodeComponent(noteId)}',
      );
      final response = await http.delete(
        uri,
        headers: _headers(userId: userId, userRole: userRole),
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

  static Future<String> getMyNote(String userId, String userRole) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/notes/me');
      final response = await http.get(
        uri,
        headers: _headers(userId: userId, userRole: userRole),
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

  static Future<void> saveMyNote(
    String userId,
    String userRole,
    String content,
  ) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/notes/me');
      final payload = jsonEncode({
        'content': content,
      });
      final response = await http.put(
        uri,
        headers: _headers(userId: userId, userRole: userRole),
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

class _NotesCacheEntry {
  final List<Note> notes;
  final DateTime fetchedAt;

  _NotesCacheEntry({
    required this.notes,
    required this.fetchedAt,
  });
}

