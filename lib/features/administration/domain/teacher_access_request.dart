enum TeacherAccessStatus { pending, approved, rejected }

enum TeacherAccessDecision { approve, reject }

/// The identity snapshot saved when a user requests teacher access.
class TeacherAccessRequest {
  const TeacherAccessRequest({
    required this.uid,
    required this.name,
    required this.email,
    required this.studentCode,
    required this.status,
    required this.createdAt,
    required this.decidedBy,
    required this.decidedAt,
    required this.rejectionReason,
  });

  final String uid;
  final String name;
  final String email;
  final String? studentCode;
  final TeacherAccessStatus status;
  final DateTime? createdAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? rejectionReason;
}

/// A request snapshot paired with the requester's current profile fields.
class TeacherAccessReview {
  const TeacherAccessReview({
    required this.request,
    required this.currentName,
    required this.currentEmail,
    required this.currentStudentCode,
    required this.currentRoles,
  });

  final TeacherAccessRequest request;
  final String currentName;
  final String currentEmail;
  final String? currentStudentCode;
  final List<String> currentRoles;
}
