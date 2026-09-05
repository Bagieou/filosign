import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/password_requirements.dart';
import '../utils/validators.dart';
import '../services/auth_service.dart';

// ─── Bottom Nav Item ─────────────────────────────────────────────
class _BottomNavItem extends StatelessWidget {
  final String asset;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;
  const _BottomNavItem({required this.asset, required this.selected, required this.onTap, required this.activeColor});

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : Colors.grey.shade500;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, width: 24, height: 24, color: color, errorBuilder: (_, __, ___) => Icon(Icons.circle, size: 24, color: color)),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final Stream<User?> _authStream;

  // Change password form state
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _errorMessage;
  String? _successMessage;
  bool _showChangePassword = false;

  // Change email form state
  final _newEmailCtrl = TextEditingController();
  final _emailPasswordCtrl = TextEditingController();
  bool _obscureEmailPassword = true;
  bool _showChangeEmail = false;
  bool _emailLoading = false;
  String? _emailError;
  String? _emailSuccess;

  // Delete account form state
  final _deletePasswordCtrl = TextEditingController();
  bool _obscureDeletePassword = true;
  bool _showDeleteAccount = false;
  bool _deleteLoading = false;
  String? _deleteError;
  String? _deleteSuccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStream = _auth.idTokenChanges();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _newEmailCtrl.dispose();
    _emailPasswordCtrl.dispose();
    _deletePasswordCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _auth.currentUser?.reload();
    }
  }

