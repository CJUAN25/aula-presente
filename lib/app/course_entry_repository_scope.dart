import 'package:flutter/widgets.dart';

import '../features/course_entry/domain/course_entry_repository.dart';

class CourseEntryRepositoryScope extends InheritedWidget {
  const CourseEntryRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final CourseEntryRepository repository;

  static CourseEntryRepository read(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CourseEntryRepositoryScope>();
    if (scope == null) {
      throw StateError('CourseEntryRepositoryScope is missing.');
    }
    return scope.repository;
  }

  @override
  bool updateShouldNotify(CourseEntryRepositoryScope oldWidget) =>
      repository != oldWidget.repository;
}
