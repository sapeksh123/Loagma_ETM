import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class UserService {
  /// Fetch a list of users/employees for admin selection.
  /// Returns a map with 'status' and 'data' keys similar to other services.
  static Future<Map<String, dynamic>> getUsers({
    int perPage = 50,
    int page = 1,
    String search = '',
  }) async {
    try {
      final queryParams = <String, String>{
        'per_page': perPage.toString(),
        'page': page.toString(),
      };

      if (search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }

      final uri = Uri.parse(ApiConfig.usersUrl).replace(
        queryParameters: queryParams,
      );

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}

