import 'course.dart';
import 'course_cursor.dart';

class CoursePage {
  CoursePage({required List<Course> items, required this.nextCursor})
    : items = List.unmodifiable(items);

  final List<Course> items;
  final CourseCursor? nextCursor;

  bool get hasMore => nextCursor != null;
}
