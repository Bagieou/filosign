import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'auth_gate.dart';
import 'services/auth_service.dart';
import 'screens/reset_password_screen.dart';
import 'screens/confirm_email_screen.dart';
 


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
   runApp(
    Provider<AuthService>.value(
      value: AuthService(),
      child: const MyApp(),
    ),
  );
 }


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FiloSign',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),

      home: const AuthGate(),
      routes: {
        '/reset-password': (context) => const ResetPasswordScreen(),
        '/confirm-email': (context) => const ConfirmEmailScreen(),
      },
    );
  }
}
