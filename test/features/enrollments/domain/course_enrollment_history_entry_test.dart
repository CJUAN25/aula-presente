import 'package:aula_presente/features/enrollments/domain/course_enrollment_history_entry.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment_page.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active canonical enrollment produces an active history row', () {
    final enrollment = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 14),
      name: 'Canonical name',
    );

    final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(active: [enrollment]),
    );

    expect(rows, hasLength(1));
    expect(rows.single.enrollment, same(enrollment));
    expect(rows.single.pending, isNull);
    expect(rows.single.identityKey, 'roster:student@example.invalid');
    expect(rows.single.displayName, 'Canonical name');
    expect(rows.single.statusLabel, 'Activo');
    expect(rows.single.createdAt, enrollment.createdAt);
  });

  test(
    'withdrawn then re-enrolled identity remains one current canonical row',
    () {
      final withdrawn = _enrollment(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'withdrawn',
        createdAt: DateTime.utc(2026, 11, 14),
      );
      final reEnrolled = _enrollment(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'active',
        createdAt: DateTime.utc(2026, 11, 14),
      );

      final withdrawnRows = CourseEnrollmentHistoryEntry.fromSnapshot(
        _snapshot(withdrawn: [withdrawn]),
      );
      final reEnrolledRows = CourseEnrollmentHistoryEntry.fromSnapshot(
        _snapshot(active: [reEnrolled]),
      );

      expect(withdrawnRows, hasLength(1));
      expect(withdrawnRows.single.statusLabel, 'Retirado');
      expect(reEnrolledRows, hasLength(1));
      expect(reEnrolledRows.single.statusLabel, 'Activo');
      expect(
        reEnrolledRows.single.identityKey,
        withdrawnRows.single.identityKey,
      );
    },
  );

  test('active then withdrawn duplicate selects the later status version', () {
    final active = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 20),
    );
    final withdrawn = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'withdrawn',
      createdAt: DateTime.utc(2026, 11, 1),
      lastStatusChangedAt: DateTime.utc(2026, 11, 14, 10),
    );

    final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(active: [active], withdrawn: [withdrawn]),
    );

    expect(rows, hasLength(1));
    expect(rows.single.enrollment, same(withdrawn));
    expect(rows.single.statusLabel, 'Retirado');
  });

  test(
    'equal status-change timestamps use newer creation time as tie-break',
    () {
      final statusChangedAt = DateTime.utc(2026, 11, 14, 10);
      final older = _enrollment(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'active',
        createdAt: DateTime.utc(2026, 11, 1),
        lastStatusChangedAt: statusChangedAt,
      );
      final newer = _enrollment(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'withdrawn',
        createdAt: DateTime.utc(2026, 11, 2),
        lastStatusChangedAt: statusChangedAt,
      );

      final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
        _snapshot(active: [older], withdrawn: [newer]),
      );

      expect(rows, hasLength(1));
      expect(rows.single.enrollment, same(newer));
      expect(rows.single.statusLabel, 'Retirado');
    },
  );

  test('withdrawn then active duplicate selects the later status version', () {
    final withdrawn = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'withdrawn',
      createdAt: DateTime.utc(2026, 11, 1),
      lastStatusChangedAt: DateTime.utc(2026, 11, 14, 10),
    );
    final active = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 1),
      lastStatusChangedAt: DateTime.utc(2026, 11, 15, 10),
    );

    final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(active: [active], withdrawn: [withdrawn]),
    );

    expect(rows, hasLength(1));
    expect(rows.single.enrollment, same(active));
    expect(rows.single.statusLabel, 'Activo');
  });

  test(
    'conflicting canonical states with the same version time are rejected',
    () {
      final changedAt = DateTime.utc(2026, 11, 14, 10);
      final active = _enrollment(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'active',
        createdAt: DateTime.utc(2026, 11, 1),
        lastStatusChangedAt: changedAt,
      );
      final withdrawn = _enrollment(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'withdrawn',
        createdAt: DateTime.utc(2026, 11, 1),
        lastStatusChangedAt: changedAt,
      );

      expect(
        () => CourseEnrollmentHistoryEntry.fromSnapshot(
          _snapshot(active: [active], withdrawn: [withdrawn]),
        ),
        throwsStateError,
      );
    },
  );

  test('pending duplicate versions also select the latest status change', () {
    final reopened = _pending(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'pending',
      createdAt: DateTime.utc(2026, 11, 1),
      lastStatusChangedAt: DateTime.utc(2026, 11, 15, 10),
    );
    final withdrawn = _pending(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'withdrawn',
      createdAt: DateTime.utc(2026, 11, 1),
      lastStatusChangedAt: DateTime.utc(2026, 11, 14, 10),
    );

    final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(pending: [reopened], withdrawnPending: [withdrawn]),
    );

    expect(rows, hasLength(1));
    expect(rows.single.pending, same(reopened));
    expect(rows.single.statusLabel, 'Pendiente de vincular');
  });

  test('pending authorization appears without an enrollment', () {
    final authorization = _pending(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'pending',
      createdAt: DateTime.utc(2026, 11, 14),
    );

    final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(pending: [authorization]),
    );

    expect(rows, hasLength(1));
    expect(rows.single.enrollment, isNull);
    expect(rows.single.pending, same(authorization));
    expect(rows.single.identityKey, 'roster:student@example.invalid');
    expect(rows.single.displayName, authorization.name);
    expect(rows.single.statusLabel, 'Pendiente de vincular');
    expect(rows.single.createdAt, authorization.createdAt);
  });

  test('withdrawn pending authorization has its own status label', () {
    final authorization = _pending(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'withdrawn',
      createdAt: DateTime.utc(2026, 11, 14),
    );

    final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(withdrawnPending: [authorization]),
    );

    expect(rows, hasLength(1));
    expect(rows.single.statusLabel, 'Autorización retirada');
  });

  test(
    'canonical enrollment wins over pending and linked is not a second row',
    () {
      final canonical = _enrollment(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'active',
        createdAt: DateTime.utc(2026, 11, 14),
        name: 'Canonical name',
      );
      final pending = _pending(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'pending',
        createdAt: DateTime.utc(2026, 11, 13),
        name: 'Pending name',
      );
      final linked = _pending(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'linked',
        studentUid: 'student-one',
        linkedAt: DateTime.utc(2026, 11, 14),
        createdAt: DateTime.utc(2026, 11, 12),
      );

      final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
        _snapshot(active: [canonical], pending: [pending, linked]),
      );

      expect(rows, hasLength(1));
      expect(rows.single.enrollment, same(canonical));
      expect(rows.single.pending, isNull);
      expect(rows.single.displayName, 'Canonical name');
      expect(rows.single.statusLabel, 'Activo');
    },
  );

  test(
    'legacy roster identity falls back to UID without email association',
    () {
      final legacy = _enrollment(
        courseId: 'course-a',
        rosterEntryId: 'legacy:student-one',
        status: 'active',
        createdAt: DateTime.utc(2026, 11, 14),
        name: 'Same visible name',
        email: 'student@example.invalid',
      );
      final authorization = _pending(
        courseId: 'course-a',
        rosterEntryId: 'student@example.invalid',
        status: 'pending',
        createdAt: DateTime.utc(2026, 11, 13),
        name: 'Same visible name',
        email: 'student@example.invalid',
      );

      final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
        _snapshot(active: [legacy], pending: [authorization]),
      );

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.identityKey), [
        'uid:student-one',
        'roster:student@example.invalid',
      ]);
      expect(rows.map((row) => row.statusLabel), [
        'Activo',
        'Pendiente de vincular',
      ]);
    },
  );

  test('separate course snapshots keep the same roster identity isolated', () {
    final courseA = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 14),
    );
    final courseB = _enrollment(
      courseId: 'course-b',
      rosterEntryId: 'student@example.invalid',
      status: 'withdrawn',
      createdAt: DateTime.utc(2026, 11, 14),
    );

    final rowsA = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(active: [courseA]),
    );
    final rowsB = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(withdrawn: [courseB]),
    );

    expect(rowsA, hasLength(1));
    expect(rowsB, hasLength(1));
    expect(rowsA.single.enrollment!.courseId, 'course-a');
    expect(rowsB.single.enrollment!.courseId, 'course-b');
    expect(rowsA.single.identityKey, rowsB.single.identityKey);
  });

  test('rejects entries from different courses in one roster snapshot', () {
    final courseA = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'student@example.invalid',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 14),
    );
    final courseB = _pending(
      courseId: 'course-b',
      rosterEntryId: 'other@example.invalid',
      status: 'pending',
      createdAt: DateTime.utc(2026, 11, 14),
      email: 'other@example.invalid',
    );

    expect(
      () => CourseEnrollmentHistoryEntry.fromSnapshot(
        _snapshot(active: [courseA], pending: [courseB]),
      ),
      throwsStateError,
    );
  });

  test('sorts by creation descending and identity key on ties', () {
    final oldest = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'z@example.invalid',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 10),
    );
    final tiedB = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'b@example.invalid',
      status: 'active',
      createdAt: DateTime.utc(2026, 11, 14),
    );
    final tiedA = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'a@example.invalid',
      status: 'withdrawn',
      createdAt: DateTime.utc(2026, 11, 14),
    );
    final noDate = _enrollment(
      courseId: 'course-a',
      rosterEntryId: 'no-date@example.invalid',
      status: 'active',
      createdAt: null,
    );

    final rows = CourseEnrollmentHistoryEntry.fromSnapshot(
      _snapshot(active: [oldest, tiedB, noDate], withdrawn: [tiedA]),
    );

    expect(rows.map((row) => row.identityKey), [
      'roster:a@example.invalid',
      'roster:b@example.invalid',
      'roster:z@example.invalid',
      'roster:no-date@example.invalid',
    ]);
  });

  test('rejects an incomplete course roster snapshot', () {
    expect(
      () =>
          CourseEnrollmentHistoryEntry.fromSnapshot(_snapshot(complete: false)),
      throwsStateError,
    );
  });
}

