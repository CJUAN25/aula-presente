import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/attendance/domain/attendance_failure.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/attendance/domain/attendance_occurrence.dart';
import 'package:aula_presente/features/attendance/domain/attendance_repository.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session_event.dart';
import 'package:aula_presente/features/attendance/presentation/attendance_session_screen.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('finalization requires explicit confirmation for unmarked rows', (
    tester,
  ) async {
    final repository = _AttendanceRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: TeacherAttendanceSessionScreen(
          course: _course(),
          session: repository.session,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Finalizar registro'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Finalizar registro'));
    await tester.pumpAndSettle();

    expect(find.text('Quedan decisiones pendientes'), findsOneWidget);
    expect(find.textContaining('1 estudiante sin marcar'), findsOneWidget);
    expect(repository.finalizeCalls, [false]);

    await tester.tap(find.text('Volver a completar'));
    await tester.pumpAndSettle();
    expect(repository.finalizeCalls, [false]);
    expect(
      find.text('El registro sigue abierto. No se marcó a nadie como ausente.'),
      findsOneWidget,
    );
  });

  testWidgets('only the confirmed pending rows are submitted as absences', (
    tester,
  ) async {
    final repository = _AttendanceRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: TeacherAttendanceSessionScreen(
          course: _course(),
          session: repository.session,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Finalizar registro'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Finalizar registro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar ausencias'));
    await tester.pumpAndSettle();

    expect(repository.finalizeCalls, [false, true, false]);
    expect(repository.session.status, AttendanceSessionStatus.finalized);
    expect(
      find.text('Asistencia finalizada y publicada para sus estudiantes.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a finalized session exposes a retry when publication is pending',
    (tester) async {
      final repository = _AttendanceRepository()
        ..session = _session(status: AttendanceSessionStatus.finalized)
        ..publicationChecksUntilSuccess = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TeacherAttendanceSessionScreen(
            course: _course(),
            session: repository.session,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.finalizeCalls, [false]);
      expect(find.text('Publicación pendiente'), findsOneWidget);
      expect(find.text('Reintentar publicación'), findsOneWidget);

      await tester.tap(find.text('Reintentar publicación'));
      await tester.pumpAndSettle();

      expect(find.text('Publicación pendiente'), findsNothing);
      expect(find.text('Registro finalizado'), findsOneWidget);
      expect(repository.finalizeCalls, [false, false, false]);
    },
  );

  testWidgets(
    'publication permission denial stays visible and is not success',
    (tester) async {
      final repository = _AttendanceRepository()
        ..session = _session(status: AttendanceSessionStatus.finalized)
        ..publicationChecksUntilSuccess = 1
        ..publicationFailureKind = AttendanceFailureKind.permissionDenied;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TeacherAttendanceSessionScreen(
            course: _course(),
            session: repository.session,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Publicación pendiente'), findsOneWidget);
      expect(
        find.textContaining('Firestore rechazó la publicación por permisos.'),
        findsOneWidget,
      );
      expect(
        find.text('Asistencia finalizada y publicada para sus estudiantes.'),
        findsNothing,
      );
    },
  );

  testWidgets('an incomplete void is reported as in progress, not as success', (
    tester,
  ) async {
    final repository = _AttendanceRepository();
    repository.voidResult = AttendanceSessionStatus.voiding;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: TeacherAttendanceSessionScreen(
          course: _course(),
          session: repository.session,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Anular sesión'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Clase registrada por error',
    );
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(repository.voidCalls, 1);
    expect(find.text('Anulación en curso'), findsOneWidget);
    expect(find.text('La sesión quedó anulada con motivo.'), findsNothing);
    expect(find.textContaining('La anulación sigue en curso.'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('teacher session fits ${width.toInt()} px with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _AttendanceRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              devicePixelRatio: 2,
              textScaler: const TextScaler.linear(1.6),
            ),
            child: TeacherAttendanceSessionScreen(
              course: _course(),
              session: repository.session,
              repository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Finalizar registro'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Guardar y continuar después'), findsOneWidget);
    });
  }
}

Course _course() => Course(
  id: 'course_1234567890123456',
  ownerUid: 'teacher_uid',
  subject: 'Matemáticas',
  group: '01',
  period: '2026-2',
  program: 'Ingeniería',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 1),
    endDate: AcademicDate(year: 2026, month: 11, day: 30),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'block_1234567890123456',
        weekday: 1,
        startTime: '08:00',
        endTime: '09:00',
      ),
    ],
  ),
);

