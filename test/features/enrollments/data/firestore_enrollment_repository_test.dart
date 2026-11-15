import 'package:aula_presente/features/enrollments/data/firestore_enrollment_repository.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment_failure.dart';
import 'package:aula_presente/features/enrollments/domain/enrollment.dart';
import 'package:aula_presente/features/enrollments/domain/student_candidate.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'student query filters own UID and continues beyond 25 results',
    () async {
      final store = _Store();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth(),
        firestore: store,
      );

      final first = await repository.listMyCourses(pageSize: 25);
      expect(first.items, hasLength(25));
      expect(first.hasMore, isTrue);
      expect(first.items.first.studentUid, 'student-one');
      expect(first.items.first.courseId, 'course-00');
      expect(store.uidFilters, ['student-one']);
      expect(store.statusFilters, ['active']);
      expect(store.serverReads, contains('users/student-one'));
      expect(store.serverReads, contains('enrollments'));

      final second = await repository.listMyCourses(
        pageSize: 25,
        cursor: first.nextCursor,
      );
      expect(second.items, hasLength(1));
      expect(second.items.single.courseId, 'course-25');
      expect(second.hasMore, isFalse);
      expect(store.uidFilters, ['student-one', 'student-one']);
      expect(store.statusFilters, ['active', 'active']);
      expect(store.startAfters.single.last, first.nextCursor!.documentPath);
    },
  );

  test('account change during query discards previous account data', () async {
    final auth = _Auth();
    final store = _Store()..onQuery = () => auth.user = null;
    final repository = FirestoreEnrollmentRepository(
      auth: auth,
      firestore: store,
    );
    await expectLater(
      repository.listMyCourses(),
      throwsA(
        isA<EnrollmentFailure>().having(
          (error) => error.kind,
          'kind',
          EnrollmentFailureKind.unauthenticated,
        ),
      ),
    );
  });

  test('course student list can request withdrawn status explicitly', () async {
    final store = _Store();
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );

    final page = await repository.listCourseStudents(
      courseId: 'course-00',
      status: 'withdrawn',
    );

    expect(page.items, isNotEmpty);
    expect(page.items.every((item) => item.status == 'withdrawn'), isTrue);
    expect(store.statusFilters, ['withdrawn']);
  });

  test('student can read only their own canonical enrollment', () async {
    final store = _Store()..existingEnrollment = _activeEnrollment();
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth(),
      firestore: store,
    );

    final enrollment = await repository.getCourseEnrollment(
      courseId: 'course-00',
      studentUid: 'student-one',
    );

    expect(enrollment.studentUid, 'student-one');
    expect(enrollment.ownerUid, 'teacher-one');
    expect(store.serverReads, contains('users/student-one'));
  });

  test('teacher can read an enrollment only when they own it', () async {
    final store = _Store()..existingEnrollment = _activeEnrollment();
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );

    final enrollment = await repository.getCourseEnrollment(
      courseId: 'course-00',
      studentUid: 'student-one',
    );

    expect(enrollment.ownerUid, 'teacher-one');
  });

  test(
    'student role cannot read another UID enrollment through owner match',
    () async {
      final store = _Store()
        ..enrollmentDocuments['courses/course-00/enrollments/other-student'] = {
          ..._activeEnrollment(),
          'studentUid': 'other-student',
          'ownerUid': 'student-one',
        };
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth(),
        firestore: store,
      );

      await expectLater(
        repository.getCourseEnrollment(
          courseId: 'course-00',
          studentUid: 'other-student',
        ),
        throwsA(
          isA<EnrollmentFailure>().having(
            (failure) => failure.kind,
            'kind',
            EnrollmentFailureKind.permissionDenied,
          ),
        ),
      );
    },
  );

  test(
    'valid student profile cannot read an enrollment for another student',
    () async {
      final store = _Store()
        ..profiles['users/other-student'] = {
          'name': 'Other Student',
          'email': 'other@example.invalid',
          'studentCode': null,
          'roles': ['student'],
        }
        ..existingEnrollment = _activeEnrollment();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _OtherStudentUser(),
        firestore: store,
      );

      await expectLater(
        repository.getCourseEnrollment(
          courseId: 'course-00',
          studentUid: 'student-one',
        ),
        throwsA(
          isA<EnrollmentFailure>().having(
            (failure) => failure.kind,
            'kind',
            EnrollmentFailureKind.permissionDenied,
          ),
        ),
      );
    },
  );

  test('malformed profile cannot read an enrollment', () async {
    final store = _Store()
      ..profiles['users/student-one'] = {
        'name': 'Student One',
        'email': 'wrong@example.invalid',
        'studentCode': '0012',
        'roles': ['student'],
      }
      ..existingEnrollment = _activeEnrollment();
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth(),
      firestore: store,
    );

    await expectLater(
      repository.getCourseEnrollment(
        courseId: 'course-00',
        studentUid: 'student-one',
      ),
      throwsA(
        isA<EnrollmentFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnrollmentFailureKind.profileInvalid,
        ),
      ),
    );
    expect(
      store.serverReads,
      isNot(contains('courses/course-00/enrollments/student-one')),
    );
  });

  test(
    'directory publication uses verified profile and server timestamp',
    () async {
      final store = _Store();
      final auth = _Auth();
      final repository = FirestoreEnrollmentRepository(
        auth: auth,
        firestore: store,
      );
      await repository.ensureStudentDirectoryEntry();
      expect(store.writtenPath, 'student_directory/student@example.invalid');
      expect(store.writtenFields!.keys.toSet(), {
        'uid',
        'name',
        'email',
        'studentCode',
        'updatedAt',
      });
      expect(store.writtenFields!['uid'], 'student-one');
      expect(store.writtenFields!['studentCode'], '0012');
      expect(store.writtenFields!['updatedAt'], isA<FieldValue>());
    },
  );

  test(
    'enrollment transaction writes once and retry returns existing ID',
    () async {
      final store = _Store();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );
      const candidate = StudentCandidate(
        uid: 'student-one',
        name: 'Student One',
        email: 'student@example.invalid',
        studentCode: '0012',
      );

      final first = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: candidate,
      );
      expect(first.alreadyEnrolled, isFalse);
      expect(first.enrollment.createdAt, isNull);
      expect(store.transactionWriteCount, 1);
      expect(
        store.transactionWritePath,
        'courses/course-00/enrollments/student-one',
      );
      expect(store.transactionWrite!.keys.toSet(), {
        'studentUid',
        'ownerUid',
        'name',
        'email',
        'studentCode',
        'subject',
        'group',
        'period',
        'status',
        'rosterEntryId',
        'effectiveStartDate',
        'createdAt',
      });
      expect(store.transactionWrite!['createdAt'], isA<FieldValue>());
      expect(store.transactionReads, [
        'courses/course-00',
        'courses/course-00/enrollments/student-one',
        'courses/course-00/join_requests/student-one',
        'courses/course-00/pending_enrollments/student@example.invalid',
        'courses/course-00/pending_enrollments/student@example.invalid/status_events/link',
        'student_directory/student@example.invalid',
      ]);

      store.transactionReads.clear();
      store.directoryAvailable = false;
      final again = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: candidate,
      );
      expect(again.alreadyEnrolled, isTrue);
      expect(again.enrollment.studentUid, 'student-one');
      expect(again.enrollment.createdAt, isNotNull);
      expect(store.transactionWriteCount, 1);
      expect(store.transactionReads, [
        'courses/course-00',
        'courses/course-00/enrollments/student-one',
        'courses/course-00/join_requests/student-one',
        'courses/course-00/pending_enrollments/student@example.invalid',
        'courses/course-00/pending_enrollments/student@example.invalid/status_events/link',
      ]);
    },
  );

  test('manual enrollment approves an exact request despite display-name differences', () async {
    final store = _Store()..joinRequest = _matchingJoinRequest();
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );

    final result = await repository.enrollStudent(
      courseId: 'course-00',
      candidate: const StudentCandidate(
        uid: 'student-one',
        name: 'Student One',
        email: 'student@example.invalid',
        studentCode: '0012',
      ),
    );

    expect(result.alreadyEnrolled, isFalse);
    expect(
      store.transactionUpdatePath,
      'courses/course-00/join_requests/student-one',
    );
    expect(store.transactionUpdate, {
      'status': 'approved',
      'decidedBy': 'teacher-one',
      'decidedAt': isA<FieldValue>(),
      'rejectionReason': null,
    });
    expect(store.joinRequest!['status'], 'approved');
    expect(
      store.transactionWritePath,
      'courses/course-00/enrollments/student-one',
    );
    expect(store.transactionWriteCount, 1);
  });

  test(
    'manual enrollment leaves an identity-mismatched request pending',
    () async {
      final store = _Store()
        ..joinRequest = {
          ..._matchingJoinRequest(),
          'studentCode': 'different-code',
        };
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );

      final result = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: const StudentCandidate(
          uid: 'student-one',
          name: 'Student One',
          email: 'student@example.invalid',
          studentCode: '0012',
        ),
      );

      expect(result.alreadyEnrolled, isFalse);
      expect(store.existingEnrollment, isNotNull);
      expect(store.joinRequest!['status'], 'pending');
      expect(store.transactionUpdatePath, isNull);
    },
  );

  test('manual enrollment preserves a prior rejected request', () async {
    final store = _Store()
      ..joinRequest = {
        'studentUid': 'student-one',
        'status': 'rejected',
        'rejectionReason': 'Grupo completo',
      };
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );

    await repository.enrollStudent(
      courseId: 'course-00',
      candidate: const StudentCandidate(
        uid: 'student-one',
        name: 'Student One',
        email: 'student@example.invalid',
        studentCode: '0012',
      ),
    );

    expect(store.transactionUpdatePath, isNull);
    expect(store.joinRequest!['status'], 'rejected');
    expect(store.joinRequest!['rejectionReason'], 'Grupo completo');
  });

  test('teacher authorizes an exact pending roster identity atomically', () async {
    final store = _Store()..directoryAvailable = false;
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );

    final result = await repository.authorizePendingEnrollment(
      course: _courseModel(),
      email: 'student@example.invalid',
      studentCode: '0012',
      name: 'Roster Student',
      effectiveStartDate: AcademicDate(year: 2026, month: 11, day: 14),
    );

    expect(result.created, isTrue);
    final pending = store
        .pendingDocuments['courses/course-00/pending_enrollments/student@example.invalid']!;
    expect(pending.keys.toSet(), {
      'courseId',
      'ownerUid',
      'subject',
      'group',
      'period',
      'email',
      'studentCode',
      'name',
      'status',
      'effectiveStartDate',
      'rosterEntryId',
      'studentUid',
      'authorizedAt',
      'linkedAt',
      'createdAt',
      'updatedAt',
      'lastEventId',
      'lastStatusChangedAt',
    });
    expect(pending['email'], 'student@example.invalid');
    expect(pending['rosterEntryId'], 'student@example.invalid');
    expect(pending['studentUid'], isNull);
    expect(pending['status'], 'pending');
    expect(pending['authorizedAt'], isA<Timestamp>());
    expect(store.transactionWriteCount, 1);
    expect(store.transactionReads, [
      'courses/course-00',
      'student_directory/student@example.invalid',
      'courses/course-00/pending_enrollments/student@example.invalid',
    ]);
  });

  test(
    'manual enrollment reconciles its exact pending row in one transaction',
    () async {
      const pendingPath =
          'courses/course-00/pending_enrollments/student@example.invalid';
      final store = _Store()
        ..pendingDocuments[pendingPath] = _pendingEnrollmentDocument();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );

      final result = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: const StudentCandidate(
          uid: 'student-one',
          name: 'Student One',
          email: 'student@example.invalid',
          studentCode: '0012',
        ),
      );

      expect(result.alreadyEnrolled, isFalse);
      expect(result.enrollment.name, 'Roster Student');
      expect(store.pendingDocuments[pendingPath]!['status'], 'linked');
      expect(store.pendingDocuments[pendingPath]!['studentUid'], 'student-one');
      expect(
        store.existingEnrollment?['rosterEntryId'],
        'student@example.invalid',
      );
      expect(store.existingEnrollment?['effectiveStartDate'], isA<Timestamp>());
      expect(store.existingEnrollment?['name'], 'Roster Student');
      expect(
        store.transactionWritePaths,
        contains('$pendingPath/status_events/link'),
      );
      expect(store.transactionUpdatePaths, contains(pendingPath));
      expect(
        store.transactionWritePaths,
        contains('courses/course-00/enrollments/student-one'),
      );
    },
  );

  test('verified student links exact pending and matching request despite name difference', () async {
    final store = _Store()
      ..pendingDocuments['courses/course-00/pending_enrollments/student@example.invalid'] =
          _pendingEnrollmentDocument()
      ..joinRequest = _matchingJoinRequest();
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth(),
      firestore: store,
    );

    final summary = await repository.linkOwnPendingEnrollments();

    expect(summary.linked, 1);
    expect(summary.hasJoinRequestForTeacherReview, isFalse);
    expect(store.pendingDocuments.values.single['status'], 'linked');
    expect(store.pendingDocuments.values.single['studentUid'], 'student-one');
    expect(
      store.existingEnrollment?['rosterEntryId'],
      'student@example.invalid',
    );
    expect(store.existingEnrollment?['effectiveStartDate'], isA<Timestamp>());
    expect(store.existingEnrollment?['name'], 'Roster Student');
    expect(store.joinRequest?['status'], 'approved');
    expect(store.joinRequest?['decidedBy'], 'teacher-one');
    expect(store.transactionReads, [
      'courses/course-00/pending_enrollments/student@example.invalid',
      'users/student-one',
      'courses/course-00/enrollments/student-one',
      'courses/course-00/join_requests/student-one',
    ]);
    expect(store.transactionReads, isNot(contains('courses/course-00')));
    expect(
      store.transactionWritePaths,
      contains(
        'courses/course-00/pending_enrollments/student@example.invalid/status_events/link',
      ),
    );
    expect(
      store.transactionUpdatePaths,
      contains('courses/course-00/pending_enrollments/student@example.invalid'),
    );
    expect(
      store.transactionWritePaths,
      contains('courses/course-00/enrollments/student-one'),
    );
  });

  test(
    'verified student links a legacy enrollment without rewriting it',
    () async {
      const pendingPath =
          'courses/course-00/pending_enrollments/student@example.invalid';
      final legacyEnrollment = _activeEnrollment();
      final legacyBefore = Map<String, dynamic>.from(legacyEnrollment);
      final store = _Store()
        ..existingEnrollment = legacyEnrollment
        ..pendingDocuments[pendingPath] = _pendingEnrollmentDocument();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth(),
        firestore: store,
      );

      final summary = await repository.linkOwnPendingEnrollments();

      expect(summary.linked, 1);
      expect(store.pendingDocuments[pendingPath]!['status'], 'linked');
      expect(store.existingEnrollment, legacyBefore);
      expect(store.existingEnrollment!.containsKey('rosterEntryId'), isFalse);
      expect(
        store.existingEnrollment!.containsKey('effectiveStartDate'),
        isFalse,
      );
      expect(
        store.transactionWritePaths,
        isNot(contains('courses/course-00/enrollments/student-one')),
      );
      expect(
        store.transactionUpdatePaths,
        isNot(contains('courses/course-00/enrollments/student-one')),
      );
    },
  );

  test(
    'verified student does not link when modern roster metadata differs',
    () async {
      const pendingPath =
          'courses/course-00/pending_enrollments/student@example.invalid';
      final store = _Store()
        ..existingEnrollment = {
          ..._activeEnrollment(),
          'rosterEntryId': 'student@example.invalid',
          'effectiveStartDate': Timestamp.fromDate(DateTime.utc(2026, 11, 15)),
        }
        ..pendingDocuments[pendingPath] = _pendingEnrollmentDocument();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth(),
        firestore: store,
      );

      final summary = await repository.linkOwnPendingEnrollments();

      expect(summary.linked, 0);
      expect(summary.needsReview, 1);
      expect(store.pendingDocuments[pendingPath]!['status'], 'pending');
      expect(store.transactionWritePaths, isEmpty);
      expect(store.transactionUpdatePaths, isEmpty);
    },
  );

  test(
    'pending link event ID stays short for a maximum-length email',
    () async {
      final email = '${'a' * 64}@${'b' * 189}';
      expect(email.length, 254);
      final pendingPath = 'courses/course-00/pending_enrollments/$email';
      final store = _Store()
        ..profiles['users/student-one'] = {
          'name': 'Student One',
          'email': email,
          'studentCode': '0012',
          'roles': ['student'],
        }
        ..pendingDocuments[pendingPath] = _pendingEnrollmentDocument(
          email: email,
        );
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _LongEmailStudentUser(email),
        firestore: store,
      );

      final summary = await repository.linkOwnPendingEnrollments();

      expect(summary.linked, 1);
      expect(store.pendingDocuments[pendingPath]!['lastEventId'], 'link');
      expect(
        store.pendingStatusEvents.containsKey(
          '$pendingPath/status_events/link',
        ),
        isTrue,
      );
    },
  );

  test('mismatched join request stays pending while authorized roster links', () async {
    final store = _Store()
      ..pendingDocuments['courses/course-00/pending_enrollments/student@example.invalid'] =
          _pendingEnrollmentDocument()
      ..joinRequest = {..._matchingJoinRequest(), 'studentCode': 'wrong-code'};
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth(),
      firestore: store,
    );

    final summary = await repository.linkOwnPendingEnrollments();

    expect(summary.linked, 1);
    expect(summary.hasJoinRequestForTeacherReview, isTrue);
    expect(store.pendingDocuments.values.single['status'], 'linked');
    expect(store.existingEnrollment, isNotNull);
    expect(store.joinRequest?['status'], 'pending');
    expect(
      store.transactionUpdatePaths,
      isNot(contains('courses/course-00/join_requests/student-one')),
    );
  });

  test('teacher can withdraw a future pending row today before its start date', () async {
    const path =
        'courses/course-00/pending_enrollments/student@example.invalid';
    final futureStart = Timestamp.fromDate(DateTime.utc(2027, 1, 1));
    final store = _Store()
      ..courseStartDate = futureStart
      ..courseEndDate = Timestamp.fromDate(DateTime.utc(2027, 11, 1))
      ..pendingDocuments[path] = {
        ..._pendingEnrollmentDocument(),
        'effectiveStartDate': futureStart,
      };
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );
    final expected = await repository.getCoursePendingEnrollment(
      courseId: 'course-00',
      email: 'student@example.invalid',
    );
    final todayBogota = DateTime.now().toUtc().subtract(
      const Duration(hours: 5),
    );
    final result = await repository.changePendingEnrollmentStatus(
      expected: expected!,
      nextStatus: 'withdrawn',
      operationId: 'withdraw-pending-before-start',
      effectiveDate: AcademicDate.fromDateTime(todayBogota),
    );

    expect(result.status, 'withdrawn');
    expect(store.pendingDocuments[path]!['status'], 'withdrawn');
    expect(store.pendingDocuments[path]!['effectiveStartDate'], futureStart);
    expect(
      store
          .pendingStatusEvents['$path/status_events/withdraw-pending-before-start']?['effectiveDate'],
      Timestamp.fromDate(
        DateTime.utc(todayBogota.year, todayBogota.month, todayBogota.day),
      ),
    );

    final writeCountAfterWithdrawal = store.transactionWriteCount;
    final retry = await repository.changePendingEnrollmentStatus(
      expected: expected,
      nextStatus: 'withdrawn',
      operationId: 'withdraw-pending-before-start',
      effectiveDate: AcademicDate.fromDateTime(todayBogota),
    );
    expect(retry.alreadyApplied, isTrue);
    expect(store.transactionWriteCount, writeCountAfterWithdrawal);

    final withdrawn = await repository.getCoursePendingEnrollment(
      courseId: 'course-00',
      email: 'student@example.invalid',
    );
    final reopened = await repository.changePendingEnrollmentStatus(
      expected: withdrawn!,
      nextStatus: 'pending',
      operationId: 'reopen-pending-before-start',
      effectiveDate: AcademicDate(year: 2027, month: 1, day: 1),
    );
    expect(reopened.status, 'pending');
    expect(store.pendingDocuments[path]!['status'], 'pending');
    expect(store.pendingDocuments[path]!['effectiveStartDate'], futureStart);
    expect(
      store
          .pendingStatusEvents['$path/status_events/reopen-pending-before-start']?['fromStatus'],
      'withdrawn',
    );
  });

  test(
    'teacher can cancel a future-start canonical enrollment today',
    () async {
      final futureStart = Timestamp.fromDate(DateTime.utc(2027, 1, 1));
      final store = _Store()
        ..courseStartDate = futureStart
        ..courseEndDate = Timestamp.fromDate(DateTime.utc(2027, 11, 1))
        ..existingEnrollment = {
          ..._activeEnrollment(),
          'rosterEntryId': 'student@example.invalid',
          'effectiveStartDate': futureStart,
        };
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );
      final expected = await repository.getCourseEnrollment(
        courseId: 'course-00',
        studentUid: 'student-one',
      );
      final todayBogota = DateTime.now().toUtc().subtract(
        const Duration(hours: 5),
      );
      final result = await repository.changeEnrollmentStatus(
        expected: expected,
        nextStatus: 'withdrawn',
        operationId: 'withdraw-future-enrollment',
        effectiveDate: AcademicDate.fromDateTime(todayBogota),
      );

      expect(result.enrollment.status, 'withdrawn');
      expect(result.enrollment.effectiveStartDate, expected.effectiveStartDate);
      expect(store.existingEnrollment!['status'], 'withdrawn');
      expect(
        store.transactionWrite!['effectiveDate'],
        Timestamp.fromDate(
          DateTime.utc(todayBogota.year, todayBogota.month, todayBogota.day),
        ),
      );
    },
  );

  test(
    'pending withdrawal earlier than authorization is invalid input',
    () async {
      const path =
          'courses/course-00/pending_enrollments/student@example.invalid';
      final store = _Store()
        ..pendingDocuments[path] = {
          ..._pendingEnrollmentDocument(),
          'effectiveStartDate': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
        };
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );
      final expected = await repository.getCoursePendingEnrollment(
        courseId: 'course-00',
        email: 'student@example.invalid',
      );

      await expectLater(
        repository.changePendingEnrollmentStatus(
          expected: expected!,
          nextStatus: 'withdrawn',
          operationId: 'withdraw-before-authorization',
          effectiveDate: AcademicDate(year: 2026, month: 11, day: 8),
        ),
        throwsA(
          isA<EnrollmentFailure>().having(
            (failure) => failure.kind,
            'kind',
            EnrollmentFailureKind.invalidInput,
          ),
        ),
      );
      expect(store.transactionWriteCount, 0);
      expect(store.transactionUpdatePath, isNull);
    },
  );

  test('reopening pending before the latest event is invalid input', () async {
    const path =
        'courses/course-00/pending_enrollments/student@example.invalid';
    final todayBogota = AcademicDate.fromDateTime(
      DateTime.now().toUtc().subtract(const Duration(hours: 5)),
    );
    const priorEventId = 'withdraw-pending-once';
    final store = _Store()
      ..pendingDocuments[path] = {
        ..._pendingEnrollmentDocument(),
        'status': 'withdrawn',
        'effectiveStartDate': Timestamp.fromDate(DateTime.utc(2026, 11, 5)),
        'lastEventId': priorEventId,
        'lastStatusChangedAt': _serverTimestamp,
      }
      ..pendingStatusEvents['$path/status_events/$priorEventId'] = {
        'fromStatus': 'pending',
        'toStatus': 'withdrawn',
        'effectiveDate': Timestamp.fromDate(todayBogota.toUtcTimestamp()),
        'changedAt': _serverTimestamp,
        'changedBy': 'teacher-one',
      };
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );
    final expected = await repository.getCoursePendingEnrollment(
      courseId: 'course-00',
      email: 'student@example.invalid',
    );

    await expectLater(
      repository.changePendingEnrollmentStatus(
        expected: expected!,
        nextStatus: 'pending',
        operationId: 'reopen-before-withdrawal-event',
        effectiveDate: todayBogota.addDays(-1),
      ),
      throwsA(
        isA<EnrollmentFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnrollmentFailureKind.invalidInput,
        ),
      ),
    );
    expect(
      store.transactionReads,
      contains('$path/status_events/$priorEventId'),
    );
    expect(store.transactionWriteCount, 0);
    expect(store.transactionUpdatePath, isNull);
  });

  test('withdrawal before the latest enrollment event is invalid input', () async {
    final todayBogota = AcademicDate.fromDateTime(
      DateTime.now().toUtc().subtract(const Duration(hours: 5)),
    );
    const priorEventId = 'previous-rejoin';
    final store = _Store()
      ..existingEnrollment = {
        ..._activeEnrollment(),
        'rosterEntryId': 'student@example.invalid',
        'effectiveStartDate': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
        'lastStatusEventId': priorEventId,
        'lastStatusChangedAt': _serverTimestamp,
      }
      ..statusEvents[priorEventId] = {
        'fromStatus': 'withdrawn',
        'toStatus': 'active',
        'effectiveDate': Timestamp.fromDate(todayBogota.toUtcTimestamp()),
        'changedAt': _serverTimestamp,
        'changedBy': 'teacher-one',
      };
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );
    final expected = await repository.getCourseEnrollment(
      courseId: 'course-00',
      studentUid: 'student-one',
    );

    await expectLater(
      repository.changeEnrollmentStatus(
        expected: expected,
        nextStatus: 'withdrawn',
        operationId: 'withdraw-before-rejoin-event',
        effectiveDate: todayBogota.addDays(-1),
      ),
      throwsA(
        isA<EnrollmentFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnrollmentFailureKind.invalidInput,
        ),
      ),
    );
    expect(
      store.transactionReads,
      contains(
        'courses/course-00/enrollments/student-one/status_events/$priorEventId',
      ),
    );
    expect(store.transactionWriteCount, 0);
    expect(store.transactionUpdatePath, isNull);
  });

  test(
    'a real enrollment status permission denial remains permissionDenied',
    () async {
      final store = _Store()..existingEnrollment = _activeEnrollment();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );
      final expected = await repository.getCourseEnrollment(
        courseId: 'course-00',
        studentUid: 'student-one',
      );
      store.onTransaction = () => throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );

      await expectLater(
        repository.changeEnrollmentStatus(
          expected: expected,
          nextStatus: 'withdrawn',
          operationId: 'actually-denied-withdrawal',
          effectiveDate: AcademicDate(year: 2026, month: 11, day: 14),
        ),
        throwsA(
          isA<EnrollmentFailure>().having(
            (failure) => failure.kind,
            'kind',
            EnrollmentFailureKind.permissionDenied,
          ),
        ),
      );
    },
  );

  test('manual enrollment never reopens a withdrawn enrollment', () async {
    final store = _Store()
      ..existingEnrollment = {
        ..._activeEnrollment(),
        'status': 'withdrawn',
        'lastStatusEventId': 'withdraw-op',
        'lastStatusChangedAt': _serverTimestamp,
      }
      ..joinRequest = {'studentUid': 'student-one', 'status': 'pending'};
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );

    final result = await repository.enrollStudent(
      courseId: 'course-00',
      candidate: const StudentCandidate(
        uid: 'student-one',
        name: 'Current name',
        email: 'student@example.invalid',
        studentCode: '0012',
      ),
    );

    expect(result.alreadyEnrolled, isTrue);
    expect(result.enrollment.status, 'withdrawn');
    expect(result.enrollment.lastStatusEventId, 'withdraw-op');
    expect(store.transactionWriteCount, 0);
    expect(store.transactionUpdatePath, isNull);
    expect(store.joinRequest!['status'], 'pending');
  });

  test(
    'existing enrollment resolves a pending request without rewriting it',
    () async {
      final store = _Store()
        ..existingEnrollment = {
          'studentUid': 'student-one',
          'ownerUid': 'teacher-one',
          'name': 'Original snapshot',
          'email': 'student@example.invalid',
          'studentCode': '0012',
          'subject': 'Course 0',
          'group': 'G1',
          'period': '2026-2',
          'status': 'active',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
        }
        ..joinRequest = _matchingJoinRequest();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );

      final result = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: const StudentCandidate(
          uid: 'student-one',
          name: 'Current name',
          email: 'student@example.invalid',
          studentCode: '0012',
        ),
      );

      expect(result.alreadyEnrolled, isTrue);
      expect(result.enrollment.name, 'Original snapshot');
      expect(store.transactionWriteCount, 0);
      expect(
        store.transactionUpdatePath,
        'courses/course-00/join_requests/student-one',
      );
      expect(store.joinRequest!['status'], 'approved');
    },
  );

  test(
    'existing enrollment leaves an identity-mismatched request pending',
    () async {
      final store = _Store()
        ..existingEnrollment = _activeEnrollment()
        ..joinRequest = {
          ..._matchingJoinRequest(),
          'email': 'other@example.invalid',
        };
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );

      final result = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: const StudentCandidate(
          uid: 'student-one',
          name: 'Current name',
          email: 'student@example.invalid',
          studentCode: '0012',
        ),
      );

      expect(result.alreadyEnrolled, isTrue);
      expect(store.joinRequest!['status'], 'pending');
      expect(store.transactionWriteCount, 0);
      expect(store.transactionUpdatePath, isNull);
    },
  );

  test(
    'Excel retry leaves a newly existing enrollment and request unchanged',
    () async {
      final store = _Store()
        ..existingEnrollment = _activeEnrollment()
        ..joinRequest = _matchingJoinRequest();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );

      final result = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: const StudentCandidate(
          uid: 'student-one',
          name: 'Student One',
          email: 'student@example.invalid',
          studentCode: '0012',
        ),
        resolvePendingWhenAlreadyEnrolled: false,
      );

      expect(result.alreadyEnrolled, isTrue);
      expect(result.enrollment.status, 'active');
      expect(store.transactionWriteCount, 0);
      expect(store.transactionUpdatePath, isNull);
      expect(store.joinRequest!['status'], 'pending');
    },
  );

  test(
    'Excel new enrollment still resolves its pending request atomically',
    () async {
      final store = _Store()..joinRequest = _matchingJoinRequest();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );

      final result = await repository.enrollStudent(
        courseId: 'course-00',
        candidate: const StudentCandidate(
          uid: 'student-one',
          name: 'Student One',
          email: 'student@example.invalid',
          studentCode: '0012',
        ),
        resolvePendingWhenAlreadyEnrolled: false,
      );

      expect(result.alreadyEnrolled, isFalse);
      expect(store.transactionWriteCount, 1);
      expect(
        store.transactionUpdatePath,
        'courses/course-00/join_requests/student-one',
      );
      expect(store.joinRequest!['status'], 'approved');
    },
  );

  test('status change writes the enrollment and event atomically', () async {
    final store = _Store()..existingEnrollment = _activeEnrollment();
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );
    final expected = await repository.getCourseEnrollment(
      courseId: 'course-00',
      studentUid: 'student-one',
    );
    final operationId = repository.newStatusEventId(
      courseId: expected.courseId,
      studentUid: expected.studentUid,
    );

    final result = await repository.changeEnrollmentStatus(
      expected: expected,
      nextStatus: 'withdrawn',
      operationId: operationId,
      effectiveDate: AcademicDate(year: 2026, month: 11, day: 11),
    );

    expect(result.alreadyApplied, isFalse);
    expect(result.enrollment.status, 'withdrawn');
    expect(result.enrollment.createdAt, expected.createdAt);
    expect(result.enrollment.lastStatusEventId, operationId);
    expect(result.enrollment.lastStatusChangedAt, isNull);
    expect(
      store.transactionUpdatePath,
      'courses/course-00/enrollments/student-one',
    );
    expect(store.transactionUpdate, {
      'status': 'withdrawn',
      'lastStatusEventId': operationId,
      'lastStatusChangedAt': isA<FieldValue>(),
    });
    expect(
      store.transactionWritePath,
      'courses/course-00/enrollments/student-one/status_events/$operationId',
    );
    expect(store.transactionWrite!.keys.toSet(), {
      'fromStatus',
      'toStatus',
      'effectiveDate',
      'changedAt',
      'changedBy',
    });
    expect(store.transactionWrite, {
      'fromStatus': 'active',
      'toStatus': 'withdrawn',
      'effectiveDate': Timestamp.fromDate(DateTime.utc(2026, 11, 11)),
      'changedAt': isA<FieldValue>(),
      'changedBy': 'teacher-one',
    });
    expect(store.existingEnrollment!['status'], 'withdrawn');
    expect(
      store.existingEnrollment!['createdAt'],
      _activeEnrollment()['createdAt'],
    );
    expect(store.statusEvents[operationId]?['toStatus'], 'withdrawn');
  });

  test(
    'status change can explicitly reinstate a withdrawn enrollment',
    () async {
      final store = _Store()
        ..existingEnrollment = {
          ..._activeEnrollment(),
          'status': 'withdrawn',
          'lastStatusEventId': 'withdraw-op',
          'lastStatusChangedAt': _serverTimestamp,
        }
        ..statusEvents['withdraw-op'] = {
          'fromStatus': 'active',
          'toStatus': 'withdrawn',
          'changedAt': _serverTimestamp,
          'changedBy': 'teacher-one',
        };
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );
      final expected = await repository.getCourseEnrollment(
        courseId: 'course-00',
        studentUid: 'student-one',
      );
      final operationId = repository.newStatusEventId(
        courseId: expected.courseId,
        studentUid: expected.studentUid,
      );

      final result = await repository.changeEnrollmentStatus(
        expected: expected,
        nextStatus: 'active',
        operationId: operationId,
        effectiveDate: AcademicDate(year: 2026, month: 11, day: 11),
      );

      expect(result.alreadyApplied, isFalse);
      expect(result.enrollment.status, 'active');
      expect(store.transactionUpdate, {
        'status': 'active',
        'lastStatusEventId': operationId,
        'lastStatusChangedAt': isA<FieldValue>(),
      });
      expect(store.transactionWrite, {
        'fromStatus': 'withdrawn',
        'toStatus': 'active',
        'effectiveDate': Timestamp.fromDate(DateTime.utc(2026, 11, 11)),
        'changedAt': isA<FieldValue>(),
        'changedBy': 'teacher-one',
      });
    },
  );

  test('two complete withdrawal and reinstatement cycles retain one enrollment', () async {
    final store = _Store()..existingEnrollment = _activeEnrollment();
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );
    final originalCreatedAt = _activeEnrollment()['createdAt'] as Timestamp;
    const operationIds = [
      'cycle-withdraw-1',
      'cycle-reinstate-1',
      'cycle-withdraw-2',
      'cycle-reinstate-2',
    ];
    const nextStatuses = ['withdrawn', 'active', 'withdrawn', 'active'];

    for (var index = 0; index < operationIds.length; index++) {
      final expected = await repository.getCourseEnrollment(
        courseId: 'course-00',
        studentUid: 'student-one',
      );
      final result = await repository.changeEnrollmentStatus(
        expected: expected,
        nextStatus: nextStatuses[index],
        operationId: operationIds[index],
        effectiveDate: AcademicDate(year: 2026, month: 11, day: 11 + index),
      );
      expect(result.enrollment.status, nextStatuses[index]);
      expect(result.enrollment.createdAt, originalCreatedAt.toDate());
      expect(result.alreadyApplied, isFalse);
    }

    expect(store.existingEnrollment!['status'], 'active');
    expect(store.existingEnrollment!['lastStatusEventId'], operationIds.last);
    expect(
      (store.existingEnrollment!['createdAt'] as Timestamp).toDate(),
      originalCreatedAt.toDate(),
    );
    expect(store.statusEvents.keys.toSet(), operationIds.toSet());
    expect(store.transactionUpdatePaths, [
      for (var index = 0; index < operationIds.length; index++)
        'courses/course-00/enrollments/student-one',
    ]);
    expect(store.transactionWritePaths, [
      for (final operationId in operationIds)
        'courses/course-00/enrollments/student-one/status_events/$operationId',
    ]);
    expect(
      store.statusEvents.values.map(
        (event) => '${event['fromStatus']}>${event['toStatus']}',
      ),
      [
        'active>withdrawn',
        'withdrawn>active',
        'active>withdrawn',
        'withdrawn>active',
      ],
    );
  });

  test(
    'same operation ID is idempotent only while it remains latest',
    () async {
      final store = _Store()..existingEnrollment = _activeEnrollment();
      final repository = FirestoreEnrollmentRepository(
        auth: _Auth()..user = _TeacherUser(),
        firestore: store,
      );
      final expected = await repository.getCourseEnrollment(
        courseId: 'course-00',
        studentUid: 'student-one',
      );
      const operationId = 'withdraw-op';
      await repository.changeEnrollmentStatus(
        expected: expected,
        nextStatus: 'withdrawn',
        operationId: operationId,
        effectiveDate: AcademicDate(year: 2026, month: 11, day: 11),
      );
      store.clearTransactionCapture();

      final retry = await repository.changeEnrollmentStatus(
        expected: expected,
        nextStatus: 'withdrawn',
        operationId: operationId,
      );

      expect(retry.alreadyApplied, isTrue);
      expect(retry.enrollment.status, 'withdrawn');
      expect(store.transactionWriteCount, 0);
      expect(store.transactionUpdatePath, isNull);

      store.existingEnrollment = {
        ...store.existingEnrollment!,
        'status': 'active',
        'lastStatusEventId': 'later-reinstate-op',
        'lastStatusChangedAt': _serverTimestamp,
      };
      store.statusEvents['later-reinstate-op'] = {
        'fromStatus': 'withdrawn',
        'toStatus': 'active',
        'changedAt': _serverTimestamp,
        'changedBy': 'teacher-one',
      };
      await expectLater(
        repository.changeEnrollmentStatus(
          expected: expected,
          nextStatus: 'withdrawn',
          operationId: operationId,
          effectiveDate: AcademicDate(year: 2026, month: 11, day: 11),
        ),
        throwsA(
          isA<EnrollmentFailure>().having(
            (failure) => failure.kind,
            'kind',
            EnrollmentFailureKind.staleEnrollment,
          ),
        ),
      );
      expect(store.transactionWriteCount, 0);
      expect(store.existingEnrollment!['status'], 'active');
    },
  );

  test('stale enrollment version cannot overwrite a newer state', () async {
    final store = _Store()
      ..existingEnrollment = {
        ..._activeEnrollment(),
        'status': 'withdrawn',
        'lastStatusEventId': 'prior-op',
        'lastStatusChangedAt': _serverTimestamp,
      };
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );
    final expected = _enrollmentModel(_activeEnrollment());

    await expectLater(
      repository.changeEnrollmentStatus(
        expected: expected,
        nextStatus: 'withdrawn',
        operationId: 'new-op',
      ),
      throwsA(
        isA<EnrollmentFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnrollmentFailureKind.staleEnrollment,
        ),
      ),
    );
    expect(store.transactionWriteCount, 0);
    expect(store.transactionUpdatePath, isNull);
  });

  test('history pages immutable status events newest first', () async {
    final oldest = Timestamp.fromDate(DateTime.utc(2026, 11, 8));
    final newest = Timestamp.fromDate(DateTime.utc(2026, 11, 10));
    final store = _Store()
      ..existingEnrollment = {
        ..._activeEnrollment(),
        'status': 'active',
        'lastStatusEventId': 'reinstate-op',
        'lastStatusChangedAt': newest,
      }
      ..statusEvents['withdraw-op'] = {
        'fromStatus': 'active',
        'toStatus': 'withdrawn',
        'changedAt': oldest,
        'changedBy': 'teacher-one',
      }
      ..statusEvents['reinstate-op'] = {
        'fromStatus': 'withdrawn',
        'toStatus': 'active',
        'changedAt': newest,
        'changedBy': 'teacher-one',
      };
    final repository = FirestoreEnrollmentRepository(
      auth: _Auth()..user = _TeacherUser(),
      firestore: store,
    );

    final first = await repository.listEnrollmentHistory(
      courseId: 'course-00',
      studentUid: 'student-one',
      pageSize: 1,
    );

    expect(first.items, hasLength(1));
    expect(first.items.single.operationId, 'reinstate-op');
    expect(first.items.single.fromStatus, 'withdrawn');
    expect(first.items.single.toStatus, 'active');
    expect(first.hasMore, isTrue);
    expect(first.nextCursor?.operationId, 'reinstate-op');

    final second = await repository.listEnrollmentHistory(
      courseId: 'course-00',
      studentUid: 'student-one',
      cursor: first.nextCursor,
      pageSize: 1,
    );
    expect(second.items.single.operationId, 'withdraw-op');
    expect(second.hasMore, isFalse);
    expect(store.startAfters.last, [newest, 'reinstate-op']);
  });
}

