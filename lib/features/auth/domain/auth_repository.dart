import 'auth_access.dart';

abstract interface class AuthRepository {
  Future<AuthAccess> restoreSession();

  Stream<AuthAccess> watchAccess();

  Future<AuthAccess> signIn({required String email, required String password});

  Future<AuthRegistrationResult> register({
    required String name,
    required String email,
    required String studentCode,
    required String password,
  });

  Future<AuthAccess> refreshAccess({String? expectedEmail});

  Future<void> retryRegistrationSetup({
    required String name,
    required String studentCode,
  });

  Future<void> resendEmailVerification();

  Future<void> sendPasswordReset(String email);

  Future<void> requestEmailCorrection({
    required String newEmail,
    required String currentPassword,
  });

  Future<void> signOut();
}
