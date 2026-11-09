import 'package:flutter/widgets.dart';

import '../features/enrollments/domain/enrollment_repository.dart';

class EnrollmentRepositoryScope extends InheritedWidget {
  const EnrollmentRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final EnrollmentRepository repository;

  static EnrollmentRepository read(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<EnrollmentRepositoryScope>();
    if (scope == null) {
      throw StateError('EnrollmentRepositoryScope is missing.');
    }
    return scope.repository;
  }

  @override
  bool updateShouldNotify(EnrollmentRepositoryScope oldWidget) =>
      repository != oldWidget.repository;
}