final _serverTimestamp = Timestamp.fromDate(DateTime.utc(2026, 11, 10));

Course _courseModel() => Course(
  id: 'course-00',
  ownerUid: 'teacher-one',
  subject: 'Course 0',
  group: 'G1',
  period: '2026-2',
  program: 'Systems',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 11, day: 1),
    endDate: AcademicDate(year: 2027, month: 11, day: 1),
    weeklyBlocks: const [],
  ),
);

Map<String, dynamic> _pendingEnrollmentDocument({
  String email = 'student@example.invalid',
}) => {
  'courseId': 'course-00',
  'ownerUid': 'teacher-one',
  'subject': 'Course 0',
  'group': 'G1',
  'period': '2026-2',
  'email': email,
  'studentCode': '0012',
  'name': 'Roster Student',
  'status': 'pending',
  'effectiveStartDate': Timestamp.fromDate(DateTime.utc(2026, 11, 14)),
  'rosterEntryId': email,
  'studentUid': null,
  'authorizedAt': _serverTimestamp,
  'linkedAt': null,
  'createdAt': _serverTimestamp,
  'updatedAt': _serverTimestamp,
  'lastEventId': null,
  'lastStatusChangedAt': null,
};

Map<String, dynamic> _matchingJoinRequest() => {
  'studentUid': 'student-one',
  'email': 'student@example.invalid',
  'studentCode': '0012',
  'name': 'Different request display name',
  'subject': 'Course 0',
  'group': 'G1',
  'period': '2026-2',
  'status': 'pending',
};

