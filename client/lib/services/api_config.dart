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
    defaultValue: false,
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
  static const String _localReverbHostOverride = String.fromEnvironment(
    'LOCAL_REVERB_HOST',
    defaultValue: '',
  );
  static const int _localReverbPortOverride = int.fromEnvironment(
    'LOCAL_REVERB_PORT',
    defaultValue: 8080,
  );
  static const String _localReverbSchemeOverride = String.fromEnvironment(
    'LOCAL_REVERB_SCHEME',
    defaultValue: 'http',
  );

  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration chatRequestTimeout = Duration(seconds: 30);
  static const Duration chatSendTimeout = Duration(seconds: 30);

  static const String _reverbKeyOverride = String.fromEnvironment(
    'REVERB_APP_KEY',
    defaultValue: '',
  );
  static const String _reverbHostOverride = String.fromEnvironment(
    'REVERB_HOST',
    defaultValue: '',
  );
  static const String _reverbSchemeOverride = String.fromEnvironment(
    'REVERB_SCHEME',
    defaultValue: '',
  );
  static const int _reverbPortOverride = int.fromEnvironment(
    'REVERB_PORT',
    defaultValue: 0,
  );

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
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        return 'http://127.0.0.1:8000/api'; // Desktop app on same machine
      }
      return _localNetworkBaseUrl; // Physical device or desktop app
    } catch (_) {
      return _localNetworkBaseUrl;
    }
  }

  /// Candidate base URLs used for local-development GET retries.
  /// Order matters: fastest/common first, then LAN fallback.
  static List<String> get localDevBaseUrlCandidates {
    final candidates = <String>[];

    void addCandidate(String value) {
      final normalized = value.trim();
      if (normalized.isEmpty) return;
      if (!candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    addCandidate(baseUrl);

    if (!useProduction && _baseUrlOverride.trim().isEmpty) {
      addCandidate('http://127.0.0.1:8000/api');
      addCandidate('http://10.0.2.2:8000/api');
      addCandidate(_localNetworkBaseUrl);
    }

    return candidates;
  }

  // Endpoints
  static String get authUrl => '$baseUrl/auth';
  static String get usersUrl => '$baseUrl/users';
  static String get accountsUrl => '$baseUrl/accounts';
  static String get locationsUrl => '$baseUrl/locations';
  static String get notificationsUrl => '$baseUrl/notifications';

  static String get reverbAppKey {
    final override = _reverbKeyOverride.trim();
    return override.isNotEmpty ? override : 'knobdmhfjp4y8jssxhj1';
  }

  static Uri get _baseUri => Uri.parse(baseUrl);

  static String get reverbHost {
    final override = _reverbHostOverride.trim();
    if (override.isNotEmpty) {
      return override;
    }

    if (!useProduction) {
      final localOverride = _localReverbHostOverride.trim();
      if (localOverride.isNotEmpty) {
        return localOverride;
      }

      if (kIsWeb) return 'localhost';

      try {
        if (Platform.isAndroid) {
          return '10.0.2.2';
        }
      } catch (_) {
        // Fall through to local network resolution below.
      }

      final localApiUri = Uri.parse(_localNetworkBaseUrl);
      return localApiUri.host;
    }

    return _baseUri.host;
  }

  static String get reverbScheme {
    final override = _reverbSchemeOverride.trim().toLowerCase();
    if (override == 'http' || override == 'https') {
      return override;
    }

    if (!useProduction) {
      final localOverride = _localReverbSchemeOverride.trim().toLowerCase();
      if (localOverride == 'http' || localOverride == 'https') {
        return localOverride;
      }
      return 'http';
    }

    return _baseUri.scheme == 'http' ? 'http' : 'https';
  }

  static bool get reverbUseTls => reverbScheme == 'https';

  static int get reverbPort {
    if (_reverbPortOverride > 0) {
      return _reverbPortOverride;
    }

    if (!useProduction) {
      return _localReverbPortOverride > 0 ? _localReverbPortOverride : 8080;
    }

    if (_baseUri.hasPort) {
      return _baseUri.port;
    }
    return reverbUseTls ? 443 : 80;
  }

  static String get realtimeAuthUrl => '$baseUrl/chat/realtime/auth';
}
