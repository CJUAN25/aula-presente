enum AttendanceFailureKind {
  unauthenticated,
  emailNotVerified,
  profileInvalid,
  teacherRoleRequired,
  studentRoleRequired,
  permissionDenied,
  notFound,
  invalidInput,
  invalidData,
  incompleteRoster,
  rosterHistoryNeedsReview,
  staleSession,
  invalidTransition,
  conflict,
  unavailable,
}

class AttendanceFailure implements Exception {
  const AttendanceFailure(this.kind, {this.message});

  final AttendanceFailureKind kind;
  final String? message;

  @override
  String toString() =>
      message == null ? 'AttendanceFailure: ${kind.name}' : message!;
}
