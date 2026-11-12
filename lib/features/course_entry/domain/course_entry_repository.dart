import 'course_invitation.dart';
import 'course_preview.dart';
import 'join_request.dart';
import 'join_request_page.dart';

abstract interface class CourseEntryRepository {
  String? get currentUid;

  Future<CourseInvitation?> getCurrentInvitation(String courseId);

  Future<CourseInvitation> createOrGetInvitation(
    String courseId, {
    Duration validity = CourseInvitation.defaultValidity,
  });

  Future<CourseInvitation> renewInvitation(
    String courseId, {
    Duration validity = CourseInvitation.defaultValidity,
  });

  Future<CourseInvitation> updateInvitationValidity(
    String courseId,
    Duration validity,
  );

  Future<CourseInvitation> pauseInvitation(String courseId);

  Future<CourseInvitation> reactivateInvitation(String courseId);

  Future<void> deactivateInvitation(String courseId);

  Future<CoursePreview> findCourseByCode(String input);

  Future<JoinRequestResult> requestJoin(String input);

  Future<JoinRequest?> getMyRequest(String courseId);

  Future<JoinRequestPage> listMyRequests({
    JoinRequestCursor? cursor,
    int pageSize = 25,
  });

  Future<JoinRequestPage> listCourseRequests(
    String courseId, {
    JoinRequestCursor? cursor,
    int pageSize = 25,
  });

  Future<JoinDecisionResult> decideJoinRequest({
    required String courseId,
    required String studentUid,
    required JoinRequestDecision decision,
    String? rejectionReason,
  });
}
