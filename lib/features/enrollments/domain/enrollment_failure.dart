enum EnrollmentFailureKind {
  unauthenticated,
  emailNotVerified,
  profileInvalid,
  teacherRoleRequired,
  studentRoleRequired,
  invalidInput,
  candidateChanged,
  courseUnavailable,
  permissionDenied,
  network,
  invalidData,
  unknown,
}

class EnrollmentFailure implements Exception {
  const EnrollmentFailure(this.kind, {this.cause});

  final EnrollmentFailureKind kind;
  final Object? cause;

  @override
  String toString() => 'EnrollmentFailure($kind)';
}
