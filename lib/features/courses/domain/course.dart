import '../../schedule/domain/course_schedule.dart';

/// Persisted course snapshot. The Firestore document ID is [id] and is not a
/// duplicated document field.
class Course {
  const Course({
    required this.id,
    required this.ownerUid,
    required this.subject,
    required this.group,
    required this.period,
    required this.program,
    required this.schedule,
    this.status = 'planned',
    this.schemaVersion = 1,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerUid;
  final String subject;
  final String group;
  final String period;
  final String program;
  final CourseSchedule schedule;
  final String status;
  final int schemaVersion;

  /// Null is valid for the immediate result of a confirmed server write when
  /// the server timestamp value has not been returned to the client.
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
