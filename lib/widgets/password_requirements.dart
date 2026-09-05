import 'package:flutter/material.dart';

class _Requirement {
  final String label;
  final bool met;
  const _Requirement({required this.label, required this.met});
}

class PasswordRequirements extends StatelessWidget {
  final String password;
  const PasswordRequirements({Key? key, required this.password}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final requirements = [
      _Requirement(label: 'At least 8 characters', met: password.length >= 8),
      _Requirement(label: 'One uppercase letter', met: password.contains(RegExp(r'[A-Z]'))),
      _Requirement(label: 'One number', met: password.contains(RegExp(r'[0-9]'))),
      _Requirement(
        label: 'One special character',
        met: password.contains(RegExp(r'[!@#\$%^&*(),.?":{}\[\] ]')),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: requirements.map((r) {
        return Row(
          children: [
            Icon(
              r.met ? Icons.check_circle : Icons.cancel,
              size: 18,
              color: r.met ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 6),
            Text(
              r.label,
              style: TextStyle(
                color: r.met ? Colors.green : Colors.red,
                fontSize: 13,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}