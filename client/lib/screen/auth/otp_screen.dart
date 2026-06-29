import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../admin/admin_dashboard.dart';
import '../employee/employee_dashboard.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  bool _isLoading = false;
  // Tracks whether we've already triggered auto-verify for the current
  // complete OTP so editing an earlier box doesn't re-fire.
  String _lastAutoVerifiedOtp = '';

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _currentOtp => _controllers.map((c) => c.text).join();

  bool get _isComplete => _controllers.every((c) => c.text.length == 1);

  void _clearOtp() {
    for (final c in _controllers) {
      c.clear();
    }
    _lastAutoVerifiedOtp = '';
    _focusNodes[0].requestFocus();
  }

  void _showToast(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _currentOtp;
    if (otp.length != 4 || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final phone = ModalRoute.of(context)!.settings.arguments as String;
      final user = await AuthService.verifyOtp(phone, otp);
      await AuthService.saveSession(user);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (user.role == 'employee') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmployeeDashboard(
              userId: user.id,
              userRole: user.role,
              userName: user.name,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminDashboard(
              userId: user.id,
              userName: user.name,
              userRole: user.role,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      // Clear fields so user re-enters cleanly instead of re-submitting wrong OTP
      _clearOtp();

      String message;
      if (e is ApiTimeoutException ||
          e.toString().toLowerCase().contains('timeout')) {
        message = 'Network is slow. Please try again.';
      } else if (e is ApiNetworkException ||
          e.toString().toLowerCase().contains('unable to reach')) {
        message = 'Cannot connect to server. Check your internet.';
      } else if (e is ApiServerException && e.statusCode >= 500) {
        message = 'Server error. Please try again.';
      } else {
        // Covers "Wrong OTP", "OTP has expired", "User not found", etc.
        final raw = e.toString().replaceFirst('Exception: ', '').trim();
        message = raw.isNotEmpty ? raw : 'Verification failed. Try again.';
      }

      _showToast(message);
    }
  }

  void _onFieldChanged(String value, int index) {
    if (value.isNotEmpty && index < 3) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (!_isLoading && _isComplete) {
      final otp = _currentOtp;
      // Only auto-verify if this is a NEW complete OTP, not the same one
      if (otp != _lastAutoVerifiedOtp) {
        _lastAutoVerifiedOtp = otp;
        FocusScope.of(context).unfocus();
        _verifyOtp();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = ModalRoute.of(context)!.settings.arguments as String;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFceb56e), Color(0xFFd4c088)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'lib/assets/logo.png',
                      height: 60,
                      errorBuilder: (context, error, stack) => const Icon(
                        Icons.task_alt,
                        size: 60,
                        color: Color(0xFFceb56e),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    "Verify OTP",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Enter the 4-digit code for +91 $phone",
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(4, (index) {
                            return SizedBox(
                              width: 55,
                              child: TextField(
                                controller: _controllers[index],
                                focusNode: _focusNodes[index],
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                maxLength: 1,
                                enabled: !_isLoading,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFceb56e),
                                      width: 2,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFceb56e),
                                      width: 2.5,
                                    ),
                                  ),
                                  disabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (value) =>
                                    _onFieldChanged(value, index),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _verifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFceb56e),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Verify',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  if (!mounted) return;
                                  try {
                                    await AuthService.sendOtp(phone);
                                    _showToast(
                                      'OTP resent to +91 $phone',
                                      isError: false,
                                    );
                                  } catch (_) {
                                    _showToast('Failed to resend OTP.');
                                  }
                                },
                          child: const Text(
                            'Resend OTP',
                            style: TextStyle(
                              color: Color(0xFFceb56e),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
