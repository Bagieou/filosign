import 'package:flutter_test/flutter_test.dart';
import 'package:filosign/features/auth/auth_page.dart';

void main() {
  group('password validation', () {
    test('accepts a valid password', () {
      expect(passwordValidationMessage('Password1!'), isNull);
    });

    test('reports a missing length requirement first', () {
      expect(
        passwordValidationMessage('Pass1!'),
        'Password must be at least 8 characters long.',
      );
    });

    test('reports a missing special character', () {
      expect(
        passwordValidationMessage('Password1A'),
        'Password must include 1 special character.',
      );
    });

    test('reports a missing number', () {
      expect(
        passwordValidationMessage('Password!A'),
        'Password must include 1 number.',
      );
    });

    test('reports a missing capital letter', () {
      expect(
        passwordValidationMessage('password1!'),
        'Password must include 1 capital letter.',
      );
    });
  });
}