CourseRosterSnapshot _snapshot({
  List<Enrollment> active = const [],
  List<Enrollment> withdrawn = const [],
  List<PendingEnrollment> pending = const [],
  List<PendingEnrollment> withdrawnPending = const [],
  bool complete = true,
}) => CourseRosterSnapshot(
  activeEnrollments: active,
  withdrawnEnrollments: withdrawn,
  pendingEnrollments: pending,
  withdrawnPendingEnrollments: withdrawnPending,
  complete: complete,
);

Enrollment _enrollment({
  required String courseId,
  required String? rosterEntryId,
  required String status,
  required DateTime? createdAt,
  DateTime? lastStatusChangedAt,
  String studentUid = 'student-one',
  String email = 'student@example.invalid',
  String name = 'Student One',
}) => Enrollment(
  courseId: courseId,
  studentUid: studentUid,
  ownerUid: 'teacher-one',
  name: name,
  email: email,
  studentCode: '0012',
  subject: 'Course',
  group: 'G1',
  period: '2026-2',
  status: status,
  createdAt: createdAt,
  rosterEntryId: rosterEntryId,
  lastStatusChangedAt: lastStatusChangedAt,
);

PendingEnrollment _pending({
  required String courseId,
  required String rosterEntryId,
  required String status,
  required DateTime createdAt,
  DateTime? lastStatusChangedAt,
  String email = 'student@example.invalid',
  String name = 'Student One',
  String? studentUid,
  DateTime? linkedAt,
}) => PendingEnrollment(
  courseId: courseId,
  ownerUid: 'teacher-one',
  subject: 'Course',
  group: 'G1',
  period: '2026-2',
  email: email,
  studentCode: '0012',
  name: name,
  status: status,
  effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 14),
  rosterEntryId: rosterEntryId,
  studentUid: studentUid,
  authorizedAt: createdAt,
  linkedAt: linkedAt,
  createdAt: createdAt,
  updatedAt: createdAt,
  lastEventId: null,
  lastStatusChangedAt: lastStatusChangedAt,
);
