import 'package:aula_presente/features/attendance/domain/attendance_justification_request.dart';
import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/attendance/domain/attendance_record.dart';
import 'package:aula_presente/features/attendance/domain/attendance_repository.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session.dart';
import 'package:aula_presente/features/attendance/presentation/student_attendance_screen.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows exact provisional summary and wraps at target widths', (
    tester,
  ) async {
    final repository = _AttendanceRepository(_fiveRecords());
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in [320.0, 390.0, 430.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              devicePixelRatio: 1,
              textScaler: const TextScaler.linear(1.3),
            ),
            child: StudentAttendanceScreen(
              course: _course(),
              repository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('20% de faltas computables'), findsOneWidget);
      expect(find.text('1 falta de 5 encuentros computables'), findsOneWidget);
      expect(
        find.textContaining('se incluyen provisionalmente en el numerador'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('shows an empty state when only voided records exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: StudentAttendanceScreen(
          course: _course(),
          repository: _AttendanceRepository([
            AttendanceRecord(
              courseId: 'course_1234567890123456',
              sessionId: 'session_voided',
              rosterEntryId: 'student_identity',
              visibility: AttendanceRecordVisibility.published,
              mode: AttendanceMode.meeting,
              scheduledDate: AcademicDate(year: 2026, month: 11, day: 2),
              effectiveDate: AcademicDate(year: 2026, month: 11, day: 2),
              startMinute: 480,
              endMinute: 540,
              unitCount: 0,
              absentUnits: 0,
              inReviewUnits: 0,
              justifiedUnits: 0,
              result: AttendanceSessionResult.voided,
              segments: const [],
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Todavía no hay asistencia registrada'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Registro anulado'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Registro anulado'), findsOneWidget);
    expect(find.textContaining('se excluye del cálculo'), findsOneWidget);
  });
}

Course _course() => Course(
  id: 'course_1234567890123456',
  ownerUid: 'teacher_uid',
  subject: 'Matemáticas',
  group: '01',
  period: '2026-2',
  program: 'Ingeniería',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 2),
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

List<AttendanceRecord> _fiveRecords() => [
  for (var index = 0; index < 5; index++)
    AttendanceRecord(
      courseId: 'course_1234567890123456',
      sessionId: 'session_$index',
      rosterEntryId: 'student_identity',
      visibility: AttendanceRecordVisibility.published,
      mode: AttendanceMode.meeting,
      scheduledDate: AcademicDate(year: 2026, month: 11, day: 2 + index),
      effectiveDate: AcademicDate(year: 2026, month: 11, day: 2 + index),
      startMinute: 480,
      endMinute: 540,
      unitCount: 1,
      absentUnits: index == 0 ? 1 : 0,
      inReviewUnits: index == 0 ? 1 : 0,
      justifiedUnits: 0,
      result: index == 0
          ? AttendanceSessionResult.absent
          : AttendanceSessionResult.present,
      segments: const [],
    ),
];

class _AttendanceRepository implements AttendanceRepository {
  _AttendanceRepository(this.records);

  final List<AttendanceRecord> records;

  @override
  Future<AttendanceRecordPage> listMyAttendanceRecords({
    required String courseId,
    AttendanceRecordCursor? cursor,
    int pageSize = 25,
  }) async => AttendanceRecordPage(items: records, nextCursor: null);

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
