import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings.dart';
import 'features/auth/auth_page.dart';
import 'features/practice/live_sign_view.dart' show kLiveSignSupported;
import 'recognizer/v4_sign_recognizer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cdkfwqlktrlyferpmpug.supabase.co',
    publishableKey: 'sb_publishable_heb483FEWgn1PZrXjfIQ7A_Rx9191Ir',
  );
  await AppSettings.load();
  runApp(const MainApp());
  // warm up the sign models after the first screen is up, so the camera
  // screens open without a loading pause
  if (kLiveSignSupported) {
    Future.delayed(const Duration(seconds: 2), V4SignRecognizer.preload);
  }
}

final supabase = Supabase.instance.client;
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FiloSign',
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D9488),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      // text size / high contrast (REQ006) and the 15-minute logout (REQ032)
      builder: (context, child) =>
          InactivityGuard(child: AppAccessibility(child: child ?? const SizedBox())),
      home: const AuthPage(),
    );
  }
}
