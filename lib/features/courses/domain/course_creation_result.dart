import 'course.dart';

class CourseCreationResult {
  const CourseCreationResult({
    required this.course,
    required this.wasAlreadyCreated,
  });

  final Course course;
  final bool wasAlreadyCreated;
}
