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
import 'package:aula_presente/features/excel_import/application/excel_import_coordinator.dart';
import 'package:aula_presente/features/excel_import/domain/excel_import_document.dart';
import 'package:aula_presente/features/excel_import/domain/excel_import_review.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

Course _course() => Course(
  id: 'course-one',
  ownerUid: 'teacher-one',
  subject: 'Materia de prueba',
  group: '01',
  period: '2026-2',
  program: 'Programa',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 1),
    endDate: AcademicDate(year: 2026, month: 11, day: 30),
    weeklyBlocks: const [],
  ),
);

AcademicDate _todayBogota() => AcademicDate.fromDateTime(
  DateTime.now().toUtc().subtract(const Duration(hours: 5)),
);

Course _futureCourse() {
  final startDate = _todayBogota().addDays(10);
  return Course(
    id: 'future-course',
    ownerUid: 'teacher-one',
    subject: 'Materia futura',
    group: '02',
    period: '2026-2',
    program: 'Programa',
    schedule: CourseSchedule(
      startDate: startDate,
      endDate: startDate.addDays(60),
      weeklyBlocks: const [],
    ),
  );
}

ExcelImportRow _row(int number, String code, String email, {String? error}) =>
    ExcelImportRow(
      rowNumber: number,
      studentCode: code,
      email: email,
      name: 'Nombre ficticio $number',
      validationError: error,
    );

ExcelImportSheet _sheet(List<ExcelImportRow> rows) => ExcelImportSheet(
  name: 'Lista ficticia',
  columnMapping: const {
    'CODIGOESTUDIANTE': 'CODIGOESTUDIANTE',
    'MAIL_INST': 'MAIL_INST',
    'NOMBRECOMPLETO': 'NOMBRECOMPLETO',
  },
  rows: rows,
);

StudentCandidate _candidate(String uid, String code, String email) =>
    StudentCandidate(
      uid: uid,
      name: 'Nombre validado $uid',
      email: email,
      studentCode: code,
    );

Enrollment _enrollment(
  StudentCandidate candidate, {
  String status = 'active',
  String courseId = 'course-one',
}) => Enrollment(
  courseId: courseId,
  studentUid: candidate.uid,
  ownerUid: 'teacher-one',
  name: candidate.name,
  email: candidate.email,
  studentCode: candidate.studentCode,
  subject: 'Materia de prueba',
  group: '01',
  period: '2026-2',
  status: status,
  createdAt: DateTime.utc(2026, 11, 1),
  rosterEntryId: candidate.email,
  effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 1),
  lastStatusEventId: status == 'withdrawn' ? 'historic-event' : null,
  lastStatusChangedAt: status == 'withdrawn' ? DateTime.utc(2026, 11, 2) : null,
);

PendingEnrollment _pending(
  String email,
  String code, {
  String status = 'pending',
}) => PendingEnrollment(
  courseId: 'course-one',
  ownerUid: 'teacher-one',
  subject: 'Materia de prueba',
  group: '01',
  period: '2026-2',
  email: email,
  studentCode: code,
  name: 'Nombre pendiente',
  status: status,
  effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 1),
  rosterEntryId: email,
  studentUid: null,
  authorizedAt: DateTime.utc(2026, 11, 1),
  linkedAt: null,
  createdAt: DateTime.utc(2026, 11, 1),
  updatedAt: DateTime.utc(2026, 11, 1),
  lastEventId: status == 'withdrawn' ? 'pending-old-event' : null,
  lastStatusChangedAt: status == 'withdrawn' ? DateTime.utc(2026, 11, 2) : null,
);

class _Repository implements EnrollmentRepository {
  String? uid = 'teacher-one';
  final directory = <String, StudentCandidate>{};
  final enrollments = <String, Enrollment>{};
  final pending = <String, PendingEnrollment>{};
  int countCalls = 0;
  int snapshotCalls = 0;
  int writeCalls = 0;
  int pendingWriteCalls = 0;
  final enrollmentStartDates = <AcademicDate>[];
  final pendingStartDates = <AcademicDate>[];
  final statusChangeDates = <AcademicDate>[];
  String? failWithdrawalStudentUid;
  bool? resolvePendingOnExisting;
  bool denyCount = false;
  bool failSnapshot = false;
  bool incompleteSnapshot = false;
  bool failAfterCreate = false;
  bool failBeforeCreate = false;
  void Function(StudentCandidate)? beforeEnroll;
  void Function()? afterEnroll;
  void Function()? afterLookup;