Map<String, dynamic> _activeEnrollment() => {
  'studentUid': 'student-one',
  'ownerUid': 'teacher-one',
  'name': 'Student One',
  'email': 'student@example.invalid',
  'studentCode': '0012',
  'subject': 'Course 0',
  'group': 'G1',
  'period': '2026-2',
  'status': 'active',
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 5)),
};

Enrollment _enrollmentModel(Map<String, dynamic> value) => Enrollment(
  courseId: 'course-00',
  studentUid: value['studentUid'] as String,
  ownerUid: value['ownerUid'] as String,
  name: value['name'] as String,
  email: value['email'] as String,
  studentCode: value['studentCode'] as String?,
  subject: value['subject'] as String,
  group: value['group'] as String,
  period: value['period'] as String,
  status: value['status'] as String,
  createdAt: (value['createdAt'] as Timestamp).toDate(),
  rosterEntryId: value['rosterEntryId'] as String? ?? 'legacy:student-one',
  effectiveStartDate: value['effectiveStartDate'] is Timestamp
      ? AcademicDate.fromUtcTimestamp(
          (value['effectiveStartDate'] as Timestamp).toDate().toUtc(),
        )
      : AcademicDate.fromDateTime(
          (value['createdAt'] as Timestamp).toDate().toUtc().subtract(
            const Duration(hours: 5),
          ),
        ),
  lastStatusEventId: value['lastStatusEventId'] as String?,
  lastStatusChangedAt: value['lastStatusChangedAt'] is Timestamp
      ? (value['lastStatusChangedAt'] as Timestamp).toDate()
      : null,
);

