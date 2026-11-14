import 'package:aula_presente/app/enrollment_route_observer.dart';
import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/courses/presentation/course_detail_screen.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_failure.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_repository.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/planned_meeting_generator.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Course _course() => Course(
  id: 'course-1',
  ownerUid: 'teacher-1',
  subject: 'Curso protegido',
  group: '01',
  period: '2026-2',
  program: 'Programa',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 2),
    endDate: AcademicDate(year: 2026, month: 11, day: 9),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'block-1',
        weekday: 1,
        startTime: '08:00',
        endTime: '09:00',
      ),
    ],
  ),
);

class _EnrollmentAccess implements EnrollmentRepository {
  String? uid = 'student-1';
  String status = 'active';
  bool denyPermission = false;
  int reads = 0;

  @override
  String? get currentUid => uid;

  @override
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  }) async {
    reads++;
    if (denyPermission) {
      throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
    }
    return Enrollment(
      courseId: courseId,
      studentUid: studentUid,
      ownerUid: 'teacher-1',
      name: 'Estudiante',
      email: 'student@example.invalid',
      studentCode: null,
      subject: 'Curso protegido',
      group: '01',
      period: '2026-2',
      status: status,
      createdAt: DateTime.utc(2026, 10, 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      navigatorObservers: [aulaPresenteRouteObserver],
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'calendario estudiante oculta horario al reanudar sin matrícula activa',
    (tester) async {
      final access = _EnrollmentAccess();
      await _pump(
        tester,
        CourseCalendarScreen(course: _course(), studentRepository: access),
      );
      expect(find.text('Curso protegido'), findsOneWidget);
      expect(
        find.textContaining('Encuentros calculados desde'),
        findsOneWidget,
      );

      access.status = 'withdrawn';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.textContaining('Lunes'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(access.reads, greaterThanOrEqualTo(2));
      expect(find.text('Tu inscripción fue retirada'), findsOneWidget);
      expect(find.textContaining('Encuentros calculados desde'), findsNothing);
    },
  );

  testWidgets('detalle del encuentro no conserva el horario tras revocación', (
    tester,
  ) async {
    final access = _EnrollmentAccess();
    final course = _course();
    final meeting = generatePlannedMeetings(
      courseId: course.id,
      schedule: course.schedule,
    ).first;
    await _pump(
      tester,
      PlannedMeetingDetailScreen(
        course: course,
        meeting: meeting,
        studentRepository: access,
      ),
    );
    expect(find.text('ENCUENTRO PREVISTO'), findsOneWidget);

    access.status = 'withdrawn';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Tu inscripción fue retirada'), findsOneWidget);
    expect(find.text('ENCUENTRO PREVISTO'), findsNothing);
    expect(find.text('Horario'), findsNothing);
  });

  testWidgets('calendario borra la vista si Rules deniega al reanudar', (
    tester,
  ) async {
    final access = _EnrollmentAccess();
    await _pump(
      tester,
      CourseCalendarScreen(course: _course(), studentRepository: access),
    );
    expect(find.textContaining('Encuentros calculados desde'), findsOneWidget);

    access.denyPermission = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.textContaining('Encuentros calculados desde'), findsNothing);
    expect(find.textContaining('Lunes'), findsNothing);
    expect(find.text('Tu inscripción fue retirada'), findsNothing);
    expect(find.textContaining('permisos'), findsOneWidget);
  });
}
