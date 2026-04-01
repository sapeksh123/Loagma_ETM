import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import 'api_config.dart';
import 'api_service.dart';

class AuthService {
  static const String _keyAuthUser = 'auth_user';
  static const List<String> appRoles = [
    'admin',
    'subadmin',
    'techincharge',
    'employee',
  ];

  // Master OTP for all users (4 digits)
  static const Set<String> masterOtps = {'5555'};

  // Admin phone number
  static const String adminPhone = '9999999999';
  static const Duration _prefetchTtl = Duration(minutes: 5);
  static const Duration _authLookupTimeoutLocal = Duration(seconds: 4);
  static const Duration _authLookupRetryTimeoutLocal = Duration(seconds: 9);
  static const Duration _authLookupTimeoutProduction = Duration(seconds: 10);
  static const Duration _authLookupRetryTimeoutProduction = Duration(seconds: 18);
  static const Duration _authWarmupWaitLocal = Duration(milliseconds: 700);
  static const Duration _authWarmupWaitProduction = Duration(milliseconds: 1400);
  static const Duration _authBackoffBaseLocal = Duration(milliseconds: 250);
  static const Duration _authBackoffBaseProduction = Duration(milliseconds: 700);
  static const int _authAttemptsLocal = 2;
  static const int _authAttemptsProduction = 3;
  static final Map<String, _CachedUserEntry> _prefetchedUsersByPhone = {};
  static final Map<String, Future<Map<String, dynamic>?>> _inflightUserLookups = {};

  static Duration get _authLookupTimeout => ApiConfig.useProduction
      ? _authLookupTimeoutProduction
      : _authLookupTimeoutLocal;
  static Duration get _authLookupRetryTimeout => ApiConfig.useProduction
      ? _authLookupRetryTimeoutProduction
      : _authLookupRetryTimeoutLocal;
  static Duration get _authWarmupWait => ApiConfig.useProduction
      ? _authWarmupWaitProduction
      : _authWarmupWaitLocal;
  static Duration get _authBackoffBase => ApiConfig.useProduction
      ? _authBackoffBaseProduction
      : _authBackoffBaseLocal;
  static int get _authAttempts =>
      ApiConfig.useProduction ? _authAttemptsProduction : _authAttemptsLocal;

