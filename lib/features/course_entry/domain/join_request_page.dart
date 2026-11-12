import '../../enrollments/domain/enrollment.dart';
import 'join_request.dart';

class JoinRequestCursor {
  const JoinRequestCursor({
    required this.createdAt,
    required this.documentPath,
  });

  final DateTime createdAt;
  final String documentPath;
}

class JoinRequestPage {
  JoinRequestPage({required List<JoinRequest> items, required this.nextCursor})
    : items = List.unmodifiable(items);

  final List<JoinRequest> items;
  final JoinRequestCursor? nextCursor;
  bool get hasMore => nextCursor != null;
}

enum JoinRequestResultKind {
  created,
  alreadyPending,
  alreadyRejected,
  alreadyEnrolled,
}

class JoinRequestResult {
  const JoinRequestResult({
    required this.kind,
    required this.courseId,
    this.request,
  });

  final JoinRequestResultKind kind;
  final String courseId;
  final JoinRequest? request;
}

enum JoinDecisionResultStatus {
  approved,
  rejected,
  alreadyApproved,
  alreadyRejected,
}

class JoinDecisionResult {
  const JoinDecisionResult({
    required this.status,
    required this.courseId,
    this.request,
    this.enrollment,
  });

  final JoinDecisionResultStatus status;
  final String courseId;
  final JoinRequest? request;
  final Enrollment? enrollment;

  bool get isApproved =>
      status == JoinDecisionResultStatus.approved ||
      status == JoinDecisionResultStatus.alreadyApproved;
}