  @override
  String? get currentUid => uid;

  @override
  Future<int> countCourseStudents(String courseId) async {
    countCalls++;
    if (denyCount) {
      throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
    }
    return enrollments.values.where((e) => e.status == 'active').length;
  }

  @override
  Future<StudentCandidate?> findStudentByEmail(String email) async {
    final candidate = directory[email];
    afterLookup?.call();
    return candidate;
  }

  @override
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  }) async {
    final value = enrollments[studentUid];
    if (value == null) {
      throw const EnrollmentFailure(EnrollmentFailureKind.courseUnavailable);
    }
    return value;
  }

  @override
  Future<Enrollment?> findCourseEnrollmentByUid({
    required String courseId,
    required String studentUid,
  }) async => enrollments[studentUid];

  @override
  Future<CourseRosterIdentityLookup> findCourseRosterByStudentCode({
    required String courseId,
    required String studentCode,
  }) async {
    final enrollmentMatches = enrollments.values
        .where((value) => value.studentCode == studentCode)
        .toList();
    final pendingMatches = pending.values
        .where((value) => value.studentCode == studentCode)
        .toList();
    return CourseRosterIdentityLookup(
      enrollmentMatches: enrollmentMatches.take(2).toList(),
      pendingMatches: pendingMatches.take(2).toList(),
      hasMoreEnrollmentMatches: enrollmentMatches.length > 2,
      hasMorePendingMatches: pendingMatches.length > 2,
    );
  }

  @override
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
    AcademicDate? effectiveStartDate,
    bool resolvePendingWhenAlreadyEnrolled = true,
  }) async {
    resolvePendingOnExisting = resolvePendingWhenAlreadyEnrolled;
    beforeEnroll?.call(candidate);
    final existing = enrollments[candidate.uid];
    if (existing != null) {
      return EnrollmentResult(enrollment: existing, alreadyEnrolled: true);
    }
    writeCalls++;
    if (failBeforeCreate) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    final created = Enrollment(
      courseId: courseId,
      studentUid: candidate.uid,
      ownerUid: 'teacher-one',
      name: candidate.name,
      email: candidate.email,
      studentCode: candidate.studentCode,
      subject: 'Materia de prueba',
      group: '01',
      period: '2026-2',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 14),
      rosterEntryId: candidate.email,
      effectiveStartDate:
          effectiveStartDate ?? AcademicDate(year: 2026, month: 11, day: 14),
    );
    enrollmentStartDates.add(created.effectiveStartDate!);
    enrollments[candidate.uid] = created;
    afterEnroll?.call();
    if (failAfterCreate) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return EnrollmentResult(enrollment: created, alreadyEnrolled: false);
  }

  @override
  Future<CourseRosterSnapshot> loadCourseRosterSnapshot({
    required String courseId,
  }) async {
    snapshotCalls++;
    if (failSnapshot) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return CourseRosterSnapshot(
      activeEnrollments: enrollments.values
          .where((value) => value.status == 'active')
          .toList(),
      withdrawnEnrollments: enrollments.values
          .where((value) => value.status == 'withdrawn')
          .toList(),
      pendingEnrollments: pending.values
          .where((value) => value.status == 'pending')
          .toList(),
      withdrawnPendingEnrollments: pending.values
          .where((value) => value.status == 'withdrawn')
          .toList(),
      complete: !incompleteSnapshot,
    );
  }

  @override
  Future<List<Enrollment>> findCourseEnrollmentsByEmail({
    required String courseId,
    required String email,
  }) async =>
      enrollments.values.where((value) => value.email == email).toList();

  @override
  Future<PendingEnrollment?> getCoursePendingEnrollment({
    required String courseId,
    required String email,
  }) async => pending[email];

  @override
  Future<PendingEnrollmentWriteResult> authorizePendingEnrollment({
    required Course course,
    required String email,
    required String studentCode,
    required String name,
    required AcademicDate effectiveStartDate,
  }) async {
    pendingWriteCalls++;
    if (failBeforeCreate) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    final existing = pending[email];
    if (existing != null) {
      if (existing.studentCode != studentCode || existing.status != 'pending') {
        throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
      }
      return const PendingEnrollmentWriteResult(
        PendingEnrollmentWriteKind.alreadyPending,
      );
    }
    pending[email] = PendingEnrollment(
      courseId: course.id,
      ownerUid: course.ownerUid,
      subject: course.subject,
      group: course.group,
      period: course.period,
      email: email,
      studentCode: studentCode,
      name: name,
      status: 'pending',
      effectiveStartDate: effectiveStartDate,
      rosterEntryId: email,
      studentUid: null,
      authorizedAt: DateTime.utc(2026, 11, 14),
      linkedAt: null,
      createdAt: DateTime.utc(2026, 11, 14),
      updatedAt: DateTime.utc(2026, 11, 14),
      lastEventId: null,
      lastStatusChangedAt: null,
    );
    pendingStartDates.add(effectiveStartDate);
    return const PendingEnrollmentWriteResult(
      PendingEnrollmentWriteKind.created,
    );
  }

  @override
  String newPendingStatusEventId({
    required String courseId,
    required String email,
  }) =>
      'pending-event-${email.hashCode}-${DateTime.now().microsecondsSinceEpoch}';

  @override
  String newStatusEventId({
    required String courseId,
    required String studentUid,
  }) => 'enrollment-event-$studentUid-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<EnrollmentStatusChangeResult> changeEnrollmentStatus({
    required Enrollment expected,
    required String nextStatus,
    required String operationId,
    AcademicDate? effectiveDate,
  }) async {
    final current = enrollments[expected.studentUid];
    if (current == null ||
        current.status != expected.status ||
        current.lastStatusEventId != expected.lastStatusEventId) {
      throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
    }
    if (nextStatus == 'withdrawn' &&
        expected.studentUid == failWithdrawalStudentUid) {
      throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
    }
    if (effectiveDate != null) statusChangeDates.add(effectiveDate);
    final changed = Enrollment(
      courseId: expected.courseId,
      studentUid: expected.studentUid,
      ownerUid: expected.ownerUid,
      name: expected.name,
      email: expected.email,
      studentCode: expected.studentCode,
      subject: expected.subject,
      group: expected.group,
      period: expected.period,
      status: nextStatus,
      createdAt: expected.createdAt,
      rosterEntryId: expected.rosterEntryId,
      effectiveStartDate: expected.effectiveStartDate,
      lastStatusEventId: operationId,
      lastStatusChangedAt: DateTime.utc(2026, 11, 14),
    );
    enrollments[expected.studentUid] = changed;
    return EnrollmentStatusChangeResult(
      enrollment: changed,
      alreadyApplied: false,
    );
  }

  @override
  Future<PendingEnrollmentStatusChangeResult> changePendingEnrollmentStatus({
    required PendingEnrollment expected,
    required String nextStatus,
    required String operationId,
    required AcademicDate effectiveDate,
  }) async {
    final current = pending[expected.email];
    if (current == null ||
        current.status != expected.status ||
        current.lastEventId != expected.lastEventId) {
      throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
    }
    pendingStartDates.add(effectiveDate);
    final changed = PendingEnrollment(
      courseId: expected.courseId,
      ownerUid: expected.ownerUid,
      subject: expected.subject,
      group: expected.group,
      period: expected.period,
      email: expected.email,
      studentCode: expected.studentCode,
      name: expected.name,
      status: nextStatus,
      effectiveStartDate: effectiveDate,
      rosterEntryId: expected.rosterEntryId,
      studentUid: expected.studentUid,
      authorizedAt: expected.authorizedAt,
      linkedAt: expected.linkedAt,
      createdAt: expected.createdAt,
      updatedAt: DateTime.utc(2026, 11, 14),
      lastEventId: operationId,
      lastStatusChangedAt: DateTime.utc(2026, 11, 14),
    );
    pending[expected.email] = changed;
    return PendingEnrollmentStatusChangeResult(
      status: nextStatus,
      operationId: operationId,
      alreadyApplied: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('review classifies each row and never writes', () async {
    final repo = _Repository();
    final available = _candidate('student-one', '0012', 'one@example.invalid');
    final mismatch = _candidate('student-two', '9999', 'two@example.invalid');
    final active = _candidate('student-three', '0034', 'three@example.invalid');
    final withdrawn = _candidate(
      'student-four',
      '0045',
      'four@example.invalid',
    );
    repo.directory.addAll({
      available.email: available,
      mismatch.email: mismatch,
      active.email: active,
      withdrawn.email: withdrawn,
    });
    repo.enrollments[active.uid] = _enrollment(active);
    repo.enrollments[withdrawn.uid] = _enrollment(
      withdrawn,
      status: 'withdrawn',
    );
    final review = await ExcelImportCoordinator(repo).review(
      course: _course(),
      sheet: _sheet([
        _row(2, '0012', available.email),
        _row(3, '0023', mismatch.email),
        _row(4, '0034', active.email),
        _row(5, '0045', withdrawn.email),
        _row(6, '0056', 'absent@example.invalid'),
        _row(7, '', 'broken@example.invalid', error: 'Falta el código.'),
      ]),
    );

    expect(review.rows.map((row) => row.status), [
      ExcelReviewStatus.eligible,
      ExcelReviewStatus.codeMismatch,
      ExcelReviewStatus.alreadyEnrolled,
      ExcelReviewStatus.rejoinEnrollment,
      ExcelReviewStatus.pendingEligible,
      ExcelReviewStatus.invalid,
    ]);
    expect(review.eligibleCount, 3);
    expect(review.rows.first.candidate?.name, available.name);
    expect(repo.writeCalls, 0);
  });

  test('duplicate exact email, code and UID block all involved rows', () async {
    final repo = _Repository();
    final shared = _candidate('same-uid', '300', 'a@example.invalid');
    repo.directory.addAll({
      shared.email: shared,
      'b@example.invalid': _candidate('same-uid', '301', 'b@example.invalid'),
    });
    final review = await ExcelImportCoordinator(repo).review(
      course: _course(),
      sheet: _sheet([
        _row(2, '100', 'repeat@example.invalid'),
        _row(3, '101', 'repeat@example.invalid'),
        _row(4, '200', 'one@example.invalid'),
        _row(5, '200', 'two@example.invalid'),
        _row(6, '300', shared.email),
        _row(7, '301', 'b@example.invalid'),
      ]),
    );
    expect(
      review.rows.every((row) => row.status == ExcelReviewStatus.duplicate),
      isTrue,
    );
    expect(review.rows[0].message, contains('2, 3'));
    expect(review.rows[2].message, contains('4, 5'));
    expect(review.rows[4].message, contains('6, 7'));
    expect(review.eligibleCount, 0);
    expect(repo.writeCalls, 0);
  });

  test(
    'only explicit selection creates; reimport does not duplicate',
    () async {
      final repo = _Repository();
      final first = _candidate('student-one', '0012', 'one@example.invalid');
      final second = _candidate('student-two', '0023', 'two@example.invalid');
      repo.directory.addAll({first.email: first, second.email: second});
      final coordinator = ExcelImportCoordinator(repo);
      final review = await coordinator.review(
        course: _course(),
        sheet: _sheet([
          _row(2, '0012', first.email),
          _row(3, '0023', second.email),
        ]),
      );
      expect(repo.writeCalls, 0);
      await expectLater(
        coordinator.confirm(course: _course(), selected: const []),
        throwsA(isA<EnrollmentFailure>()),
      );
      final result = await coordinator.confirm(
        course: _course(),
        selected: [review.rows.first],
      );
      expect(result.enrolledNow, 1);
      expect(repo.writeCalls, 1);
      expect(repo.enrollments.length, 1);
      expect(repo.resolvePendingOnExisting, isFalse);
      final again = await coordinator.review(
        course: _course(),
        sheet: _sheet([_row(2, '0012', first.email)]),
      );
      expect(again.rows.single.status, ExcelReviewStatus.alreadyEnrolled);
    },
  );

  test(
    'race with active or withdrawn enrollment reports current state',
    () async {
      final repo = _Repository();
      final candidate = _candidate(
        'student-one',
        '0012',
        'one@example.invalid',
      );
      repo.directory[candidate.email] = candidate;
      final coordinator = ExcelImportCoordinator(repo);
      final review = await coordinator.review(
        course: _course(),
        sheet: _sheet([_row(2, '0012', candidate.email)]),
      );
      repo.enrollments[candidate.uid] = _enrollment(candidate);
      final active = await coordinator.confirm(
        course: _course(),
        selected: review.rows,
      );
      expect(active.alreadyEnrolled, 1);
      expect(repo.writeCalls, 0);
      repo.enrollments[candidate.uid] = _enrollment(
        candidate,
        status: 'withdrawn',
      );
      final withdrawn = await coordinator.confirm(
        course: _course(),
        selected: review.rows,
      );
      expect(withdrawn.withdrawn, 1);
      expect(
        repo.enrollments[candidate.uid]!.lastStatusEventId,
        'historic-event',
      );
      expect(repo.writeCalls, 0);
    },
  );

  test(
    'transaction race still reports existing enrollment without a write',
    () async {
      final repo = _Repository();
      final candidate = _candidate(
        'student-one',
        '0012',
        'one@example.invalid',
      );
      repo.directory[candidate.email] = candidate;
      final coordinator = ExcelImportCoordinator(repo);
      final review = await coordinator.review(
        course: _course(),
        sheet: _sheet([_row(2, '0012', candidate.email)]),
      );
      repo.beforeEnroll = (value) =>
          repo.enrollments[value.uid] = _enrollment(value);
      final result = await coordinator.confirm(
        course: _course(),
        selected: review.rows,
      );
      expect(result.alreadyEnrolled, 1);
      expect(repo.writeCalls, 0);
      expect(repo.resolvePendingOnExisting, isFalse);
    },
  );

  test('changed candidate and partial network failure stay separate', () async {
    final repo = _Repository();
    final first = _candidate('student-one', '0012', 'one@example.invalid');
    final second = _candidate('student-two', '0023', 'two@example.invalid');
    repo.directory.addAll({first.email: first, second.email: second});
    final coordinator = ExcelImportCoordinator(repo);
    final review = await coordinator.review(
      course: _course(),
      sheet: _sheet([
        _row(2, '0012', first.email),
        _row(3, '0023', second.email),
      ]),
    );
    repo.directory[first.email] = _candidate('new-uid', '0012', first.email);
    repo.failBeforeCreate = true;
    final result = await coordinator.confirm(
      course: _course(),
      selected: review.rows,
    );
    expect(result.needsReview, 1);
    expect(result.failed, 1);
    expect(repo.enrollments, isEmpty);
  });

  test('uncertain network result is reconciled by a fresh review', () async {
    final repo = _Repository()..failAfterCreate = true;
    final candidate = _candidate('student-one', '0012', 'one@example.invalid');
    repo.directory[candidate.email] = candidate;
    final coordinator = ExcelImportCoordinator(repo);
    final review = await coordinator.review(
      course: _course(),
      sheet: _sheet([_row(2, '0012', candidate.email)]),
    );
    final result = await coordinator.confirm(
      course: _course(),
      selected: review.rows,
    );
    expect(result.failed, 1);
    expect(repo.enrollments.length, 1);
    final refreshed = await coordinator.review(
      course: _course(),
      sheet: _sheet([_row(2, '0012', candidate.email)]),
    );
    expect(refreshed.rows.single.status, ExcelReviewStatus.alreadyEnrolled);
    expect(repo.writeCalls, 1);
  });

  test('other teacher and permission failure cannot review or write', () async {
    final repo = _Repository()..uid = 'other-teacher';
    final coordinator = ExcelImportCoordinator(repo);
    await expectLater(
      coordinator.review(course: _course(), sheet: _sheet([])),
      throwsA(
        isA<EnrollmentFailure>().having(
          (error) => error.kind,
          'kind',
          EnrollmentFailureKind.permissionDenied,
        ),
      ),
    );
    expect(repo.countCalls, 0);
    expect(repo.writeCalls, 0);
    repo.uid = 'teacher-one';
    repo.denyCount = true;
    await expectLater(
      coordinator.review(course: _course(), sheet: _sheet([])),
      throwsA(
        isA<EnrollmentFailure>().having(
          (error) => error.kind,
          'kind',
          EnrollmentFailureKind.permissionDenied,
        ),
      ),
    );
  });

  test('session switch after confirmed write preserves its result', () async {
    final repo = _Repository();
    final candidate = _candidate('student-one', '0012', 'one@example.invalid');
    repo.directory[candidate.email] = candidate;
    final coordinator = ExcelImportCoordinator(repo);
    final review = await coordinator.review(
      course: _course(),
      sheet: _sheet([_row(2, '0012', candidate.email)]),
    );
    repo.afterEnroll = () => repo.uid = 'other-teacher';
    final result = await coordinator.confirm(
      course: _course(),
      selected: review.rows,
    );
    expect(result.enrolledNow, 1);
    expect(repo.writeCalls, 1);
  });

  test('session switch before writing stops the selected row', () async {
    final repo = _Repository();
    final candidate = _candidate('student-one', '0012', 'one@example.invalid');
    repo.directory[candidate.email] = candidate;
    final coordinator = ExcelImportCoordinator(repo);
    final review = await coordinator.review(
      course: _course(),
      sheet: _sheet([_row(2, '0012', candidate.email)]),
    );
    repo.afterLookup = () => repo.uid = 'other-teacher';
    final result = await coordinator.confirm(
      course: _course(),
      selected: review.rows,
    );
    expect(result.failed, 1);
    expect(result.rows.single.message, contains('sesión'));
    expect(repo.writeCalls, 0);
  });

  test(
    'additions-only authorizes an unavailable account without full scan',
    () async {
      final repo = _Repository();
      final review = await ExcelImportCoordinator(repo).review(
        course: _course(),
        sheet: _sheet([_row(2, '0012', 'pending@example.invalid')]),
      );
      expect(repo.snapshotCalls, 0);
      expect(review.mode, ExcelImportMode.additionsOnly);
      expect(review.retirementsAllowed, isFalse);
      expect(review.potentialWithdrawals, isEmpty);
      expect(review.rows.single.action, ExcelReviewAction.authorizePending);
      expect(repo.pendingWriteCalls, 0);

      final result = await ExcelImportCoordinator(repo).confirm(
        course: _course(),
        selected: review.rows,
        effectiveDate: AcademicDate(year: 2026, month: 11, day: 14),
      );
      expect(result.pendingNow, 1);
      expect(repo.pendingWriteCalls, 1);
      expect(repo.pending['pending@example.invalid']?.status, 'pending');
      expect(repo.writeCalls, 0);
    },
  );

  test('full list proposes active and pending withdrawals but applies only selected', () async {
    final repo = _Repository();
    final active = _candidate('old-active', '0100', 'old@example.invalid');
    repo.enrollments[active.uid] = _enrollment(active);
    repo.pending['old-pending@example.invalid'] = _pending(
      'old-pending@example.invalid',
      '0200',
    );
    final coordinator = ExcelImportCoordinator(repo);
    final review = await coordinator.review(
      course: _course(),
      mode: ExcelImportMode.completeList,
      sheet: _sheet([_row(2, '0300', 'new@example.invalid')]),
    );
    expect(repo.snapshotCalls, 1);
    expect(review.retirementsAllowed, isTrue);
    expect(review.potentialWithdrawals, hasLength(2));
    expect(
      review.potentialWithdrawals.first.kind,
      ExcelRosterMemberKind.enrollment,
    );
    expect(
      review.potentialWithdrawals.last.kind,
      ExcelRosterMemberKind.pending,
    );
    expect(repo.enrollments[active.uid]?.status, 'active');
    expect(repo.pending['old-pending@example.invalid']?.status, 'pending');

    final result = await coordinator.confirm(
      course: _course(),
      review: review,
      selected: const [],
      selectedWithdrawals: [review.potentialWithdrawals.first],
      effectiveDate: AcademicDate(year: 2026, month: 11, day: 14),
    );
    expect(result.withdrawnNow, 1);
    expect(result.pendingWithdrawnNow, 0);
    expect(repo.enrollments[active.uid]?.status, 'withdrawn');
    expect(repo.pending['old-pending@example.invalid']?.status, 'pending');
  });

  test(
    'invalid rows, empty sheets and incomplete snapshots block retirements',
    () async {
      final active = _candidate('old-active', '0100', 'old@example.invalid');
      final repo = _Repository()..enrollments[active.uid] = _enrollment(active);
      final coordinator = ExcelImportCoordinator(repo);
      final invalid = await coordinator.review(
        course: _course(),
        mode: ExcelImportMode.completeList,
        sheet: _sheet([
          _row(2, '0200', 'new@example.invalid'),
          _row(3, '', 'broken@example.invalid', error: 'Falta el código.'),
        ]),
      );
      expect(invalid.retirementsAllowed, isFalse);
      expect(invalid.retirementBlockReason, contains('inválidas'));
      await expectLater(
        coordinator.confirm(
          course: _course(),
          review: invalid,
          selected: const [],
          selectedWithdrawals: invalid.potentialWithdrawals,
        ),
        throwsA(isA<EnrollmentFailure>()),
      );
      expect(repo.enrollments[active.uid]?.status, 'active');

      final empty = await coordinator.review(
        course: _course(),
        mode: ExcelImportMode.completeList,
        sheet: _sheet(const []),
      );
      expect(empty.retirementsAllowed, isFalse);
      expect(empty.retirementBlockReason, contains('vacía'));

      repo.incompleteSnapshot = true;
      final incomplete = await coordinator.review(
        course: _course(),
        mode: ExcelImportMode.completeList,
        sheet: _sheet([_row(2, '0200', 'new@example.invalid')]),
      );
      expect(incomplete.isComplete, isFalse);
      expect(incomplete.retirementsAllowed, isFalse);
      expect(incomplete.potentialWithdrawals, isEmpty);
      expect(incomplete.rows.single.selectable, isFalse);
    },
  );

  test('same student code with a different email is a conflict, never add plus retire', () async {
    final repo = _Repository();
    final existing = _candidate('existing', '0077', 'old@example.invalid');
    repo.enrollments[existing.uid] = _enrollment(existing);
    repo.directory['new@example.invalid'] = _candidate(
      'new-uid',
      '0077',
      'new@example.invalid',
    );
    final review = await ExcelImportCoordinator(repo).review(
      course: _course(),
      mode: ExcelImportMode.completeList,
      sheet: _sheet([_row(2, '0077', 'new@example.invalid')]),
    );
    expect(review.rows.single.status, ExcelReviewStatus.identityConflict);
    expect(review.rows.single.selectable, isFalse);
    expect(review.retirementsAllowed, isFalse);
    expect(review.potentialWithdrawals, isEmpty);
    expect(repo.writeCalls, 0);
    expect(repo.pendingWriteCalls, 0);
  });

  test(
    'a withdrawn pending entry reappears only as explicit reopen action',
    () async {
      final repo = _Repository()
        ..pending['return@example.invalid'] = _pending(
          'return@example.invalid',
          '0044',
          status: 'withdrawn',
        );
      final coordinator = ExcelImportCoordinator(repo);
      final review = await coordinator.review(
        course: _course(),
        sheet: _sheet([_row(2, '0044', 'return@example.invalid')]),
      );
      expect(review.rows.single.status, ExcelReviewStatus.reopenPending);
      expect(review.rows.single.action, ExcelReviewAction.reopenPending);
      expect(review.rows.single.selectable, isTrue);
      expect(repo.pending['return@example.invalid']?.status, 'withdrawn');

      final result = await coordinator.confirm(
        course: _course(),
        selected: review.rows,
        effectiveDate: AcademicDate(year: 2026, month: 11, day: 14),
      );
      expect(result.pendingReopened, 1);
      expect(repo.pending['return@example.invalid']?.status, 'pending');
    },
  );

  test(
    'future course batch uses separate start and withdrawal dates',
    () async {
      final course = _futureCourse();
      final today = _todayBogota();
      final active = _candidate(
        'future-active',
        '0100',
        'active@example.invalid',
      );
      final withdrawn = _candidate(
        'future-withdrawn',
        '0200',
        'return@example.invalid',
      );
      final added = _candidate('future-new', '0300', 'new@example.invalid');
      final repo = _Repository()
        ..directory[added.email] = added
        ..enrollments[active.uid] = _enrollment(active, courseId: course.id)
        ..enrollments[withdrawn.uid] = _enrollment(
          withdrawn,
          status: 'withdrawn',
          courseId: course.id,
        );
      final coordinator = ExcelImportCoordinator(repo);
      final review = await coordinator.review(
        course: course,
        mode: ExcelImportMode.completeList,
        sheet: _sheet([
          _row(2, '0200', withdrawn.email),
          _row(3, '0300', added.email),
        ]),
      );
      expect(review.retirementsAllowed, isTrue);
      expect(review.rows.map((row) => row.action), [
        ExcelReviewAction.rejoinEnrollment,
        ExcelReviewAction.enrollDirect,
      ]);
      expect(review.potentialWithdrawals.single.email, active.email);

      await expectLater(
        coordinator.confirm(
          course: course,
          review: review,
          selected: review.rows,
          selectedWithdrawals: review.potentialWithdrawals,
          effectiveStartDate: course.schedule.startDate,
          withdrawalEffectiveDate: today.addDays(1),
        ),
        throwsA(isA<EnrollmentFailure>()),
      );
      expect(repo.writeCalls, 0);
      expect(repo.enrollments[active.uid]?.status, 'active');

      final result = await coordinator.confirm(
        course: course,
        review: review,
        selected: review.rows,
        selectedWithdrawals: review.potentialWithdrawals,
        effectiveStartDate: course.schedule.startDate,
        withdrawalEffectiveDate: today,
      );
      expect(result.enrolledNow, 1);
      expect(result.rejoined, 1);
      expect(result.withdrawnNow, 1);
      expect(
        repo.enrollments[added.uid]?.effectiveStartDate,
        course.schedule.startDate,
      );
      expect(repo.enrollments[withdrawn.uid]?.status, 'active');
      expect(repo.enrollments[active.uid]?.status, 'withdrawn');
      expect(repo.enrollmentStartDates, [course.schedule.startDate]);
      expect(repo.statusChangeDates, contains(course.schedule.startDate));
      expect(repo.statusChangeDates, contains(today));
    },
  );

  test('one failed retirement does not erase a confirmed addition', () async {
    final repo = _Repository();
    final current = _candidate('current', '0100', 'current@example.invalid');
    final addition = _candidate('addition', '0200', 'addition@example.invalid');
    repo.enrollments[current.uid] = _enrollment(current);
    repo.directory[addition.email] = addition;
    final coordinator = ExcelImportCoordinator(repo);
    final review = await coordinator.review(
      course: _course(),
      mode: ExcelImportMode.completeList,
      sheet: _sheet([_row(2, '0200', addition.email)]),
    );
    expect(review.retirementsAllowed, isTrue);
    repo.failWithdrawalStudentUid = current.uid;

    final result = await coordinator.confirm(
      course: _course(),
      review: review,
      selected: review.rows,
      selectedWithdrawals: review.potentialWithdrawals,
      effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 14),
      withdrawalEffectiveDate: AcademicDate(year: 2026, month: 11, day: 14),
    );
    expect(result.enrolledNow, 1);
    expect(result.needsReview, 1);
    expect(result.failed, 0);
    expect(repo.enrollments[addition.uid]?.status, 'active');
    expect(repo.enrollments[current.uid]?.status, 'active');
  });
}
