import 'package:flutter/material.dart';
import 'screen/splash_screen.dart';
import 'screen/auth/login_screen.dart';
import 'screen/auth/otp_screen.dart';
import 'screen/admin/admin_dashboard.dart';
// Employee dashboard is pushed with runtime user data from OtpScreen.

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Employee Task Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFceb56e),
          primary: const Color(0xFFceb56e),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFceb56e),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFceb56e),
          foregroundColor: Colors.white,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/otp': (context) => const OtpScreen(),
        // Admin dashboard still uses a simple named route.
        '/admin-dashboard': (context) => const AdminDashboard(),
        // Employee dashboard is now created with runtime user details
        // in OtpScreen via MaterialPageRoute, so no named route is needed.
        // '/employee-dashboard': (context) => const EmployeeDashboard(),
      },
    );
  }
}
