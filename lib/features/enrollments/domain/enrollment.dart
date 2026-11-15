// Canonical course/student enrollment. Snapshots and creation time are
// immutable; only status and the last transition markers can change.
import '../../schedule/domain/academic_date.dart';

class Enrollment {
  const Enrollment({
    required this.courseId,
    required this.studentUid,
    required this.ownerUid,
    required this.name,
    required this.email,
    required this.studentCode,
    required this.subject,
    required this.group,
    required this.period,
    required this.status,
    required this.createdAt,
    this.rosterEntryId,
    this.effectiveStartDate,
    this.lastStatusEventId,
    this.lastStatusChangedAt,
  });

  final String courseId;
  final String studentUid;
  final String ownerUid;
  final String name;
  final String email;
  final String? studentCode;
  final String subject;
  final String group;
  final String period;
  final String status;

  /// Null only for the immediate result of a confirmed server write.
  final DateTime? createdAt;

  /// Stable academic row identity for newly created memberships. Existing
  /// documents without this field remain readable through the UID fallback.
  final String? rosterEntryId;

  /// Civil date from which this enrollment is effective. Legacy records derive
  /// it from [createdAt] when read.
  final AcademicDate? effectiveStartDate;

  /// Missing on legacy enrollments that have never changed status.
  final String? lastStatusEventId;

  /// Missing together with [lastStatusEventId] on legacy enrollments. It is
  /// null on the immediate result of a confirmed server timestamp write.
  final DateTime? lastStatusChangedAt;
}
