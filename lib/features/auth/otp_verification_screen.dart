import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_page.dart';
import 'change_password_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String action; // 'signup', 'forgot_password', 'signin_with_code', 'reauthenticate'
  final VoidCallback? onDelete; // Callback for delete account after reauth

  const OtpVerificationScreen({
    required this.email,
    required this.action,
    this.onDelete,
    super.key,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _obscureText = true;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

Future<void> _verifyOtp() async {
    setState(() => _isLoading = true);
    try {
      final otp = _otpController.text.trim();
      if (otp.length != 6) {
        _showError('OTP must be 6 digits');
        return;
      }

       // Determine OTP type based on action
       OtpType type;
       if (widget.action == 'signup') {
         type = OtpType.signup;
       } else if (widget.action == 'forgot_password'){
         type = OtpType.recovery;
       } else if (widget.action == 'reauthenticate') {
         type = OtpType.magiclink;
       } else {
         type = OtpType.magiclink;
       }

       await Supabase.instance.client.auth.verifyOTP(
         email: widget.email,
         token: otp,
         type: type,
       );

       if (!mounted) return;
       if (widget.action == 'forgot_password') {
         // For forgot password, after OTP verification navigate to change password screen
         if (!mounted) return;
         Navigator.push(
           context,
           MaterialPageRoute(
             builder: (_) => ChangePasswordScreen(
               email: widget.email,
             ),
           ),
         );
} else if (widget.action == 'reauthenticate') {
          // For reauthenticate, pop back to settings screen and call onDelete
          if (widget.onDelete != null) {
            widget.onDelete!();
          }
          Navigator.pop(context);
        } else {
         // For signup and signin_with_code, go to home
         Navigator.pushAndRemoveUntil(
           context,
           MaterialPageRoute(builder: (_) => const HomePage()),
           (route) => false,
         );
       }
    } on AuthException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      _showError('Invalid OTP. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Color(0xFF087F73)),
              const SizedBox(height: 24),
              Text(
                widget.action == 'signup'
                    ? 'Verify your email'
                    : widget.action == 'forgot_password'
                        ? 'Enter OTP sent to your email'
                        : 'Enter sign-in code',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF153B39),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.action == 'signup'
                    ? 'We sent a 6-digit OTP to your email address'
                    : widget.action == 'forgot_password'
                        ? 'We sent a 6-digit OTP to your email address'
                        : 'We sent a 6-digit OTP to your email address',
                style: const TextStyle(color: Color(0xFF64807C), fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _otpController,
                obscureText: _obscureText,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'OTP Code',
                  prefixIcon: const Icon(Icons.numbers),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureText = !_obscureText),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                maxLength: 6,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        backgroundColor: const Color(0xFF087F73),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Verify OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      
                    ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}