String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Enter your password';
  if (value.length < 8) return 'Password must be at least 8 characters';
  if (!value.contains(RegExp(r'[A-Z]'))) return 'Password must contain an uppercase letter';
  if (!value.contains(RegExp(r'[0-9]'))) return 'Password must contain a number';
  if (!value.contains(RegExp(r'[!@#\$%^&*(),.?":{}\[\] ]'))) {
    return 'Password must contain a special character';
  }
  return null; // valid
}