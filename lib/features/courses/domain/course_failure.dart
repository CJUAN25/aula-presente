enum CourseFailureKind {
  unauthenticated,
  emailNotVerified,
  profileInvalid,
  teacherRoleRequired,
  permissionDenied,
  network,
  idempotencyConflict,
  invalidCourse,
  unknown,
}

class CourseFailure implements Exception {
  const CourseFailure(this.kind, {this.cause});

  final CourseFailureKind kind;
  final Object? cause;

  @override
  String toString() => 'CourseFailure($kind)';
}
