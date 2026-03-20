// lib/config/api_config.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized API Configuration.
class ApiConfig {
  /// Toggle between environments.
  /// - Set to false for local development.
  /// - Set to true for production/deployed backend.
  ///
  /// You can override without code changes using:
  /// --dart-define=USE_PRODUCTION_API=true
  /// --dart-define=API_BASE_URL=https://example.com/api
  static const bool useProduction = bool.fromEnvironment(
    'USE_PRODUCTION_API',
    defaultValue: true,
  );

  static const String productionBaseUrl = 'https://loagma-etm.onrender.com/api';
  static const String _baseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// For real devices on local Wi-Fi, override via:
  /// --dart-define=LOCAL_API_BASE_URL=http://<your-lan-ip>:8000/api
  static const String _localNetworkBaseUrl = String.fromEnvironment(
    'LOCAL_API_BASE_URL',
    defaultValue: 'http://192.168.1.8:8000/api',
  );

  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration chatRequestTimeout = Duration(seconds: 30);
  static const Duration chatSendTimeout = Duration(seconds: 35);

  static String get baseUrl {
    final override = _baseUrlOverride.trim();
    if (override.isNotEmpty) {
      return override;
    }

    if (useProduction) {
      return productionBaseUrl;
    }

    if (kIsWeb) return 'http://localhost:8000/api';

    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8000/api'; // Android emulator
      }
      return _localNetworkBaseUrl; // Physical device or desktop app
    } catch (_) {
      return _localNetworkBaseUrl;
    }
  }

  // Endpoints
  static String get authUrl => '$baseUrl/auth';
  static String get usersUrl => '$baseUrl/users';
  static String get accountsUrl => '$baseUrl/accounts';
  static String get locationsUrl => '$baseUrl/locations';
  static String get notificationsUrl => '$baseUrl/notifications';
}
