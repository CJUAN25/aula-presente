import '../../enrollments/domain/student_candidate.dart';
import '../../enrollments/domain/enrollment.dart';
import '../../enrollments/domain/pending_enrollment.dart';
import 'excel_import_document.dart';

enum ExcelImportMode { additionsOnly, completeList }

enum ExcelReviewAction {
  none,
  enrollDirect,
  authorizePending,
  rejoinEnrollment,
  reopenPending,
}

enum ExcelRosterMemberKind { enrollment, pending }

enum ExcelReviewStatus {
  eligible,
  unavailable,
  codeMismatch,
  duplicate,
  alreadyEnrolled,
  withdrawn,
  pendingEligible,
  unchangedPending,
  rejoinEnrollment,
  reopenPending,
  identityConflict,
  invalid,
  error,
}

class ExcelReviewedRow {
  const ExcelReviewedRow({
    required this.row,
    required this.status,
    required this.message,
    this.candidate,
    this.enrollment,
    this.pendingEnrollment,
    this.action = ExcelReviewAction.none,
    this.operationId,
  });

  final ExcelImportRow row;
  final ExcelReviewStatus status;
  final StudentCandidate? candidate;
  final Enrollment? enrollment;
  final PendingEnrollment? pendingEnrollment;
  final ExcelReviewAction action;

  /// Stable for retries while this review result remains in memory.
  final String? operationId;
  final String message;

  bool get selectable => action != ExcelReviewAction.none;
}

class ExcelReview {
  ExcelReview({
    required List<ExcelReviewedRow> rows,
    this.mode = ExcelImportMode.additionsOnly,
    List<ExcelRosterMember> potentialWithdrawals = const [],
    this.isComplete = true,
    this.retirementsAllowed = false,
    this.retirementBlockReason,
  }) : rows = List.unmodifiable(rows),
       potentialWithdrawals = List.unmodifiable(potentialWithdrawals);

  final List<ExcelReviewedRow> rows;
  final ExcelImportMode mode;
  final List<ExcelRosterMember> potentialWithdrawals;

  /// True only when all data needed by this comparison was read successfully.
  final bool isComplete;

  /// Requires explicit complete-list mode and a trustworthy file/snapshot.
  final bool retirementsAllowed;
  final String? retirementBlockReason;

  int get eligibleCount => rows.where((row) => row.selectable).length;
  int get newCount => rows
      .where(
        (row) =>
            row.action == ExcelReviewAction.enrollDirect ||
            row.action == ExcelReviewAction.authorizePending,
      )
      .length;
  int get unchangedCount => rows
      .where(
        (row) =>
            row.status == ExcelReviewStatus.alreadyEnrolled ||
            row.status == ExcelReviewStatus.unchangedPending,
      )
      .length;
  int get needsReviewCount => rows
      .where(
        (row) =>
            row.status == ExcelReviewStatus.invalid ||
            row.status == ExcelReviewStatus.duplicate ||
            row.status == ExcelReviewStatus.unavailable ||
            row.status == ExcelReviewStatus.codeMismatch ||
            row.status == ExcelReviewStatus.identityConflict ||
            row.status == ExcelReviewStatus.withdrawn ||
            row.status == ExcelReviewStatus.error,
      )
      .length;
  int count(ExcelReviewStatus status) =>
      rows.where((row) => row.status == status).length;
}

/// A currently active roster identity which is absent from a complete file.
/// Only an explicit selection in complete-list mode can change its status.
class ExcelRosterMember {
  const ExcelRosterMember.fromEnrollment(this.enrollment, {this.operationId})
    : pendingEnrollment = null,
      kind = ExcelRosterMemberKind.enrollment;

  const ExcelRosterMember.fromPending(
    this.pendingEnrollment, {
    this.operationId,
  }) : enrollment = null,
       kind = ExcelRosterMemberKind.pending;

  final ExcelRosterMemberKind kind;
  final Enrollment? enrollment;
  final PendingEnrollment? pendingEnrollment;
  final String? operationId;

  String get email => enrollment?.email ?? pendingEnrollment!.email;
  String? get studentCode =>
      enrollment?.studentCode ?? pendingEnrollment!.studentCode;
  String get name => enrollment?.name ?? pendingEnrollment!.name;
  String get identityKey {
    final currentEnrollment = enrollment;
    if (currentEnrollment != null) {
      return currentEnrollment.rosterEntryId ??
          'legacy:${currentEnrollment.studentUid}';
    }
    return pendingEnrollment!.rosterEntryId;
  }

  String get versionEventId =>
      enrollment?.lastStatusEventId ?? pendingEnrollment!.lastEventId ?? '';

  ExcelRosterMember withOperationId(String value) =>
      kind == ExcelRosterMemberKind.enrollment
      ? ExcelRosterMember.fromEnrollment(enrollment!, operationId: value)
      : ExcelRosterMember.fromPending(pendingEnrollment!, operationId: value);
}

enum ExcelImportOutcome {
  enrolledNow,
  pendingNow,
  alreadyEnrolled,
  unchanged,
  rejoined,
  pendingReopened,
  withdrawn,
  needsReview,
  failed,
}

class ExcelConfirmedRow {
  const ExcelConfirmedRow({
    required this.reviewed,
    required this.outcome,
    required this.message,
  });

  final ExcelReviewedRow reviewed;
  final ExcelImportOutcome outcome;
  final String message;
}

enum ExcelRosterChangeOutcome {
  withdrawnNow,
  pendingWithdrawnNow,
  needsReview,
  failed,
}

class ExcelConfirmedRosterChange {
  const ExcelConfirmedRosterChange({
    required this.member,
    required this.outcome,
    required this.message,
  });

  final ExcelRosterMember member;
  final ExcelRosterChangeOutcome outcome;
  final String message;
}

class ExcelImportResult {
  ExcelImportResult({
    required List<ExcelConfirmedRow> rows,
    List<ExcelConfirmedRosterChange> rosterChanges = const [],
  }) : rows = List.unmodifiable(rows),
       rosterChanges = List.unmodifiable(rosterChanges);

  final List<ExcelConfirmedRow> rows;
  final List<ExcelConfirmedRosterChange> rosterChanges;

  int count(ExcelImportOutcome outcome) =>
      rows.where((row) => row.outcome == outcome).length;
  int get enrolledNow => count(ExcelImportOutcome.enrolledNow);
  int get pendingNow => count(ExcelImportOutcome.pendingNow);
  int get alreadyEnrolled => count(ExcelImportOutcome.alreadyEnrolled);
  int get unchanged => count(ExcelImportOutcome.unchanged);
  int get rejoined => count(ExcelImportOutcome.rejoined);
  int get pendingReopened => count(ExcelImportOutcome.pendingReopened);
  int get withdrawn => count(ExcelImportOutcome.withdrawn);
  int get withdrawnNow => rosterChanges
      .where(
        (change) => change.outcome == ExcelRosterChangeOutcome.withdrawnNow,
      )
      .length;
  int get pendingWithdrawnNow => rosterChanges
      .where(
        (change) =>
            change.outcome == ExcelRosterChangeOutcome.pendingWithdrawnNow,
      )
      .length;
  int get needsReview =>
      count(ExcelImportOutcome.needsReview) +
      rosterChanges
          .where(
            (change) => change.outcome == ExcelRosterChangeOutcome.needsReview,
          )
          .length;
  int get failed =>
      count(ExcelImportOutcome.failed) +
      rosterChanges
          .where((change) => change.outcome == ExcelRosterChangeOutcome.failed)
          .length;
}
