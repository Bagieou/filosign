import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _welcomeMessage = '';
  bool _showWelcome = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final welcomeType = prefs.getString('welcome_type');

    if (welcomeType != null) {
      await prefs.remove('welcome_type');
    }

    final shouldShowWelcome = welcomeType != null;
    setState(() {
      _welcomeMessage = welcomeType == 'signup' ? 'Welcome to FiloSign' : 'Welcome back';
      _showWelcome = shouldShowWelcome;
    });

    if (_showWelcome) {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() => _showWelcome = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FiloSign'),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: () => AuthService().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFBF1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.sign_language,
                  size: 64,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 16),
              if (_showWelcome)
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _welcomeMessage,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F766E),
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Start learning Filipino Sign Language through simple lessons and practice.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}