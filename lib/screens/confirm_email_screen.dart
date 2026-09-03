import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ConfirmEmailScreen extends StatefulWidget {
  const ConfirmEmailScreen({super.key});

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  bool _resending = false;

  Future<void> _resend() async {
    setState(() => _resending = true);
    await FirebaseAuth.instance.currentUser?.sendEmailVerification();
    if (mounted) {
      setState(() => _resending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification e‑mail sent')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your e‑mail')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_email_read_outlined,
                  size: 80, color: Color(0xFF0F766E)),
              const SizedBox(height: 16),
              const Text(
                'We\'ve sent a verification link to your e‑mail address.\n'
                'Please open the link, then come back here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _resending ? null : _resend,
                icon: _resending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.email),
                label: const Text('Resend e‑mail'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}