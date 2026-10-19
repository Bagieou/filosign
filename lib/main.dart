import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/auth_page.dart';
import 'recognizer/v4_sign_recognizer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cdkfwqlktrlyferpmpug.supabase.co',
    publishableKey: 'sb_publishable_heb483FEWgn1PZrXjfIQ7A_Rx9191Ir',
  );
  runApp(const MainApp());
  // warm up the sign models after the first screen is up, so the camera
  // screens open without a loading pause
  Future.delayed(const Duration(seconds: 2), V4SignRecognizer.preload);
}

final supabase = Supabase.instance.client;
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Filosign',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D9488),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AuthPage(),
    );
  }
}
