import 'package:flutter/material.dart';
import 'package:aula_presente/features/attendance/domain/attendance_segment.dart';
import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/attendance/application/attendance_record_calculator.dart';
import 'package:aula_presente/features/attendance/presentation/attendance_session_screen.dart';
import 'package:aula_presente/features/attendance/presentation/student_attendance_screen.dart';
import 'package:aula_presente/features/attendance/domain/attendance_justification_request.dart';
import 'package:aula_presente/features/attendance/application/attendance_segment_factory.dart';
import 'package:aula_presente/features/attendance/data/attendance_firestore_codec.dart';
import 'package:aula_presente/features/attendance/domain/attendance_mode.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment_page.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:aula_presente/features/attendance/domain/attendance_occurrence.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_status_change.dart';

import 'package:aula_presente/features/attendance/data/firestore_attendance_repository.dart';
import 'package:aula_presente/features/attendance/domain/attendance_failure.dart';
import 'package:aula_presente/features/attendance/domain/attendance_session.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_failure.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('real repository corrects the second hour and student screen sees zero absences', (tester) async {
    const parent='courses/course-1/attendance_sessions/occurrence-1';
    final store=_Store()..documents['users/teacher-1']=_teacherProfile()..documents['users/student-1']=_studentProfile()..documents['courses/course-1']={'ownerUid':'teacher-1'};
    final data={..._session(status:'finalized',rosterCount:1,markedCount:1,unmarkedCount:0,version:8),'mode':'minutes','segmentIds':['seg-1','seg-2'],'startMinute':600,'endMinute':720};
    store.documents[parent]=data;
    final session=AttendanceFirestoreCodec.sessionFromMap(data,expectedCourseId:'course-1',expectedOccurrenceId:'occurrence-1');
    final segments=const [AttendanceSegment(id:'seg-1',order:0,startMinute:600,endMinute:660,durationMinutes:60),AttendanceSegment(id:'seg-2',order:1,startMinute:660,endMinute:720,durationMinutes:60)];
    final first=const AttendanceRosterMark(mark:AttendanceMark.present,absentUnits:0,justificationStatus:AttendanceJustificationStatus.none,justifiedUnits:0);
    final entry=AttendanceRosterEntry(rosterEntryId:'roster-1',displayName:'Synthetic student',studentUid:'student-1',meetingMark:null,segmentMarks:{'seg-1':first,'seg-2':const AttendanceRosterMark(mark:AttendanceMark.absent,absentUnits:60,justificationStatus:AttendanceJustificationStatus.none,justifiedUnits:0)},version:1);
    store.documents['$parent/roster/roster-1']={...AttendanceFirestoreCodec.rosterDocument(entry:entry,mode:AttendanceMode.minutes,uid:'teacher-1'),'updatedAt':Timestamp.fromDate(DateTime.utc(2026,11,16))};
    for(final segment in segments) {
      store.documents['$parent/segments/${segment.id}']={...AttendanceFirestoreCodec.segmentForCreate(segment:segment),'createdAt':Timestamp.fromDate(DateTime.utc(2026,11,16))};
    }
    store.documents['courses/course-1/attendance_records/occurrence-1|roster-1']={...AttendanceFirestoreCodec.stagedRecord(AttendanceRecordCalculator.fromRosterEntry(session:session,entry:entry,segments:segments)),'visibility':'published','publishedAt':Timestamp.fromDate(DateTime.utc(2026,11,16)),'updatedAt':Timestamp.fromDate(DateTime.utc(2026,11,16))};
    final course=Course(id:'course-1',ownerUid:'teacher-1',subject:'Synthetic course',group:'01',period:'2026',program:'Program',schedule:CourseSchedule(startDate:AcademicDate(year:2026,month:11,day:1),endDate:AcademicDate(year:2026,month:11,day:30),weeklyBlocks:const [WeeklyBlock(id:'block',weekday:1,startTime:'10:00',endTime:'12:00')]));
    await tester.pumpWidget(MaterialApp(theme:AppTheme.dark,home:TeacherAttendanceSessionScreen(course:course,session:session,repository:_repository(store))));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(DropdownButtonFormField<String>),200,scrollable:find.byType(Scrollable).first);
    await tester.tap(find.byType(DropdownButtonFormField<String>));await tester.pumpAndSettle();
    await tester.tap(find.text('11:00\u201312:00 \u00b7 60 min').last);await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Corregir registro'),200,scrollable:find.byType(Scrollable).first);await tester.tap(find.text('Corregir registro'));await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:find.byType(SegmentedButton<AttendanceMark>),matching:find.text('Presente')));await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambios'));await tester.pumpAndSettle();
    final record=store.documents['courses/course-1/attendance_records/occurrence-1|roster-1']!;
    expect(record['absentUnits'],0);expect(record['unitCount'],120);
    expect((record['segments'] as List).first['mark'],'present');
    expect((record['segments'] as List).last['mark'],'present');
    final student=FirestoreAttendanceRepository(auth:_Auth(_User('student-1','student@example.invalid')),firestore:store,enrollments:_StudentEnrollmentRepository());
    await tester.pumpWidget(MaterialApp(theme:AppTheme.dark,home:StudentAttendanceScreen(course:course,repository:student)));await tester.pumpAndSettle();
    expect(find.text('0% de faltas computables'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  test('restoration reuses marks and resumes after a failed write', () async {
    final store = _auditStore(mark: 'absent')
      ..documents['courses/course-1'] = {'ownerUid': 'teacher-1'};
    final repo = _repository(store);
    await repo.voidSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      operationId: 'void-restore',
      reason: '',
    );
    final original = Map<String, dynamic>.from(
      store
          .documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-1']!,
    );
    store.failRestorePathOnce =
        'courses/course-1/attendance_records/occurrence-1|student-1';
    await expectLater(
      repo.restoreSession(courseId: 'course-1', occurrenceId: 'occurrence-1'),
      throwsA(isA<AttendanceFailure>()),
    );
    final parent =
        store.documents['courses/course-1/attendance_sessions/occurrence-1']!;
    expect(parent['status'], 'restoring');
    final eventId = parent['lastEventId'];
    final result = await _repository(store)
        .restoreSession(courseId: 'course-1', occurrenceId: 'occurrence-1');
    expect(result.status, AttendanceSessionStatus.finalized);
    expect(result.lastEventId, eventId);
    expect(
      store
          .documents['courses/course-1/attendance_records/occurrence-1|student-1']!['unitCount'],
      1,
    );
    expect(
      store
          .documents['courses/course-1/attendance_records/occurrence-1|student-1']!['absentUnits'],
      1,
    );
    expect(
      store
          .documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-1'],
      original,
    );
    final writes = store.transactionWrites.length;
    await repo.restoreSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
    );
    expect(store.transactionWrites.length, writes);
    // Corrections remain parseable after restoration, including the historical void metadata.
    final entry = await repo.getRosterEntry(
      session: result,
      rosterEntryId: 'student-1',
    );
    final replacement = AttendanceRosterEntry(
      rosterEntryId: 'student-1',
      displayName: entry!.displayName,
      studentUid: entry.studentUid,
      meetingMark: const AttendanceRosterMark(
        mark: AttendanceMark.present,
        absentUnits: 0,
        justificationStatus: AttendanceJustificationStatus.none,
        justifiedUnits: 0,
      ),
      segmentMarks: {},
      version: entry.version,
    );
    await repo.correctRosterEntry(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      operationId: 'after-restore',
      replacement: replacement,
      reason: '',
    );
    expect(
      (await repo.getSession(
        courseId: 'course-1',
        occurrenceId: 'occurrence-1',
      ))!.status,
      AttendanceSessionStatus.finalized,
    );
  });

  test('twelve restored projections resume after a committed first chunk', () async {
    final store = _auditStore(mark: 'absent');
    final parent =
        store.documents['courses/course-1/attendance_sessions/occurrence-1']!;
    parent['rosterCount'] = 12;
    parent['markedCount'] = 12;
    for (var i = 1; i <= 12; i++) {
      store.documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-$i'] =
          _entry(rosterEntryId: 'student-$i', mark: 'absent', version: 1);
      store.documents['courses/course-1/attendance_records/occurrence-1|student-$i'] =
          _record(rosterEntryId: 'student-$i', mark: 'absent');
    }
    await _repository(store).voidSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      operationId: 'void-all',
      reason: '',
    );
    store.failRestorePathOnce =
        'courses/course-1/attendance_records/occurrence-1|student-9';
    await expectLater(
      _repository(store)
          .restoreSession(courseId: 'course-1', occurrenceId: 'occurrence-1'),
      throwsA(isA<AttendanceFailure>()),
    );
    final published = store.documents.entries
        .where(
          (e) =>
              e.key.startsWith('courses/course-1/attendance_records/') &&
              e.value?['result'] != 'voided',
        )
        .length;
    expect(published, 10);
    await _repository(store)
        .restoreSession(courseId: 'course-1', occurrenceId: 'occurrence-1');
    expect(
      store.documents.entries.where(
        (e) =>
            e.key.startsWith('courses/course-1/attendance_records/') &&
            e.value?['result'] == 'absent',
      ),
      hasLength(12),
    );
    final events = store.documents.entries.where(
      (e) => e.key.contains('/events/') && e.value?['kind'] == 'restore',
    );
    expect(events, hasLength(1));
    expect(parent['rosterCount'], 12);
  });

  for (final approve in [true, false]) {
    test(
      'student request is single and decision $approve updates the projection atomically',
      () async {
        final store = _auditStore(mark: 'absent');
        final row = store.documents.remove(
          'courses/course-1/attendance_sessions/occurrence-1/roster/student-1',
        )!;
        row['rosterEntryId'] = 'roster-1';
        store.documents['courses/course-1/attendance_sessions/occurrence-1/roster/roster-1'] =
            row;
        store.documents['courses/course-1/attendance_records/occurrence-1|roster-1'] =
            _record(mark: 'absent', rosterEntryId: 'roster-1');
        store.documents['users/student-1'] = _studentProfile();
        final student = FirestoreAttendanceRepository(
          auth: _Auth(_User('student-1', 'student@example.invalid')),
          firestore: store,
          enrollments: _StudentEnrollmentRepository(),
        );
        final record = AttendanceFirestoreCodec.recordFromMap(
          store
              .documents['courses/course-1/attendance_records/occurrence-1|roster-1']!,
          expectedCourseId: 'course-1',
          expectedRecordId: 'occurrence-1|roster-1',
        );
        final request = await student.submitJustification(
          record: record,
          segmentId: null,
          text: 'Solicitud sintética',
        );
        final repeated = await student.submitJustification(
          record: record,
          segmentId: null,
          text: 'Segundo toque',
        );
        expect(request.id, repeated.id);
        expect(
          store
              .documents['courses/course-1/attendance_records/occurrence-1|roster-1']!['justifiedUnits'],
          0,
        );
        await _repository(store).decideJustificationRequest(
          courseId: 'course-1',
          request: request,
          approve: approve,
        );
        final writes = store.transactionWrites.length;
        await _repository(store).decideJustificationRequest(
          courseId: 'course-1',
          request: request,
          approve: approve,
        );
        expect(store.transactionWrites.length, writes);
        final result = store
            .documents['courses/course-1/attendance_records/occurrence-1|roster-1']!;
        expect(result['unitCount'], 1);
        expect(result['justifiedUnits'], approve ? 1 : 0);
        expect(
          (await student.getMyJustification(
            record: record,
            segmentId: null,
          ))!.status,
          approve
              ? AttendanceRequestStatus.approved
              : AttendanceRequestStatus.rejected,
        );
        final decisionWrites = store.transactionGroups
            .where(
              (g) => g.any(
                (w) => w.path.contains('/attendance_requests/') && w.update,
              ),
            )
            .single;
        expect(decisionWrites, hasLength(5));
      },
    );
  }

  test('C8 latency profile prepare complete view', () async {
    final date = AcademicDate(year: 2026, month: 11, day: 16);
    final occurrence = AttendanceOccurrence(
      id: 'occurrence-1',
      courseId: 'course-1',
      kind: AttendanceOccurrenceKind.rescheduled,
      scheduledDate: AcademicDate(year: 2026, month: 11, day: 5),
      effectiveDate: date,
      startMinute: 360,
      endMinute: 480,
    );
    final course = Course(
      id: 'course-1',
      ownerUid: 'teacher-1',
      subject: 'Sintético',
      group: '01',
      period: '2026',
      program: 'Programa',
      schedule: CourseSchedule(
        startDate: occurrence.scheduledDate,
        endDate: date,
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
    final source = _PreparationEnrollments(
      count: 12,
      delay: const Duration(milliseconds: 5),
    );
    final store = _Store()
      ..ioDelay = const Duration(milliseconds: 5)
      ..documents['users/teacher-1'] = _teacherProfile()
      ..documents['courses/course-1'] = {'ownerUid': 'teacher-1'}
      ..documents['courses/course-1/attendance_config/current'] = {
        'schemaVersion': 1,
        'mode': 'minutes',
        'sessionCount': 0,
        'lastSessionId': null,
        'createdAt': null,
        'createdBy': 'teacher-1',
        'updatedAt': null,
        'updatedBy': 'teacher-1',
      }
      ..documents['courses/course-1/attendance_calendar/occurrence-1'] = {
        'occurrenceId': occurrence.id,
        'kind': 'rescheduled',
        'originalDate': Timestamp.fromDate(
          occurrence.scheduledDate.toUtcTimestamp(),
        ),
        'effectiveDate': Timestamp.fromDate(date.toUtcTimestamp()),
        'startMinute': 360,
        'endMinute': 480,
        'reason': 'Cambio sintético',
        'version': 1,
        'createdAt': null,
        'createdBy': 'teacher-1',
        'updatedAt': null,
        'updatedBy': 'teacher-1',
      };
    final timings = <String, int>{};
    var operation = 'preparar';
    final repository = FirestoreAttendanceRepository(
      auth: _Auth(_User('teacher-1', 'teacher@example.invalid')),
      firestore: store,
      enrollments: source,
      onTiming: (name, phase, duration) {
        timings['$operation/$name/$phase'] = duration.inMilliseconds;
      },
    );
    final watch = Stopwatch()..start();
    var session = await repository.prepareSession(
      course: course,
      occurrence: occurrence,
      lateRegistrationReason: 'Prueba local',
    );
    timings['preparar/total'] = watch.elapsedMilliseconds;
    expect(session.rosterCount, 12);
    operation = 'completar';
    store.documents['courses/course-1/attendance_sessions/occurrence-1']!['rosterState'] =
        'building';
    watch.reset();
    session = await repository.prepareSession(
      course: course,
      occurrence: occurrence,
    );
    timings['completar/total'] = watch.elapsedMilliseconds;
    expect(session.rosterState, AttendanceRosterState.ready);
    expect(
      store
          .documents['courses/course-1/attendance_config/current']!['sessionCount'],
      1,
    );
    operation = 'ver';
    watch.reset();
    await Future.wait<Object>([
      repository.listRoster(session: session, pageSize: 100),
      repository.listSegments(session: session, pageSize: 100),
    ]);
    timings['ver/total'] = watch.elapsedMilliseconds;
    // Timings are evidence, not assertions tied to the host's scheduling speed.
    // ignore: avoid_print
    print(
      'C8_LATENCY $timings reads=${store.directReads.length} queries=${store.queryLogs.length} source=${source.calls}',
    );
    expect(source.calls['history'], 24);
    expect(source.calls['snapshot'], 6);
    expect(source.calls['linked'], 72);
    expect(source.maxInFlight, inInclusiveRange(2, 6));
    // Any failed historical source still blocks ready, even with concurrent reads.
    source.failHistoryUid = 'student-2';
    store.documents['courses/course-1/attendance_sessions/occurrence-1']!['rosterState'] =
        'building';
    await expectLater(
      repository.prepareSession(course: course, occurrence: occurrence),
      throwsA(
        isA<AttendanceFailure>().having(
          (e) => e.kind,
          'kind',
          AttendanceFailureKind.unavailable,
        ),
      ),
    );
    expect(
      store
          .documents['courses/course-1/attendance_sessions/occurrence-1']!['rosterState'],
      'building',
    );
    expect(
      store
          .documents['courses/course-1/attendance_config/current']!['sessionCount'],
      1,
    );
  });

  test('C8 latency profile finalized view publication check', () async {
    const parent = 'courses/course-1/attendance_sessions/occurrence-1';
    final store = _Store()
      ..ioDelay = const Duration(milliseconds: 5)
      ..documents['users/teacher-1'] = _teacherProfile()
      ..documents[parent] = _session(
        status: 'finalized',
        rosterCount: 12,
        markedCount: 12,
        unmarkedCount: 0,
      );
    for (var index = 0; index < 12; index++) {
      final id = 'student-$index';
      store.documents['$parent/roster/$id'] = _entry(
        rosterEntryId: id,
        mark: 'present',
        version: 1,
      );
      store.documents['courses/course-1/attendance_records/occurrence-1|$id'] =
          _record(rosterEntryId: id, mark: 'present');
    }
    final timings = <String, int>{};
    final repository = FirestoreAttendanceRepository(
      auth: _Auth(_User('teacher-1', 'teacher@example.invalid')),
      firestore: store,
      enrollments: _UnusedEnrollments(),
      onTiming: (operation, phase, elapsed) =>
          timings[phase] = elapsed.inMilliseconds,
    );
    final watch = Stopwatch()..start();
    final result = await repository.finalizeSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      confirmUnmarked: false,
    );
    timings['total'] = watch.elapsedMilliseconds;
    expect(result.status, AttendanceFinalizeStatus.confirmed);
    expect(store.transactionWrites, isEmpty);
    // ignore: avoid_print
    print('C8_FINALIZED_VIEW $timings');
  });

  test(
    'resumes the same closing rescheduled hours session after a denied stage',
    () async {
      const parent = 'courses/course-1/attendance_sessions/occurrence-1';
      final occurrence = AttendanceOccurrence(
        id: 'occurrence-1',
        courseId: 'course-1',
        kind: AttendanceOccurrenceKind.rescheduled,
        scheduledDate: AcademicDate(year: 2026, month: 11, day: 5),
        effectiveDate: AcademicDate(year: 2026, month: 11, day: 16),
        startMinute: 360,
        endMinute: 480,
      );
      final segments = AttendanceSegmentFactory.forOccurrence(occurrence);
      final store = _Store()
        ..documents['users/teacher-1'] = _teacherProfile()
        ..documents['courses/course-1'] = {'ownerUid': 'teacher-1'}
        ..documents[parent] = {
          ..._session(status: 'closing', markedCount: 2, unmarkedCount: 0),
          'occurrenceKind': 'rescheduled',
          'mode': 'minutes',
          'scheduledDate': Timestamp.fromDate(
            occurrence.scheduledDate.toUtcTimestamp(),
          ),
          'effectiveDate': Timestamp.fromDate(
            occurrence.effectiveDate.toUtcTimestamp(),
          ),
          'startMinute': 360,
          'endMinute': 480,
          'segmentIds': segments.map((s) => s.id).toList(),
        };
      for (final segment in segments) {
        store.documents['$parent/segments/${segment.id}'] = {
          ...AttendanceFirestoreCodec.segmentForCreate(segment: segment),
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 16)),
        };
      }
      for (final student in ['student-1', 'student-2']) {
        store.documents['$parent/roster/$student'] = {
          'rosterEntryId': student,
          'displayName': 'Sintético',
          'version': 2,
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 16)),
          'updatedBy': 'teacher-1',
          'segments': {
            for (final segment in segments)
              segment.id: {
                'mark': segment == segments.first ? 'absent' : 'present',
                'absentUnits': segment == segments.first ? 60 : 0,
                'justificationStatus': 'none',
                'justifiedUnits': 0,
              },
          },
        };
      }
      final marks = [
        for (final student in ['student-1', 'student-2'])
          store.documents['$parent/roster/$student'],
      ];
      store.failStagePathOnce =
          'courses/course-1/attendance_records/occurrence-1|student-2';
      await expectLater(
        _repository(store).finalizeSession(
          courseId: 'course-1',
          occurrenceId: 'occurrence-1',
          confirmUnmarked: false,
        ),
        throwsA(
          isA<AttendanceFailure>().having(
            (e) => e.message,
            'phase',
            contains('preparar resultados privados (permission-denied)'),
          ),
        ),
      );
      expect(store.documents[parent]!['status'], 'closing');
      final result = await _repository(store).finalizeSession(
        courseId: 'course-1',
        occurrenceId: 'occurrence-1',
        confirmUnmarked: false,
      );
      expect(result.status, AttendanceFinalizeStatus.confirmed);
      final records = store.documents.entries
          .where(
            (e) => e.key.startsWith('courses/course-1/attendance_records/'),
          )
          .map((e) => e.value!)
          .toList();
      expect(records, hasLength(2));
      for (final record in records) {
        expect(record['visibility'], 'published');
        expect(record['unitCount'], 120);
        expect(record['absentUnits'], 60);
      }
      expect([
        for (final student in ['student-1', 'student-2'])
          store.documents['$parent/roster/$student'],
      ], marks);
      final publishedAt = records.map((r) => r['publishedAt']).toList();
      final writes = store.transactionWrites.length;
      await _repository(store).finalizeSession(
        courseId: 'course-1',
        occurrenceId: 'occurrence-1',
        confirmUnmarked: false,
      );
      expect(store.transactionWrites.length, writes);
      expect(records.map((r) => r['publishedAt']).toList(), publishedAt);
    },
  );

  test('future and rescheduled preparation materialize roster using effective date without starting', () async {
    for (final rescheduled in [false, true]) {
      final tomorrow = AcademicDate.fromDateTime(
        DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      final oldDate = AcademicDate(year: 2026, month: 11, day: 13);
      final store = _Store()
        ..documents['users/teacher-1'] = _teacherProfile()
        ..documents['courses/course-1'] = {'ownerUid': 'teacher-1'}
        ..documents['courses/course-1/attendance_config/current'] = {
          'schemaVersion': 1,
          'mode': 'meeting',
          'sessionCount': 0,
          'lastSessionId': null,
          'createdAt': null,
          'createdBy': 'teacher-1',
          'updatedAt': null,
          'updatedBy': 'teacher-1',
        };
      if (rescheduled) {
        store.documents['courses/course-1/attendance_calendar/occurrence-1'] = {
          'occurrenceId': 'occurrence-1',
          'kind': 'rescheduled',
          'originalDate': Timestamp.fromDate(oldDate.toUtcTimestamp()),
          'effectiveDate': Timestamp.fromDate(tomorrow.toUtcTimestamp()),
          'startMinute': 480,
          'endMinute': 540,
          'reason': 'Cambio',
          'version': 1,
          'createdAt': null,
          'createdBy': 'teacher-1',
          'updatedAt': null,
          'updatedBy': 'teacher-1',
        };
      }
      final repository = FirestoreAttendanceRepository(
        auth: _Auth(_User('teacher-1', 'teacher@example.invalid')),
        firestore: store,
        enrollments: _PreparationEnrollments(),
      );
      final course = Course(
        id: 'course-1',
        ownerUid: 'teacher-1',
        subject: 'Curso',
        group: '01',
        period: '2026',
        program: 'Programa',
        schedule: CourseSchedule(
          startDate: oldDate,
          endDate: tomorrow,
          weeklyBlocks: const [
            WeeklyBlock(
              id: 'block',
              weekday: 1,
              startTime: '08:00',
              endTime: '09:00',
            ),
          ],
        ),
      );
      final session = await repository.prepareSession(
        course: course,
        occurrence: AttendanceOccurrence(
          id: 'occurrence-1',
          courseId: course.id,
          kind: rescheduled
              ? AttendanceOccurrenceKind.rescheduled
              : AttendanceOccurrenceKind.planned,
          scheduledDate: rescheduled ? oldDate : tomorrow,
          effectiveDate: tomorrow,
          startMinute: 480,
          endMinute: 540,
        ),
      );
      expect(session.status, AttendanceSessionStatus.preparing);
      expect(session.rosterState, AttendanceRosterState.ready);
      expect(session.rosterCount, 1);
      expect(
        store
            .documents['courses/course-1/attendance_sessions/occurrence-1/roster/student@example.invalid']!['studentUid'],
        'student-1',
      );
      final stillPrepared = await repository.startSession(
        courseId: course.id,
        occurrenceId: session.occurrenceId,
      );
      expect(stillPrepared.status, AttendanceSessionStatus.preparing);
    }
  });

  for (final rescheduled in [false, true]) {
    test(
      'resume incomplete hours roster without a second session (rescheduled=$rescheduled)',
      () async {
        final date = AcademicDate(year: 2026, month: 11, day: 15);
        final occurrence = AttendanceOccurrence(
          id: 'occurrence-1',
          courseId: 'course-1',
          kind: rescheduled
              ? AttendanceOccurrenceKind.rescheduled
              : AttendanceOccurrenceKind.planned,
          scheduledDate: rescheduled
              ? AcademicDate(year: 2026, month: 11, day: 12)
              : date,
          effectiveDate: date,
          startMinute: 600,
          endMinute: 720,
        );
        final segments = AttendanceSegmentFactory.forOccurrence(occurrence);
        const parentPath = 'courses/course-1/attendance_sessions/occurrence-1';
        final store = _Store()
          ..documents['users/teacher-1'] = _teacherProfile()
          ..documents['courses/course-1'] = {'ownerUid': 'teacher-1'}
          ..documents['courses/course-1/attendance_config/current'] = {
            'schemaVersion': 1,
            'mode': 'minutes',
            'sessionCount': 1,
            'lastSessionId': occurrence.id,
            'createdAt': null,
            'createdBy': 'teacher-1',
            'updatedAt': null,
            'updatedBy': 'teacher-1',
          }
          ..documents[parentPath] = {
            ..._session(
              status: 'preparing',
              rosterCount: 1,
              markedCount: 0,
              unmarkedCount: 1,
            ),
            'rosterState': 'building',
            'mode': 'minutes',
            'occurrenceKind': occurrence.kind.value,
            'scheduledDate': Timestamp.fromDate(
              occurrence.scheduledDate.toUtcTimestamp(),
            ),
            'effectiveDate': Timestamp.fromDate(date.toUtcTimestamp()),
            'startMinute': 600,
            'endMinute': 720,
            'segmentIds': segments.map((e) => e.id).toList(),
          };
        for (final segment in segments) {
          store.documents['$parentPath/segments/${segment.id}'] = {
            ...AttendanceFirestoreCodec.segmentForCreate(segment: segment),
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
          };
        }
        final rowPath = '$parentPath/roster/student@example.invalid';
        store.documents[rowPath] = {
          ...AttendanceFirestoreCodec.rosterDocument(
            entry: AttendanceRosterEntry.unmarkedForMode(
              rosterEntryId: 'student@example.invalid',
              displayName: 'Snapshot anterior',
              studentUid: null,
              mode: AttendanceMode.minutes,
              segments: segments,
            ),
            mode: AttendanceMode.minutes,
            uid: 'teacher-1',
          ),
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
        };
        if (rescheduled) {
          store.documents['courses/course-1/attendance_calendar/occurrence-1'] =
              {
                'occurrenceId': occurrence.id,
                'kind': 'rescheduled',
                'originalDate': Timestamp.fromDate(
                  occurrence.scheduledDate.toUtcTimestamp(),
                ),
                'effectiveDate': Timestamp.fromDate(date.toUtcTimestamp()),
                'startMinute': 600,
                'endMinute': 720,
                'reason': 'Cambio de horario',
                'version': 1,
                'createdAt': null,
                'createdBy': 'teacher-1',
                'updatedAt': null,
                'updatedBy': 'teacher-1',
              };
        }
        final originalMarks = store.documents[rowPath]!['segments'];
        final originalCreatedAt = store.documents[parentPath]!['createdAt'];
        final course = Course(
          id: 'course-1',
          ownerUid: 'teacher-1',
          subject: 'Curso',
          group: '01',
          period: '2026',
          program: 'Programa',
          schedule: CourseSchedule(
            startDate: AcademicDate(year: 2026, month: 11, day: 1),
            endDate: date,
            weeklyBlocks: const [
              WeeklyBlock(
                id: 'block',
                weekday: 1,
                startTime: '10:00',
                endTime: '12:00',
              ),
            ],
          ),
        );
        FirestoreAttendanceRepository reopened() =>
            FirestoreAttendanceRepository(
              auth: _Auth(_User('teacher-1', 'teacher@example.invalid')),
              firestore: store,
              enrollments: _PreparationEnrollments(),
            );
        final ready = await reopened().prepareSession(
          course: course,
          occurrence: occurrence,
        );
        expect(ready.rosterState, AttendanceRosterState.ready);
        expect(store.documents[rowPath]!['studentUid'], 'student-1');
        expect(store.documents[rowPath]!['segments'], originalMarks);
        expect(store.documents[parentPath]!['createdAt'], originalCreatedAt);
        expect(
          store
              .documents['courses/course-1/attendance_config/current']!['sessionCount'],
          1,
        );
        final writes = store.transactionWrites.length;
        await reopened().prepareSession(course: course, occurrence: occurrence);
        expect(store.transactionWrites.length, writes);
        // An omitted late reason is allowed; an optional nonempty reason persists
        // it once before completing the same session (no counter increment).
        store.documents[parentPath]!['rosterState'] = 'building';
        store.documents[parentPath]!['createdAt'] = Timestamp.fromDate(
          DateTime.utc(2026, 11, 15, 18),
        );
        await reopened().prepareSession(course: course, occurrence: occurrence);
        expect(store.documents[parentPath]!['lateRegistrationReason'], isNull);
        store.documents[parentPath]!['rosterState'] = 'building';
        await reopened().prepareSession(
          course: course,
          occurrence: occurrence,
          lateRegistrationReason: 'Registro posterior revisado',
        );
        expect(
          store.documents[parentPath]!['lateRegistrationReason'],
          'Registro posterior revisado',
        );
        expect(store.documents[rowPath]!['segments'], originalMarks);
        // Even an inconsistent pre-existing marked row is rejected, never reset.
        store.documents[parentPath]!['rosterState'] = 'building';
        final marks = Map<String, dynamic>.from(
          store.documents[rowPath]!['segments'] as Map,
        );
        marks[segments.first.id] = {
          'mark': 'present',
          'absentUnits': 0,
          'justificationStatus': 'none',
          'justifiedUnits': 0,
        };
        store.documents[rowPath]!['segments'] = marks;
        await expectLater(
          reopened().prepareSession(course: course, occurrence: occurrence),
          throwsA(isA<AttendanceFailure>()),
        );
        expect(store.documents[rowPath]!['segments'], marks);
      },
    );
  }

  test('a meeting mark commits the roster row and session counters atomically', () async {
    final store = _Store()
      ..documents['users/teacher-1'] = _teacherProfile()
      ..documents['courses/course-1/attendance_sessions/occurrence-1'] =
          _session()
      ..documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-1'] =
          _entry(mark: 'unmarked', version: 0);
    final repository = FirestoreAttendanceRepository(
      auth: _Auth(_User('teacher-1', 'teacher@example.invalid')),
      firestore: store,
      enrollments: _UnusedEnrollments(),
    );

    final result = await repository.setMeetingMark(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      rosterEntryId: 'student-1',
      mark: AttendanceMark.present,
    );

    expect(result.alreadyApplied, isFalse);
    expect(result.entry.meetingMark?.mark, AttendanceMark.present);
    expect(result.session.markedCount, 1);
    expect(result.session.unmarkedCount, 1);
    expect(result.session.version, 2);
    expect(
      store.transactionWrites.map((write) => write.path),
      unorderedEquals([
        'courses/course-1/attendance_sessions/occurrence-1/roster/student-1',
        'courses/course-1/attendance_sessions/occurrence-1',
      ]),
    );
    final parentWrite = store.transactionWrites.singleWhere(
      (write) => write.path.endsWith('/occurrence-1'),
    );
    expect(parentWrite.data['markedCount'], 1);
    expect(parentWrite.data['unmarkedCount'], 1);
    expect(parentWrite.data['lastMutationRosterEntryId'], 'student-1');
    expect(parentWrite.data['lastMutationKind'], 'mark');
    expect(parentWrite.data['lastEventId'], isNull);
    expect(
      store
          .documents['courses/course-1/attendance_sessions/occurrence-1']!['version'],
      2,
    );
  });

  test('a non-teacher cannot write attendance', () async {
    final store = _Store()
      ..documents['users/student-1'] = {
        ..._teacherProfile(),
        'roles': ['student'],
        'email': 'student@example.invalid',
      }
      ..documents['courses/course-1/attendance_sessions/occurrence-1'] =
          _session(ownerUid: 'student-1')
      ..documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-1'] =
          _entry(mark: 'unmarked', version: 0);
    final repository = FirestoreAttendanceRepository(
      auth: _Auth(_User('student-1', 'student@example.invalid')),
      firestore: store,
      enrollments: _UnusedEnrollments(),
    );

    await expectLater(
      repository.setMeetingMark(
        courseId: 'course-1',
        occurrenceId: 'occurrence-1',
        rosterEntryId: 'student-1',
        mark: AttendanceMark.present,
      ),
      throwsA(
        isA<AttendanceFailure>().having(
          (failure) => failure.kind,
          'kind',
          AttendanceFailureKind.teacherRoleRequired,
        ),
      ),
    );
    expect(store.transactionWrites, isEmpty);
  });

  test('finalization requires confirmation, then stages and publishes all records', () async {
    final store = _Store()
      ..documents['users/teacher-1'] = _teacherProfile()
      ..documents['courses/course-1/attendance_sessions/occurrence-1'] =
          _session(markedCount: 1, unmarkedCount: 1)
      ..documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-1'] =
          _entry(mark: 'present', version: 1)
      ..documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-2'] =
          _entry(rosterEntryId: 'student-2', mark: 'unmarked', version: 0);
    final repository = _repository(store);

    final review = await repository.finalizeSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      confirmUnmarked: false,
    );
    expect(review.confirmationRequired, isTrue);
    expect(review.unmarkedCount, 1);
    expect(review.writeConfirmed, isFalse);
    expect(store.transactionWrites, isEmpty);

    final closed = await repository.finalizeSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      confirmUnmarked: true,
    );
    expect(closed.status, AttendanceFinalizeStatus.confirmed);
    expect(closed.writeConfirmed, isTrue);
    expect(closed.session?.status, AttendanceSessionStatus.finalized);
    expect(
      store
          .documents['courses/course-1/attendance_sessions/occurrence-1']!['unmarkedConfirmed'],
      isTrue,
    );
    expect(
      store
          .documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-2']!['meetingMark'],
      'absent',
    );
    for (final studentId in ['student-1', 'student-2']) {
      final record = store
          .documents['courses/course-1/attendance_records/occurrence-1|$studentId']!;
      expect(record['visibility'], 'published');
    }
    expect(
      store.transactionWrites.any(
        (write) =>
            write.path.startsWith('courses/course-1/attendance_records/') &&
            write.data['visibility'] == 'staged',
      ),
      isTrue,
    );
    expect(
      store.transactionWrites.any(
        (write) =>
            write.path.startsWith('courses/course-1/attendance_records/') &&
            write.data['visibility'] == 'published',
      ),
      isTrue,
    );
  });

  test('void resumes after a read failure and reuses its event and projections', () async {
    final store = _Store()
      ..documents['users/teacher-1'] = _teacherProfile()
      ..documents['courses/course-1/attendance_sessions/occurrence-1'] =
          _session(
            status: 'finalized',
            markedCount: 2,
            unmarkedCount: 0,
            version: 8,
          )
      ..documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-1'] =
          _entry(mark: 'present', version: 1)
      ..documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-2'] =
          _entry(rosterEntryId: 'student-2', mark: 'absent', version: 1)
      ..documents['courses/course-1/attendance_records/occurrence-1|student-1'] =
          _record(mark: 'absent')
      ..failReadPathOnce =
          'courses/course-1/attendance_records/occurrence-1|student-1';
    final repository = _repository(store);

    final interrupted = await repository.voidSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      operationId: 'void-operation-1',
      reason: 'La clase no se realizó.',
    );
    expect(interrupted.status, AttendanceSessionStatus.voiding);
    expect(interrupted.lastEventId, 'void-operation-1');

    final completed = await _repository(store).voidSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      operationId: 'void-operation-1',
      reason: 'La clase no se realizó.',
    );
    expect(
      store
          .documents['courses/course-1/attendance_records/occurrence-1|student-1']!['publishedAt'],
      Timestamp.fromDate(DateTime.utc(2026, 11, 15)),
    );
    expect(completed.status, AttendanceSessionStatus.voided);
    expect(completed.lastMutationKind, AttendanceMutationKind.voidSession);
    expect(completed.lastEventId, 'void-operation-1');
    expect(
      store
          .documents['courses/course-1/attendance_sessions/occurrence-1/events/void-operation-1']!['kind'],
      'void',
    );
    for (final studentId in ['student-1', 'student-2']) {
      final record = store
          .documents['courses/course-1/attendance_records/occurrence-1|$studentId']!;
      expect(record['visibility'], 'published');
      expect(record['result'], 'voided');
      expect(record.containsKey('reason'), isFalse);
    }
    final eventWriteCount = store.transactionWrites
        .where((write) => write.path.endsWith('/events/void-operation-1'))
        .length;
    expect(eventWriteCount, 1);
  });

  test('void chunks are version-stable and resume idempotently after a failed chunk', () async {
    const operationId = 'void-operation-1';
    const reason = 'La clase no se realizó.';
    final store = _Store()
      ..documents['users/teacher-1'] = _teacherProfile()
      ..documents['courses/course-1/attendance_sessions/occurrence-1'] =
          _session(
            status: 'finalized',
            rosterCount: 12,
            markedCount: 12,
            unmarkedCount: 0,
            version: 8,
          )
      ..failVoidPathOnce =
          'courses/course-1/attendance_records/occurrence-1|student-11';
    for (var index = 1; index <= 12; index++) {
      final studentId = 'student-${index.toString().padLeft(2, '0')}';
      store.documents['courses/course-1/attendance_sessions/occurrence-1/roster/$studentId'] =
          _entry(rosterEntryId: studentId, mark: 'present', version: 1);
    }
    final repository = _repository(store);

    final interrupted = await repository.voidSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      operationId: operationId,
      reason: reason,
    );

    expect(interrupted.status, AttendanceSessionStatus.voiding);
    expect(interrupted.version, 9);
    final parentPath = 'courses/course-1/attendance_sessions/occurrence-1';
    final eventPath = '$parentPath/events/$operationId';
    expect(store.documents[parentPath]!['version'], 9);
    expect(store.documents[eventPath]!['kind'], 'void');
    for (var index = 1; index <= 12; index++) {
      final studentId = 'student-${index.toString().padLeft(2, '0')}';
      final recordPath =
          'courses/course-1/attendance_records/occurrence-1|$studentId';
      expect(
        store.documents[recordPath]?['result'],
        index <= 10 ? 'voided' : isNull,
      );
    }

    final writesBeforeTamperedRetry = store.transactionWrites.length;
    store.documents[eventPath]!['reason'] = 'Motivo modificado';
    await expectLater(
      repository.voidSession(
        courseId: 'course-1',
        occurrenceId: 'occurrence-1',
        operationId: operationId,
        reason: reason,
      ),
      throwsA(
        isA<AttendanceFailure>().having(
          (failure) => failure.kind,
          'kind',
          AttendanceFailureKind.staleSession,
        ),
      ),
    );
    expect(store.transactionWrites, hasLength(writesBeforeTamperedRetry));
    store.documents[eventPath]!['reason'] = reason;

    final completed = await repository.voidSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      operationId: operationId,
      reason: reason,
    );

    expect(completed.status, AttendanceSessionStatus.voided);
    expect(completed.version, 10);
    expect(completed.lastEventId, operationId);
    expect(store.documents[parentPath]!['version'], 10);
    expect(
      store.transactionWrites.where(
        (write) => write.path.endsWith('/events/$operationId'),
      ),
      hasLength(1),
    );
    for (var index = 1; index <= 12; index++) {
      final studentId = 'student-${index.toString().padLeft(2, '0')}';
      final recordPath =
          'courses/course-1/attendance_records/occurrence-1|$studentId';
      expect(store.documents[recordPath]!['visibility'], 'published');
      expect(store.documents[recordPath]!['result'], 'voided');
      expect(
        store.transactionWrites.where((write) => write.path == recordPath),
        hasLength(1),
      );
    }
    final projectionTransactions = store.transactionGroups.where(
      (writes) => writes.any(
        (write) =>
            write.path.startsWith('courses/course-1/attendance_records/'),
      ),
    );
    expect(
      projectionTransactions.every(
        (writes) => writes.every((write) => write.path != parentPath),
      ),
      isTrue,
    );
    final projectionReads = store.transactionReadGroups.where(
      (reads) => reads.any(
        (path) => path.startsWith('courses/course-1/attendance_records/'),
      ),
    );
    expect(projectionReads, isNotEmpty);
    expect(
      projectionReads.every(
        (reads) => reads.contains(parentPath) && reads.contains(eventPath),
      ),
      isTrue,
    );
  });

  test(
    'correction retries with its operation ID without writing twice',
    () async {
      final store = _auditStore(mark: 'absent');
      final repository = _repository(store);
      final replacement = _entryModel(mark: AttendanceMark.present, version: 1);

      final saved = await repository.correctRosterEntry(
        courseId: 'course-1',
        occurrenceId: 'occurrence-1',
        operationId: 'correction-operation-1',
        replacement: replacement,
        reason: 'Se verificó la lista de clase.',
      );
      final writeCount = store.transactionWrites.length;
      final retry = await repository.correctRosterEntry(
        courseId: 'course-1',
        occurrenceId: 'occurrence-1',
        operationId: 'correction-operation-1',
        replacement: replacement,
        reason: 'Se verificó la lista de clase.',
      );

      expect(saved.alreadyApplied, isFalse);
      expect(retry.alreadyApplied, isTrue);
      expect(retry.entry.meetingMark?.mark, AttendanceMark.present);
      expect(store.transactionWrites, hasLength(writeCount));
      final atomicWrites = store.transactionGroups.singleWhere(
        (group) => group.any(
          (write) => write.path.endsWith('/events/correction-operation-1'),
        ),
      );
      expect(
        atomicWrites.map((write) => write.path),
        containsAll([
          'courses/course-1/attendance_sessions/occurrence-1/roster/student-1',
          'courses/course-1/attendance_sessions/occurrence-1/events/correction-operation-1',
          'courses/course-1/attendance_records/occurrence-1|student-1',
          'courses/course-1/attendance_sessions/occurrence-1',
        ]),
      );
    },
  );

  test('justification retries with its operation ID without duplicate audit writes', () async {
    final store = _auditStore(mark: 'absent');
    final repository = _repository(store);
    final arguments = {
      'courseId': 'course-1',
      'occurrenceId': 'occurrence-1',
      'rosterEntryId': 'student-1',
      'segmentId': null,
      'operationId': 'justification-operation-1',
      'status': AttendanceJustificationStatus.inReview,
      'justifiedUnits': 0,
      'reason': 'Se recibió el soporte para revisión.',
    };

    final saved = await repository.decideJustification(
      courseId: arguments['courseId']! as String,
      occurrenceId: arguments['occurrenceId']! as String,
      rosterEntryId: arguments['rosterEntryId']! as String,
      segmentId: arguments['segmentId'] as String?,
      operationId: arguments['operationId']! as String,
      status: arguments['status']! as AttendanceJustificationStatus,
      justifiedUnits: arguments['justifiedUnits']! as int,
      reason: arguments['reason']! as String,
    );
    final writeCount = store.transactionWrites.length;
    final retry = await repository.decideJustification(
      courseId: arguments['courseId']! as String,
      occurrenceId: arguments['occurrenceId']! as String,
      rosterEntryId: arguments['rosterEntryId']! as String,
      segmentId: arguments['segmentId'] as String?,
      operationId: arguments['operationId']! as String,
      status: arguments['status']! as AttendanceJustificationStatus,
      justifiedUnits: arguments['justifiedUnits']! as int,
      reason: arguments['reason']! as String,
    );

    expect(saved.alreadyApplied, isFalse);
    expect(retry.alreadyApplied, isTrue);
    expect(
      retry.entry.meetingMark?.justificationStatus,
      AttendanceJustificationStatus.inReview,
    );
    expect(store.transactionWrites, hasLength(writeCount));
  });

  test('publication failure after finalized is explicit and retryable', () async {
    final store = _Store()
      ..documents['users/teacher-1'] = _teacherProfile()
      ..documents['courses/course-1/attendance_sessions/occurrence-1'] =
          _session(rosterCount: 1, markedCount: 1, unmarkedCount: 0)
      ..documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-1'] =
          _entry(mark: 'present', version: 1)
      ..failPublicationPathOnce =
          'courses/course-1/attendance_records/occurrence-1|student-1';
    final repository = _repository(store);

    final pending = await repository.finalizeSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      confirmUnmarked: false,
    );

    expect(pending.status, AttendanceFinalizeStatus.reviewRequired);
    expect(pending.publicationPending, isTrue);
    expect(pending.writeConfirmed, isTrue);
    expect(pending.failureKind, AttendanceFailureKind.unavailable);
    expect(pending.session?.status, AttendanceSessionStatus.finalized);
    expect(
      store
          .documents['courses/course-1/attendance_records/occurrence-1|student-1']!['visibility'],
      'staged',
    );

    final retried = await repository.finalizeSession(
      courseId: 'course-1',
      occurrenceId: 'occurrence-1',
      confirmUnmarked: false,
    );
    expect(retried.status, AttendanceFinalizeStatus.confirmed);
    expect(retried.publicationPending, isFalse);
    expect(retried.session?.status, AttendanceSessionStatus.finalized);
    expect(
      store
          .documents['courses/course-1/attendance_records/occurrence-1|student-1']!['visibility'],
      'published',
    );
    final finalizedIndex = store.transactionGroups.indexWhere(
      (group) => group.any(
        (write) =>
            write.path.endsWith('/occurrence-1') &&
            write.data['status'] == 'finalized',
      ),
    );
    final publishIndex = store.transactionGroups.indexWhere(
      (group) => group.any(
        (write) =>
            write.path.endsWith('occurrence-1|student-1') &&
            write.data['visibility'] == 'published',
      ),
    );
    expect(finalizedIndex, greaterThanOrEqualTo(0));
    expect(publishIndex, greaterThan(finalizedIndex));
  });

  test(
    'student query uses only own roster ID and published visibility',
    () async {
      final store = _Store()
        ..documents['users/student-1'] = _studentProfile()
        ..documents['courses/course-1/attendance_records/a|roster-1'] = _record(
          sessionId: 'a',
          rosterEntryId: 'roster-1',
          mark: 'present',
        )
        ..documents['courses/course-1/attendance_records/b|roster-1'] = _record(
          sessionId: 'b',
          rosterEntryId: 'roster-1',
          mark: 'absent',
          visibility: 'staged',
        )
        ..documents['courses/course-1/attendance_records/c|other-roster'] =
            _record(
              sessionId: 'c',
              rosterEntryId: 'other-roster',
              mark: 'absent',
            );
      final repository = FirestoreAttendanceRepository(
        auth: _Auth(_User('student-1', 'student@example.invalid')),
        firestore: store,
        enrollments: _StudentEnrollmentRepository(),
      );

      final page = await repository.listMyAttendanceRecords(
        courseId: 'course-1',
        pageSize: 10,
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.recordId, 'a|roster-1');
      expect(
        store.queryLogs.single.path,
        'courses/course-1/attendance_records',
      );
      expect(store.queryLogs.single.filters, [
        const _Filter('rosterEntryId', 'roster-1'),
        const _Filter('visibility', 'published'),
      ]);
      expect(store.queryLogs.single.orders, [
        const _Order('effectiveDate', true),
        _Order(FieldPath.documentId, true),
      ]);
      expect(store.directReads, [
        'users/student-1',
      ], reason: 'The student query must not point-read session status.');
    },
  );
}

