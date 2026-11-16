import 'package:flutter/widgets.dart';

import '../features/attendance/domain/attendance_repository.dart';

class AttendanceRepositoryScope extends InheritedWidget {
  const AttendanceRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final AttendanceRepository repository;

  static AttendanceRepository read(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AttendanceRepositoryScope>();
    if (scope == null) {
      throw StateError('AttendanceRepositoryScope is missing.');
    }
    return scope.repository;
  }

  @override
  bool updateShouldNotify(AttendanceRepositoryScope oldWidget) =>
      repository != oldWidget.repository;
}
