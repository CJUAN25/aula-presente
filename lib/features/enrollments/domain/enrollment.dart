/// Canonical course/student enrollment. The snapshots and creation time are
/// immutable; only [status] and the last transition markers can change.
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

  /// Missing on legacy enrollments that have never changed status.
  final String? lastStatusEventId;

  /// Missing together with [lastStatusEventId] on legacy enrollments. It is
  /// null on the immediate result of a confirmed server timestamp write.
  final DateTime? lastStatusChangedAt;
}