FirestoreAttendanceRepository _repository(_Store store) =>
    FirestoreAttendanceRepository(
      auth: _Auth(_User('teacher-1', 'teacher@example.invalid')),
      firestore: store,
      enrollments: _UnusedEnrollments(),
    );

_Store _auditStore({required String mark}) => _Store()
  ..documents['users/teacher-1'] = _teacherProfile()
  ..documents['courses/course-1/attendance_sessions/occurrence-1'] = _session(
    status: 'finalized',
    rosterCount: 1,
    markedCount: 1,
    unmarkedCount: 0,
    version: 6,
  )
  ..documents['courses/course-1/attendance_sessions/occurrence-1/roster/student-1'] =
      _entry(mark: mark, version: 1)
  ..documents['courses/course-1/attendance_records/occurrence-1|student-1'] =
      _record(mark: mark);

Map<String, dynamic> _studentProfile() => {
  'name': 'Synthetic student',
  'email': 'student@example.invalid',
  'studentCode': 'S-1',
  'roles': ['student'],
};

Map<String, dynamic> _teacherProfile() => {
  'name': 'Synthetic teacher',
  'email': 'teacher@example.invalid',
  'studentCode': null,
  'roles': ['teacher'],
};

Map<String, dynamic> _session({
  String ownerUid = 'teacher-1',
  String status = 'inProgress',
  int rosterCount = 2,
  int markedCount = 0,
  int unmarkedCount = 2,
  int version = 1,
}) => {
  'schemaVersion': 1,
  'courseId': 'course-1',
  'ownerUid': ownerUid,
  'occurrenceId': 'occurrence-1',
  'occurrenceKind': 'planned',
  'mode': 'meeting',
  'status': status,
  'rosterState': 'ready',
  'scheduledDate': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
  'effectiveDate': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
  'startMinute': 0,
  'endMinute': 60,
  'timezone': 'America/Bogota',
  'segmentIds': <String>[],
  'rosterCount': rosterCount,
  'markedCount': markedCount,
  'unmarkedCount': unmarkedCount,
  'unmarkedConfirmed': false,
  'lastMutationRosterEntryId': null,
  'lastMutationKind': null,
  'lastEventId': null,
  'version': version,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
  'createdBy': ownerUid,
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
  'updatedBy': ownerUid,
  if (status == 'finalized')
    'finalizedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 15)),
  if (status == 'voiding' || status == 'voided')
    'reason': 'La clase no se realizó.',
  if (status == 'voided')
    'voidedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 15)),
};

