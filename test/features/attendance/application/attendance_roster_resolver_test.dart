import 'package:aula_presente/features/attendance/application/attendance_roster_resolver.dart';
import 'package:aula_presente/features/attendance/domain/attendance_roster.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_status_change.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/pending_enrollment_page.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rescheduled effective date includes enrollment on day 14 for class on day 15', () {
    final snapshot = _snapshot(
      active: [_enrollment(effectiveStartDate: _date(14))],
    );
    expect(_resolve(snapshot: snapshot, date: _date(13)).entries, isEmpty);
    expect(
      _resolve(snapshot: snapshot, date: _date(15)).entries.single.studentUid,
      'uid-1',
    );
    expect(_resolve(snapshot: snapshot, date: _date(20)).entries, hasLength(1));
  });
  test('canonical enrollment includes start and rejoin dates, excludes withdrawal date', () {
    final start = _date(1);
    final withdrawalDate = _date(10);
    final rejoinDate = _date(20);
    final withdrewAt = DateTime.utc(2026, 11, 10, 16);
    final rejoinedAt = DateTime.utc(2026, 11, 20, 16);
    final events = [
      _enrollmentEvent(
        id: 'withdraw-1',
        from: 'active',
        to: 'withdrawn',
        date: withdrawalDate,
        changedAt: withdrewAt,
      ),
      _enrollmentEvent(
        id: 'rejoin-1',
        from: 'withdrawn',
        to: 'active',
        date: rejoinDate,
        changedAt: rejoinedAt,
      ),
    ];
    final enrollment = _enrollment(
      status: 'active',
      rosterEntryId: 'student@example.invalid',
      effectiveStartDate: start,
      lastStatusEventId: 'rejoin-1',
      lastStatusChangedAt: rejoinedAt,
    );

    expect(
      _resolve(
        snapshot: _snapshot(active: [enrollment]),
        date: _date(1),
        enrollmentEvents: events,
      ).entries,
      hasLength(1),
    );
    expect(
      _resolve(
        snapshot: _snapshot(active: [enrollment]),
        date: _date(9),
        enrollmentEvents: events,
      ).entries,
      hasLength(1),
    );
    expect(
      _resolve(
        snapshot: _snapshot(active: [enrollment]),
        date: _date(10),
        enrollmentEvents: events,
      ).entries,
      isEmpty,
    );
    expect(
      _resolve(
        snapshot: _snapshot(active: [enrollment]),
        date: _date(19),
        enrollmentEvents: events,
      ).entries,
      isEmpty,
    );
    expect(
      _resolve(
        snapshot: _snapshot(active: [enrollment]),
        date: _date(20),
        enrollmentEvents: events,
      ).entries,
      hasLength(1),
    );
    expect(
      _resolve(
        snapshot: _snapshot(active: [enrollment]),
        date: AcademicDate(year: 2026, month: 12, day: 1),
        enrollmentEvents: events,
      ).entries,
      hasLength(1),
    );
  });

  test('pending authorization re-entry uses effective event dates', () {
    final start = _date(1);
    final withdrawalDate = _date(10);
    final rejoinDate = _date(20);
    final withdrewAt = DateTime.utc(2026, 11, 10, 16);
    final rejoinedAt = DateTime.utc(2026, 11, 20, 16);
    final pending = _pending(
      status: 'pending',
      effectiveStartDate: rejoinDate,
      lastEventId: 'pending-rejoin',
      lastStatusChangedAt: rejoinedAt,
    );
    final events = [
      _pendingEvent(
        id: 'pending-withdraw',
        from: 'pending',
        to: 'withdrawn',
        date: withdrawalDate,
        previousStart: start,
        changedAt: withdrewAt,
      ),
      _pendingEvent(
        id: 'pending-rejoin',
        from: 'withdrawn',
        to: 'pending',
        date: rejoinDate,
        previousStart: start,
        changedAt: rejoinedAt,
      ),
    ];
    final snapshot = _snapshot(pending: [pending]);

    expect(
      _resolve(
        snapshot: snapshot,
        date: _date(1),
        pendingEvents: events,
      ).entries,
      hasLength(1),
    );
    expect(
      _resolve(
        snapshot: snapshot,
        date: _date(10),
        pendingEvents: events,
      ).entries,
      isEmpty,
    );
    expect(
      _resolve(
        snapshot: snapshot,
        date: _date(19),
        pendingEvents: events,
      ).entries,
      isEmpty,
    );
    expect(
      _resolve(
        snapshot: snapshot,
        date: _date(20),
        pendingEvents: events,
      ).entries,
      hasLength(1),
    );
  });

  test('legacy pending re-entry without prior start data requires review before boundary', () {
    final boundary = _date(20);
    final changedAt = DateTime.utc(2026, 11, 20, 16);
    final pending = _pending(
      status: 'pending',
      effectiveStartDate: boundary,
      lastEventId: 'legacy-rejoin',
      lastStatusChangedAt: changedAt,
    );
    final events = [
      _pendingEvent(
        id: 'legacy-withdraw',
        from: 'pending',
        to: 'withdrawn',
        date: _date(10),
        changedAt: DateTime.utc(2026, 11, 10, 16),
      ),
      _pendingEvent(
        id: 'legacy-rejoin',
        from: 'withdrawn',
        to: 'pending',
        date: boundary,
        changedAt: changedAt,
      ),
    ];
    final snapshot = _snapshot(pending: [pending]);
    final beforeBoundary = _resolve(
      snapshot: snapshot,
      date: _date(15),
      pendingEvents: events,
    );
    final atBoundary = _resolve(
      snapshot: snapshot,
      date: boundary,
      pendingEvents: events,
    );

    expect(beforeBoundary.canPrepareSession, isFalse);
    expect(
      beforeBoundary.issues.single.kind,
      AttendanceRosterIssueKind.needsReview,
    );
    expect(atBoundary.canPrepareSession, isTrue);
    expect(atBoundary.entries, hasLength(1));
  });

  test(
    'legacy identity falls back to legacy:uid and Bogota civil creation date',
    () {
      final enrollment = _enrollment(
        rosterEntryId: null,
        effectiveStartDate: null,
        createdAt: DateTime.utc(2026, 11, 2, 2), // Nov 1 in Bogota.
      );

      final onBogotaDay = _resolve(
        snapshot: _snapshot(active: [enrollment]),
        date: _date(1),
      );
      final beforeBogotaDay = _resolve(
        snapshot: _snapshot(active: [enrollment]),
        date: _date(31, month: 10),
      );

      expect(onBogotaDay.entries.single.rosterEntryId, 'legacy:uid-1');
      expect(beforeBogotaDay.entries, isEmpty);
    },
  );

  test(
    'linked modern authorization is one roster identity across link date',
    () {
      final linkedAt = DateTime.utc(2026, 11, 15, 5); // Nov 15 in Bogota.
      final linkedDate = _date(15);
      final linkEvent = _pendingEvent(
        id: 'linked-event',
        from: 'pending',
        to: 'linked',
        date: linkedDate,
        previousStart: _date(1),
        changedAt: linkedAt,
      );
      final enrollment = _enrollment(
        rosterEntryId: 'student@example.invalid',
        effectiveStartDate: _date(1),
        createdAt: linkedAt,
      );
      final linked = _pending(
        status: 'linked',
        studentUid: 'uid-1',
        linkedAt: linkedAt,
        effectiveStartDate: _date(1),
        lastEventId: 'linked-event',
        lastStatusChangedAt: linkedAt,
      );
      final snapshot = _snapshot(active: [enrollment]);

      for (final date in [_date(10), linkedDate, _date(16)]) {
        final resolved = _resolve(
          snapshot: snapshot,
          date: date,
          linkedByUid: {'uid-1': linked},
          pendingEvents: [linkEvent],
        );
        expect(resolved.canPrepareSession, isTrue);
        expect(resolved.entries, hasLength(1));
        expect(
          resolved.entries.single.rosterEntryId,
          'student@example.invalid',
        );
      }
    },
  );

  test('linked legacy authorization retains pre-link period and canonical fallback ID', () {
    final linkedAt = DateTime.utc(2026, 11, 15, 5);
    final start = _date(1);
    final linkDate = _date(15);
    final withdrewAt = DateTime.utc(2026, 11, 10, 16);
    final rejoinedAt = DateTime.utc(2026, 11, 13, 16);
    final events = [
      _pendingEvent(
        id: 'withdraw-old',
        from: 'pending',
        to: 'withdrawn',
        date: _date(10),
        previousStart: start,
        changedAt: withdrewAt,
      ),
      _pendingEvent(
        id: 'reopen-old',
        from: 'withdrawn',
        to: 'pending',
        date: _date(13),
        previousStart: start,
        changedAt: rejoinedAt,
      ),
      _pendingEvent(
        id: 'link-now',
        from: 'pending',
        to: 'linked',
        date: linkDate,
        previousStart: _date(13),
        changedAt: linkedAt,
      ),
    ];
    final enrollment = _enrollment(
      rosterEntryId: null,
      effectiveStartDate: null,
      createdAt: linkedAt,
    );
    final linked = _pending(
      status: 'linked',
      studentUid: 'uid-1',
      linkedAt: linkedAt,
      effectiveStartDate: _date(13),
      lastEventId: 'link-now',
      lastStatusChangedAt: linkedAt,
    );
    final snapshot = _snapshot(active: [enrollment]);

    expect(
      _resolve(
        snapshot: snapshot,
        date: _date(9),
        linkedByUid: {'uid-1': linked},
        pendingEvents: events,
      ).entries,
      hasLength(1),
    );
    expect(
      _resolve(
        snapshot: snapshot,
        date: _date(10),
        linkedByUid: {'uid-1': linked},
        pendingEvents: events,
      ).entries,
      isEmpty,
    );
    final rejoinedBeforeLink = _resolve(
      snapshot: snapshot,
      date: _date(13),
      linkedByUid: {'uid-1': linked},
      pendingEvents: events,
    );
    final onLinkDate = _resolve(
      snapshot: snapshot,
      date: linkDate,
      linkedByUid: {'uid-1': linked},
      pendingEvents: events,
    );

    expect(rejoinedBeforeLink.entries.single.rosterEntryId, 'legacy:uid-1');
    expect(onLinkDate.entries.single.rosterEntryId, 'legacy:uid-1');
    expect(onLinkDate.entries, hasLength(1));
  });

  test('an incomplete course roster cannot be resolved', () {
    expect(
      () => _resolve(snapshot: _snapshot(complete: false), date: _date(1)),
      throwsA(isA<AttendanceRosterResolutionFailure>()),
    );
  });
}

