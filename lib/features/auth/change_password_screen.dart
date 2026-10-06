import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_page.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String email;

  const ChangePasswordScreen({
    required this.email,
    super.key,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

 String? passwordValidationMessage(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Enter a password.';
  }

  if (value.length < 8) {
    return 'Password must be at least 8 characters long.';
  }

  if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
    return 'Password must include 1 special character.';
  }

  if (!RegExp(r'\d').hasMatch(value)) {
    return 'Password must include 1 number.';
  }

  if (!RegExp(r'[A-Z]').hasMatch(value)) {
    return 'Password must include 1 capital letter.';
  }

  return null;
}

  Future<void> _changePassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showError('Please enter all fields');
      return;
    }

    if (newPassword != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (!mounted) return;
      _showSuccess('Password changed successfully!');

      // Navigate to home page
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _showError(_authErrorMessage(e.message));
    } catch (e) {
      if (!mounted) return;
      _showError('An unexpected error occurred.');
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

  String _authErrorMessage(String? message) {
    if (message == null) return 'Something went wrong. Please try again.';
    final lower = message.toLowerCase();
    if (lower.contains('invalid email') || lower.contains('invalid-credential')) {
      return 'Enter a valid email address.';
    }
    if (lower.contains('wrong-password') || lower.contains('invalid-credential') || lower.contains('user-not-found')) {
      return 'The email or password is incorrect.';
    }
    if (lower.contains('weak-password')) {
      return 'Choose a stronger password with at least 6 characters.';
    }
    if (lower.contains('too-many-requests') || lower.contains('rate limit')) {
      return 'Too many attempts. Please try again later.';
    }
    if (lower.contains('email not verified') || lower.contains('email_confirmation_required')) {
      return 'Please verify your email before signing in.';
    }
    return message;
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
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
        title: const Text('Change Password'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_reset, size: 80, color: Color(0xFF087F73)),
              const SizedBox(height: 24),
              Text(
                'Enter your new password',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF153B39),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a password reset link to your email. Create a new password below.',
                style: const TextStyle(color: Color(0xFF64807C), fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildField(
                controller: _newPasswordController,
                label: 'New password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscureNewPassword,
                validator: passwordValidationMessage,
                suffix: IconButton(
                  onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                  icon: Icon(_obscureNewPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _confirmPasswordController,
                label: 'Confirm password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirmPassword,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Enter confirm password';
                  if (value != _newPasswordController.text) return 'Passwords do not match';
                  return null;
                },
                suffix: IconButton(
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _changePassword,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        backgroundColor: const Color(0xFF087F73),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Change Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF5FAF9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE3EFEC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE06A5F)),
        ),
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
      ),
    );
  }
}