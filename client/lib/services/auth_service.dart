import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import 'api_service.dart';

class AuthService {
  static const String _keyAuthUser = 'auth_user';

  // Master OTP for all users (4 digits)
  static const String masterOtp = '1234';

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
    if (otp != masterOtp) {
      throw Exception('Invalid OTP');
    }

    // Resolve the user and primary role from backend "users" table.
    final response = await ApiService.get('/users');
    if (response['status'] != 'success') {
      throw Exception('Unable to fetch users from server');
    }

    final List<dynamic> users = response['data'] ?? [];

    final dynamic match = users.firstWhere(
      (u) => (u['contactNumber'] ?? '').toString() == phone,
      orElse: () => null,
    );

    if (match == null) {
      // User not found in DB, stop login.
      throw Exception('User not found');
    }

    // Business rule based on your DB (roles table screenshot):
    //   R001 => admin
    //   R006 => subadmin
    //   R007 => technincharge
    //   others => treated as employee inside this app
    final roleId = match['roleId']?.toString();
    String appRole;
    switch (roleId) {
      case 'R001':
        appRole = 'admin';
        break;
      case 'R006':
        appRole = 'subadmin';
        break;
      case 'R007':
        appRole = 'techincharge';
        break;
      default:
        appRole = 'employee';
        break;
    }

    final isManagerRole =
        appRole == 'admin' || appRole == 'subadmin' || appRole == 'techincharge';

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

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAuthUser);
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
