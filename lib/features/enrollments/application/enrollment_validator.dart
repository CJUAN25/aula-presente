import '../domain/enrollment_failure.dart';
import '../domain/student_candidate.dart';

abstract final class EnrollmentValidator {
  static String exactEmail(String input) {
    final email = input.trim();
    if (email.length < 3 ||
        email.length > 254 ||
        email.contains('/') ||
        email.contains(RegExp(r'\s')) ||
        !email.contains('@')) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
    return email;
  }

  static void verifyOptionalCode(StudentCandidate candidate, String input) {
    final code = input.trim();
    if (code.isNotEmpty && candidate.studentCode != code) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
  }

  static void documentId(String id) {
    if (id.isEmpty || id.contains('/')) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
  }
}