AttendanceRosterResolution _resolve({
  required CourseRosterSnapshot snapshot,
  required AcademicDate date,
  List<EnrollmentStatusEvent> enrollmentEvents = const [],
  List<PendingEnrollmentStatusEvent> pendingEvents = const [],
  Map<String, PendingEnrollment> linkedByUid = const {},
}) => AttendanceRosterResolver.resolveForDate(
  snapshot: snapshot,
  enrollmentEventsByStudentUid: {'uid-1': enrollmentEvents},
  pendingEventsByEmail: {'student@example.invalid': pendingEvents},
  linkedAuthorizationsByStudentUid: linkedByUid,
  effectiveDate: date,
);

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
  String status = 'active',
  String? rosterEntryId = 'student@example.invalid',
  AcademicDate? effectiveStartDate,
  DateTime? createdAt,
  String? lastStatusEventId,
  DateTime? lastStatusChangedAt,
}) => Enrollment(
  courseId: 'course-1',
  studentUid: 'uid-1',
  ownerUid: 'teacher-1',
  name: 'Estudiante Uno',
  email: 'student@example.invalid',
  studentCode: '000123',
  subject: 'Matemáticas',
  group: 'A',
  period: '2026-2',
  status: status,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 1, 15),
  rosterEntryId: rosterEntryId,
  effectiveStartDate: effectiveStartDate,
  lastStatusEventId: lastStatusEventId,
  lastStatusChangedAt: lastStatusChangedAt,
);

