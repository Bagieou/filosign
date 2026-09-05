import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/terms_loader.dart';
import '../utils/validators.dart';
import '../widgets/password_requirements.dart';
import '../widgets/terms_dialog.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _isLogin = true;
  bool _isLoading = false;
  String? _message;
  String? _emailError;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _failedLoginAttempts = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  void _onEmailChanged(String value) {
    setState(() {
      _emailError = _validateEmail(value);
    });
  }

  

  String? _validateConfirmPassword(String? value) {
    if (!_isLogin) {
      if (value == null || value.isEmpty) {
        return 'Confirm your password';
      }
      if (value != _passwordController.text) {
        return 'Passwords do not match';
      }
    }
    return null;
  }

Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final isLogin = _isLogin; // capture button pressed
      if (isLogin) {
        await _authService.signIn(email: email, password: password);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('welcome_type', 'login');
      } else {
        // Load terms and show dialog
        final terms = await TermsLoader.load();
        final ctx = context; // capture context for async gap
        // ignore: use_build_context_synchronously
        final agreed = await showDialog<bool>(
          // ignore: use_build_context_synchronously
          context: ctx,
          barrierDismissible: false,
          builder: (_) => TermsDialog(termsText: terms),
        );
        if (!mounted) return;

        if (agreed != true) {
          setState(() {
            _isLoading = false;
            _message = 'You must accept the terms to create an account.';
          });
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('welcome_type', 'signup');
        await _authService.signUpVerified(email: email, password: password);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      String msg = e.toString().replaceFirst('Exception: ', '');
      
      // Improve error messages for login
      if (_isLogin) {
        setState(() => _failedLoginAttempts++);
        if (msg.contains('Invalid email or password') || 
            msg.contains('user-not-found') || 
            msg.contains('wrong-password') ||
            msg.contains('invalid-credential')) {
          msg = 'Invalid email or password. Please check your credentials.';
        } else if (msg.contains('user-disabled')) {
          msg = 'This account has been disabled. Please contact support.';
        } else if (msg.contains('too-many-requests')) {
          msg = 'Too many failed attempts. Please try again later.';
        }
      } else {
        // Sign up errors
        if (msg.contains('already exists') || msg.contains('email-already-in-use')) {
          msg = 'An account already exists for this email. Please log in instead.';
        } else if (msg.contains('weak-password')) {
          msg = 'Password is too weak. Please use a stronger password.';
        } else if (msg.contains('invalid-email')) {
          msg = 'Please enter a valid email address.';
        }
      }
      
      setState(() => _message = msg);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF14B8A6), Color(0xFF0F766E)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      const Icon(
                        Icons.sign_language,
                        size: 48,
                        color: Color(0xFF0F766E),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'FiloSign',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Learn Filipino Sign Language with confidence.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isLogin ? 'Log in to continue' : 'Create your account',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onChanged: _onEmailChanged,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          border: const OutlineInputBorder(),
                          errorText: _emailError,
                        ),
                        validator: (value) => _validateEmail(value),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
                        onFieldSubmitted: (_) => _submit(),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: _isLogin
                            ? (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Enter your password';
                                }
                                return null;
                              }
                            : validatePassword,
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 8),
                        PasswordRequirements(password: _passwordController.text),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword = !_obscureConfirmPassword;
                                });
                              },
                            ),
                          ),
                          validator: _validateConfirmPassword,
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  _message!.contains('successful') ||
                                      _message!.contains('created')
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_isLogin ? 'Log in' : 'Create account'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLogin = !_isLogin;
                            _message = null;
                          });
                        },
                        child: Text(
                          _isLogin
                              ? 'Need an account? Sign up'
                              : 'Already have an account? Log in',
                        ),
                      ),
                      if (_isLogin && _failedLoginAttempts >= 3)
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/reset-password');
                          },
                          child: const Text('Forgot password?'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}