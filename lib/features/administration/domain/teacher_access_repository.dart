import 'teacher_access_request.dart';

abstract interface class TeacherAccessRepository {
  Future<TeacherAccessRequest?> getOwnRequest();

  Stream<TeacherAccessRequest?> watchOwnRequest();

  Future<TeacherAccessRequest> createOwnRequest();

  Stream<List<TeacherAccessRequest>> watchPendingRequests();

  Future<TeacherAccessReview> getReview(String requesterUid);

  Future<TeacherAccessRequest> decideRequest({
    required String requesterUid,
    required TeacherAccessDecision decision,
    String? rejectionReason,
  });
}

enum TeacherAccessFailureKind {
  unauthenticated,
  verificationRequired,
  profileUnavailable,
  profileInvalid,
  alreadyExists,
  notFound,
  notPending,
  invalidReason,
  permissionDenied,
  network,
  unknown,
}

class TeacherAccessFailure implements Exception {
  const TeacherAccessFailure(this.kind);

  final TeacherAccessFailureKind kind;
}
