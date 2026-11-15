import '../../schedule/domain/academic_date.dart';

/// A teacher-authorized course roster entry that may not have a student UID
/// yet. The document ID and [rosterEntryId] are the validated exact email.
class PendingEnrollment {
  const PendingEnrollment({
    required this.courseId,
    required this.ownerUid,
    required this.subject,
    required this.group,
    required this.period,
    required this.email,
    required this.studentCode,
    required this.name,
    required this.status,
    required this.effectiveStartDate,
    required this.rosterEntryId,
    required this.studentUid,
    required this.authorizedAt,
    required this.linkedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.lastEventId,
    required this.lastStatusChangedAt,
  });

  final String courseId;
  final String ownerUid;
  final String subject;
  final String group;
  final String period;
  final String email;
  final String studentCode;
  final String name;

  /// `pending`, `linked`, or `withdrawn`.
  final String status;
  final AcademicDate effectiveStartDate;

  /// Stable academic identity. It remains unchanged if the student later
  /// changes the email address on their account.
  final String rosterEntryId;
  final String? studentUid;
  final DateTime authorizedAt;
  final DateTime? linkedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastEventId;
  final DateTime? lastStatusChangedAt;
}

class PendingEnrollmentStatusEvent {
  const PendingEnrollmentStatusEvent({
    required this.operationId,
    required this.fromStatus,
    required this.toStatus,
    required this.effectiveDate,
    required this.changedAt,
    required this.changedBy,
  });

  final String operationId;
  final String fromStatus;
  final String toStatus;
  final AcademicDate effectiveDate;
  final DateTime changedAt;
  final String changedBy;
}