class _Auth implements FirebaseAuth {
  User? user = _User();
  @override
  User? get currentUser => user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  @override
  String get uid => 'student-one';
  @override
  String get email => 'student@example.invalid';
  @override
  bool get emailVerified => true;
  @override
  Future<void> reload() async {}
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'test-token';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LongEmailStudentUser extends _User {
  _LongEmailStudentUser(this.email);

  @override
  final String email;
}

class _TeacherUser extends _User {
  @override
  String get uid => 'teacher-one';
  @override
  String get email => 'teacher@example.invalid';
}

class _OtherStudentUser extends _User {
  @override
  String get uid => 'other-student';
  @override
  String get email => 'other@example.invalid';
}

class _Store implements FirebaseFirestore {
  final uidFilters = <Object?>[];
  final statusFilters = <Object?>[];
  final startAfters = <List<Object?>>[];
  final serverReads = <String>[];
  final statusEvents = <String, Map<String, dynamic>>{};
  final pendingDocuments = <String, Map<String, dynamic>>{};
  final pendingStatusEvents = <String, Map<String, dynamic>>{};
  final _transactionOperations = <_TransactionOperation>[];
  void Function()? onQuery;
  void Function()? onTransaction;
  String? writtenPath;
  Map<String, dynamic>? writtenFields;
  Map<String, dynamic>? transactionWrite;
  String? transactionWritePath;
  final transactionWritePaths = <String>[];
  int transactionWriteCount = 0;
  final transactionReads = <String>[];
  String? transactionUpdatePath;
  final transactionUpdatePaths = <String>[];
  Map<String, dynamic>? transactionUpdate;
  Map<String, dynamic>? existingEnrollment;
  final enrollmentDocuments = <String, Map<String, dynamic>>{};
  final profiles = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? joinRequest;
  bool directoryAvailable = true;
  Timestamp courseStartDate = Timestamp.fromDate(DateTime.utc(2026, 11, 1));
  Timestamp courseEndDate = Timestamp.fromDate(DateTime.utc(2027, 11, 1));