Map<String, dynamic> _entry({
  String rosterEntryId = 'student-1',
  required String mark,
  required int version,
  String justificationStatus = 'none',
  int justifiedUnits = 0,
}) => {
  'rosterEntryId': rosterEntryId,
  'displayName': 'Synthetic student',
  'meetingMark': mark,
  'justificationStatus': justificationStatus,
  'justifiedUnits': justifiedUnits,
  'version': version,
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
  'updatedBy': 'teacher-1',
};

AttendanceRosterEntry _entryModel({
  String rosterEntryId = 'student-1',
  required AttendanceMark mark,
  required int version,
}) => AttendanceRosterEntry(
  rosterEntryId: rosterEntryId,
  displayName: 'Synthetic student',
  studentUid: null,
  meetingMark: AttendanceRosterMark(
    mark: mark,
    absentUnits: mark == AttendanceMark.absent ? 1 : 0,
    justificationStatus: AttendanceJustificationStatus.none,
    justifiedUnits: 0,
  ),
  segmentMarks: const {},
  version: version,
);

Map<String, dynamic> _record({
  String sessionId = 'occurrence-1',
  String rosterEntryId = 'student-1',
  String mark = 'absent',
  String justificationStatus = 'none',
  int justifiedUnits = 0,
  String visibility = 'published',
}) {
  final absent = mark == 'absent' ? 1 : 0;
  return {
    'schemaVersion': 1,
    'courseId': 'course-1',
    'sessionId': sessionId,
    'rosterEntryId': rosterEntryId,
    'visibility': visibility,
    'mode': 'meeting',
    'scheduledDate': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
    'effectiveDate': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
    'startMinute': 0,
    'endMinute': 60,
    'unitCount': 1,
    'absentUnits': absent,
    'inReviewUnits': justificationStatus == 'inReview' ? absent : 0,
    'justifiedUnits': justifiedUnits,
    'result': absent == 0
        ? 'present'
        : justifiedUnits == absent
        ? 'justified'
        : 'absent',
    'publishedAt': visibility == 'published'
        ? Timestamp.fromDate(DateTime.utc(2026, 11, 15))
        : null,
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 15)),
  };
}