AttendanceSession _session({
  AttendanceSessionStatus status = AttendanceSessionStatus.inProgress,
  String? reason,
}) => AttendanceSession(
  courseId: 'course_1234567890123456',
  ownerUid: 'teacher_uid',
  occurrenceId: 'course|block|2026-11-02',
  occurrenceKind: AttendanceOccurrenceKind.planned,
  mode: AttendanceMode.meeting,
  status: status,
  rosterState: AttendanceRosterState.ready,
  scheduledDate: AcademicDate(year: 2026, month: 11, day: 2),
  effectiveDate: AcademicDate(year: 2026, month: 11, day: 2),
  startMinute: 480,
  endMinute: 540,
  timezone: 'America/Bogota',
  segmentIds: const [],
  rosterCount: 1,
  markedCount: status == AttendanceSessionStatus.finalized ? 1 : 0,
  unmarkedCount: status == AttendanceSessionStatus.finalized ? 0 : 1,
  unmarkedConfirmed: status == AttendanceSessionStatus.finalized,
  version: status == AttendanceSessionStatus.finalized ? 4 : 3,
  lastMutationRosterEntryId: null,
  lastMutationKind: null,
  lastEventId: null,
  reason: reason,
  createdAt: null,
  createdBy: 'teacher_uid',
  updatedAt: null,
  updatedBy: 'teacher_uid',
);

class _AttendanceRepository implements AttendanceRepository {
  AttendanceSession session = _session();
  AttendanceSessionStatus voidResult = AttendanceSessionStatus.voided;
  final List<bool> finalizeCalls = [];
  int publicationChecksUntilSuccess = 0;
  AttendanceFailureKind publicationFailureKind =
      AttendanceFailureKind.unavailable;
  int voidCalls = 0;

  @override
  Future<AttendanceSession?> getSession({
    required String courseId,
    required String occurrenceId,
  }) async => session;

  @override
  Future<AttendanceRosterPage> listRoster({
    required AttendanceSession session,
    AttendanceRosterCursor? cursor,
    int pageSize = 25,
  }) async => AttendanceRosterPage(
    items: [
      AttendanceRosterEntry(
        rosterEntryId: 'student_identity',
        displayName: 'Estudiante de prueba',
        studentUid: 'student_uid',
        meetingMark: AttendanceRosterMark.unmarked(),
        segmentMarks: const {},
        version: 0,
      ),
    ],
    nextCursor: null,
  );

  @override
  Future<AttendanceSegmentPage> listSegments({
    required AttendanceSession session,
    AttendanceSegmentCursor? cursor,
    int pageSize = 25,
  }) async => AttendanceSegmentPage(items: const [], nextCursor: null);

  @override
  Future<AttendanceSessionEventPage> listSessionEvents({
    required AttendanceSession session,
    AttendanceSessionEventCursor? cursor,
    int pageSize = 25,
  }) async => AttendanceSessionEventPage(items: const [], nextCursor: null);

  @override
  Future<AttendanceFinalizeResult> finalizeSession({
    required String courseId,
    required String occurrenceId,
    required bool confirmUnmarked,
  }) async {
    finalizeCalls.add(confirmUnmarked);
    if (session.status == AttendanceSessionStatus.finalized) {
      if (publicationChecksUntilSuccess > 0) {
        publicationChecksUntilSuccess--;
        return AttendanceFinalizeResult(
          status: AttendanceFinalizeStatus.reviewRequired,
          unmarkedCount: 0,
          writeConfirmed: true,
          publicationPending: true,
          failureKind: publicationFailureKind,
        );
      }
      return AttendanceFinalizeResult(
        status: AttendanceFinalizeStatus.confirmed,
        unmarkedCount: 0,
        session: session,
        writeConfirmed: true,
      );
    }
    if (!confirmUnmarked) {
      return const AttendanceFinalizeResult(
        status: AttendanceFinalizeStatus.reviewRequired,
        unmarkedCount: 1,
      );
    }
    session = _session(status: AttendanceSessionStatus.finalized);
    return AttendanceFinalizeResult(
      status: AttendanceFinalizeStatus.confirmed,
      unmarkedCount: 0,
      session: session,
    );
  }

  @override
  Future<AttendanceSession> voidSession({
    required String courseId,
    required String occurrenceId,
    required String operationId,
    required String reason,
  }) async {
    voidCalls += 1;
    session = _session(status: voidResult, reason: reason);
    return session;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
