import 'package:flutter/widgets.dart';

import '../features/courses/domain/course_repository.dart';

class CourseRepositoryScope extends InheritedWidget {
  const CourseRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final CourseRepository repository;

  static CourseRepository of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CourseRepositoryScope>();
    assert(scope != null, 'CourseRepositoryScope is missing.');
    return scope!.repository;
  }

  static CourseRepository read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<CourseRepositoryScope>();
    final scope = element?.widget as CourseRepositoryScope?;
    assert(scope != null, 'CourseRepositoryScope is missing.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(CourseRepositoryScope oldWidget) =>
      repository != oldWidget.repository;
}
