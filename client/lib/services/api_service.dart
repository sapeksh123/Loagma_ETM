import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class ApiService {
  static final http.Client _client = http.Client();

  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
    {Duration? timeout}
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout ?? ApiConfig.requestTimeout);

      return _parseResponse(response, allowedStatuses: const {200, 201});
    } on TimeoutException {
      throw Exception('Request timeout. Please try again.');
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> get(String endpoint, {Duration? timeout}) async {
    final resolvedTimeout = timeout ?? ApiConfig.requestTimeout;
    final candidates = ApiConfig.localDevBaseUrlCandidates;
    Exception? lastNetworkError;

    for (final baseUrl in candidates) {
      try {
        final response = await _client
            .get(
              Uri.parse('$baseUrl$endpoint'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(resolvedTimeout);

        return _parseResponse(response, allowedStatuses: const {200});
      } on TimeoutException {
        lastNetworkError = Exception('Request timeout. Please try again.');
      } on SocketException catch (e) {
        lastNetworkError = Exception('Network error: ${e.message}');
      } on http.ClientException catch (e) {
        lastNetworkError = Exception('Network error: ${e.message}');
      } on Exception {
        rethrow;
      } catch (e) {
        throw Exception('Network error: $e');
      }
    }

    if (lastNetworkError != null) {
      throw lastNetworkError;
    }

    throw Exception('Network error: Unable to reach server');
  }

  static Map<String, dynamic> _parseResponse(
    http.Response response, {
    required Set<int> allowedStatuses,
  }) {
    if (allowedStatuses.contains(response.statusCode)) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw Exception('Unexpected response format');
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>?;
      final message = data?['message'] ??
          (data?['errors'] != null ? data!['errors'].toString() : null);
      if (message != null && message.toString().trim().isNotEmpty) {
        throw Exception(message.toString().trim());
      }
    } on FormatException {
      // Ignore and return status-based error.
    }

    throw Exception('Server error: ${response.statusCode}');
  }
}
