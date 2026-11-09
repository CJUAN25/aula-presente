import 'dart:async';

import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_failure.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_page.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_repository.dart';
import 'package:aula_presente/features/enrollments/domain/student_candidate.dart';
import 'package:aula_presente/features/enrollments/presentation/student_enrollment_screens.dart';
import 'package:aula_presente/features/enrollments/presentation/teacher_enrollment_screens.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Course _course() => Course(
  id: 'course-1',
  ownerUid: 'teacher-1',
  subject: 'Curso de prueba',
  group: '02',
  period: '2026-2',
  program: 'Programa de prueba',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 2),
    endDate: AcademicDate(year: 2026, month: 11, day: 16),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'block-1',
        weekday: 1,
        startTime: '08:00',
        endTime: '10:00',
      ),
    ],
  ),
);

const _candidate = StudentCandidate(
  uid: 'student-1',
  name: 'Estudiante de prueba',
  email: 'student@example.invalid',
  studentCode: '0012',
);

Enrollment _enrollment({DateTime? createdAt}) => Enrollment(
  courseId: 'course-1',
  studentUid: 'student-1',
  ownerUid: 'teacher-1',
  name: _candidate.name,
  email: _candidate.email,
  studentCode: _candidate.studentCode,
  subject: 'Curso de prueba',
  group: '02',
  period: '2026-2',
  status: 'active',
  createdAt: createdAt,
);

class _Repository implements EnrollmentRepository {
  String? uid = 'teacher-1';
  bool candidateExists = true;
  bool failCount = false;
  bool failList = false;
  int writes = 0;
  int directoryCalls = 0;
  Completer<EnrollmentResult>? pendingDecision;
  final records = <Enrollment>[];

  @override
  String? get currentUid => uid;

  @override
  Future<void> ensureStudentDirectoryEntry() async {
    directoryCalls++;
  }

  @override
  Future<StudentCandidate?> findStudentByEmail(String email) async =>
      candidateExists && email == _candidate.email ? _candidate : null;

  @override
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
  }) async {
    final pending = pendingDecision;
    if (pending != null) return pending.future;
    if (records.isNotEmpty) {
      return EnrollmentResult(
        enrollment: records.single,
        alreadyEnrolled: true,
      );
    }
    writes++;
    records.add(_enrollment(createdAt: DateTime.utc(2026, 11, 5)));
    return EnrollmentResult(enrollment: _enrollment(), alreadyEnrolled: false);
  }

  @override
  Future<EnrollmentPage> listCourseStudents({
    required String courseId,
    EnrollmentCursor? cursor,
    int pageSize = 25,
  }) async {
    if (failList) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return EnrollmentPage(items: records, nextCursor: null);
  }

  @override
  Future<EnrollmentPage> listMyCourses({
    EnrollmentCursor? cursor,
    int pageSize = 25,
  }) async => EnrollmentPage(items: records, nextCursor: null);

  @override
  Future<int> countCourseStudents(String courseId) async {
    if (failCount) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return records.length;
  }

  @override
  Future<Course> getMyEnrolledCourse(String courseId) async => _course();
}

Widget _app(Widget screen, {double scale = 1}) => MaterialApp(
  theme: AppTheme.dark,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: screen,
);

Future<void> _openAdd(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    _app(TeacherEnrollmentHubScreen(course: _course(), repository: repository)),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Lista de estudiantes'), 250);
  await tester.tap(find.text('Lista de estudiantes'));
  await tester.pumpAndSettle();
  expect(find.text('Aún no hay estudiantes inscritos'), findsOneWidget);
  await tester.scrollUntilVisible(find.text('Agregar estudiante'), 250);
  await tester.tap(find.text('Agregar estudiante'));
  await tester.pumpAndSettle();
}