PendingEnrollment _pending({
  String status = 'pending',
  String? studentUid,
  DateTime? linkedAt,
  AcademicDate? effectiveStartDate,
  String? lastEventId,
  DateTime? lastStatusChangedAt,
}) => PendingEnrollment(
  courseId: 'course-1',
  ownerUid: 'teacher-1',
  subject: 'Matemáticas',
  group: 'A',
  period: '2026-2',
  email: 'student@example.invalid',
  studentCode: '000123',
  name: 'Estudiante Uno',
  status: status,
  effectiveStartDate: effectiveStartDate ?? _date(1),
  rosterEntryId: 'student@example.invalid',
  studentUid: studentUid,
  authorizedAt: DateTime.utc(2026, 10, 1),
  linkedAt: linkedAt,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: linkedAt ?? DateTime.utc(2026, 10, 1),
  lastEventId: lastEventId,
  lastStatusChangedAt: lastStatusChangedAt,
);

EnrollmentStatusEvent _enrollmentEvent({
  required String id,
  required String from,
  required String to,
  required AcademicDate date,
  required DateTime changedAt,
}) => EnrollmentStatusEvent(
  operationId: id,
  fromStatus: from,
  toStatus: to,
  effectiveDate: date,
  changedAt: changedAt,
  changedBy: 'teacher-1',
);

PendingEnrollmentStatusEvent _pendingEvent({
  required String id,
  required String from,
  required String to,
  required AcademicDate date,
  AcademicDate? previousStart,
  required DateTime changedAt,
}) => PendingEnrollmentStatusEvent(
  operationId: id,
  fromStatus: from,
  toStatus: to,
  effectiveDate: date,
  fromEffectiveStartDate: previousStart,
  changedAt: changedAt,
  changedBy: 'teacher-1',
);

AcademicDate _date(int day, {int month = 11}) =>
    AcademicDate(year: 2026, month: month, day: day);
