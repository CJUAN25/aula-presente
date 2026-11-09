/// One immutable active enrollment. The course/student pair is the document path.
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
}
