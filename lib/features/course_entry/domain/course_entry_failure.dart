enum CourseEntryFailureKind {
  unauthenticated,
  emailNotVerified,
  profileInvalid,
  teacherRoleRequired,
  studentRoleRequired,
  invalidInput,
  invalidTransition,
  inviteUnavailable,
  courseUnavailable,
  alreadyResolved,
  permissionDenied,
  network,
  invalidData,
  unknown,
}

class CourseEntryFailure implements Exception {
  const CourseEntryFailure(
    this.kind, {
    this.cause,
    this.diagnosticStep,
    this.diagnosticCode,
  });

  final CourseEntryFailureKind kind;
  final Object? cause;
  // Safe, fixed identifiers only: never include invitation codes or user data.
  final String? diagnosticStep;
  final String? diagnosticCode;

  @override
  String toString() => 'CourseEntryFailure($kind)';
}