  void clearTransactionCapture() {
    transactionReads.clear();
    transactionWrite = null;
    transactionWritePath = null;
    transactionWritePaths.clear();
    transactionWriteCount = 0;
    transactionUpdate = null;
    transactionUpdatePath = null;
    transactionUpdatePaths.clear();
    _transactionOperations.clear();
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  Query<Map<String, dynamic>> collectionGroup(String collectionId) =>
      _Query(this, collectionId, page: 0);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    onTransaction?.call();
    final result = await transactionHandler(_FakeTransaction(this));
    for (final operation in _transactionOperations) {
      final resolved = _resolveMap(operation.data);
      if (operation.path.contains('/pending_enrollments/')) {
        if (operation.path.contains('/status_events/')) {
          pendingStatusEvents[operation.path] = resolved;
        } else if (operation.update) {
          pendingDocuments[operation.path] = {
            ...?pendingDocuments[operation.path],
            ...resolved,
          };
        } else {
          pendingDocuments[operation.path] = resolved;
        }
      } else if (operation.path.contains('/join_requests/')) {
        if (joinRequest != null) {
          joinRequest = {...joinRequest!, ...resolved};
        }
      } else if (operation.path.contains('/enrollments/') &&
          operation.path.contains('/status_events/')) {
        statusEvents[operation.path.split('/').last] = resolved;
      } else if (operation.path.contains('/enrollments/')) {
        if (operation.update) {
          if (existingEnrollment != null) {
            existingEnrollment = {...existingEnrollment!, ...resolved};
          }
        } else {
          existingEnrollment = {
            ...resolved,
            'createdAt':
                resolved['createdAt'] ??
                Timestamp.fromDate(DateTime.utc(2026, 11, 5)),
          };
        }
      }
    }
    return result;
  }

