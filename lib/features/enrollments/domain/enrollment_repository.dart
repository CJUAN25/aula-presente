import '../../courses/domain/course.dart';
import 'enrollment_page.dart';
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
  });

  Future<EnrollmentPage> listCourseStudents({
    required String courseId,
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
