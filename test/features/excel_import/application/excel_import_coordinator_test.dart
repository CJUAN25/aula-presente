import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_failure.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_page.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_repository.dart';
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
}) => Enrollment(
  courseId: 'course-one',
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
  lastStatusEventId: status == 'withdrawn' ? 'historic-event' : null,
  lastStatusChangedAt: status == 'withdrawn' ? DateTime.utc(2026, 11, 2) : null,
);

class _Repository implements EnrollmentRepository {
  String? uid = 'teacher-one';
  final directory = <String, StudentCandidate>{};
  final enrollments = <String, Enrollment>{};
  int countCalls = 0;
  int writeCalls = 0;
  bool? resolvePendingOnExisting;
  bool denyCount = false;
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
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
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
    final created = _enrollment(candidate);
    enrollments[candidate.uid] = created;
    afterEnroll?.call();
    if (failAfterCreate) {
      throw const EnrollmentFailure(EnrollmentFailureKind.network);
    }
    return EnrollmentResult(enrollment: created, alreadyEnrolled: false);
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
      ExcelReviewStatus.withdrawn,
      ExcelReviewStatus.unavailable,
      ExcelReviewStatus.invalid,
    ]);
    expect(review.eligibleCount, 1);
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
}
