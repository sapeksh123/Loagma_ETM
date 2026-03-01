import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class ApiService {
  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        // Surface the backend message so user sees e.g. "You have already taken a lunch break today."
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>?;
          final message = data?['message'] ??
              (data?['errors'] != null ? data!['errors'].toString() : null);
          if (message != null && message.toString().trim().isNotEmpty) {
            throw Exception(message.toString().trim());
          }
        } on FormatException {
          // JSON parse failed
        }
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}$endpoint'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>?;
          final message = data?['message'] ??
              (data?['errors'] != null ? data!['errors'].toString() : null);
          if (message != null && message.toString().trim().isNotEmpty) {
            throw Exception(message.toString().trim());
          }
        } on FormatException {
          // JSON parse failed
        }
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}
