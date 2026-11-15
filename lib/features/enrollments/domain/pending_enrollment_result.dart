import 'enrollment_failure.dart';

enum PendingEnrollmentWriteKind { created, alreadyPending }

class PendingEnrollmentWriteResult {
  const PendingEnrollmentWriteResult(this.kind);

  final PendingEnrollmentWriteKind kind;
  bool get created => kind == PendingEnrollmentWriteKind.created;
}

class PendingEnrollmentStatusChangeResult {
  const PendingEnrollmentStatusChangeResult({
    required this.status,
    required this.operationId,
    required this.alreadyApplied,
  });

  final String status;
  final String operationId;
  final bool alreadyApplied;
}

enum PendingEnrollmentLinkOutcome { linked, alreadyLinked, needsReview, failed }

class PendingEnrollmentLinkRowResult {
  const PendingEnrollmentLinkRowResult({
    required this.courseId,
    required this.email,
    required this.outcome,
    this.joinRequestNeedsTeacherReview = false,
    this.failureKind,
  });

  final String courseId;
  final String email;
  final PendingEnrollmentLinkOutcome outcome;
  final bool joinRequestNeedsTeacherReview;
  final EnrollmentFailureKind? failureKind;
}

class PendingEnrollmentLinkSummary {
  PendingEnrollmentLinkSummary({
    required List<PendingEnrollmentLinkRowResult> rows,
    this.studentCodeMissing = false,
  }) : rows = List.unmodifiable(rows);

  final List<PendingEnrollmentLinkRowResult> rows;
  final bool studentCodeMissing;

  int get linked => rows
      .where((row) => row.outcome == PendingEnrollmentLinkOutcome.linked)
      .length;
  int get needsReview => rows
      .where((row) => row.outcome == PendingEnrollmentLinkOutcome.needsReview)
      .length;
  int get failed => rows
      .where((row) => row.outcome == PendingEnrollmentLinkOutcome.failed)
      .length;
  bool get hasJoinRequestForTeacherReview =>
      rows.any((row) => row.joinRequestNeedsTeacherReview);
}
