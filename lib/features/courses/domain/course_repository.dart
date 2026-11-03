import 'course.dart';
import 'course_creation_result.dart';
import 'course_cursor.dart';
import 'course_draft.dart';
import 'course_page.dart';

abstract interface class CourseRepository {
  Future<CoursePage> getOwnCoursePage({
    CourseCursor? cursor,
    int pageSize = 25,
  });

  /// Fetches every own course by following pages. It must not treat one page
  /// as the complete agenda.
  Future<List<Course>> getAllOwnCourses({int pageSize = 25});

  /// Commits the stable draft ID once, or recognizes the same committed
  /// draft on retry. It must not perform UI/navigation effects.
  Future<CourseCreationResult> createCourse(CourseDraft draft);
}