  /// Persist user session so app can restore on next launch.
  static Future<void> saveSession(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthUser, jsonEncode(user.toJson()));
  }

  /// Restore stored user; null if not logged in or session cleared.
  static Future<User?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyAuthUser);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return User.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> sendOtp(String phone) async {
    final normalizedPhone = normalizePhone(phone);
    final backendWarmup = _warmupBackend();
    unawaited(backendWarmup);

    // Start prefetch immediately and wait briefly if it can finish quickly.
    final userWarmup = _getOrFetchUserByContact(phone);
    unawaited(userWarmup);
    try {
      await Future.wait([
        userWarmup.timeout(_authWarmupWait),
        backendWarmup.timeout(_authWarmupWait),
      ]);
    } catch (_) {
      // Keep OTP navigation snappy even if network is slow.
    }

    // If a fresh prefetch exists already, keep it warm.
    final existing = _prefetchedUsersByPhone[normalizedPhone];
    if (existing != null && existing.expiresAt.isAfter(DateTime.now())) {
      return;
    }
  }

  static Future<void> prefetchUserByContact(String phone) async {
    final normalizedPhone = normalizePhone(phone);
    final existing = _prefetchedUsersByPhone[normalizedPhone];
    if (existing != null && existing.expiresAt.isAfter(DateTime.now())) {
      return;
    }

    final user = await _getOrFetchUserByContact(phone);
    if (user == null) return;
    _prefetchedUsersByPhone[normalizedPhone] = _CachedUserEntry(
      user: user,
      expiresAt: DateTime.now().add(_prefetchTtl),
    );
  }

  static Future<User> verifyOtp(String phone, String otp) async {
    // Check if OTP is correct (4-digit master OTP)
    if (!masterOtps.contains(otp)) {
      throw Exception('Invalid OTP');
    }

    // Trigger backend warmup so production cold starts are less likely to
    // impact the first auth lookup.
    final backendWarmup = _warmupBackend();
    unawaited(backendWarmup);
    try {
      await backendWarmup.timeout(_authWarmupWait);
    } catch (_) {
      // Continue to verification even if warmup isn't ready yet.
    }

    dynamic match = _getPrefetchedUser(phone);
    ApiException? byContactError;
    ApiException? fallbackError;

    // First try dedicated backend lookup so pagination never blocks valid logins.
    if (match == null) {
      try {
        match = await _getOrFetchUserByContact(phone);
      } on ApiException catch (e) {
        byContactError = e;
      }
    }

    if (match == null) {
      try {
        final fallbackResponse = await _fetchUsersFallback(phone);
        if (fallbackResponse['status'] != 'success') {
          throw Exception('Unable to fetch users from server');
        }

        final List<dynamic> users = fallbackResponse['data'] ?? [];
        final normalizedInput = normalizePhone(phone);

        match = users.firstWhere(
          (u) => normalizePhone((u['contactNumber'] ?? '').toString()) ==
              normalizedInput,
          orElse: () => null,
        );
      } on ApiException catch (e) {
        fallbackError = e;
        throw _preferredAuthError(primary: byContactError, secondary: fallbackError);
      }
    }

    if (match == null) {
      // User not found in DB, stop login.
      throw Exception('User not found');
    }

    final appRole = mapRoleIdToAppRole(match['roleId']?.toString());

    final isManagerRole =
        appRole == 'admin' ||
        appRole == 'subadmin' ||
        appRole == 'techincharge';

    return User(
      id: match['id']?.toString() ?? phone,
      name: match['name']?.toString().isNotEmpty == true
          ? match['name'].toString()
          : (isManagerRole ? 'Manager User' : 'Employee User'),
      phone: match['contactNumber']?.toString().isNotEmpty == true
          ? match['contactNumber'].toString()
          : phone,
      role: appRole,
      email: match['email']?.toString(),
    );
  }

  static Map<String, dynamic>? _getPrefetchedUser(String phone) {
    final key = normalizePhone(phone);
    final entry = _prefetchedUsersByPhone[key];
    if (entry == null) return null;
    if (entry.expiresAt.isBefore(DateTime.now())) {
      _prefetchedUsersByPhone.remove(key);
      return null;
    }
    return entry.user;
  }

  static Future<Map<String, dynamic>?> _fetchUserByContact(String phone) async {
    return _getOrFetchUserByContact(phone);
  }

  static Future<Map<String, dynamic>?> _getOrFetchUserByContact(String phone) {
    final key = normalizePhone(phone);
    final existing = _inflightUserLookups[key];
    if (existing != null) {
      return existing;
    }

    final future = _fetchUserByContactNetwork(phone).whenComplete(() {
      _inflightUserLookups.remove(key);
    });
    _inflightUserLookups[key] = future;
    return future;
  }

  static Future<Map<String, dynamic>?> _fetchUserByContactNetwork(
    String phone,
  ) async {
    final encodedPhone = Uri.encodeComponent(phone);
    final endpoint = '/users/by-contact/$encodedPhone?view=minimal';
    ApiException? lastError;

    for (var attempt = 1; attempt <= _authAttempts; attempt++) {
      final timeout = attempt == 1 ? _authLookupTimeout : _authLookupRetryTimeout;
      try {
        final response = await ApiService.get(endpoint, timeout: timeout);
        if (response['status'] == 'success' && response['data'] != null) {
          final user = Map<String, dynamic>.from(response['data'] as Map);
          return user;
        }
        return null;
      } on ApiServerException catch (e) {
        if (e.statusCode == 404) {
          return null;
        }
        lastError = e;
      } on ApiTimeoutException catch (e) {
        lastError = e;
      } on ApiNetworkException catch (e) {
        lastError = e;
      }

      if (attempt < _authAttempts) {
        await Future.delayed(_retryDelay(attempt));
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    return null;
  }

  static Future<Map<String, dynamic>> _fetchUsersFallback(String phone) async {
    final endpoint = '/users?search=$phone&per_page=20';
    ApiException? lastError;

    for (var attempt = 1; attempt <= _authAttempts; attempt++) {
      final timeout = attempt == 1 ? _authLookupTimeout : _authLookupRetryTimeout;
      try {
        return await ApiService.get(endpoint, timeout: timeout);
      } on ApiServerException catch (e) {
        if (e.statusCode >= 500) {
          lastError = e;
        } else {
          rethrow;
        }
      } on ApiTimeoutException catch (e) {
        lastError = e;
      } on ApiNetworkException catch (e) {
        lastError = e;
      }

      if (attempt < _authAttempts) {
        await Future.delayed(_retryDelay(attempt));
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    throw const ApiNetworkException('Unable to fetch users from server');
  }

  static Future<void> _warmupBackend() async {
    try {
      await ApiService.get('/health', timeout: const Duration(seconds: 6));
    } catch (_) {
      // Warmup is best-effort only.
    }
  }

  static Duration _retryDelay(int attempt) {
    return Duration(milliseconds: _authBackoffBase.inMilliseconds * attempt);
  }

  static ApiException _preferredAuthError({
    ApiException? primary,
    ApiException? secondary,
  }) {
    final candidates = [secondary, primary].whereType<ApiException>().toList();
    for (final error in candidates) {
      if (error is ApiTimeoutException) return error;
    }
    for (final error in candidates) {
      if (error is ApiNetworkException) return error;
    }
    return candidates.isNotEmpty
        ? candidates.first
        : const ApiNetworkException('Unable to reach server');
  }

  static String normalizePhone(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length >= 10) {
      return digitsOnly.substring(digitsOnly.length - 10);
    }
    return digitsOnly;
  }

  static String mapRoleIdToAppRole(String? roleId) {
    switch (roleId) {
      case 'R001':
        return 'admin';
      case 'R006':
        return 'subadmin';
      case 'R007':
        return 'techincharge';
      default:
        return 'employee';
    }
  }

  static String normalizeAppRole(String? role) {
    final value = (role ?? '').trim().toLowerCase();
    if (appRoles.contains(value)) {
      return value;
    }
    return 'employee';
  }

  static Future<List<User>> getSwitchableUsers({
    int page = 1,
    int perPage = 25,
    String search = '',
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }

    final endpoint = Uri(
      path: '/users',
      queryParameters: query,
    ).toString();

    final response = await ApiService.get(endpoint);
    if (response['status'] != 'success') {
      throw Exception('Unable to fetch users from server');
    }

    final payload = response['data'];
    final List<dynamic> users;
    if (payload is List) {
      users = payload;
    } else if (payload is Map<String, dynamic> && payload['data'] is List) {
      users = payload['data'] as List<dynamic>;
    } else {
      users = [];
    }

    final mapped = users
        .whereType<Map<String, dynamic>>()
        .map(
          (u) => User(
            id: u['id']?.toString() ?? '',
            name: u['name']?.toString().trim().isNotEmpty == true
                ? u['name'].toString().trim()
                : 'Unknown User',
            phone: u['contactNumber']?.toString() ?? '',
            role: mapRoleIdToAppRole(u['roleId']?.toString()),
            email: u['email']?.toString(),
          ),
        )
        .where((u) => u.id.isNotEmpty)
        .toList();

    mapped.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return mapped;
  }

  static Future<User> switchSessionContext({
    required User selectedUser,
    required String selectedRole,
  }) async {
    final switchedUser = User(
      id: selectedUser.id,
      name: selectedUser.name,
      phone: selectedUser.phone,
      role: normalizeAppRole(selectedRole),
      email: selectedUser.email,
    );
    await saveSession(switchedUser);
    return switchedUser;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAuthUser);
    _prefetchedUsersByPhone.clear();
    _inflightUserLookups.clear();
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

class _CachedUserEntry {
  final Map<String, dynamic> user;
  final DateTime expiresAt;

  _CachedUserEntry({
    required this.user,
    required this.expiresAt,
  });
}
