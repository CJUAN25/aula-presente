enum JoinRequestStatus { pending, approved, rejected }

enum JoinRequestDecision { approve, reject }

class JoinRequest {
  const JoinRequest({
    required this.courseId,
    required this.studentUid,
    required this.name,
    required this.email,
    required this.studentCode,
    required this.subject,
    required this.group,
    required this.period,
    required this.status,
    required this.createdAt,
    required this.decidedBy,
    required this.decidedAt,
    required this.rejectionReason,
  });

  final String courseId;
  final String studentUid;
  final String name;
  final String email;
  final String? studentCode;
  final String subject;
  final String group;
  final String period;
  final JoinRequestStatus status;
  final DateTime createdAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? rejectionReason;
}
