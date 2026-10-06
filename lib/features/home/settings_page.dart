import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

import '../auth/auth_page.dart';
import '../auth/otp_verification_screen.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    return _buildSecondaryPage(
      icon: Icons.settings_rounded,
      title: 'Settings',
      child: Column(
        children: [
          _buildSettingTile(
            Icons.notifications_none_rounded,
            'Notifications',
            'Daily learning reminders',
            trailing: Switch(
              value: _notificationsEnabled,
              onChanged: (value) => setState(() => _notificationsEnabled = value),
            ),
          ),
          _buildSettingTile(
            Icons.language_rounded,
            'Learning language',
            'Filipino Sign Language',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF6B8581),
            ),
          ),
          _buildSettingTile(
            Icons.help_outline_rounded,
            'Help and feedback',
            'Get support or share feedback',
            trailing: const Icon(git remote set-url origin https://github.com

              Icons.chevron_right_rounded,
              color: Color(0xFF6B8581),
            ),
          ),
          _buildAccountActionTile(
            icon: Icons.alternate_email_rounded,
            title: 'Change email',
            subtitle: Supabase.instance.client.auth.currentUser?.email ?? '',
            onTap: _showChangeEmailDialog,
          ),
          _buildAccountActionTile(
            icon: Icons.password_rounded,
            title: 'Change password',
            subtitle: 'Update your account password',
            onTap: _showChangePasswordDialog,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _deleteAccount,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete Account'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB42318),
                side: const BorderSide(color: Color(0xFFF0B8B2), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB42318),
                side: const BorderSide(color: Color(0xFFF0B8B2), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
          

  Widget _buildSecondaryPage({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF087F73), size: 27),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF153B39),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          child,
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    IconData icon,
    String title,
    String subtitle, {
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EEEB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF087F73)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF153B39),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6B8581),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildAccountActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EEEB)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(icon, color: const Color(0xFF087F73)),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF153B39),
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF6B8581), fontSize: 12),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF6B8581),
          ),
        ),
      ),
    );
  }

  Future<void> _showChangeEmailDialog() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final currentEmail = Supabase.instance.client.auth.currentUser?.email ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Change email'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'New email address',
                  ),
                  validator: (value) {
                    if (value == null || !value.contains('@')) {
                      return 'Enter a valid email';
                    }
                    if (value.trim() == currentEmail) {
                      return 'New email must be different from current email';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final newEmail = emailController.text.trim();
                Navigator.pop(dialogContext);
                await _sendOtpAndVerify(
                  email: newEmail,
                  type: OtpType.emailChange,
                  onVerified: () async {
                    try {
                      await Supabase.instance.client.auth.updateUser(
                        UserAttributes(email: newEmail),
                      );
                      if (mounted) {
                        _showMessage('Verification email sent to new address.');
                      }
                    } on AuthException catch (e) {
                      if (mounted) _showMessage(_accountErrorMessage(e.code ?? ''), isError: true);
                    }
                  },
                );
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    emailController.dispose();
  }

Future<void> _showChangePasswordDialog() async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Change password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: newPasswordController,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscureNew = !obscureNew),
                    ),
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    final msg = passwordValidationMessage(value);
                    if (msg != null) return msg;
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setDialogState(
                          () => obscureConfirm = !obscureConfirm),
                    ),
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    if (value != newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext);
                final currentUser = Supabase.instance.client.auth.currentUser;
                if (currentUser == null) return;
                await _sendOtpAndVerify(
                  email: currentUser.email!,
                  type: OtpType.recovery, // use recovery OTP for password change verification
                  onVerified: () async {
                    try {
                      await Supabase.instance.client.auth.updateUser(
                        UserAttributes(password: newPasswordController.text.trim()),
                      );
                      if (mounted) {
                        _showMessage('Password updated – confirmation email sent.');
                      }
                    } on AuthException catch (e) {
                      if (mounted) _showMessage(_accountErrorMessage(e.code ?? ''), isError: true);
                    }
                  },
                );
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  String _accountErrorMessage(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Your current password is incorrect.';
      case 'email-already-in-use':
        return 'That email is already in use.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Choose a stronger password with at least 6 characters.';
      case 'requires-recent-login':
        return 'Please sign in again before changing your account details.';
      default:
        return 'Could not update your account details. Please try again.';
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFB42318)
              : const Color(0xFF087F73),
        ),
      );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));
    }
  }

  Future<void> _deleteAccount() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to permanently delete your account? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    // Send OTP for re-authentication
    await _sendOtpForReauthentication(user.email!);
  }

  Future<void> _sendOtpForReauthentication(String email) async {
    await Supabase.instance.client.auth
        .signInWithOtp(email: email, shouldCreateUser: false);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          email: email,
          action: 'reauthenticate',
          onDelete: _deleteAccountWithOtpVerified,
        ),
      ),
    );
  }

  Future<void> _deleteAccountWithOtpVerified() async {
    // OTP verified, now delete the account
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // Delete the user via Supabase admin API
      await Supabase.instance.client.auth.admin.deleteUser(user.id);
      if (!mounted) return;
      // Sign out and navigate to home
      await Supabase.instance.client.auth.signOut();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthPage()),
      );
      _showMessage('Account permanently deleted.');
    } on AuthException catch (e) {
      if (!mounted) return;
      _showMessage(_accountErrorMessage(e.code ?? ''), isError: true);
    }
  }

  Future<void> _sendOtpAndVerify({
    required String email,
    required OtpType type,
    required Future<void> Function() onVerified,
  }) async {
    final auth = Supabase.instance.client.auth;
    try {
      await auth.signInWithOtp(email: email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OtpVerificationScreen(
            email: AutofillHints.email,
            action: 'reauthenticate',
          ),
          ),
        );
} catch (e) {
      if (mounted) _showMessage(e.toString(), isError: true);
    }
  }

  String? passwordValidationMessage(String? value) {
    if (value == null || value.isEmpty) return 'Enter a password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }
}