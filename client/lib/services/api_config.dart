// lib/config/api_config.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized API Configuration
/// ✅ Toggle between local and production backend
class ApiConfig {
  /// Toggle between environments
  /// Set to false for local development
  /// Set to true for production/deployed backend
  ///
  /// NOTE: If you're getting "Failed host lookup" errors with the production server,
  /// it might be because the free Render server is sleeping. Try:
  /// 1. Wait 30-60 seconds and retry
  /// 2. Set useProduction = false to use local backend
  /// 3. Make sure your local backend is running on port 5000
  static const bool useProduction = false; // Using production backend on Render

  static String get baseUrl {
    if (useProduction) {
      // 🌍 Your live backend on Render
      // Note: If DNS fails on emulator, try restarting with: flutter run --host-vmservice-port 0
      return 'https://loagma-crm.onrender.com/api';
    } else {
      // 🧪 Local testing
      if (kIsWeb) return 'http://localhost:8000/api';
      try {
        if (Platform.isAndroid) {
          return 'http://10.0.2.2:8000/api'; // Android Emulator
        } else {
          return 'http://192.168.1.9:8000/api'; // Physical Device / iOS
        }
      } catch (_) {
        return 'http://192.168.1.9:8000/api';
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Endpoints
  // ---------------------------------------------------------------------------
  static String get authUrl => '$baseUrl/auth';
  static String get usersUrl => '$baseUrl/users';
  static String get accountsUrl => '$baseUrl/accounts';
  static String get locationsUrl => '$baseUrl/locations';
}
