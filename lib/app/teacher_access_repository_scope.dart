import 'package:flutter/widgets.dart';

import '../features/administration/domain/teacher_access_repository.dart';

class TeacherAccessRepositoryScope extends InheritedWidget {
  const TeacherAccessRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final TeacherAccessRepository repository;

  static TeacherAccessRepository of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TeacherAccessRepositoryScope>();
    assert(scope != null, 'TeacherAccessRepositoryScope is missing.');
    return scope!.repository;
  }

  static TeacherAccessRepository read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<TeacherAccessRepositoryScope>();
    final scope = element?.widget as TeacherAccessRepositoryScope?;
    assert(scope != null, 'TeacherAccessRepositoryScope is missing.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(TeacherAccessRepositoryScope oldWidget) =>
      repository != oldWidget.repository;
}
