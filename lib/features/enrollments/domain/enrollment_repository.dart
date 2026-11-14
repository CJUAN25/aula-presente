import '../../courses/domain/course.dart';
import 'enrollment.dart';
import 'enrollment_page.dart';
import 'enrollment_status_change.dart';
import 'student_candidate.dart';

abstract interface class EnrollmentRepository {
  /// Current session identity for guarding confirmed results in presentation.
  String? get currentUid;

  /// Publishes the current verified student's profile at the exact email key.
  Future<void> ensureStudentDirectoryEntry();

  /// Gets one known email; never enumerates profiles or directory documents.
  Future<StudentCandidate?> findStudentByEmail(String email);

  /// Commits at most one enrollment per course/student, without a post-write read.
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,

    /// Importing an already-existing enrollment must not decide a pending
    /// request that belongs to a separate admission flow.
    bool resolvePendingWhenAlreadyEnrolled = true,
  });

  /// Allocates a stable transition ID before the caller starts its transaction.
  String newStatusEventId({
    required String courseId,
    required String studentUid,
  });

  /// Changes only an active/withdrawn status and records its immutable event in
  /// the same transaction. The caller should retain [operationId] for retry.
  Future<EnrollmentStatusChangeResult> changeEnrollmentStatus({
    required Enrollment expected,
    required String nextStatus,
    required String operationId,
  });

  /// Loads one canonical enrollment from the server.
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  });

  /// Lists immutable status events, newest first.
  Future<EnrollmentHistoryPage> listEnrollmentHistory({
    required String courseId,
    required String studentUid,
    EnrollmentHistoryCursor? cursor,
    int pageSize = 25,
  });

  Future<EnrollmentPage> listCourseStudents({
    required String courseId,
    String status = 'active',
    EnrollmentCursor? cursor,
    int pageSize = 25,
  });

  Future<EnrollmentPage> listMyCourses({
    EnrollmentCursor? cursor,
    int pageSize = 25,
  });

  Future<int> countCourseStudents(String courseId);

  Future<Course> getMyEnrolledCourse(String courseId);
}
