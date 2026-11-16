import 'package:flutter/material.dart';

import '../features/administration/data/firestore_teacher_access_repository.dart';
import '../features/administration/domain/teacher_access_repository.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/courses/data/firestore_course_repository.dart';
import '../features/courses/domain/course_repository.dart';
import '../features/course_entry/data/firestore_course_entry_repository.dart';
import '../features/course_entry/domain/course_entry_repository.dart';
import '../features/enrollments/data/firestore_enrollment_repository.dart';
import '../features/enrollments/domain/enrollment_repository.dart';
import '../features/attendance/data/firestore_attendance_repository.dart';
import '../features/attendance/domain/attendance_repository.dart';
import 'theme/app_theme.dart';
import 'attendance_repository_scope.dart';
import 'course_repository_scope.dart';
import 'course_entry_repository_scope.dart';
import 'enrollment_repository_scope.dart';
import 'teacher_access_repository_scope.dart';
import 'enrollment_route_observer.dart';

class AulaPresenteApp extends StatelessWidget {
  const AulaPresenteApp({
    super.key,
    this.authRepository,
    this.teacherAccessRepository,
    this.courseRepository,
    this.enrollmentRepository,
    this.courseEntryRepository,
    this.attendanceRepository,
  });

  final AuthRepository? authRepository;
  final TeacherAccessRepository? teacherAccessRepository;
  final CourseRepository? courseRepository;
  final EnrollmentRepository? enrollmentRepository;
  final CourseEntryRepository? courseEntryRepository;
  final AttendanceRepository? attendanceRepository;

  @override
  Widget build(BuildContext context) {
    final auth = authRepository ?? FirebaseAuthRepository();
    final teacherAccess =
        teacherAccessRepository ?? FirestoreTeacherAccessRepository();
    final courses = courseRepository ?? FirestoreCourseRepository();
    final enrollments = enrollmentRepository ?? FirestoreEnrollmentRepository();
    final courseEntry =
        courseEntryRepository ?? FirestoreCourseEntryRepository();
    final attendance =
        attendanceRepository ??
        FirestoreAttendanceRepository(enrollments: enrollments);
    return TeacherAccessRepositoryScope(
      repository: teacherAccess,
      child: EnrollmentRepositoryScope(
        repository: enrollments,
        child: AttendanceRepositoryScope(
          repository: attendance,
          child: CourseEntryRepositoryScope(
            repository: courseEntry,
            child: CourseRepositoryScope(
              repository: courses,
              child: MaterialApp(
                title: 'Aula Presente',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.dark,
                navigatorObservers: [aulaPresenteRouteObserver],
                home: AuthStartScreen(repository: auth),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
