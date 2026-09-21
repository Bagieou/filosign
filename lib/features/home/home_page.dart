import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final _searchController = TextEditingController();
  bool _notificationsEnabled = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_buildDashboard(), _buildProfile(), _buildSettings()];

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBFA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: pages[_selectedIndex],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFD8F3EE),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search FSL lessons, signs, or topics',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2EEEB)),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 17),
            ),
          ),
          const SizedBox(height: 22),
          _buildStreakCard(),
          const SizedBox(height: 28),
          const Text(
            'Keep learning',
            style: TextStyle(
              color: Color(0xFF153B39),
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.school_rounded,
                  title: 'Learn',
                  subtitle: 'New lessons',
                  color: const Color(0xFF087F73),
                  onTap: () => _showComingSoon('Lessons'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.fitness_center_rounded,
                  title: 'Practice',
                  subtitle: 'Test your skills',
                  color: const Color(0xFFE8782F),
                  onTap: () => _showComingSoon('Practice'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'Continue where you left off',
            style: TextStyle(
              color: Color(0xFF153B39),
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 13),
          _buildLessonPreview(),
        ],
      ),
    );
  }

  Widget _buildStreakCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF087F73), Color(0xFF10A99A), Color(0xFFF18A3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26087F73),
            blurRadius: 18,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your learning streak',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                SizedBox(height: 3),
                Text(
                  '3 days',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Keep it going today!',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white,
            size: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2EEEB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF153B39),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF6B8581), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonPreview() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2EEEB)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFD8F3EE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.waving_hand_rounded,
              color: Color(0xFF087F73),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Everyday greetings',
                  style: TextStyle(
                    color: Color(0xFF153B39),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Beginner lesson  ·  20 min',
                  style: TextStyle(color: Color(0xFF6B8581), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showComingSoon('Everyday greetings'),
            icon: const Icon(
              Icons.play_circle_fill_rounded,
              color: Color(0xFFE8782F),
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    final user = FirebaseAuth.instance.currentUser;
    final profileName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'FSL Learner';
    return _buildSecondaryPage(
      icon: Icons.person_rounded,
      title: 'Profile',
      child: Column(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: const Color(0xFFFFE1C8),
            child: Text(
              profileName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFC45E22),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            profileName,
            style: const TextStyle(
              color: Color(0xFF153B39),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            user?.email ?? '',
            style: const TextStyle(color: Color(0xFF6B8581)),
          ),
          const SizedBox(height: 30),
          _buildInfoTile(
            Icons.local_fire_department_outlined,
            'Current streak',
            '3 days',
          ),
          _buildInfoTile(
            Icons.school_outlined,
            'Lessons completed',
            '0 lessons',
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
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
              onChanged: (value) =>
                  setState(() => _notificationsEnabled = value),
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
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF6B8581),
            ),
          ),
          _buildAccountActionTile(
            icon: Icons.alternate_email_rounded,
            title: 'Change email',
            subtitle: FirebaseAuth.instance.currentUser?.email ?? '',
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

  Widget _buildInfoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF153B39),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(value, style: const TextStyle(color: Color(0xFF6B8581))),
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
    final currentPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var isLoading = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Enter a valid email'
                      : null,
                ),
                TextFormField(
                  controller: currentPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your current password'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isLoading = true);
                      var success = false;
                      try {
                        success = await _changeEmail(
                          emailController.text.trim(),
                          currentPasswordController.text,
                        ).timeout(const Duration(seconds: 15));
                      } on TimeoutException {
                        _showMessage(
                          'The request timed out. Please try again.',
                          isError: true,
                        );
                      } catch (_) {
                        _showMessage(
                          'Could not change your email. Please try again.',
                          isError: true,
                        );
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => isLoading = false);
                          if (success) Navigator.pop(dialogContext);
                        }
                        if (success && mounted) {
                          _showMessage('Verification email sent.');
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    emailController.dispose();
    currentPasswordController.dispose();
  }

  Future<void> _showChangePasswordDialog() async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final currentPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var isLoading = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Change password'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (value) => value == null || value.length < 6
                      ? 'Use at least 6 characters'
                      : null,
                ),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  validator: (value) => value != newPasswordController.text
                      ? 'Passwords do not match'
                      : null,
                ),
                TextFormField(
                  controller: currentPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your current password'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isLoading = true);
                      var success = false;
                      try {
                        success = await _changePassword(
                          newPasswordController.text,
                          currentPasswordController.text,
                        ).timeout(const Duration(seconds: 15));
                      } on TimeoutException {
                        _showMessage(
                          'The request timed out. Please try again.',
                          isError: true,
                        );
                      } catch (_) {
                        _showMessage(
                          'Could not change your password. Please try again.',
                          isError: true,
                        );
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => isLoading = false);
                          if (success) Navigator.pop(dialogContext);
                        }
                        if (success && mounted) {
                          _showMessage('Password updated successfully.');
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    currentPasswordController.dispose();
  }

  Future<bool> _reauthenticate(String currentPassword) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      _showMessage('Unable to find the current account.', isError: true);
      return false;
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    return true;
  }

  Future<bool> _changeEmail(String email, String currentPassword) async {
    try {
      if (await _reauthenticate(currentPassword)) {
        await FirebaseAuth.instance.currentUser!.verifyBeforeUpdateEmail(email);
        return true;
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(_accountErrorMessage(error.code), isError: true);
    }
    return false;
  }

  Future<bool> _changePassword(
    String newPassword,
    String currentPassword,
  ) async {
    try {
      if (await _reauthenticate(currentPassword)) {
        await FirebaseAuth.instance.currentUser!.updatePassword(newPassword);
        return true;
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(_accountErrorMessage(error.code), isError: true);
    }
    return false;
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
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => const AuthPage()));
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is ready for your next lesson.')),
    );
  }
}