  Map<String, dynamic> _resolveMap(Map<String, dynamic> source) => {
    for (final entry in source.entries)
      entry.key: entry.value is FieldValue ? _serverTimestamp : entry.value,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Query implements Query<Map<String, dynamic>> {
  _Query(
    this.store,
    this.path, {
    required this.page,
    this.maximum = 100,
    Map<String, Object?>? filters,
    this.cursorDocumentId,
  }) : filters = filters ?? const {};

  final _Store store;
  final String path;
  final int page;
  final int maximum;
  final Map<String, Object?> filters;
  final String? cursorDocumentId;

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
  }) {
    if (path.contains('pending_enrollments')) {
      return _Query(
        store,
        path,
        page: page,
        maximum: maximum,
        filters: {...filters, field.toString(): isEqualTo},
        cursorDocumentId: cursorDocumentId,
      );
    } else if (field == 'studentUid') {
      store.uidFilters.add(isEqualTo);
    } else if (field == 'status') {
      store.statusFilters.add(isEqualTo);
    } else {
      fail('Unexpected enrollment query filter: $field');
    }
    return this;
  }

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    expect(descending, isTrue);
    return this;
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) => _Query(
    store,
    path,
    page: page,
    maximum: limit,
    filters: filters,
    cursorDocumentId: cursorDocumentId,
  );