class _Auth implements FirebaseAuth {
  _Auth(this.user);
  User? user;
  @override
  User? get currentUser => user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  _User(this.uid, this.email);
  @override
  final String uid;
  @override
  final String email;
  @override
  bool get emailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedEnrollments implements EnrollmentRepository {
  @override
  String? get currentUid => 'teacher-1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StudentEnrollmentRepository implements EnrollmentRepository {
  @override
  String? get currentUid => 'student-1';

  @override
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  }) async => Enrollment(
    courseId: courseId,
    studentUid: studentUid,
    ownerUid: 'teacher-1',
    name: 'Synthetic student',
    email: 'student@example.invalid',
    studentCode: 'S-1',
    subject: 'Synthetic subject',
    group: '01',
    period: '2026',
    status: 'active',
    createdAt: DateTime.utc(2026, 11, 1),
    rosterEntryId: 'roster-1',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements FirebaseFirestore {
  Duration ioDelay = Duration.zero;
  final documents = <String, Map<String, dynamic>?>{};
  final transactionWrites = <_Write>[];
  final transactionGroups = <List<_Write>>[];
  final transactionReadGroups = <List<String>>[];
  final directReads = <String>[];
  final queryLogs = <_QuerySpec>[];
  String? failReadPathOnce;
  String? failPublicationPathOnce;
  String? failVoidPathOnce;
  String? failStagePathOnce;
  int _commitNumber = 0;
  int autoIds = 0;
  String? failRestorePathOnce;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = _Transaction(this);
    try {
      final result = await transactionHandler(transaction);
      final writes = List<_Write>.of(transaction.writes);
      transactionWrites.addAll(writes);
      transactionGroups.add(writes);
      _commitNumber++;
      for (final write in writes) {
        final resolved = _resolve(write.data);
        if (write.update) {
          documents[write.path] = {...?documents[write.path], ...resolved};
        } else {
          documents[write.path] = resolved;
        }
      }
      return result;
    } finally {
      transactionReadGroups.add(List.of(transaction.reads));
    }
  }

  Map<String, dynamic> _resolve(Map<String, dynamic> values) => {
    for (final entry in values.entries)
      entry.key: entry.value is FieldValue
          ? Timestamp.fromDate(
              DateTime.utc(2026, 11, 15).add(Duration(seconds: _commitNumber)),
            )
          : entry.value,
  };

  QuerySnapshot<Map<String, dynamic>> _query(
    String path, {
    required List<_Filter> filters,
    required List<_Order> orders,
    required int? limit,
  }) {
    queryLogs.add(_QuerySpec(path, filters, orders, limit));
    final prefix = '$path/';
    final docs = documents.entries
        .where(
          (entry) =>
              entry.value != null &&
              entry.key.startsWith(prefix) &&
              !entry.key.substring(prefix.length).contains('/'),
        )
        .map((entry) => _Document(entry.key, entry.value!))
        .where(
          (document) => filters.every(
            (filter) => _fieldValue(document, filter.field) == filter.value,
          ),
        )
        .toList();
    if (orders.isNotEmpty) {
      docs.sort((left, right) {
        for (final order in orders) {
          final comparison = _compare(
            _fieldValue(left, order.field),
            _fieldValue(right, order.field),
          );
          if (comparison != 0) {
            return order.descending ? -comparison : comparison;
          }
        }
        return 0;
      });
    }
    return _QuerySnapshot(limit == null ? docs : docs.take(limit).toList());
  }

  Object? _fieldValue(_Document document, Object field) =>
      field == FieldPath.documentId ? document.id : document.value[field];

  int _compare(Object? left, Object? right) {
    if (left is Timestamp && right is Timestamp) return left.compareTo(right);
    if (left is Comparable && right is Comparable) {
      return left.compareTo(right);
    }
    return left.toString().compareTo(right.toString());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Collection extends _Query
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(super.store, super.path);
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Reference(store, '${this.path}/${path ?? 'auto-${store.autoIds++}'}');
}

// ignore: subtype_of_sealed_class
class _Reference implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(store, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    if (store.ioDelay != Duration.zero) {
      await Future<void>.delayed(store.ioDelay);
    }
    if (store.failReadPathOnce == path) {
      store.failReadPathOnce = null;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    store.directReads.add(path);
    final document = store.documents[path];
    return document == null
        ? _MissingDocument(path)
        : _Document(path, document);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Write {
  const _Write(this.path, this.data, {this.update = false});
  final String path;
  final Map<String, dynamic> data;
  final bool update;
}

// ignore: subtype_of_sealed_class
class _Transaction implements Transaction {
  _Transaction(this.store);
  final _Store store;
  final writes = <_Write>[];
  final reads = <String>[];
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async {
    if (store.ioDelay != Duration.zero) {
      await Future<void>.delayed(store.ioDelay);
    }
    reads.add(reference.path);
    final value = store.documents[reference.path];
    return (value == null
            ? _MissingDocument(reference.path)
            : _Document(reference.path, value))
        as DocumentSnapshot<T>;
  }

  @override
  Transaction update(
    DocumentReference<Object?> reference,
    Map<Object, Object?> data,
  ) {
    if (store.failPublicationPathOnce == reference.path &&
        data['visibility'] == 'published') {
      store.failPublicationPathOnce = null;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    writes.add(
      _Write(reference.path, data.cast<String, dynamic>(), update: true),
    );
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    final values = Map<String, dynamic>.from(data as Map);
    if (store.failRestorePathOnce == reference.path &&
        values['result'] != 'voided') {
      store.failRestorePathOnce = null;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    if (store.failStagePathOnce == reference.path &&
        values['visibility'] == 'staged') {
      store.failStagePathOnce = null;
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    if (store.failVoidPathOnce == reference.path &&
        values['result'] == 'voided') {
      store.failVoidPathOnce = null;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    writes.add(_Write(reference.path, values));
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MissingDocument implements DocumentSnapshot<Map<String, dynamic>> {
  _MissingDocument(this.path);
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  bool get exists => false;
  @override
  Map<String, dynamic>? data() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Document implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Document(this.path, this.value);
  final String path;
  final Map<String, dynamic> value;
  @override
  String get id => path.split('/').last;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Filter {
  const _Filter(this.field, this.value);
  final Object field;
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is _Filter && other.field == field && other.value == value;

  @override
  int get hashCode => Object.hash(field, value);
}

class _Order {
  const _Order(this.field, this.descending);
  final Object field;
  final bool descending;

  @override
  bool operator ==(Object other) =>
      other is _Order && other.field == field && other.descending == descending;

  @override
  int get hashCode => Object.hash(field, descending);
}

class _QuerySpec {
  const _QuerySpec(this.path, this.filters, this.orders, this.limit);
  final String path;
  final List<_Filter> filters;
  final List<_Order> orders;
  final int? limit;
}

// ignore: subtype_of_sealed_class
class _Query implements Query<Map<String, dynamic>> {
  _Query(
    this.store,
    this.path, {
    this.filters = const [],
    this.orders = const [],
    this.pageLimit,
  });

  final _Store store;
  final String path;
  final List<_Filter> filters;
  final List<_Order> orders;
  final int? pageLimit;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => _Query(
    store,
    path,
    filters: [...filters, _Filter(field, isEqualTo)],
    orders: orders,
    pageLimit: pageLimit,
  );

  @override
  Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) => _Query(
    store,
    path,
    filters: filters,
    orders: [...orders, _Order(field, descending)],
    pageLimit: pageLimit,
  );

  @override
  Query<Map<String, dynamic>> limit(int limit) =>
      _Query(store, path, filters: filters, orders: orders, pageLimit: limit);

  @override
  Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) => this;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    if (store.ioDelay != Duration.zero) {
      await Future<void>.delayed(store.ioDelay);
    }
    return store._query(
      path,
      filters: filters,
      orders: orders,
      limit: pageLimit,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _QuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreparationEnrollments extends _UnusedEnrollments {
  _PreparationEnrollments({this.count = 1, this.delay = Duration.zero});
  final int count;
  final Duration delay;
  final calls = <String, int>{};
  String? failHistoryUid;
  int inFlight = 0;
  int maxInFlight = 0;
  Future<void> _read(String kind) async {
    calls.update(kind, (n) => n + 1, ifAbsent: () => 1);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
    } finally {
      inFlight--;
    }
  }

  @override
  Future<CourseRosterSnapshot> loadCourseRosterSnapshot({
    required String courseId,
  }) async {
    await _read('snapshot');
    return CourseRosterSnapshot(
      activeEnrollments: [
        for (var index = 0; index < count; index++)
          Enrollment(
            courseId: courseId,
            studentUid: 'student-${index + 1}',
            ownerUid: 'teacher-1',
            name: 'Synthetic student',
            email: index == 0
                ? 'student@example.invalid'
                : 'student-${index + 1}@example.invalid',
            studentCode: 'S-1',
            subject: 'Curso',
            group: '01',
            period: '2026',
            status: 'active',
            createdAt: DateTime.utc(2026, 11, 14, 15),
            rosterEntryId: index == 0
                ? 'student@example.invalid'
                : 'student-${index + 1}@example.invalid',
            effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 14),
          ),
      ],
      withdrawnEnrollments: const [],
      pendingEnrollments: const [],
      withdrawnPendingEnrollments: const [],
      complete: true,
    );
  }

  @override
  Future<PendingEnrollment?> getCoursePendingEnrollment({
    required String courseId,
    required String email,
  }) async {
    await _read('linked');
    return null;
  }

  @override
  Future<EnrollmentHistoryPage> listEnrollmentHistory({
    required String courseId,
    required String studentUid,
    EnrollmentHistoryCursor? cursor,
    int pageSize = 25,
  }) async {
    await _read('history');
    if (failHistoryUid == studentUid) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return EnrollmentHistoryPage(items: [], nextCursor: null);
  }
}
