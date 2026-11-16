import '../../../helpers/calendar_attendance_stub.dart';

import 'package:aula_presente/app/attendance_repository_scope.dart';

import 'dart:async';

import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_failure.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_page.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_repository.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_status_change.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment_page.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment_result.dart';
import 'package:aula_presente/features/enrollments/domain/student_candidate.dart';
import 'package:aula_presente/features/enrollments/presentation/course_enrollment_history_screen.dart';
import 'package:aula_presente/features/enrollments/presentation/enrollment_history_screen.dart';
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

Enrollment _enrollment({
  DateTime? createdAt,
  String status = 'active',
  String courseId = 'course-1',
  String studentUid = 'student-1',
  String ownerUid = 'teacher-1',
  String? name,
  String email = 'student@example.invalid',
  String? studentCode = '0012',
  String subject = 'Curso de prueba',
  String group = '02',
  String period = '2026-2',
  String? rosterEntryId,
  AcademicDate? effectiveStartDate,
}) => Enrollment(
  courseId: courseId,
  studentUid: studentUid,
  ownerUid: ownerUid,
  name: name ?? _candidate.name,
  email: email,
  studentCode: studentCode,
  subject: subject,
  group: group,
  period: period,
  status: status,
  createdAt: createdAt,
  rosterEntryId: rosterEntryId,
  effectiveStartDate: effectiveStartDate,
);

PendingEnrollment _pendingEnrollment({
  String courseId = 'course-1',
  String ownerUid = 'teacher-1',
  String email = 'pending@example.invalid',
  String studentCode = '0023',
  String name = 'Estudiante pendiente',
  String status = 'pending',
  String rosterEntryId = 'pending@example.invalid',
  String? studentUid,
  DateTime? linkedAt,
  DateTime? createdAt,
}) {
  final timestamp = createdAt ?? DateTime.utc(2026, 11, 5, 9);
  return PendingEnrollment(
    courseId: courseId,
    ownerUid: ownerUid,
    subject: 'Curso de prueba',
    group: '02',
    period: '2026-2',
    email: email,
    studentCode: studentCode,
    name: name,
    status: status,
    effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 5),
    rosterEntryId: rosterEntryId,
    studentUid: studentUid,
    authorizedAt: timestamp,
    linkedAt: linkedAt,
    createdAt: timestamp,
    updatedAt: timestamp,
    lastEventId: null,
    lastStatusChangedAt: null,
  );
}

class _Repository implements EnrollmentRepository {
  String? uid = 'teacher-1';
  bool candidateExists = true;
  bool failCount = false;
  bool failList = false;
  bool denyStatusChange = false;
  bool failAfterStatusWrite = false;
  Object? failPendingLink;
  PendingEnrollmentLinkSummary pendingLinkSummary =
      PendingEnrollmentLinkSummary(rows: const []);
  int writes = 0;
  int statusAttempts = 0;
  int statusChanges = 0;
  int statusEventIds = 0;
  int directoryCalls = 0;
  int pendingLinkCalls = 0;
  int myCoursesCalls = 0;
  final callOrder = <String>[];
  Completer<EnrollmentResult>? pendingDecision;
  Completer<EnrollmentHistoryPage>? pendingHistoryPage;
  final records = <Enrollment>[];
  final statusEvents = <EnrollmentStatusEvent>[];
  CourseRosterSnapshot rosterSnapshot = CourseRosterSnapshot(
    activeEnrollments: const [],
    withdrawnEnrollments: const [],
    pendingEnrollments: const [],
    withdrawnPendingEnrollments: const [],
    complete: true,
  );
  bool failRosterSnapshot = false;
  Completer<CourseRosterSnapshot>? pendingRosterSnapshot;
  PendingEnrollment? pendingAuthorization;
  final pendingStatusEvents = <PendingEnrollmentStatusEvent>[];
  int rosterSnapshotReads = 0;

