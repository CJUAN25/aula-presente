import 'dart:async';

import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/attendance/application/attendance_validator.dart';
import 'package:aula_presente/features/attendance/data/attendance_firestore_codec.dart';
import 'package:aula_presente/features/attendance/domain/attendance_calendar_change.dart';
import 'package:aula_presente/features/attendance/domain/attendance_config.dart';
import 'package:aula_presente/features/attendance/domain/attendance_failure.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/attendance/domain/attendance_occurrence.dart';
import 'package:aula_presente/features/attendance/domain/attendance_repository.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session_event.dart';
import 'package:aula_presente/features/attendance/presentation/teacher_attendance_screens.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/planned_meeting_generator.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'slow completion shows progress then preserves the failure on screen',
    (tester) async {
      final gate = Completer<void>();
      final repo = _Repository()..preparationGate = gate;
      await _pump(tester, repo);
      await tester.ensureVisible(find.text('Completar lista').first);
      await tester.tap(find.text('Completar lista').first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(
        find.textContaining('Está tardando más de lo habitual'),
        findsOneWidget,
      );
      gate.completeError(
        const AttendanceFailure(
          AttendanceFailureKind.permissionDenied,
          message:
              'No se pudo leer matrículas e historial (permission-denied).',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Está tardando más de lo habitual'),
        findsNothing,
      );
      expect(
        find.text(
          'No se pudo leer matrículas e historial (permission-denied).',
        ),
        findsOneWidget,
      );
      expect(repo.startedIds, isEmpty);
      expect(find.text('Completar lista'), findsNWidgets(3));
    },
  );

  test(
    'late reason uses effective time and preserves an on-time preparation',
    () {
      final occurrence = _occurrence('reprogramada', 15, 600);
      final now = DateTime.utc(2026, 11, 16, 18);
      expect(
        AttendanceValidator.needsLateRegistrationReason(
          occurrence,
          nowUtc: now,
        ),
        isTrue,
      );
      expect(
        AttendanceValidator.needsLateRegistrationReason(
          occurrence,
          nowUtc: now,
          preparedAt: DateTime.utc(2026, 11, 14),
        ),
        isFalse,
      );
      expect(
        AttendanceValidator.needsLateRegistrationReason(
          occurrence,
          nowUtc: now,
          preparedAt: DateTime.utc(2026, 11, 15, 16),
        ),
        isTrue,
      );
      expect(
        AttendanceValidator.needsLateRegistrationReason(
          occurrence,
          nowUtc: now,
          storedReason: 'Motivo conservado',
        ),
        isFalse,
      );
      expect(
        AttendanceValidator.needsLateRegistrationReason(
          occurrence,
          nowUtc: DateTime.utc(2026, 11, 15, 14, 59),
        ),
        isFalse,
      );
      expect(
        AttendanceValidator.needsLateRegistrationReason(
          occurrence,
          nowUtc: DateTime.utc(2026, 11, 15, 15),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'incomplete normal and rescheduled cards offer completing the list, not prepared',
    (tester) async {
      final repo = _Repository();
      await _pump(tester, repo);
      expect(find.text('Lista incompleta'), findsNWidgets(3));
      expect(find.text('Completar lista'), findsNWidgets(3));
      expect(find.text('Preparada'), findsNothing);
      expect(find.text('Reintentar preparación'), findsNothing);
      expect(find.text('15/11/2026'), findsOneWidget);
      expect(find.text('16/11/2026'), findsNWidgets(2));
    },
  );

  testWidgets(
    'resuming an on-time partial session opens marking with same ID without another reason',
    (tester) async {
      final repo = _Repository();
      await _pump(tester, repo);
      final button = find.text('Completar lista').first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repo.preparedIds, ['from-12']);
      expect(repo.startedIds, ['from-12']);
      expect(repo.reasons, [null]);
      expect(find.text('Registrar asistencia'), findsOneWidget);
      expect(repo.sessions.length, 3);
    },
  );

  testWidgets(
    'late incomplete preparation asks for missing reason before retry',
    (tester) async {
      final repo = _Repository(late: true);
      await _pump(tester, repo);
      await tester.ensureVisible(find.text('Completar lista').first);
      await tester.tap(find.text('Completar lista').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Registro posterior a la clase'), findsOneWidget);
      expect(repo.preparedIds, isEmpty);
      await tester.enterText(
        find.byType(TextField),
        'Registro de la clase realizada',
      );
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Completar lista'),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.reasons, ['Registro de la clase realizada']);
      expect(repo.preparedIds, ['from-12']);
    },
  );

  for (final state in [
    (AttendanceSessionStatus.inProgress, 'En curso', 'Continuar asistencia'),
    (AttendanceSessionStatus.closing, 'Finalizando', 'Continuar cierre'),
    (AttendanceSessionStatus.finalized, 'Finalizada', 'Ver asistencia'),
    (
      AttendanceSessionStatus.voiding,
      'Anulación en curso',
      'Completar anulación',
    ),
    (AttendanceSessionStatus.voided, 'Anulada', 'Ver asistencia anulada'),
  ]) {
    testWidgets('primary action follows persisted state: ${state.$1.name}', (
      tester,
    ) async {
      final repo = _Repository();
      repo.sessions = {
        'from-12': _session(repo.occurrences.first, status: state.$1),
      };
      await _pump(tester, repo);
      expect(find.text(state.$2), findsOneWidget);
      expect(find.text(state.$3), findsOneWidget);
      expect(find.text('Completar lista'), findsNothing);
      if (state.$1 == AttendanceSessionStatus.inProgress) {
        await tester.ensureVisible(find.text('Opciones').first);
        await tester.tap(find.text('Opciones').first);
        await tester.pumpAndSettle();
        expect(find.text('Anular asistencia'), findsOneWidget);
      }
    });
  }
}

AcademicDate _date(int day) => AcademicDate(year: 2026, month: 11, day: day);
Course _course() => Course(
  id: 'course',
  ownerUid: 'owner',
  subject: 'Curso sintético',
  group: '01',
  period: '2026',
  program: 'Programa',
  schedule: CourseSchedule(
    startDate: _date(16),
    endDate: _date(16),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'normal',
        weekday: 1,
        startTime: '10:00',
        endTime: '12:00',
      ),
    ],
  ),
);
AttendanceOccurrence _occurrence(String id, int day, int start) =>
    AttendanceOccurrence(
      id: id,
      courseId: 'course',
      kind: AttendanceOccurrenceKind.rescheduled,
      scheduledDate: _date(id == 'from-05' ? 5 : 12),
      effectiveDate: _date(day),
      startMinute: start,
      endMinute: start + 120,
    );
AttendanceSession _session(
  AttendanceOccurrence occurrence, {
  AttendanceSessionStatus status = AttendanceSessionStatus.preparing,
  AttendanceRosterState roster = AttendanceRosterState.building,
  bool late = false,
}) => AttendanceFirestoreCodec.sessionFromMap(
  {
    ...AttendanceFirestoreCodec.newSession(
      occurrence: occurrence,
      mode: AttendanceMode.minutes,
      uid: 'owner',
      segmentIds: ['seg-1', 'seg-2'],
      rosterCount: 0,
    ),
    'status': status.value,
    'rosterState': roster.value,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, late ? 16 : 14, 18)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 16, 18)),
    if (status == AttendanceSessionStatus.finalized)
      'finalizedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 16)),
    if (status == AttendanceSessionStatus.voiding ||
        status == AttendanceSessionStatus.voided) ...{
      'lastEventId': 'existing-void',
      'lastMutationKind': 'void',
      'reason': 'Motivo conservado',
    },
    if (status == AttendanceSessionStatus.voided)
      'voidedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 16)),
  },
  expectedCourseId: 'course',
  expectedOccurrenceId: occurrence.id,
);
Future<void> _pump(WidgetTester tester, _Repository repo) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: TeacherAttendanceScreen(course: _course(), repository: repo),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repository implements AttendanceRepository {
  _Repository({bool late = false}) {
    occurrences = [
      _occurrence('from-12', 15, 600),
      _occurrence('from-05', 16, 360),
      AttendanceOccurrence.fromPlannedMeeting(
        generatePlannedMeetings(
          courseId: 'course',
          schedule: _course().schedule,
        ).single,
      ),
    ];
    sessions = {for (final o in occurrences) o.id: _session(o, late: late)};
  }
  late List<AttendanceOccurrence> occurrences;
  late Map<String, AttendanceSession> sessions;
  final preparedIds = <String>[];
  final startedIds = <String>[];
  final reasons = <String?>[];
  Completer<void>? preparationGate;
  @override
  Future<AttendanceConfig?> getConfig({required String courseId}) async =>
      const AttendanceConfig(
        mode: AttendanceMode.minutes,
        sessionCount: 3,
        lastSessionId: 'from-12',
      );
  @override
  Future<List<AttendanceCalendarChange>> listCalendarChanges({
    required String courseId,
    bool forStudent = false,
  }) async => [
    for (final o in occurrences.where(
      (o) => o.kind == AttendanceOccurrenceKind.rescheduled,
    ))
      AttendanceCalendarChange(
        occurrenceId: o.id,
        kind: AttendanceCalendarChangeKind.rescheduled,
        originalDate: o.scheduledDate,
        effectiveDate: o.effectiveDate,
        startMinute: o.startMinute,
        endMinute: o.endMinute,
        reason: 'Cambio',
        version: 1,
      ),
  ];
  @override
  Future<List<AttendanceSession>> listSessions({
    required String courseId,
    required AcademicDate from,
    required AcademicDate to,
  }) async => sessions.values.toList();
  @override
  Future<AttendanceSession> prepareSession({
    required Course course,
    required AttendanceOccurrence occurrence,
    String? lateRegistrationReason,
  }) async {
    if (preparationGate != null) await preparationGate!.future;
    preparedIds.add(occurrence.id);
    reasons.add(lateRegistrationReason);
    return sessions[occurrence.id] = _session(
      occurrence,
      roster: AttendanceRosterState.ready,
    );
  }

  @override
  Future<AttendanceSession> startSession({
    required String courseId,
    required String occurrenceId,
  }) async {
    startedIds.add(occurrenceId);
    return sessions[occurrenceId] = _session(
      occurrences.firstWhere((o) => o.id == occurrenceId),
      status: AttendanceSessionStatus.inProgress,
      roster: AttendanceRosterState.ready,
    );
  }

  @override
  Future<AttendanceSession?> getSession({
    required String courseId,
    required String occurrenceId,
  }) async => sessions[occurrenceId];
  @override
  Future<AttendanceRosterPage> listRoster({
    required AttendanceSession session,
    AttendanceRosterCursor? cursor,
    int pageSize = 25,
  }) async => AttendanceRosterPage(items: [], nextCursor: null);
  @override
  Future<AttendanceSegmentPage> listSegments({
    required AttendanceSession session,
    AttendanceSegmentCursor? cursor,
    int pageSize = 25,
  }) async => AttendanceSegmentPage(items: [], nextCursor: null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