Future<void> _sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent')),
        );
      }
    }
  }

  Widget _buildChangeEmailForm() {
    final buttonTextStyle = Theme.of(context).textTheme.labelLarge;
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    final messageStyle = Theme.of(context).textTheme.bodySmall;

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Change Email',
                      style: buttonTextStyle?.copyWith(fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _showChangeEmail = false;
                      _emailError = null;
                      _emailSuccess = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _newEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'New Email',
                  border: OutlineInputBorder(),
                ).copyWith(labelStyle: labelStyle),
                validator: _validateEmail,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailPasswordCtrl,
                obscureText: _obscureEmailPassword,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureEmailPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureEmailPassword = !_obscureEmailPassword),
                  ),
                ).copyWith(labelStyle: labelStyle),
                validator: (v) => v == null || v.isEmpty ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 16),
              if (_emailError != null)
                Text(_emailError!,
                    style: messageStyle?.copyWith(color: Colors.red),
                    textAlign: TextAlign.center),
              if (_emailSuccess != null)
                Text(_emailSuccess!,
                    style: messageStyle?.copyWith(color: Colors.green),
                    textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _emailLoading ? null : _changeEmail,
                style: ElevatedButton.styleFrom(textStyle: buttonTextStyle),
                child: _emailLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Send Verification Email'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, bool obscure, VoidCallback toggle) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
        onPressed: toggle,
      ),
    );
  }

  String? _validateEmail(String? v) {
    if (v == null || v.isEmpty) return 'Enter an e‑mail address';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) return 'Enter a valid e‑mail address';
    return null;
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await AuthService().changePassword(
        currentPassword: _currentCtrl.text.trim(),
        newPassword: _newCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _successMessage = 'Password changed successfully';
        });
        // Show success for 3 seconds then close form
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          setState(() {
            _showChangePassword = false;
            _successMessage = null;
            _currentCtrl.clear();
            _newCtrl.clear();
            _confirmCtrl.clear();
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      String friendly;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          friendly = 'Password is incorrect';
          break;
        case 'weak-password':
          friendly = 'New password is too weak';
          break;
        case 'requires-recent-login':
          friendly = 'Please sign in again before changing password';
          break;
        default:
          friendly = 'Failed to change password. Please try again.';
      }
      if (mounted) setState(() => _errorMessage = friendly);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeEmail() async {
    if (!_formKey.currentState!.validate()) return;

    final currentEmail = _auth.currentUser?.email ?? '';
    final newEmail = _newEmailCtrl.text.trim();
    final password = _emailPasswordCtrl.text;

    if (newEmail == currentEmail) {
      setState(() => _emailError = 'The new e‑mail is the same as your current e‑mail');
      return;
    }

    setState(() {
      _emailLoading = true;
      _emailError = null;
      _emailSuccess = null;
    });

    try {
      // Re‑authenticate the user before changing email
      final credential = EmailAuthProvider.credential(email: currentEmail, password: password);
      await _auth.currentUser!.reauthenticateWithCredential(credential);

      // Now request verification email to the new address
      await _auth.currentUser!.verifyBeforeUpdateEmail(newEmail);

      if (mounted) {
        setState(() => _emailSuccess = 'Verification email sent to $newEmail');
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          setState(() {
            _showChangeEmail = false;
            _emailSuccess = null;
            _newEmailCtrl.clear();
            _emailPasswordCtrl.clear();
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      String friendly;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          friendly = 'Password is incorrect';
          break;
        case 'requires-recent-login':
          friendly = 'Please sign in again before changing your e‑mail';
          break;
        case 'email-already-in-use':
          friendly = 'That e‑mail is already used by another account';
          break;
        case 'invalid-email':
          friendly = 'The e‑mail address is malformed';
          break;
        default:
          friendly = 'Could not send verification e‑mail. Try again.';
      }
      if (mounted) setState(() => _emailError = friendly);
    } catch (_) {
      if (mounted) setState(() => _emailError = 'An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final currentEmail = _auth.currentUser?.email ?? '';
    final password = _deletePasswordCtrl.text;

    setState(() {
      _deleteLoading = true;
      _deleteError = null;
      _deleteSuccess = null;
    });

    try {
      // Re‑authenticate before deletion
      final credential = EmailAuthProvider.credential(email: currentEmail, password: password);
      await _auth.currentUser!.reauthenticateWithCredential(credential);

      // Delete the account
      await _auth.currentUser!.delete();

      if (mounted) {
        setState(() => _deleteSuccess = 'Account deleted successfully');
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) {
          // Sign out and go to auth gate (login screen)
          await _auth.signOut();
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    } on FirebaseAuthException catch (e) {
      String friendly;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          friendly = 'Password is incorrect';
          break;
        case 'requires-recent-login':
          friendly = 'Please sign in again before deleting your account';
          break;
        default:
          friendly = 'Could not delete account. Try again.';
      }
      if (mounted) setState(() => _deleteError = friendly);
    } catch (_) {
      if (mounted) setState(() => _deleteError = 'An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _deleteLoading = false);
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Widget _buildDeleteAccountForm() {
    final buttonTextStyle = Theme.of(context).textTheme.labelLarge;
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    final messageStyle = Theme.of(context).textTheme.bodySmall;

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Delete Account',
                      style: buttonTextStyle?.copyWith(fontWeight: FontWeight.w600, color: Colors.red)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() {
                      _showDeleteAccount = false;
                      _deleteError = null;
                      _deleteSuccess = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _deletePasswordCtrl,
                obscureText: _obscureDeletePassword,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureDeletePassword ? Icons.visibility_off : Icons.visibility, color: Colors.red),
                    onPressed: () => setState(() => _obscureDeletePassword = !_obscureDeletePassword),
                  ),
                ).copyWith(labelStyle: labelStyle),
                validator: (v) => v == null || v.isEmpty ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 16),
              if (_deleteError != null)
                Text(_deleteError!,
                    style: messageStyle?.copyWith(color: Colors.red),
                    textAlign: TextAlign.center),
              if (_deleteSuccess != null)
                Text(_deleteSuccess!,
                    style: messageStyle?.copyWith(color: Colors.green),
                    textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _deleteLoading ? null : _deleteAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  textStyle: buttonTextStyle,
                ),
                child: _deleteLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Delete Account', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChangePasswordForm() {
    final buttonTextStyle = Theme.of(context).textTheme.labelLarge;
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    final messageStyle = Theme.of(context).textTheme.bodySmall;

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Change Password',
                    style: buttonTextStyle?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _showChangePassword = false;
                      _errorMessage = null;
                      _successMessage = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _currentCtrl,
                obscureText: _obscureCurrent,
                decoration: _decoration(
                  'Current Password',
                  _obscureCurrent,
                  () => setState(() => _obscureCurrent = !_obscureCurrent),
                ).copyWith(labelStyle: labelStyle),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newCtrl,
                obscureText: _obscureNew,
                decoration: _decoration(
                  'New Password',
                  _obscureNew,
                  () => setState(() => _obscureNew = !_obscureNew),
                ).copyWith(labelStyle: labelStyle),
                validator: validatePassword,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              PasswordRequirements(password: _newCtrl.text),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: _decoration(
                  'Confirm New Password',
                  _obscureConfirm,
                  () => setState(() => _obscureConfirm = !_obscureConfirm),
                ).copyWith(labelStyle: labelStyle),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Confirm your new password';
                  if (v != _newCtrl.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: messageStyle?.copyWith(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              if (_successMessage != null)
                Text(
                  _successMessage!,
                  style: messageStyle?.copyWith(color: Colors.green),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  textStyle: buttonTextStyle,
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Change Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF14B8A6);
    const primaryDark = Color(0xFF0F766E);

    int _selectedIndex = 3; // Settings tab active
    void _onNavTap(int index) {
      if (index == _selectedIndex) return;
      HapticFeedback.lightImpact();
      switch (index) {
        case 0:
          Navigator.pushReplacementNamed(context, '/home');
          break;
        case 1:
          Navigator.pushReplacementNamed(context, '/practice');
          break;
        case 2:
          Navigator.pushReplacementNamed(context, '/notifications');
          break;
        case 3:
          // already here
          break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<User?>(
        stream: _authStream,
        builder: (_, snap) {
          final user = snap.data ?? _auth.currentUser;
          final email = user?.email ?? '';
          final verified = user?.emailVerified ?? false;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: const AssetImage('assets/icon/Profile.png'),
                    backgroundColor: Colors.grey[200],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          email,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        verified
                            ? _VerificationBadge(label: 'Verified', color: Colors.green)
                            : InkWell(
                                onTap: _sendVerificationEmail,
                                borderRadius: BorderRadius.circular(4),
                                child: _VerificationBadge(label: 'Verify', color: Colors.red),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Toggle change password form
              if (!_showChangePassword)
                OutlinedButton.icon(
                  label: const Text('Change Password'),
                  onPressed: () => setState(() => _showChangePassword = true),
                )
              else
                _buildChangePasswordForm(),
              const SizedBox(height: 16),
              // Toggle change email form
              if (!_showChangeEmail)
                OutlinedButton.icon(
                  label: const Text('Change Email'),
                  onPressed: () => setState(() => _showChangeEmail = true),
                )
              else
                _buildChangeEmailForm(),
              const SizedBox(height: 16),
              // Log out button
              OutlinedButton.icon(
                label: const Text('Log out'),
                onPressed: _signOut,
              ),
              const SizedBox(height: 16),
              // Toggle delete account form (closest to nav bar)
              if (!_showDeleteAccount)
                OutlinedButton.icon(
                  label: const Text('Delete Account', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() => _showDeleteAccount = true),
                )
              else
                _buildDeleteAccountForm(),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 12, offset: const Offset(0, -2)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(asset: 'assets/icon/Home.png', selected: false, onTap: () => _onNavTap(0), activeColor: primaryDark),
              _BottomNavItem(asset: 'assets/icon/practice_icon.png', selected: false, onTap: () => _onNavTap(1), activeColor: primaryDark),
              _BottomNavItem(asset: 'assets/icon/Notification.png', selected: false, onTap: () => _onNavTap(2), activeColor: primaryDark),
              _BottomNavItem(asset: 'assets/icon/Setting.png', selected: true, onTap: () => _onNavTap(3), activeColor: primaryDark),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small coloured box with centred text.
class _VerificationBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _VerificationBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}