Future<void> _findCandidate(WidgetTester tester, {String code = '0012'}) async {
  await tester.enterText(find.byType(TextField).at(0), _candidate.email);
  await tester.enterText(find.byType(TextField).at(1), code);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Comprobar y agregar'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Comprobar y agregar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'docente revisa, confirma una vez y ve al estudiante en su curso',
    (tester) async {
      final repository = _Repository();
      await _openAdd(tester, repository);
      await _findCandidate(tester);
      expect(find.text('Revisa a quién agregarás.'), findsOneWidget);
      expect(find.text(_candidate.name), findsOneWidget);
      expect(repository.writes, 0);
      await tester.ensureVisible(find.text('Confirmar inscripción'));
      await tester.tap(find.text('Confirmar inscripción'));
      await tester.pumpAndSettle();
      expect(find.text('Inscripción confirmada.'), findsOneWidget);
      expect(repository.writes, 1);
      await tester.tap(find.text('Ver estudiantes'));
      await tester.pumpAndSettle();
      expect(find.text(_candidate.name), findsOneWidget);
      expect(find.textContaining('Datos al inscribir'), findsOneWidget);
    },
  );

  testWidgets('un guardado confirmado no falla por el refresco de la lista', (
    tester,
  ) async {
    final repository = _Repository();
    await _openAdd(tester, repository);
    await _findCandidate(tester);
    await tester.tap(find.text('Confirmar inscripción'));
    await tester.pumpAndSettle();
    expect(find.text('Inscripción confirmada.'), findsOneWidget);
    expect(repository.writes, 1);

    repository.failList = true;
    await tester.tap(find.text('Ver estudiantes'));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar la información'), findsOneWidget);
    expect(find.text('No se confirmó la inscripción'), findsNothing);
    expect(find.textContaining('Vuelve a consultar'), findsOneWidget);
    expect(repository.records, hasLength(1));
    expect(repository.writes, 1);

    repository.failList = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text(_candidate.name), findsOneWidget);
    expect(repository.writes, 1);
  });

  testWidgets(
    'correo ausente y código discordante conservan salida sin escribir',
    (tester) async {
      final repository = _Repository()..candidateExists = false;
      await tester.pumpWidget(
        _app(AddStudentScreen(course: _course(), repository: repository)),
      );
      await tester.pumpAndSettle();
      await _findCandidate(tester);
      expect(find.text('No se encontró una cuenta apta'), findsOneWidget);
      repository.candidateExists = true;
      await tester.enterText(find.byType(TextField).at(1), '9999');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Comprobar y agregar'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Comprobar y agregar'));
      await tester.pumpAndSettle();
      expect(find.text('Estos datos no coinciden.'), findsOneWidget);
      expect(repository.writes, 0);
      await tester.tap(find.text('Corregir datos'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
    },
  );

  testWidgets(
    'confirmación tardía de otra sesión no abre resultado protegido',
    (tester) async {
      final repository = _Repository()
        ..pendingDecision = Completer<EnrollmentResult>();
      await tester.pumpWidget(
        _app(AddStudentScreen(course: _course(), repository: repository)),
      );
      await tester.pumpAndSettle();
      await _findCandidate(tester);
      await tester.tap(find.text('Confirmar inscripción'));
      await tester.pump();
      repository.uid = 'other-user';
      repository.pendingDecision!.complete(
        EnrollmentResult(enrollment: _enrollment(), alreadyEnrolled: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Inscripción confirmada.'), findsNothing);
      expect(
        find.text('Guardado confirmado en la cuenta anterior'),
        findsOneWidget,
      );
    },
  );

  testWidgets('estudiante ve curso, horario y calendario previstos reales', (
    tester,
  ) async {
    final repository = _Repository()..uid = 'student-1';
    repository.records.add(_enrollment(createdAt: DateTime.utc(2026, 11, 5)));
    await tester.pumpWidget(_app(StudentCoursesScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Curso de prueba'), findsOneWidget);
    await tester.tap(find.text('Curso de prueba'));
    await tester.pumpAndSettle();
    expect(find.text('Horario semanal'), findsOneWidget);
    expect(find.textContaining('3 encuentros previstos'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver calendario previsto'));
    await tester.pumpAndSettle();
    expect(find.text('Calendario del curso'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('formulario se adapta a ${width.toInt()} px y texto ampliado', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          AddStudentScreen(course: _course(), repository: _Repository()),
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, _candidate.email);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Incorpora a tu estudiante.'), findsOneWidget);
    });
  }
}
