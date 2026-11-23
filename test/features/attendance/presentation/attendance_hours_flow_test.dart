import 'package:aula_presente/features/attendance/domain/attendance_record.dart';
import 'package:aula_presente/features/attendance/presentation/attendance_request_button.dart';
import 'package:aula_presente/features/attendance/domain/attendance_justification_request.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/attendance/data/attendance_firestore_codec.dart';
import 'package:aula_presente/features/attendance/domain/attendance_config.dart';
import 'package:aula_presente/features/attendance/domain/attendance_calendar_change.dart';
import 'package:aula_presente/features/attendance/domain/attendance_failure.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/attendance/domain/attendance_occurrence.dart';
import 'package:aula_presente/features/attendance/domain/attendance_repository.dart';
import 'package:aula_presente/features/attendance/domain/attendance_segment.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session_event.dart';
import 'package:aula_presente/features/attendance/presentation/attendance_session_screen.dart';
import 'package:aula_presente/features/attendance/presentation/teacher_attendance_screens.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('present to absent saves the selected hour from the dialog', (
    tester,
  ) async {
    final repo = _HoursRepository(status: AttendanceSessionStatus.finalized);
    await _pump(tester, repo);
    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, 'Corregir registro').hitTestable(),
      140,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Corregir registro').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<AttendanceMark>),
        matching: find.text('Ausente'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(repo.rows.first.segmentMarks['seg-1']!.absentUnits, 60);
  });

  testWidgets(
    'list is available while publication and history are still delayed',
    (tester) async {
      final repo = _HoursRepository(status: AttendanceSessionStatus.finalized)
        ..publicationGate = Completer<void>()
        ..historyGate = Completer<void>();
      await _pump(tester, repo, settle: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Estudiante Alfa'), findsOneWidget);
      expect(find.text('Comprobando publicaci\u00f3n'), findsOneWidget);
      expect(repo.publicationGate!.isCompleted, isFalse);
      expect(repo.historyGate!.isCompleted, isFalse);
      repo.publicationGate!.complete();
      repo.historyGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Registro finalizado'), findsOneWidget);
    },
  );

  testWidgets('second hour changes absent to present with an empty reason', (
    tester,
  ) async {
    final repo = _HoursRepository(status: AttendanceSessionStatus.finalized);
    await _pump(tester, repo);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('07:00–08:00 · 60 min').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Corregir registro').first);
    await tester.tap(find.text('Corregir registro').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<AttendanceMark>),
        matching: find.text('Presente'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(repo.correctionReason, '');
    expect(repo.rows.first.segmentMarks['seg-1']!.mark, AttendanceMark.present);
    expect(repo.rows.first.segmentMarks['seg-2']!.mark, AttendanceMark.present);
  });

  testWidgets('void confirmation cancels and an empty reason permits restore', (
    tester,
  ) async {
    final repo = _HoursRepository(status: AttendanceSessionStatus.finalized);
    await _pump(tester, repo);
    await tester.tap(find.byTooltip('Anular sesi\u00f3n'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.voidCalls, 0);
    await tester.tap(find.byTooltip('Anular sesi\u00f3n'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(repo.voidCalls, 1);
    await tester.ensureVisible(find.text('Restaurar asistencia'));
    await tester.tap(find.text('Restaurar asistencia'));
    await tester.pumpAndSettle();
    expect(repo.restoreCalls, 1);
    expect(find.text('Registro finalizado'), findsOneWidget);
  });

  testWidgets(
    'student submits once and pending text explains the counted absence',
    (tester) async {
      final repo = _HoursRepository();
      final record = AttendanceRecord(
        courseId: 'course',
        sessionId: 'session',
        rosterEntryId: 'alfa@example.invalid',
        visibility: AttendanceRecordVisibility.published,
        mode: AttendanceMode.meeting,
        scheduledDate: _date(16),
        effectiveDate: _date(16),
        startMinute: 360,
        endMinute: 480,
        unitCount: 1,
        absentUnits: 1,
        inReviewUnits: 0,
        justifiedUnits: 0,
        result: AttendanceSessionResult.absent,
        segments: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AttendanceRequestButton(
              record: record,
              segmentId: null,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solicitar justificaci\u00f3n'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ausencia sint\u00e9tica');
      await tester.tap(find.text('Enviar solicitud'));
      await tester.pumpAndSettle();
      expect(repo.submissions, 1);
      expect(find.textContaining('La falta sigue contando'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    },
  );
  for (final decision in [
    AttendanceRequestStatus.approved,
    AttendanceRequestStatus.rejected,
  ]) {
    testWidgets('student sees $decision and cannot resubmit', (tester) async {
      final repo = _HoursRepository()
        ..requests = [
          AttendanceJustificationRequest(
            id: 'request',
            sessionId: 'session',
            rosterEntryId: 'alfa@example.invalid',
            studentUid: 'alfa',
            segmentId: null,
            text: 'Solicitud',
            status: decision,
          ),
        ];
      final record = AttendanceRecord(
        courseId: 'course',
        sessionId: 'session',
        rosterEntryId: 'alfa@example.invalid',
        visibility: AttendanceRecordVisibility.published,
        mode: AttendanceMode.meeting,
        scheduledDate: _date(16),
        effectiveDate: _date(16),
        startMinute: 360,
        endMinute: 480,
        unitCount: 1,
        absentUnits: 1,
        inReviewUnits: 0,
        justifiedUnits: decision == AttendanceRequestStatus.approved ? 1 : 0,
        result: AttendanceSessionResult.absent,
        segments: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AttendanceRequestButton(
              record: record,
              segmentId: null,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Si tienes dudas, comun\u00edcate con tu docente'),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });
  }
  for (final approve in [true, false]) {
    testWidgets('teacher can read request text and decide $approve', (
      tester,
    ) async {
      final repo = _HoursRepository(status: AttendanceSessionStatus.finalized)
        ..requests = [
          const AttendanceJustificationRequest(
            id: 'request',
            sessionId: 'session',
            rosterEntryId: 'alfa@example.invalid',
            studentUid: 'alfa',
            segmentId: 'seg-2',
            text: 'Texto del estudiante',
            status: AttendanceRequestStatus.pending,
          ),
        ];
      await _pump(tester, repo);
      await tester.scrollUntilVisible(
        find.text('Texto del estudiante'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.text(approve ? 'Aprobar' : 'Rechazar'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(approve ? 'Aprobar' : 'Rechazar'));
      await tester.pumpAndSettle();
      expect(
        repo.requests.single.status,
        approve
            ? AttendanceRequestStatus.approved
            : AttendanceRequestStatus.rejected,
      );
    });
  }

  testWidgets('teacher calendar opens the same hours session', (tester) async {
    final repo = _HoursRepository(status: AttendanceSessionStatus.closing);
    await _pump(tester, repo, calendar: true);
    await _capture(tester, 'calendar');
    await tester.scrollUntilVisible(
      find.text('Continuar cierre'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar cierre'));
    await tester.pumpAndSettle();
    expect(find.text('Cierre en curso'), findsOneWidget);
    expect(repo.session.occurrenceId, 'course|block|2026-11-05');
  });

  testWidgets('visual capture of the real hours screen', (tester) async {
    await _pump(tester, _HoursRepository());
    await _capture(tester, 'hours');
    await tester.scrollUntilVisible(
      find.text('Finalizar registro'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await _capture(tester, 'hours-actions');
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed hours keep both segments available for review', (
    tester,
  ) async {
    final repo = _HoursRepository(status: AttendanceSessionStatus.finalized);
    await _pump(tester, repo);
    expect(find.text('Tramo de la clase'), findsOneWidget);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('07:00–08:00 · 60 min').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Estudiante Alfa'));
    expect(find.text('Ausente · 60 min · 07:00–08:00'), findsOneWidget);
    await _capture(tester, 'closed-second-hour');
    await tester.ensureVisible(find.text('Corregir registro').first);
    await tester.tap(find.text('Corregir registro').first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    expect(find.textContaining('07:00–08:00').last, findsOneWidget);
    await _capture(tester, 'correction');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(repo.correctionReason, isNull);
    expect(find.text('No hay cambios que guardar.'), findsOneWidget);
    expect(repo.rows.first.segmentMarks['seg-2']!.absentUnits, 60);
  });

  testWidgets('search filters locally and mark targets the selected hour', (
    tester,
  ) async {
    final repo = _HoursRepository();
    await _pump(tester, repo);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('07:00–08:00 · 60 min').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'alfa');
    await tester.pumpAndSettle();
    expect(find.text('Estudiante Beta'), findsNothing);
    await tester.ensureVisible(find.text('Presente').last);
    await tester.tap(find.text('Presente').last);
    await tester.pumpAndSettle();
    expect(repo.markCalls, ['alfa|seg-2|present']);
    expect(repo.rows.first.segmentMarks['seg-1']!.mark, AttendanceMark.present);
    expect(repo.rows.first.segmentMarks['seg-2']!.mark, AttendanceMark.present);
    await tester.enterText(find.byType(TextField), 'no existe');
    await tester.pumpAndSettle();
    expect(find.text('Sin coincidencias'), findsOneWidget);
    expect(repo.rosterReads, 1);
  });

  testWidgets('slow load and failure disable writes until retry succeeds', (
    tester,
  ) async {
    final repo = _HoursRepository()..gate = Completer<void>();
    await _pump(tester, repo, settle: false);
    await tester.pump(const Duration(seconds: 9));
    await _capture(tester, 'loading');
    expect(
      find.textContaining('Está tardando más de lo habitual'),
      findsOneWidget,
    );
    expect(find.text('Finalizar registro'), findsNothing);
    repo.gate!.completeError(
      const AttendanceFailure(AttendanceFailureKind.permissionDenied),
    );
    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar la asistencia'), findsOneWidget);
    await _capture(tester, 'error');
    expect(find.text('Finalizar registro'), findsNothing);
    repo.gate = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar la asistencia'), findsNothing);
    expect(repo.markCalls, isEmpty);
  });

  testWidgets(
    'closing resumes the same session and exposes pending publication',
    (tester) async {
      final repo = _HoursRepository(status: AttendanceSessionStatus.closing);
      await _pump(tester, repo);
      await _capture(tester, 'closing');
      await tester.ensureVisible(find.text('Continuar finalización'));
      await tester.tap(find.text('Continuar finalización'));
      await tester.pumpAndSettle();
      expect(repo.finalizeCalls, 1);
      expect(find.text('Publicación pendiente'), findsOneWidget);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await _capture(tester, 'publication-pending');
      await tester.ensureVisible(find.text('Reintentar publicación'));
      await tester.tap(find.text('Reintentar publicación'));
      await tester.pumpAndSettle();
      expect(find.text('Registro finalizado'), findsOneWidget);
      expect(
        find.textContaining(
          'La conexión no permitió confirmar todas las filas.',
        ),
        findsNothing,
      );
      expect(repo.session.occurrenceId, 'course|block|2026-11-05');
      expect(
        repo.rows.first.segmentMarks['seg-2']!.mark,
        AttendanceMark.absent,
      );
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await _capture(tester, 'finalized');
    },
  );

  testWidgets('failed mark remains visible after reload and preserves search', (
    tester,
  ) async {
    final repo = _HoursRepository()..failMark = true;
    await _pump(tester, repo);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'alfa');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ausente').last);
    await tester.tap(find.text('Ausente').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('No pudimos cargar la asistencia'), findsOneWidget);
    await tester.ensureVisible(find.text('Reintentar'));
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'alfa',
    );
    expect(find.text('Estudiante Beta'), findsNothing);
    expect(repo.rows.first.segmentMarks['seg-1']!.mark, AttendanceMark.present);
  });

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('hours fits $width with enlarged text', (tester) async {
      await _pump(tester, _HoursRepository(), width: width, textScale: 1.6);
      await tester.scrollUntilVisible(
        find.text('Finalizar registro'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _HoursRepository repo, {
  bool settle = true,
  double width = 390,
  double textScale = 1,
  bool calendar = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final font = FontLoader('Manrope')
    ..addFont(rootBundle.load('assets/fonts/Manrope/Manrope-Variable.ttf'));
  await font.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('visual-root'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(textScale),
          ),
          child: calendar
              ? TeacherAttendanceScreen(course: _course(), repository: repo)
              : TeacherAttendanceSessionScreen(
                  course: _course(),
                  session: repo.session,
                  repository: repo,
                ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final prefix = Platform.environment['C8_VISUAL_CAPTURE'];
  if (prefix == null) return;
  await tester.pump(const Duration(milliseconds: 100));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('visual-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/c8-visual/$prefix-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

AcademicDate _date(int day) => AcademicDate(year: 2026, month: 11, day: day);
Course _course() => Course(
  id: 'course',
  ownerUid: 'owner',
  subject: 'Curso sintético',
  group: '02',
  period: '2026-2',
  program: 'Programa',
  schedule: CourseSchedule(
    startDate: _date(1),
    endDate: _date(30),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'block',
        weekday: 1,
        startTime: '06:00',
        endTime: '08:00',
      ),
    ],
  ),
);

class _HoursRepository implements AttendanceRepository {
  _HoursRepository({
    AttendanceSessionStatus status = AttendanceSessionStatus.inProgress,
  }) {
    session = _session(status);
    if (status != AttendanceSessionStatus.inProgress) {
      final old = rows[1];
      rows[1] = AttendanceRosterEntry(
        rosterEntryId: old.rosterEntryId,
        displayName: old.displayName,
        studentUid: old.studentUid,
        meetingMark: null,
        segmentMarks: {
          ...old.segmentMarks,
          'seg-1': _mark(AttendanceMark.absent),
        },
        version: 2,
      );
    }
  }
  late AttendanceSession session;
  Completer<void>? gate;
  final markCalls = <String>[];
  int rosterReads = 0;
  int finalizeCalls = 0;
  int voidCalls = 0, restoreCalls = 0, submissions = 0;
  Completer<void>? publicationGate, historyGate;
  List<AttendanceJustificationRequest> requests = [];
  bool failMark = false;
  String? correctionReason;
  final segments = const [
    AttendanceSegment(
      id: 'seg-1',
      order: 0,
      startMinute: 360,
      endMinute: 420,
      durationMinutes: 60,
    ),
    AttendanceSegment(
      id: 'seg-2',
      order: 1,
      startMinute: 420,
      endMinute: 480,
      durationMinutes: 60,
    ),
  ];
  final rows = [
    AttendanceRosterEntry(
      rosterEntryId: 'alfa@example.invalid',
      displayName: 'Estudiante Alfa',
      studentUid: 'alfa',
      meetingMark: null,
      segmentMarks: {
        'seg-1': _mark(AttendanceMark.present),
        'seg-2': _mark(AttendanceMark.absent),
      },
      version: 1,
    ),
    AttendanceRosterEntry(
      rosterEntryId: 'beta@example.invalid',
      displayName: 'Estudiante Beta',
      studentUid: 'beta',
      meetingMark: null,
      segmentMarks: {
        'seg-1': _mark(AttendanceMark.unmarked),
        'seg-2': _mark(AttendanceMark.present),
      },
      version: 1,
    ),
  ];

  AttendanceSession _session(AttendanceSessionStatus status) =>
      AttendanceFirestoreCodec.sessionFromMap(
        {
          ...AttendanceFirestoreCodec.newSession(
            occurrence: AttendanceOccurrence(
              id: 'course|block|2026-11-05',
              courseId: 'course',
              kind: AttendanceOccurrenceKind.rescheduled,
              scheduledDate: _date(5),
              effectiveDate: _date(16),
              startMinute: 360,
              endMinute: 480,
            ),
            mode: AttendanceMode.minutes,
            uid: 'owner',
            segmentIds: ['seg-1', 'seg-2'],
            rosterCount: 2,
          ),
          'status': status.value,
          if (status == AttendanceSessionStatus.voided) ...{
            'voidedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 17)),
            'reason': '',
            'lastMutationKind': 'void',
            'lastEventId': 'void-test',
          },
          'rosterState': 'ready',
          'markedCount': status == AttendanceSessionStatus.inProgress ? 1 : 2,
          'unmarkedCount': status == AttendanceSessionStatus.inProgress ? 1 : 0,
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 4)),
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 16)),
          if (status != AttendanceSessionStatus.inProgress &&
              status != AttendanceSessionStatus.closing)
            'finalizedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 16)),
        },
        expectedCourseId: 'course',
        expectedOccurrenceId: 'course|block|2026-11-05',
      );

  @override
  Future<AttendanceConfig?> getConfig({required String courseId}) async =>
      const AttendanceConfig(
        mode: AttendanceMode.minutes,
        sessionCount: 1,
        lastSessionId: 'course|block|2026-11-05',
      );
  @override
  Future<List<AttendanceSession>> listSessions({
    required String courseId,
    required AcademicDate from,
    required AcademicDate to,
  }) async => [session];
  @override
  Future<List<AttendanceCalendarChange>> listCalendarChanges({
    required String courseId,
    bool forStudent = false,
  }) async => [
    AttendanceCalendarChange(
      occurrenceId: session.occurrenceId,
      kind: AttendanceCalendarChangeKind.rescheduled,
      originalDate: _date(5),
      effectiveDate: _date(16),
      startMinute: 360,
      endMinute: 480,
      reason: 'Ensayo sintético',
      version: 1,
    ),
  ];
  @override
  Future<AttendanceSession?> getSession({
    required String courseId,
    required String occurrenceId,
  }) async {
    await gate?.future;
    return session;
  }

  @override
  Future<AttendanceRosterPage> listRoster({
    required AttendanceSession session,
    AttendanceRosterCursor? cursor,
    int pageSize = 25,
  }) async {
    rosterReads++;
    return AttendanceRosterPage(items: rows, nextCursor: null);
  }

  @override
  Future<AttendanceSegmentPage> listSegments({
    required AttendanceSession session,
    AttendanceSegmentCursor? cursor,
    int pageSize = 25,
  }) async => AttendanceSegmentPage(items: segments, nextCursor: null);
  @override
  Future<AttendanceSessionEventPage> listSessionEvents({
    required AttendanceSession session,
    AttendanceSessionEventCursor? cursor,
    int pageSize = 25,
  }) async {
    await historyGate?.future;
    return AttendanceSessionEventPage(items: [], nextCursor: null);
  }

  @override
  Future<AttendanceRosterMutationResult> setSegmentMark({
    required String courseId,
    required String occurrenceId,
    required String rosterEntryId,
    required String segmentId,
    required AttendanceMark mark,
    int? absentUnits,
  }) async {
    if (failMark) {
      throw const AttendanceFailure(AttendanceFailureKind.permissionDenied);
    }
    final index = rows.indexWhere((r) => r.rosterEntryId == rosterEntryId);
    final old = rows[index];
    markCalls.add('${old.studentUid}|$segmentId|${mark.value}');
    rows[index] = AttendanceRosterEntry(
      rosterEntryId: old.rosterEntryId,
      displayName: old.displayName,
      studentUid: old.studentUid,
      meetingMark: null,
      segmentMarks: {...old.segmentMarks, segmentId: _mark(mark)},
      version: old.version + 1,
    );
    return AttendanceRosterMutationResult(
      session: session,
      entry: rows[index],
      alreadyApplied: false,
    );
  }

  @override
  Future<AttendanceRosterMutationResult> correctRosterEntry({
    required String courseId,
    required String occurrenceId,
    required String operationId,
    required AttendanceRosterEntry replacement,
    required String reason,
  }) async {
    correctionReason = reason;
    final index = rows.indexWhere(
      (r) => r.rosterEntryId == replacement.rosterEntryId,
    );
    rows[index] = replacement;
    return AttendanceRosterMutationResult(
      session: session,
      entry: replacement,
      alreadyApplied: false,
    );
  }

  @override
  Future<AttendanceFinalizeResult> finalizeSession({
    required String courseId,
    required String occurrenceId,
    required bool confirmUnmarked,
  }) async {
    await publicationGate?.future;
    finalizeCalls++;
    final closing = session.status == AttendanceSessionStatus.closing;
    session = _session(AttendanceSessionStatus.finalized);
    return AttendanceFinalizeResult(
      status: closing
          ? AttendanceFinalizeStatus.reviewRequired
          : AttendanceFinalizeStatus.confirmed,
      session: session,
      unmarkedCount: 0,
      writeConfirmed: true,
      publicationPending: closing,
      failureKind: closing ? AttendanceFailureKind.unavailable : null,
    );
  }

  @override
  Future<AttendanceSession> voidSession({
    required String courseId,
    required String occurrenceId,
    required String operationId,
    required String reason,
  }) async {
    voidCalls++;
    return session = _session(AttendanceSessionStatus.voided);
  }

  @override
  Future<AttendanceSession> restoreSession({
    required String courseId,
    required String occurrenceId,
  }) async {
    restoreCalls++;
    return session = _session(AttendanceSessionStatus.finalized);
  }

  @override
  Future<List<AttendanceJustificationRequest>> listJustificationRequests({
    required String courseId,
    required String occurrenceId,
  }) async => requests;
  @override
  Future<AttendanceJustificationRequest?> getMyJustification({
    required AttendanceRecord record,
    required String? segmentId,
  }) async => requests.firstOrNull;
  @override
  Future<AttendanceJustificationRequest> submitJustification({
    required AttendanceRecord record,
    required String? segmentId,
    required String text,
  }) async {
    if (requests.isNotEmpty) return requests.first;
    submissions++;
    final request = AttendanceJustificationRequest(
      id: 'request',
      sessionId: record.sessionId,
      rosterEntryId: record.rosterEntryId,
      studentUid: 'alfa',
      segmentId: segmentId,
      text: text,
      status: AttendanceRequestStatus.pending,
    );
    requests = [request];
    return request;
  }

  @override
  Future<void> decideJustificationRequest({
    required String courseId,
    required AttendanceJustificationRequest request,
    required bool approve,
  }) async {
    requests = [
      AttendanceJustificationRequest(
        id: request.id,
        sessionId: request.sessionId,
        rosterEntryId: request.rosterEntryId,
        studentUid: request.studentUid,
        segmentId: request.segmentId,
        text: request.text,
        status: approve
            ? AttendanceRequestStatus.approved
            : AttendanceRequestStatus.rejected,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listJustificationRequests) {
      return Future<List<AttendanceJustificationRequest>>.value([]);
    }
    if (invocation.memberName == #getMyJustification) {
      return Future<AttendanceJustificationRequest?>.value(null);
    }
    return super.noSuchMethod(invocation);
  }
}

AttendanceRosterMark _mark(AttendanceMark mark) => AttendanceRosterMark(
  mark: mark,
  absentUnits: mark == AttendanceMark.absent ? 60 : 0,
  justificationStatus: AttendanceJustificationStatus.none,
  justifiedUnits: 0,
);
