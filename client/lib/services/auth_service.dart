import '../models/user_model.dart';
import 'api_service.dart';

class AuthService {
  // Master OTP for all users (4 digits)
  static const String masterOtp = '1234';

  // Admin phone number
  static const String adminPhone = '9999999999';

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

    // Business rule based on your DB:
    // - roles table has id R001 with name 'admin'
    // - users.roleId = R001  => Admin dashboard
    // - Any other roleId     => Employee dashboard
    final roleId = match['roleId']?.toString();
    final bool isAdminFromRoles = roleId == 'R001';

    return User(
      id: match['id']?.toString() ?? phone,
      name: match['name']?.toString().isNotEmpty == true
          ? match['name'].toString()
          : (isAdminFromRoles ? 'Admin User' : 'Employee User'),
      phone: match['contactNumber']?.toString().isNotEmpty == true
          ? match['contactNumber'].toString()
          : phone,
      role: isAdminFromRoles ? 'admin' : 'employee',
      email: match['email']?.toString(),
    );
  }

  static Future<void> logout() async {
    // Clear any stored data
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
