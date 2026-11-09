import 'package:flutter/material.dart';

import '../features/administration/data/firestore_teacher_access_repository.dart';
import '../features/administration/domain/teacher_access_repository.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/courses/data/firestore_course_repository.dart';
import '../features/courses/domain/course_repository.dart';
import '../features/enrollments/data/firestore_enrollment_repository.dart';
import '../features/enrollments/domain/enrollment_repository.dart';
import 'theme/app_theme.dart';
import 'course_repository_scope.dart';
import 'enrollment_repository_scope.dart';
import 'teacher_access_repository_scope.dart';

class AulaPresenteApp extends StatelessWidget {
  const AulaPresenteApp({
    super.key,
    this.authRepository,
    this.teacherAccessRepository,
    this.courseRepository,
    this.enrollmentRepository,
  });

  final AuthRepository? authRepository;
  final TeacherAccessRepository? teacherAccessRepository;
  final CourseRepository? courseRepository;
  final EnrollmentRepository? enrollmentRepository;

  @override
  Widget build(BuildContext context) {
    final auth = authRepository ?? FirebaseAuthRepository();
    final teacherAccess =
        teacherAccessRepository ?? FirestoreTeacherAccessRepository();
    final courses = courseRepository ?? FirestoreCourseRepository();
    final enrollments = enrollmentRepository ?? FirestoreEnrollmentRepository();
    return TeacherAccessRepositoryScope(
      repository: teacherAccess,
      child: EnrollmentRepositoryScope(
        repository: enrollments,
        child: CourseRepositoryScope(
          repository: courses,
          child: MaterialApp(
            title: 'Aula Presente',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            home: AuthStartScreen(repository: auth),
          ),
        ),
      ),
    );
  }
}
