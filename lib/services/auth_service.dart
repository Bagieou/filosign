import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  // Singleton‑style access (optional but convenient)
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // -----------------------------------------------------------------
  //  Public API
  // -----------------------------------------------------------------

  /// Stream that emits the current User (null when signed‑out)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Create a new account with email & password and send verification email
  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      // Send verification email
      await cred.user?.sendEmailVerification();
      return cred;
    } on FirebaseAuthException catch (e) {
      _throwReadable(e);
    }
  }

  /// Alias used by UI to emphasise verification step
  Future<UserCredential> signUpVerified({
    required String email,
    required String password,
  }) => signUp(email: email, password: password);

  /// Sign‑in existing user with email & password
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      _throwReadable(e);
    }
  }

  /// Sign‑out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // -----------------------------------------------------------------
  //  Helpers
  // -----------------------------------------------------------------
  /// Convert the raw FirebaseAuthException into a friendly message
  Never _throwReadable(FirebaseAuthException e) {
    String msg;
    switch (e.code) {
      case 'weak-password':
        msg = 'Password is too weak (min 6 chars).';
        break;
      case 'email-already-in-use':
        msg = 'An account already exists for that email.';
        break;
      case 'invalid-email':
        msg = 'Email address is malformed.';
        break;
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        msg = 'Invalid email or password.';
        break;
      case 'user-disabled':
        msg = 'This account has been disabled.';
        break;
      case 'too-many-requests':
        msg = 'Too many failed attempts. Please try again later.';
        break;
      default:
        msg = e.message ?? 'Authentication failed.';
    }
    // Include the error code in the exception for better handling
    throw Exception('${e.code}: $msg');
  }
}