import 'package:flutter_test/flutter_test.dart';
import 'package:filosign/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sign up and sign in work with the in-memory auth store', () async {
    final service = AuthService();
    await service.resetDatabaseForTesting();

    final createdUser = await service.signUp(
      'alice@example.com',
      'super-secret',
    );
    expect(createdUser, isNotNull);
    expect(createdUser!.email, 'alice@example.com');

    final signedInUser = await service.signIn(
      'alice@example.com',
      'super-secret',
    );
    expect(signedInUser, isNotNull);
    expect(signedInUser!.email, 'alice@example.com');

    final wrongPasswordUser = await service.signIn(
      'alice@example.com',
      'wrong',
    );
    expect(wrongPasswordUser, isNull);
  });
}
