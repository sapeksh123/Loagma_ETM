import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class ApiTimeoutException extends ApiException {
  const ApiTimeoutException(super.message);
}

class ApiNetworkException extends ApiException {
  final String? details;

  const ApiNetworkException(super.message, {this.details});
}

class ApiServerException extends ApiException {
  final int statusCode;

  const ApiServerException(this.statusCode, super.message);
}

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
      throw const ApiTimeoutException('Request timeout. Please try again.');
    } on SocketException catch (e) {
      throw ApiNetworkException(
        'Unable to reach server. Check your internet connection and try again.',
        details: e.message,
      );
    } on http.ClientException catch (e) {
      throw ApiNetworkException(
        'Unable to reach server. Check your internet connection and try again.',
        details: e.message,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiNetworkException('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> get(String endpoint, {Duration? timeout}) async {
    final resolvedTimeout = timeout ?? ApiConfig.requestTimeout;
    final candidates = ApiConfig.localDevBaseUrlCandidates;
    ApiException? lastNetworkError;

    for (final baseUrl in candidates) {
      try {
        final response = await _client
            .get(
              Uri.parse('$baseUrl$endpoint'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(resolvedTimeout);

        return _parseResponse(response, allowedStatuses: const {200});
      } on ApiTimeoutException catch (e) {
        lastNetworkError = e;
      } on TimeoutException {
        lastNetworkError = const ApiTimeoutException(
          'Request timeout. Please try again.',
        );
      } on SocketException catch (e) {
        lastNetworkError = ApiNetworkException(
          'Unable to reach server. Check your internet connection and try again.',
          details: e.message,
        );
      } on http.ClientException catch (e) {
        lastNetworkError = ApiNetworkException(
          'Unable to reach server. Check your internet connection and try again.',
          details: e.message,
        );
      } on ApiNetworkException catch (e) {
        lastNetworkError = e;
      } on ApiServerException {
        rethrow;
      } on ApiException {
        rethrow;
      } catch (e) {
        throw ApiNetworkException('Network error: $e');
      }
    }

    if (lastNetworkError != null) {
      throw lastNetworkError;
    }

    throw const ApiNetworkException(
      'Unable to reach server. Check your internet connection and try again.',
    );
  }

  static Map<String, dynamic> _parseResponse(
    http.Response response, {
    required Set<int> allowedStatuses,
  }) {
    if (allowedStatuses.contains(response.statusCode)) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const ApiServerException(500, 'Unexpected response format');
    }

    String? message;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>?;
      message = data?['message'] ??
          (data?['errors'] != null ? data!['errors'].toString() : null);
    } on FormatException {
      // Ignore and return status-based error.
    }

    final normalizedMessage = (message ?? '').toString().trim();
    throw ApiServerException(
      response.statusCode,
      normalizedMessage.isNotEmpty
          ? normalizedMessage
          : 'Server error: ${response.statusCode}',
    );
  }
}
