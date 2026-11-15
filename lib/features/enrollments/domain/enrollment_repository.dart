import '../../courses/domain/course.dart';
import 'enrollment.dart';
import 'enrollment_page.dart';
import 'enrollment_status_change.dart';
import 'pending_enrollment.dart';
import 'pending_enrollment_page.dart';
import 'pending_enrollment_result.dart';
import 'student_candidate.dart';
import '../../schedule/domain/academic_date.dart';

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
    AcademicDate? effectiveStartDate,

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
    AcademicDate? effectiveDate,
  });

  /// Creates one teacher-authorized pending roster entry without copying the
  /// source spreadsheet. An existing changed/conflicting identity is rejected.
  Future<PendingEnrollmentWriteResult> authorizePendingEnrollment({
    required Course course,
    required String email,
    required String studentCode,
    required String name,
    required AcademicDate effectiveStartDate,
  });

  /// Allocates a stable operation ID before a pending status transaction.
  String newPendingStatusEventId({
    required String courseId,
    required String email,
  });

  /// Retires a still-unlinked authorization or explicitly reopens one that was
  /// retired. The operation and immutable history event commit atomically.
  Future<PendingEnrollmentStatusChangeResult> changePendingEnrollmentStatus({
    required PendingEnrollment expected,
    required String nextStatus,
    required String operationId,
    required AcademicDate effectiveDate,
  });

  Future<PendingEnrollment?> getCoursePendingEnrollment({
    required String courseId,
    required String email,
  });

  Future<PendingEnrollmentPage> listCoursePendingEnrollments({
    required String courseId,
    required String status,
    PendingEnrollmentCursor? cursor,
    int pageSize = 25,
  });

  /// Returns a complete server-backed snapshot only after all four lists
  /// (active/withdrawn enrollments and pending/withdrawn authorizations) load.
  Future<CourseRosterSnapshot> loadCourseRosterSnapshot({
    required String courseId,
  });

  /// Exact owner-side email lookup used to prevent duplicate membership even
  /// when the student's directory entry is unavailable or has changed UID.
  Future<List<Enrollment>> findCourseEnrollmentsByEmail({
    required String courseId,
    required String email,
  });

  /// Bounded owner-side collision check by exact student code. It returns at
  /// most two rows from each roster collection and flags further matches.
  Future<CourseRosterIdentityLookup> findCourseRosterByStudentCode({
    required String courseId,
    required String studentCode,
  });

  /// Automatically links every eligible pending entry for the authenticated,
  /// verified student. It never approves a join request or grants a role.
  Future<PendingEnrollmentLinkSummary> linkOwnPendingEnrollments();

  /// Loads one canonical enrollment from the server.
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  });

  /// Owner-side point read for a reviewed directory candidate. It returns null
  /// when the canonical UID document does not exist and never lists a roster.
  Future<Enrollment?> findCourseEnrollmentByUid({
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

  Future<PendingEnrollmentHistoryPage> listPendingEnrollmentHistory({
    required String courseId,
    required String email,
    PendingEnrollmentHistoryCursor? cursor,
    int pageSize = 25,
  });

  Future<EnrollmentPage> listMyCourses({
    EnrollmentCursor? cursor,
    int pageSize = 25,
  });

  Future<int> countCourseStudents(String courseId);

  Future<int> countCoursePendingEnrollments(String courseId);

  Future<Course> getMyEnrolledCourse(String courseId);
}
