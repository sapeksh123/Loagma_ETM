import 'dart:convert';

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
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // In a real app, this would call your backend API
    // For now, we just simulate success
    return;
  }

  static Future<User> verifyOtp(String phone, String otp) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Check if OTP is correct (4-digit master OTP)
    if (!masterOtps.contains(otp)) {
      throw Exception('Invalid OTP');
    }

    dynamic match;

    // First try dedicated backend lookup so pagination never blocks valid logins.
    try {
      final encodedPhone = Uri.encodeComponent(phone);
      final response = await ApiService.get('/users/by-contact/$encodedPhone');
      if (response['status'] == 'success' && response['data'] != null) {
        match = response['data'];
      }
    } catch (_) {
      // Fallback keeps compatibility with older backend versions.
    }

    if (match == null) {
      final fallbackResponse = await ApiService.get(
        '/users?search=$phone&per_page=50',
      );
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
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
