import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
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
  static const Duration _authLookupTimeout = Duration(seconds: 4);
  static const Duration _authLookupRetryTimeout = Duration(seconds: 9);
  static const Duration _authWarmupWait = Duration(milliseconds: 700);
  static final Map<String, _CachedUserEntry> _prefetchedUsersByPhone = {};
  static final Map<String, Future<Map<String, dynamic>?>> _inflightUserLookups = {};

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

    // Start prefetch immediately and wait briefly if it can finish quickly.
    final warmup = _getOrFetchUserByContact(phone);
    unawaited(warmup);
    try {
      await warmup.timeout(_authWarmupWait);
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

    dynamic match = _getPrefetchedUser(phone);

    // First try dedicated backend lookup so pagination never blocks valid logins.
    if (match == null) {
      match = await _getOrFetchUserByContact(phone);
    }

    if (match == null) {
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
    Map<String, dynamic>? response;

    try {
      response = await ApiService.get(endpoint, timeout: _authLookupTimeout);
    } catch (_) {
      // Retry once with a longer timeout for slow backend/network moments.
      try {
        response = await ApiService.get(
          endpoint,
          timeout: _authLookupRetryTimeout,
        );
      } catch (_) {
        return null;
      }
    }

    if (response['status'] == 'success' && response['data'] != null) {
      final user = Map<String, dynamic>.from(response['data'] as Map);
      return user;
    }

    return null;
  }

  static Future<Map<String, dynamic>> _fetchUsersFallback(String phone) async {
    final endpoint = '/users?search=$phone&per_page=20';
    try {
      return await ApiService.get(endpoint, timeout: _authLookupTimeout);
    } catch (_) {
      return ApiService.get(endpoint, timeout: _authLookupRetryTimeout);
    }
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