  @override
  String? get currentUid => uid;

  @override
  Future<void> ensureStudentDirectoryEntry() async {
    directoryCalls++;
    callOrder.add('directory');
  }

  @override
  Future<StudentCandidate?> findStudentByEmail(String email) async =>
      candidateExists && email == _candidate.email ? _candidate : null;

  @override
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
    AcademicDate? effectiveStartDate,
    bool resolvePendingWhenAlreadyEnrolled = true,
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
    String status = 'active',
    EnrollmentCursor? cursor,
    int pageSize = 25,
  }) async {
    if (failList) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return EnrollmentPage(
      items: records.where((record) => record.status == status).toList(),
      nextCursor: null,
    );
  }

  @override
  Future<EnrollmentPage> listMyCourses({
    EnrollmentCursor? cursor,
    int pageSize = 25,
  }) async {
    myCoursesCalls++;
    callOrder.add('courses');
    return EnrollmentPage(
      items: records.where((record) => record.status == 'active').toList(),
      nextCursor: null,
    );
  }

  @override
  Future<int> countCourseStudents(String courseId) async {
    if (failCount) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return records.where((record) => record.status == 'active').length;
  }

  @override
  Future<int> countCoursePendingEnrollments(String courseId) async => 0;

  @override
  Future<CourseRosterSnapshot> loadCourseRosterSnapshot({
    required String courseId,
  }) async {
    rosterSnapshotReads++;
    if (failRosterSnapshot) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    final pending = pendingRosterSnapshot;
    if (pending != null) return pending.future;
    return rosterSnapshot;
  }

  @override
  Future<PendingEnrollment?> getCoursePendingEnrollment({
    required String courseId,
    required String email,
  }) async {
    final pending = pendingAuthorization;
    if (pending == null ||
        pending.courseId != courseId ||
        pending.email != email) {
      return null;
    }
    return pending;
  }

  @override
  Future<PendingEnrollmentHistoryPage> listPendingEnrollmentHistory({
    required String courseId,
    required String email,
    PendingEnrollmentHistoryCursor? cursor,
    int pageSize = 25,
  }) async => PendingEnrollmentHistoryPage(
    items: pendingStatusEvents,
    nextCursor: null,
  );

  @override
  Future<PendingEnrollmentLinkSummary> linkOwnPendingEnrollments() async {
    pendingLinkCalls++;
    callOrder.add('link');
    if (failPendingLink case final error?) throw error;
    return pendingLinkSummary;
  }

  @override
  String newStatusEventId({
    required String courseId,
    required String studentUid,
  }) => 'operation-${++statusEventIds}';

  @override
  Future<EnrollmentStatusChangeResult> changeEnrollmentStatus({
    required Enrollment expected,
    required String nextStatus,
    required String operationId,
    AcademicDate? effectiveDate,
  }) async {
    statusAttempts++;
    if (denyStatusChange) {
      throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
    }
    final index = records.indexWhere(
      (record) => record.studentUid == expected.studentUid,
    );
    final current = index < 0 ? expected : records[index];
    if (current.status == nextStatus &&
        current.lastStatusEventId == operationId) {
      return EnrollmentStatusChangeResult(
        enrollment: current,
        alreadyApplied: true,
      );
    }
    if (current.status != expected.status ||
        current.lastStatusEventId != expected.lastStatusEventId) {
      throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
    }
    statusChanges++;
    final changedAt = DateTime.utc(
      2026,
      11,
      8,
      2,
      30,
    ).add(Duration(minutes: statusChanges));
    final updated = Enrollment(
      courseId: current.courseId,
      studentUid: current.studentUid,
      ownerUid: current.ownerUid,
      name: current.name,
      email: current.email,
      studentCode: current.studentCode,
      subject: current.subject,
      group: current.group,
      period: current.period,
      status: nextStatus,
      createdAt: current.createdAt,
      lastStatusEventId: operationId,
      lastStatusChangedAt: changedAt,
    );
    if (index >= 0) records[index] = updated;
    statusEvents.insert(
      0,
      EnrollmentStatusEvent(
        operationId: operationId,
        fromStatus: current.status,
        toStatus: nextStatus,
        changedAt: changedAt,
        changedBy: 'teacher-1',
      ),
    );
    if (failAfterStatusWrite) {
      failAfterStatusWrite = false;
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return EnrollmentStatusChangeResult(
      enrollment: updated,
      alreadyApplied: false,
    );
  }

  @override
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  }) async => records.firstWhere(
    (record) => record.courseId == courseId && record.studentUid == studentUid,
  );

  @override
  Future<EnrollmentHistoryPage> listEnrollmentHistory({
    required String courseId,
    required String studentUid,
    EnrollmentHistoryCursor? cursor,
    int pageSize = 25,
  }) async {
    final pending = pendingHistoryPage;
    if (pending != null) return pending.future;
    return EnrollmentHistoryPage(
      items: statusEvents
          .where((event) => event.changedBy == 'teacher-1')
          .toList(),
      nextCursor: null,
    );
  }

  @override
  Future<Course> getMyEnrolledCourse(String courseId) async => _course();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget screen, {double scale = 1}) => MaterialApp(
  theme: AppTheme.dark,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: AttendanceRepositoryScope(
      repository: CalendarAttendanceStub(),
      child: child!,
    ),
  ),
  home: screen,
);