  @override
  Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) {
    store.startAfters.add(values.toList());
    return _Query(
      store,
      path,
      page: 1,
      maximum: maximum,
      filters: filters,
      cursorDocumentId: values.isEmpty ? null : values.last as String?,
    );
  }

  @override
  Query<Map<String, dynamic>> startAfterDocument(
    DocumentSnapshot<Object?> documentSnapshot,
  ) => _Query(
    store,
    path,
    page: 1,
    maximum: maximum,
    filters: filters,
    cursorDocumentId: documentSnapshot.id,
  );

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    expect(options?.source, Source.server);
    store.serverReads.add(path);
    store.onQuery?.call();
    if (path == 'pending_enrollments' ||
        path.endsWith('/pending_enrollments')) {
      final prefix = path == 'pending_enrollments' ? null : '$path/';
      final entries =
          store.pendingDocuments.entries
              .where((entry) => prefix == null || entry.key.startsWith(prefix))
              .where(
                (entry) => filters.entries.every(
                  (filter) => entry.value[filter.key] == filter.value,
                ),
              )
              .toList()
            ..sort((left, right) {
              final leftCreatedAt = left.value['createdAt'] as Timestamp;
              final rightCreatedAt = right.value['createdAt'] as Timestamp;
              final dateOrder = rightCreatedAt.compareTo(leftCreatedAt);
              if (dateOrder != 0) return dateOrder;
              return right.key
                  .split('/')
                  .last
                  .compareTo(left.key.split('/').last);
            });
      final cursorIndex = cursorDocumentId == null
          ? -1
          : entries.indexWhere(
              (entry) => entry.key.split('/').last == cursorDocumentId,
            );
      return _Snapshot(
        entries
            .skip(cursorIndex + 1)
            .take(maximum)
            .map((entry) => _Document(store, entry.key, entry.value))
            .toList(growable: false),
      );
    }
    if (path.endsWith('/status_events')) {
      final sorted = store.statusEvents.entries.toList()
        ..sort((left, right) {
          final dateOrder = (right.value['changedAt'] as Timestamp).compareTo(
            left.value['changedAt'] as Timestamp,
          );
          return dateOrder != 0 ? dateOrder : right.key.compareTo(left.key);
        });
      var start = 0;
      if (page > 0 && store.startAfters.isNotEmpty) {
        final cursorId = store.startAfters.last.last as String;
        final cursorIndex = sorted.indexWhere((entry) => entry.key == cursorId);
        start = cursorIndex < 0 ? 0 : cursorIndex + 1;
      }
      return _Snapshot(
        sorted
            .skip(start)
            .take(maximum)
            .map((entry) => _Document(store, '$path/${entry.key}', entry.value))
            .toList(growable: false),
      );
    }
    return _Snapshot([
      for (
        var index = page == 0 ? 0 : 25;
        index < (page == 0 ? 26 : 26) && index < (page == 0 ? maximum : 26);
        index++
      )
        _Document(
          store,
          'courses/course-${index.toString().padLeft(2, '0')}/enrollments/student-one',
          {
            'studentUid': 'student-one',
            'ownerUid': 'teacher-one',
            'name': 'Student One',
            'email': 'student@example.invalid',
            'studentCode': '0012',
            'subject': 'Course $index',
            'group': 'G1',
            'period': '2026-2',
            'status': store.statusFilters.isEmpty
                ? 'active'
                : store.statusFilters.last as String,
            'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 30 - index)),
          },
        ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Collection extends _Query
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(super.store, super.path) : super(page: 0);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _Reference(
    store,
    path == null ? '${this.path}/generated-event-id' : '${this.path}/$path',
  );
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
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(store, '$path/$collectionPath');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    expect(options?.source, Source.server);
    store.serverReads.add(path);
    if (path.startsWith('users/')) {
      final Map<String, dynamic>? profile =
          store.profiles[path] ??
          switch (path) {
            'users/student-one' => {
              'name': 'Student One',
              'email': 'student@example.invalid',
              'studentCode': '0012',
              'roles': ['student'],
            },
            'users/teacher-one' => {
              'name': 'Teacher One',
              'email': 'teacher@example.invalid',
              'studentCode': null,
              'roles': ['student', 'teacher'],
            },
            'users/other-student' => {
              'name': 'Other Student',
              'email': 'other@example.invalid',
              'studentCode': null,
              'roles': ['student'],
            },
            _ => null,
          };
      return profile == null
          ? _MissingDocument(path)
          : _Document(store, path, profile);
    }
    if (path.contains('/pending_enrollments/') &&
        !path.contains('/status_events/')) {
      final pending = store.pendingDocuments[path];
      return pending == null
          ? _MissingDocument(path)
          : _Document(store, path, pending);
    }
    final enrollment =
        store.enrollmentDocuments[path] ??
        (path == 'courses/course-00/enrollments/student-one'
            ? store.existingEnrollment
            : null);
    if (path.startsWith('courses/') && path.contains('/enrollments/')) {
      return enrollment == null
          ? _MissingDocument(path)
          : _Document(store, path, enrollment);
    }
    throw StateError('Unexpected document read: $path');
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    store.writtenPath = path;
    store.writtenFields = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransaction implements Transaction {
  _FakeTransaction(this.store);
  final _Store store;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> reference,
  ) async {
    final path = reference.path;
    store.transactionReads.add(path);
    Map<String, dynamic>? value;
    if (path == 'users/student-one') {
      value =
          store.profiles[path] ??
          {
            'name': 'Student One',
            'email': 'student@example.invalid',
            'studentCode': '0012',
            'roles': ['student'],
          };
    } else if (path == 'courses/course-00') {
      value = {
        'ownerUid': 'teacher-one',
        'subject': 'Course 0',
        'group': 'G1',
        'period': '2026-2',
        'startDate': store.courseStartDate,
        'endDate': store.courseEndDate,
      };
    } else if (path == 'student_directory/student@example.invalid') {
      if (store.directoryAvailable) {
        value = {
          'uid': 'student-one',
          'name': 'Student One',
          'email': 'student@example.invalid',
          'studentCode': '0012',
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 5)),
        };
      }
    } else if (path == 'courses/course-00/enrollments/student-one') {
      value = store.existingEnrollment;
    } else if (path == 'courses/course-00/join_requests/student-one') {
      value = store.joinRequest;
    } else if (path.startsWith('courses/course-00/pending_enrollments/') &&
        path.contains('/status_events/')) {
      value = store.pendingStatusEvents[path];
    } else if (path.startsWith('courses/course-00/pending_enrollments/')) {
      value = store.pendingDocuments[path];
    } else if (path.startsWith(
      'courses/course-00/enrollments/student-one/status_events/',
    )) {
      value = store.statusEvents[path.split('/').last];
    } else {
      throw StateError('Unexpected transaction read: $path');
    }
    final doc = value == null
        ? _MissingDocument(path)
        : _Document(store, path, value);
    return doc as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> reference,
    T data, [
    SetOptions? options,
  ]) {
    store.transactionWritePath = reference.path;
    store.transactionWritePaths.add(reference.path);
    store.transactionWrite = data as Map<String, dynamic>;
    store.transactionWriteCount++;
    store._transactionOperations.add(
      _TransactionOperation(reference.path, data as Map<String, dynamic>),
    );
    return this;
  }

  @override
  Transaction update(
    DocumentReference<Object?> reference,
    Map<Object, Object?> data,
  ) {
    store.transactionUpdatePath = reference.path;
    store.transactionUpdatePaths.add(reference.path);
    store.transactionUpdate = data.cast<String, dynamic>();
    store._transactionOperations.add(
      _TransactionOperation(
        reference.path,
        data.cast<String, dynamic>(),
        update: true,
      ),
    );
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TransactionOperation {
  const _TransactionOperation(this.path, this.data, {this.update = false});

  final String path;
  final Map<String, dynamic> data;
  final bool update;
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
  _Document(this.store, this.path, this.value);
  final _Store store;
  final String path;
  final Map<String, dynamic> value;
  @override
  String get id => path.split('/').last;
  @override
  bool get exists => true;
  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      _Reference(store, path);
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshot implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