Future<void> _openAdd(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    _app(TeacherEnrollmentHubScreen(course: _course(), repository: repository)),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Lista de estudiantes'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Lista de estudiantes'));
  await tester.pumpAndSettle();
  expect(find.text('Aún no hay estudiantes en esta lista'), findsOneWidget);
  await tester.scrollUntilVisible(
    find.text('Agregar estudiante'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
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

Future<void> _tapStatusAction(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Mis materias publica el directorio antes de enlazar y consulta después',
    (tester) async {
      final repository = _Repository()
        ..uid = 'student-1'
        ..records.add(_enrollment())
        ..pendingLinkSummary = PendingEnrollmentLinkSummary(
          rows: const [
            PendingEnrollmentLinkRowResult(
              courseId: 'course-2',
              email: 'student@example.invalid',
              outcome: PendingEnrollmentLinkOutcome.linked,
            ),
          ],
        );

      await tester.pumpWidget(
        _app(StudentCoursesScreen(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(repository.callOrder.take(3), ['directory', 'link', 'courses']);
      expect(repository.pendingLinkCalls, 1);
      expect(find.text('Curso de prueba'), findsOneWidget);
      expect(find.textContaining('Se vinculó 1 materia'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'gestión separa comparar lista y solo agregar a ${width.toInt()} px',
      (tester) async {
        tester.view.physicalSize = Size(width * 2, 844 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _app(
            TeacherEnrollmentHubScreen(
              course: _course(),
              repository: _Repository(),
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Actualizar lista con Excel'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Actualizar lista con Excel'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Solo agregar estudiantes'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Solo agregar estudiantes'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Pendientes de vincular'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Pendientes de vincular'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'si falla la vinculación conserva y muestra materias y permite reintentar',
    (tester) async {
      final repository = _Repository()
        ..uid = 'student-1'
        ..records.add(_enrollment())
        ..failPendingLink = const EnrollmentFailure(
          EnrollmentFailureKind.network,
        );

      await tester.pumpWidget(
        _app(StudentCoursesScreen(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Curso de prueba'), findsOneWidget);
      expect(
        find.text('No se comprobaron las inscripciones pendientes'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Tus materias actuales siguen disponibles.'),
        findsOneWidget,
      );

      repository.failPendingLink = null;
      await tester.tap(find.text('Reintentar comprobación'));
      await tester.pumpAndSettle();

      expect(repository.pendingLinkCalls, 2);
      expect(find.text('Curso de prueba'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets(
      'estado de vinculación se adapta a ${width.toInt()} px con texto 1.6',
      (tester) async {
        tester.view.physicalSize = Size(width * 2, 844 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository()
          ..uid = 'student-1'
          ..pendingLinkSummary = PendingEnrollmentLinkSummary(
            rows: const [
              PendingEnrollmentLinkRowResult(
                courseId: 'course-2',
                email: 'student@example.invalid',
                outcome: PendingEnrollmentLinkOutcome.needsReview,
              ),
            ],
          );

        await tester.pumpWidget(
          _app(StudentCoursesScreen(repository: repository), scale: 1.6),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Hay inscripciones que requieren atención'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'el contador activo se actualiza al volver del historial tras reincorporar',
    (tester) async {
      final repository = _Repository()
        ..records.add(_enrollment(status: 'withdrawn'));
      await tester.pumpWidget(
        _app(
          TeacherEnrollmentHubScreen(course: _course(), repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Retirados'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Retirados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_candidate.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reincorporar al curso'));
      await tester.pumpAndSettle();
      await _tapStatusAction(tester, 'Confirmar reincorporación');
      expect(repository.records.single.status, 'active');
      await tester.tap(find.text('Ver estudiantes'));
      await tester.pumpAndSettle();
      expect(find.text(_candidate.name), findsNothing);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Gestionar estudiantes'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Estudiantes inscritos'), findsOneWidget);
    },
  );

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

  testWidgets(
    'docente retira, consulta historial y reincorpora sin recrear matrícula',
    (tester) async {
      final repository = _Repository();
      final originalCreatedAt = DateTime.utc(2026, 11, 5, 14);
      repository.records.add(_enrollment(createdAt: originalCreatedAt));
      await tester.pumpWidget(
        _app(CourseStudentsScreen(course: _course(), repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_candidate.name));
      await tester.pumpAndSettle();
      expect(find.text('Ficha del estudiante'), findsOneWidget);
      expect(find.text('Retirar del curso'), findsOneWidget);
      await tester.tap(find.text('Retirar del curso'));
      await tester.pumpAndSettle();
      expect(find.text('Al confirmar'), findsOneWidget);
      expect(
        find.text(
          'El servidor registrará la fecha efectiva del retiro al confirmar.',
        ),
        findsOneWidget,
      );
      expect(repository.statusEvents, isEmpty);
      await _tapStatusAction(tester, 'Confirmar retiro');
      expect(find.text('Estudiante retirado.'), findsOneWidget);
      expect(repository.records.single.status, 'withdrawn');
      expect(repository.statusChanges, 1);
      expect(repository.records.single.createdAt, originalCreatedAt);

      await tester.tap(find.text('Ver estudiantes'));
      await tester.pumpAndSettle();
      expect(find.text(_candidate.name), findsNothing);
      await tester.ensureVisible(find.text('Retirados'));
      await tester.tap(find.text('Retirados'));
      await tester.pumpAndSettle();
      expect(find.text(_candidate.name), findsOneWidget);
      await tester.tap(find.text(_candidate.name));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ver historial de matrícula'));
      await tester.tap(find.text('Ver historial de matrícula'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ingreso confirmado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Ingreso confirmado'), findsOneWidget);
      expect(
        find.textContaining('Fecha registrada · 05/11/2026'),
        findsOneWidget,
      );
      expect(find.text('Retiro confirmado'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Retiro confirmado')).dy,
        lessThan(tester.getTopLeft(find.text('Ingreso confirmado')).dy),
      );
      expect(find.textContaining('07/11/2026 · 21:31'), findsOneWidget);
      expect(find.textContaining('08/11/2026 · 02:30'), findsNothing);
      await tester.tap(find.byTooltip('Volver a la ficha'));
      await tester.pumpAndSettle();
      expect(find.text('Reincorporar al curso'), findsOneWidget);
      await tester.tap(find.text('Reincorporar al curso'));
      await tester.pumpAndSettle();
      expect(find.text('Al confirmar'), findsOneWidget);
      expect(
        find.text(
          'El servidor registrará la fecha efectiva del nuevo ingreso al confirmar.',
        ),
        findsOneWidget,
      );
      expect(repository.statusEvents, hasLength(1));
      await _tapStatusAction(tester, 'Confirmar reincorporación');
      expect(find.text('Reincorporación confirmada.'), findsOneWidget);
      expect(repository.records.single.status, 'active');
      expect(repository.records.single.createdAt, originalCreatedAt);
      expect(repository.statusChanges, 2);
      expect(repository.statusEvents, hasLength(2));
      await tester.tap(find.text('Ver estudiantes'));
      await tester.pumpAndSettle();
      expect(repository.records, hasLength(1));
      expect(find.text(_candidate.name), findsNothing);
      await tester.tap(find.text('Volver a estudiantes activos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_candidate.name));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ver historial de matrícula'));
      await tester.tap(find.text('Ver historial de matrícula'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ingreso confirmado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Reincorporación confirmada'), findsOneWidget);
      expect(find.text('Retiro confirmado'), findsOneWidget);
      expect(find.text('Ingreso confirmado'), findsOneWidget);
      expect(find.textContaining('07/11/2026 · 21:32'), findsOneWidget);
      expect(find.textContaining('07/11/2026 · 21:31'), findsOneWidget);
      expect(
        find.textContaining('Fecha registrada · 05/11/2026'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Reincorporación confirmada')).dy,
        lessThan(tester.getTopLeft(find.text('Retiro confirmado')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Retiro confirmado')).dy,
        lessThan(tester.getTopLeft(find.text('Ingreso confirmado')).dy),
      );
    },
  );

  testWidgets(
    'un reintento incierto conserva el mismo operationId y no repite el retiro',
    (tester) async {
      final repository = _Repository()..failAfterStatusWrite = true;
      final originalCreatedAt = DateTime.utc(2026, 11, 5, 14);
      repository.records.add(_enrollment(createdAt: originalCreatedAt));
      await tester.pumpWidget(
        _app(CourseStudentsScreen(course: _course(), repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_candidate.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirar del curso'));
      await tester.pumpAndSettle();
      await _tapStatusAction(tester, 'Confirmar retiro');
      expect(find.text('No se confirmó el cambio'), findsOneWidget);
      expect(repository.records.single.status, 'withdrawn');
      final operationId = repository.records.single.lastStatusEventId;
      expect(operationId, 'operation-1');
      await _tapStatusAction(tester, 'Confirmar retiro');
      expect(find.text('Estudiante retirado.'), findsOneWidget);
      expect(repository.statusAttempts, 2);
      expect(repository.statusChanges, 1);
      expect(repository.statusEvents, hasLength(1));
      expect(repository.records.single.lastStatusEventId, operationId);
    },
  );

  testWidgets('permiso denegado conserva el estado y muestra el error claro', (
    tester,
  ) async {
    final repository = _Repository()..denyStatusChange = true;
    repository.records.add(
      _enrollment(createdAt: DateTime.utc(2026, 11, 5, 14)),
    );
    await tester.pumpWidget(
      _app(CourseStudentsScreen(course: _course(), repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_candidate.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirar del curso'));
    await tester.pumpAndSettle();
    await _tapStatusAction(tester, 'Confirmar retiro');
    expect(
      find.text('No tienes permiso para completar esta operación'),
      findsOneWidget,
    );
    expect(find.text('Estudiante retirado.'), findsNothing);
    expect(repository.records.single.status, 'active');
    expect(repository.statusChanges, 0);
  });

  testWidgets(
    'un estado obsoleto bloquea la repetición y pide actualizar la lista',
    (tester) async {
      final repository = _Repository();
      repository.records.add(
        _enrollment(createdAt: DateTime.utc(2026, 11, 5, 14)),
      );
      await tester.pumpWidget(
        _app(CourseStudentsScreen(course: _course(), repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_candidate.name));
      await tester.pumpAndSettle();
      repository.records[0] = _enrollment(
        createdAt: DateTime.utc(2026, 11, 5, 14),
        status: 'withdrawn',
      );
      await tester.tap(find.text('Retirar del curso'));
      await tester.pumpAndSettle();
      await _tapStatusAction(tester, 'Confirmar retiro');
      expect(find.text('La inscripción cambió'), findsOneWidget);
      expect(repository.statusChanges, 0);
      await tester.scrollUntilVisible(
        find.text('Confirmar retiro'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar retiro'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('el detalle del estudiante descarta el horario tras el retiro', (
    tester,
  ) async {
    final repository = _Repository()
      ..uid = 'student-1'
      ..records.add(_enrollment(status: 'withdrawn'));
    await tester.pumpWidget(
      _app(
        StudentEnrolledCourseScreen(
          enrollment: _enrollment(),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tu inscripción fue retirada'), findsOneWidget);
    expect(find.text('Horario semanal'), findsNothing);
    expect(find.text('Ver calendario previsto'), findsNothing);
  });

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
    testWidgets(
      'listas y confirmación C5 se adaptan a ${width.toInt()} px y texto 1.6',
      (tester) async {
        tester.view.physicalSize = Size(width * 2, 844 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repository = _Repository();
        final activeEnrollment = _enrollment(
          createdAt: DateTime.utc(2026, 11, 5, 14),
        );
        repository.records.add(activeEnrollment);
        await tester.pumpWidget(
          _app(
            CourseStudentsScreen(course: _course(), repository: repository),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(_candidate.name), findsOneWidget);

        repository.records[0] = _enrollment(
          createdAt: activeEnrollment.createdAt,
          status: 'withdrawn',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          _app(
            CourseStudentsScreen(
              course: _course(),
              repository: repository,
              status: 'withdrawn',
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Retirados'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text(_candidate.name),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(_candidate.name), findsOneWidget);

        await tester.pumpWidget(
          _app(
            EnrollmentStatusChangeScreen(
              course: _course(),
              expected: activeEnrollment,
              repository: repository,
            ),
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Al confirmar'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Al confirmar'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Al confirmar'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Confirmar retiro'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Confirmar retiro'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Confirmar retiro'), findsOneWidget);
      },
    );
  }

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

  testWidgets(
    'gestión abre historial unificado por curso y conserva eventos previos al vínculo',
    (tester) async {
      final enrolled = _enrollment(
        name: 'Estudiante reincorporado',
        email: 'reincorporado@example.invalid',
        studentUid: 'student-rejoined',
        rosterEntryId: 'reincorporado@example.invalid',
        createdAt: DateTime.utc(2026, 11, 5, 14),
        effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 5),
      );
      final linkedPending = _pendingEnrollment(
        email: enrolled.email,
        name: enrolled.name,
        rosterEntryId: enrolled.rosterEntryId!,
        status: 'linked',
        studentUid: enrolled.studentUid,
        linkedAt: DateTime.utc(2026, 11, 6, 14),
      );
      final currentWithdrawn = _enrollment(
        name: 'Estudiante retirado',
        email: 'retirado@example.invalid',
        studentUid: 'student-withdrawn',
        rosterEntryId: 'retirado@example.invalid',
        status: 'withdrawn',
        createdAt: DateTime.utc(2026, 11, 4, 14),
        effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 4),
      );
      final pending = _pendingEnrollment();
      final withdrawnPending = _pendingEnrollment(
        email: 'autorizacion-retirada@example.invalid',
        name: 'Autorización retirada',
        rosterEntryId: 'autorizacion-retirada@example.invalid',
        status: 'withdrawn',
      );
      final repository = _Repository()
        ..records.add(enrolled)
        ..rosterSnapshot = CourseRosterSnapshot(
          activeEnrollments: [enrolled],
          withdrawnEnrollments: [currentWithdrawn],
          pendingEnrollments: [pending, linkedPending],
          withdrawnPendingEnrollments: [withdrawnPending],
          complete: true,
        )
        ..pendingAuthorization = linkedPending
        ..statusEvents.addAll([
          EnrollmentStatusEvent(
            operationId: 'rejoin',
            fromStatus: 'withdrawn',
            toStatus: 'active',
            changedAt: DateTime.utc(2026, 11, 14, 2, 30),
            changedBy: 'teacher-1',
            effectiveDate: AcademicDate(year: 2026, month: 11, day: 14),
          ),
          EnrollmentStatusEvent(
            operationId: 'withdraw',
            fromStatus: 'active',
            toStatus: 'withdrawn',
            changedAt: DateTime.utc(2026, 11, 10, 2, 30),
            changedBy: 'teacher-1',
            effectiveDate: AcademicDate(year: 2026, month: 11, day: 10),
          ),
        ])
        ..pendingStatusEvents.addAll([
          PendingEnrollmentStatusEvent(
            operationId: 'linked',
            fromStatus: 'pending',
            toStatus: 'linked',
            effectiveDate: AcademicDate(year: 2026, month: 11, day: 5),
            changedAt: DateTime.utc(2026, 11, 6, 14),
            changedBy: enrolled.studentUid,
          ),
        ]);

      await tester.pumpWidget(
        _app(
          TeacherEnrollmentHubScreen(course: _course(), repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Historial de matrícula'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Historial de matrícula').first);
      await tester.pumpAndSettle();

      expect(find.text('Curso de prueba · Grupo 02 · 2026-2'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Estudiante reincorporado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Activo · reincorporado@example.invalid'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Estudiante retirado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Retirado · retirado@example.invalid'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Estudiante pendiente'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Pendiente de vincular · pending@example.invalid'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Autorización retirada'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(
          'Autorización retirada · autorizacion-retirada@example.invalid',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Estudiante reincorporado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Estudiante reincorporado'), findsOneWidget);
      expect(repository.writes, 0);
      expect(repository.statusChanges, 0);

      await tester.tap(find.text('Estudiante reincorporado'));
      await tester.pumpAndSettle();
      expect(find.text('Historial de matrícula'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Ingreso confirmado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Ingreso confirmado'), findsOneWidget);
      expect(find.text('Fecha efectiva · 2026-11-05'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Retiro confirmado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Retiro confirmado'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Reincorporación confirmada'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Reincorporación confirmada'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Autorización previa'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Autorización previa'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Cuenta vinculada'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cuenta vinculada'), findsOneWidget);
      expect(repository.writes, 0);
      expect(repository.statusChanges, 0);
    },
  );

  testWidgets(
    'una reincorporación queda Activa, sale de Retirados y abre el mismo historial desde la ficha',
    (tester) async {
      final enrolled = _enrollment(
        name: 'Estudiante reincorporado',
        email: 'reincorporado@example.invalid',
        studentUid: 'student-rejoined',
        createdAt: DateTime.utc(2026, 11, 5, 14),
        effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 5),
        status: 'active',
      );
      final repository = _Repository()
        ..records.add(enrolled)
        ..statusEvents.addAll([
          EnrollmentStatusEvent(
            operationId: 'rejoin',
            fromStatus: 'withdrawn',
            toStatus: 'active',
            changedAt: DateTime.utc(2026, 11, 14, 2, 30),
            changedBy: 'teacher-1',
            effectiveDate: AcademicDate(year: 2026, month: 11, day: 14),
          ),
          EnrollmentStatusEvent(
            operationId: 'withdraw',
            fromStatus: 'active',
            toStatus: 'withdrawn',
            changedAt: DateTime.utc(2026, 11, 10, 2, 30),
            changedBy: 'teacher-1',
            effectiveDate: AcademicDate(year: 2026, month: 11, day: 10),
          ),
        ]);

      await tester.pumpWidget(
        _app(
          CourseStudentsScreen(
            course: _course(),
            repository: repository,
            status: 'withdrawn',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retirados'), findsOneWidget);
      expect(
        find.text('No hay estudiantes retirados actualmente'),
        findsOneWidget,
      );
      expect(find.text('Estudiante reincorporado'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _app(CourseStudentsScreen(course: _course(), repository: repository)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Estudiante reincorporado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Estudiante reincorporado'), findsOneWidget);
      await tester.tap(find.text('Estudiante reincorporado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver historial de matrícula'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Ingreso confirmado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Ingreso confirmado'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Retiro confirmado'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Retiro confirmado'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Reincorporación confirmada'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Reincorporación confirmada'), findsOneWidget);
      expect(find.text('Fecha efectiva · 2026-11-05'), findsOneWidget);
    },
  );

  testWidgets('el historial del curso permite reintentar un error de lectura', (
    tester,
  ) async {
    final repository = _Repository()..failRosterSnapshot = true;
    repository.rosterSnapshot = CourseRosterSnapshot(
      activeEnrollments: [_enrollment(name: 'Fila tras reintento')],
      withdrawnEnrollments: const [],
      pendingEnrollments: const [],
      withdrawnPendingEnrollments: const [],
      complete: true,
    );
    await tester.pumpWidget(
      _app(
        CourseEnrollmentHistoryScreen(
          course: _course(),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar la información'), findsOneWidget);
    expect(find.text('Fila tras reintento'), findsNothing);

    repository.failRosterSnapshot = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Fila tras reintento'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Fila tras reintento'), findsOneWidget);
    expect(repository.rosterSnapshotReads, 2);
  });

  testWidgets(
    'el cambio de cuenta descarta la respuesta tardía del historial',
    (tester) async {
      final repository = _Repository();
      final pending = Completer<CourseRosterSnapshot>();
      repository.pendingRosterSnapshot = pending;
      await tester.pumpWidget(
        _app(
          CourseEnrollmentHistoryScreen(
            course: _course(),
            repository: repository,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Cargando historial del curso…'), findsOneWidget);

      repository.uid = 'teacher-2';
      pending.complete(
        CourseRosterSnapshot(
          activeEnrollments: [_enrollment(name: 'No mostrar tras el cambio')],
          withdrawnEnrollments: const [],
          pendingEnrollments: const [],
          withdrawnPendingEnrollments: const [],
          complete: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('La sesión cambió. Vuelve a entrar.'), findsOneWidget);
      expect(find.text('No mostrar tras el cambio'), findsNothing);
    },
  );

  testWidgets('el historial individual oculta resultados si cambia la cuenta', (
    tester,
  ) async {
    final repository = _Repository();
    final pending = Completer<EnrollmentHistoryPage>();
    repository.pendingHistoryPage = pending;
    await tester.pumpWidget(
      _app(
        EnrollmentHistoryScreen(
          course: _course(),
          enrollment: _enrollment(
            createdAt: DateTime.utc(2026, 11, 5, 14),
            effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 5),
          ),
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    repository.uid = 'teacher-2';
    pending.complete(
      EnrollmentHistoryPage(
        items: [
          EnrollmentStatusEvent(
            operationId: 'private-change',
            fromStatus: 'active',
            toStatus: 'withdrawn',
            changedAt: DateTime.utc(2026, 11, 8),
            changedBy: 'teacher-1',
            effectiveDate: AcademicDate(year: 2026, month: 11, day: 8),
          ),
        ],
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('La sesión cambió'), findsOneWidget);
    expect(find.text('Retiro confirmado'), findsNothing);
    expect(find.text('Ingreso confirmado'), findsNothing);
  });
}
