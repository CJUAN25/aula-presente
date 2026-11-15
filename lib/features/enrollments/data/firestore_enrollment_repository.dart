import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../courses/data/firestore_course_repository.dart';
import '../../courses/domain/course.dart';
import '../../courses/domain/course_failure.dart';
import '../../schedule/domain/academic_date.dart';
import '../application/enrollment_validator.dart';
import '../domain/enrollment.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_page.dart';
import '../domain/enrollment_repository.dart';
import '../domain/enrollment_status_change.dart';
import '../domain/pending_enrollment.dart';
import '../domain/pending_enrollment_page.dart';
import '../domain/pending_enrollment_result.dart';
import '../domain/student_candidate.dart';

/// Server-backed enrollment access. The owner always comes from Auth; target
/// student IDs come from canonical records, not editable owner fields.
class FirestoreEnrollmentRepository implements EnrollmentRepository {
  FirestoreEnrollmentRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  String? get currentUid => _auth.currentUser?.uid;

  static const _enrollmentKeys = {
    'studentUid',
    'ownerUid',
    'name',
    'email',
    'studentCode',
    'subject',
    'group',
    'period',
    'status',
    'createdAt',
  };
  static const _enrollmentTransitionKeys = {
    'lastStatusEventId',
    'lastStatusChangedAt',
  };
  static const _enrollmentRosterKeys = {'rosterEntryId', 'effectiveStartDate'};
  static const _statusEventKeys = {
    'fromStatus',
    'toStatus',
    'changedAt',
    'changedBy',
  };
  static const _effectiveStatusEventKeys = {'effectiveDate'};
  static const _pendingKeys = {
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
  };
  static const _pendingEventKeys = {
    'fromStatus',
    'toStatus',
    'effectiveDate',
    'changedAt',
    'changedBy',
  };
  static const _directoryKeys = {
    'uid',
    'name',
    'email',
    'studentCode',
    'updatedAt',
  };

  CollectionReference<Map<String, dynamic>> get _courses =>
      _firestore.collection('courses');

  CollectionReference<Map<String, dynamic>> get _directory =>
      _firestore.collection('student_directory');

  CollectionReference<Map<String, dynamic>> _enrollments(String courseId) =>
      _courses.doc(courseId).collection('enrollments');

  CollectionReference<Map<String, dynamic>> _pendingEnrollments(
    String courseId,
  ) => _courses.doc(courseId).collection('pending_enrollments');

  CollectionReference<Map<String, dynamic>> _statusEvents(
    String courseId,
    String studentUid,
  ) => _enrollments(courseId).doc(studentUid).collection('status_events');

  CollectionReference<Map<String, dynamic>> _pendingStatusEvents(
    String courseId,
    String email,
  ) => _pendingEnrollments(courseId).doc(email).collection('status_events');

  @override
  Future<void> ensureStudentDirectoryEntry() async {
    try {
      final user = _requireVerifiedUser();
      final uid = user.uid;
      final profile = await _requireProfile(user, role: 'student');
      _requireSameUser(uid);
      final email = EnrollmentValidator.exactEmail(user.email!);
      await _directory.doc(email).set({
        'uid': uid,
        'name': profile['name'],
        'email': email,
        'studentCode': profile['studentCode'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // The server has confirmed this write. A later account change must not
      // turn it into a reported failed publication.
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<StudentCandidate?> findStudentByEmail(String email) async {
    try {
      final searchedEmail = EnrollmentValidator.exactEmail(email);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final document = await _directory
          .doc(searchedEmail)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      if (!document.exists) return null;
      return _candidateFromDirectory(document, expectedEmail: searchedEmail);
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<PendingEnrollment?> getCoursePendingEnrollment({
    required String courseId,
    required String email,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      final exactEmail = EnrollmentValidator.exactEmail(email);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final document = await _pendingEnrollments(courseId)
          .doc(exactEmail)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      if (!document.exists) return null;
      return _pendingEnrollmentFromDocument(
        document,
        expectedCourseId: courseId,
      );
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<PendingEnrollmentPage> listCoursePendingEnrollments({
    required String courseId,
    required String status,
    PendingEnrollmentCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      _validatePageSize(pageSize);
      _validatePendingStatus(status, includeLinked: false);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      Query<Map<String, dynamic>> query = _pendingEnrollments(courseId)
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(pageSize + 1);
      if (cursor != null) {
        EnrollmentValidator.exactEmail(cursor.email);
        query = query.startAfter([
          Timestamp.fromDate(cursor.createdAt),
          cursor.email,
        ]);
      }
      final snapshot = await query.get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      return _pendingPageFromSnapshot(
        snapshot,
        pageSize: pageSize,
        expectedCourseId: courseId,
      );
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<CourseRosterSnapshot> loadCourseRosterSnapshot({
    required String courseId,
  }) async {
    EnrollmentValidator.documentId(courseId);
    final active = await _loadAllCourseEnrollments(
      courseId: courseId,
      status: 'active',
    );
    final withdrawn = await _loadAllCourseEnrollments(
      courseId: courseId,
      status: 'withdrawn',
    );
    final pending = await _loadAllCoursePendingEnrollments(
      courseId: courseId,
      status: 'pending',
    );
    final withdrawnPending = await _loadAllCoursePendingEnrollments(
      courseId: courseId,
      status: 'withdrawn',
    );
    return CourseRosterSnapshot(
      activeEnrollments: active,
      withdrawnEnrollments: withdrawn,
      pendingEnrollments: pending,
      withdrawnPendingEnrollments: withdrawnPending,
      complete: true,
    );
  }

  Future<List<Enrollment>> _loadAllCourseEnrollments({
    required String courseId,
    required String status,
  }) async {
    final items = <Enrollment>[];
    EnrollmentCursor? cursor;
    do {
      final page = await listCourseStudents(
        courseId: courseId,
        status: status,
        cursor: cursor,
        pageSize: 100,
      );
      items.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return List.unmodifiable(items);
  }

  Future<List<PendingEnrollment>> _loadAllCoursePendingEnrollments({
    required String courseId,
    required String status,
  }) async {
    final items = <PendingEnrollment>[];
    PendingEnrollmentCursor? cursor;
    do {
      final page = await listCoursePendingEnrollments(
        courseId: courseId,
        status: status,
        cursor: cursor,
        pageSize: 100,
      );
      items.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return List.unmodifiable(items);
  }

  @override
  Future<List<Enrollment>> findCourseEnrollmentsByEmail({
    required String courseId,
    required String email,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      final exactEmail = EnrollmentValidator.exactEmail(email);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final snapshot = await _enrollments(courseId)
          .where('email', isEqualTo: exactEmail)
          .limit(2)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      final matches = snapshot.docs
          .map(
            (document) => _enrollmentFromDocument(document, courseId: courseId),
          )
          .toList(growable: false);
      return List.unmodifiable(matches);
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<CourseRosterIdentityLookup> findCourseRosterByStudentCode({
    required String courseId,
    required String studentCode,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      final code = studentCode.trim();
      if (code.isEmpty || code.length > 40) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
      }
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      const resultLimit = 3;
      final enrollmentSnapshot = await _enrollments(courseId)
          .where('studentCode', isEqualTo: code)
          .limit(resultLimit)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      final pendingSnapshot = await _pendingEnrollments(courseId)
          .where('studentCode', isEqualTo: code)
          .limit(resultLimit)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      final enrollmentDocuments = enrollmentSnapshot.docs
          .take(2)
          .toList(growable: false);
      final pendingDocuments = pendingSnapshot.docs
          .take(2)
          .toList(growable: false);
      return CourseRosterIdentityLookup(
        enrollmentMatches: enrollmentDocuments
            .map(
              (document) =>
                  _enrollmentFromDocument(document, courseId: courseId),
            )
            .toList(growable: false),
        pendingMatches: pendingDocuments
            .map(
              (document) => _pendingEnrollmentFromDocument(
                document,
                expectedCourseId: courseId,
              ),
            )
            .toList(growable: false),
        hasMoreEnrollmentMatches: enrollmentSnapshot.docs.length > 2,
        hasMorePendingMatches: pendingSnapshot.docs.length > 2,
      );
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<PendingEnrollmentWriteResult> authorizePendingEnrollment({
    required Course course,
    required String email,
    required String studentCode,
    required String name,
    required AcademicDate effectiveStartDate,
  }) async {
    try {
      EnrollmentValidator.documentId(course.id);
      final exactEmail = EnrollmentValidator.exactEmail(email);
      final code = studentCode.trim();
      final normalizedName = name.trim();
      if (code.isEmpty ||
          code.length > 40 ||
          normalizedName.isEmpty ||
          normalizedName.length > 100) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
      }
      _validateEffectiveDateForCourse(
        effectiveStartDate,
        course.schedule.startDate,
        course.schedule.endDate,
        allowFutureCourseStart: true,
      );
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      if (course.ownerUid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
      }
      final courseRef = _courses.doc(course.id);
      final directoryRef = _directory.doc(exactEmail);
      final pendingRef = _pendingEnrollments(course.id).doc(exactEmail);
      return await _firestore.runTransaction<PendingEnrollmentWriteResult>((
        transaction,
      ) async {
        _requireSameUser(uid);
        final courseSnapshot = await transaction.get(courseRef);
        final directorySnapshot = await transaction.get(directoryRef);
        final pendingSnapshot = await transaction.get(pendingRef);
        _requireSameUser(uid);
        final persistedCourse = courseSnapshot.data();
        if (!courseSnapshot.exists ||
            persistedCourse == null ||
            persistedCourse['ownerUid'] != uid ||
            persistedCourse['subject'] != course.subject ||
            persistedCourse['group'] != course.group ||
            persistedCourse['period'] != course.period) {
          throw const EnrollmentFailure(
            EnrollmentFailureKind.courseUnavailable,
          );
        }
        if (directorySnapshot.exists) {
          // A matching account appeared after comparison. The caller must
          // re-read the exact directory candidate and decide whether to link.
          throw const EnrollmentFailure(EnrollmentFailureKind.candidateChanged);
        }
        if (pendingSnapshot.exists) {
          final current = _pendingEnrollmentFromDocument(
            pendingSnapshot,
            expectedCourseId: course.id,
          );
          if (current.status == 'pending' &&
              current.ownerUid == uid &&
              current.email == exactEmail &&
              current.studentCode == code &&
              current.name == normalizedName &&
              current.effectiveStartDate == effectiveStartDate &&
              current.subject == course.subject &&
              current.group == course.group &&
              current.period == course.period) {
            return const PendingEnrollmentWriteResult(
              PendingEnrollmentWriteKind.alreadyPending,
            );
          }
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }
        transaction.set(pendingRef, {
          'courseId': course.id,
          'ownerUid': uid,
          'subject': course.subject,
          'group': course.group,
          'period': course.period,
          'email': exactEmail,
          'studentCode': code,
          'name': normalizedName,
          'status': 'pending',
          'effectiveStartDate': Timestamp.fromDate(
            effectiveStartDate.toUtcTimestamp(),
          ),
          'rosterEntryId': exactEmail,
          'studentUid': null,
          'authorizedAt': FieldValue.serverTimestamp(),
          'linkedAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastEventId': null,
          'lastStatusChangedAt': null,
        });
        return const PendingEnrollmentWriteResult(
          PendingEnrollmentWriteKind.created,
        );
      });
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  String newPendingStatusEventId({
    required String courseId,
    required String email,
  }) {
    EnrollmentValidator.documentId(courseId);
    final exactEmail = EnrollmentValidator.exactEmail(email);
    return _pendingStatusEvents(courseId, exactEmail).doc().id;
  }

  @override
  Future<PendingEnrollmentStatusChangeResult> changePendingEnrollmentStatus({
    required PendingEnrollment expected,
    required String nextStatus,
    required String operationId,
    required AcademicDate effectiveDate,
  }) async {
    try {
      EnrollmentValidator.documentId(expected.courseId);
      final exactEmail = EnrollmentValidator.exactEmail(expected.email);
      EnrollmentValidator.documentId(operationId);
      if (expected.rosterEntryId != exactEmail ||
          expected.status == nextStatus ||
          !((expected.status == 'pending' && nextStatus == 'withdrawn') ||
              (expected.status == 'withdrawn' && nextStatus == 'pending'))) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
      }
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      if (expected.ownerUid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
      }
      final courseRef = _courses.doc(expected.courseId);
      final pendingRef = _pendingEnrollments(expected.courseId).doc(exactEmail);
      final eventRef = _pendingStatusEvents(
        expected.courseId,
        exactEmail,
      ).doc(operationId);
      return await _firestore.runTransaction<
        PendingEnrollmentStatusChangeResult
      >((transaction) async {
        _requireSameUser(uid);
        final courseSnapshot = await transaction.get(courseRef);
        final pendingSnapshot = await transaction.get(pendingRef);
        final eventSnapshot = await transaction.get(eventRef);
        _requireSameUser(uid);
        final courseData = courseSnapshot.data();
        if (!courseSnapshot.exists ||
            courseData == null ||
            courseData['ownerUid'] != uid) {
          throw const EnrollmentFailure(
            EnrollmentFailureKind.courseUnavailable,
          );
        }
        if (!pendingSnapshot.exists) {
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }
        final current = _pendingEnrollmentFromDocument(
          pendingSnapshot,
          expectedCourseId: expected.courseId,
        );
        if (eventSnapshot.exists) {
          final event = _pendingEventFromDocument(eventSnapshot);
          if (current.lastEventId == operationId &&
              current.status == nextStatus &&
              event.fromStatus == expected.status &&
              event.toStatus == nextStatus &&
              event.changedBy == uid &&
              event.effectiveDate == effectiveDate &&
              _sameInstant(current.lastStatusChangedAt, event.changedAt)) {
            return PendingEnrollmentStatusChangeResult(
              status: nextStatus,
              operationId: operationId,
              alreadyApplied: true,
            );
          }
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }
        if (!_samePendingVersion(current, expected) ||
            current.lastEventId == operationId) {
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }
        PendingEnrollmentStatusEvent? previousEvent;
        if (current.lastEventId != null) {
          final previousEventSnapshot = await transaction.get(
            _pendingStatusEvents(
              expected.courseId,
              exactEmail,
            ).doc(current.lastEventId),
          );
          if (!previousEventSnapshot.exists) {
            throw const EnrollmentFailure(
              EnrollmentFailureKind.staleEnrollment,
            );
          }
          previousEvent = _pendingEventFromDocument(previousEventSnapshot);
        }
        final courseDates = _courseDateRange(courseData);
        if (nextStatus == 'pending') {
          _validateEffectiveDateForCourse(
            effectiveDate,
            courseDates.$1,
            courseDates.$2,
            allowFutureCourseStart: true,
          );
          if (previousEvent == null) {
            throw const EnrollmentFailure(EnrollmentFailureKind.invalidData);
          }
          if (effectiveDate.compareTo(previousEvent.effectiveDate) < 0) {
            throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
          }
        } else {
          // An upcoming, not-yet-linked row can be withdrawn before its
          // effective start date. The decision itself still cannot be
          // backdated or placed after the course ends.
          final today = _todayInBogota();
          if (effectiveDate.compareTo(today) > 0 ||
              effectiveDate.compareTo(courseDates.$2) > 0 ||
              effectiveDate.compareTo(_bogotaDate(current.authorizedAt)) < 0) {
            throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
          }
          final futureStart = current.effectiveStartDate.compareTo(today) > 0;
          final previousEffectiveDate =
              previousEvent?.effectiveDate ?? current.effectiveStartDate;
          if (!futureStart &&
              effectiveDate.compareTo(previousEffectiveDate) < 0) {
            throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
          }
        }
        final newStartDate = nextStatus == 'pending'
            ? effectiveDate
            : current.effectiveStartDate;
        transaction.update(pendingRef, {
          'status': nextStatus,
          'effectiveStartDate': Timestamp.fromDate(
            newStartDate.toUtcTimestamp(),
          ),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastEventId': operationId,
          'lastStatusChangedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(eventRef, {
          'fromStatus': current.status,
          'toStatus': nextStatus,
          'effectiveDate': Timestamp.fromDate(effectiveDate.toUtcTimestamp()),
          'changedAt': FieldValue.serverTimestamp(),
          'changedBy': uid,
        });
        return PendingEnrollmentStatusChangeResult(
          status: nextStatus,
          operationId: operationId,
          alreadyApplied: false,
        );
      });
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<PendingEnrollmentLinkSummary> linkOwnPendingEnrollments() async {
    final firstUser = _auth.currentUser;
    if (firstUser == null) {
      throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
    }
    final uid = firstUser.uid;
    try {
      await firstUser.reload();
      var user = _auth.currentUser;
      if (user == null || user.uid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
      }
      if (!user.emailVerified || user.email == null) {
        throw const EnrollmentFailure(EnrollmentFailureKind.emailNotVerified);
      }
      await user.getIdToken(true);
      user = _auth.currentUser;
      if (user == null || user.uid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
      }
      final exactEmail = EnrollmentValidator.exactEmail(user.email!);
      final profile = await _requireProfile(user, role: 'student');
      final rawCode = profile['studentCode'];
      if (rawCode is! String || rawCode.trim().isEmpty) {
        return PendingEnrollmentLinkSummary(
          rows: const [],
          studentCodeMissing: true,
        );
      }
      final studentCode = rawCode.trim();
      _requireSameUser(uid);

      const pageSize = 25;
      Query<Map<String, dynamic>> query = _firestore
          .collectionGroup('pending_enrollments')
          .where('email', isEqualTo: exactEmail)
          .where('studentCode', isEqualTo: studentCode)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(pageSize + 1);
      final results = <PendingEnrollmentLinkRowResult>[];
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      while (true) {
        _requireSameUser(uid);
        final pageQuery = cursor == null
            ? query
            : query.startAfterDocument(cursor);
        final snapshot = await pageQuery.get(
          const GetOptions(source: Source.server),
        );
        _requireSameUser(uid);
        final hasMore = snapshot.docs.length > pageSize;
        final visible = snapshot.docs.take(pageSize).toList(growable: false);
        for (final document in visible) {
          _requireSameUser(uid);
          final courseId = _courseIdFromPendingPath(document.reference.path);
          final pending = _pendingEnrollmentFromDocument(
            document,
            expectedCourseId: courseId,
          );
          if (pending.email != exactEmail ||
              pending.studentCode != studentCode ||
              pending.status != 'pending') {
            continue;
          }
          try {
            results.add(
              await _linkPendingEnrollment(
                pending: pending,
                studentUid: uid,
                email: exactEmail,
                studentCode: studentCode,
              ),
            );
          } on EnrollmentFailure catch (error) {
            if (error.kind == EnrollmentFailureKind.unauthenticated ||
                error.kind == EnrollmentFailureKind.emailNotVerified) {
              rethrow;
            }
            results.add(
              PendingEnrollmentLinkRowResult(
                courseId: courseId,
                email: exactEmail,
                outcome:
                    error.kind == EnrollmentFailureKind.staleEnrollment ||
                        error.kind == EnrollmentFailureKind.candidateChanged
                    ? PendingEnrollmentLinkOutcome.needsReview
                    : PendingEnrollmentLinkOutcome.failed,
                failureKind: error.kind,
              ),
            );
          } on FirebaseException catch (error) {
            final failure = _translate(error);
            results.add(
              PendingEnrollmentLinkRowResult(
                courseId: courseId,
                email: exactEmail,
                outcome: failure.kind == EnrollmentFailureKind.permissionDenied
                    ? PendingEnrollmentLinkOutcome.needsReview
                    : PendingEnrollmentLinkOutcome.failed,
                failureKind: failure.kind,
              ),
            );
          }
        }
        if (!hasMore || visible.isEmpty) break;
        cursor = visible.last;
      }
      _requireSameUser(uid);
      return PendingEnrollmentLinkSummary(rows: results);
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
    AcademicDate? effectiveStartDate,
    bool resolvePendingWhenAlreadyEnrolled = true,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      EnrollmentValidator.documentId(candidate.uid);
      final exactEmail = EnrollmentValidator.exactEmail(candidate.email);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final courseRef = _courses.doc(courseId);
      final directoryRef = _directory.doc(candidate.email);
      final enrollmentRef = _enrollments(courseId).doc(candidate.uid);
      final pendingRef = _pendingEnrollments(courseId).doc(exactEmail);
      final pendingLinkId = _pendingLinkOperationId(exactEmail);
      final pendingLinkEventRef = _pendingStatusEvents(
        courseId,
        exactEmail,
      ).doc(pendingLinkId);
      final joinRequestRef = _courses
          .doc(courseId)
          .collection('join_requests')
          .doc(candidate.uid);

      // A retry reads the same stable document ID. Nothing after this
      // transaction is required to declare a confirmed write successful.
      return await _firestore.runTransaction<EnrollmentResult>((tx) async {
        _requireSameUser(uid);
        final courseDoc = await tx.get(courseRef);
        final existingDoc = await tx.get(enrollmentRef);
        final joinRequestDoc = await tx.get(joinRequestRef);
        final pendingDoc = await tx.get(pendingRef);
        final pendingLinkEventDoc = await tx.get(pendingLinkEventRef);
        _requireSameUser(uid);

        final course = courseDoc.data();
        if (!courseDoc.exists ||
            course == null ||
            course['ownerUid'] != uid ||
            course['subject'] is! String ||
            course['group'] is! String ||
            course['period'] is! String) {
          throw const EnrollmentFailure(
            EnrollmentFailureKind.courseUnavailable,
          );
        }
        if (existingDoc.exists) {
          final enrollment = _enrollmentFromDocument(
            existingDoc,
            courseId: courseId,
          );
          if (enrollment.ownerUid != uid ||
              enrollment.studentUid != candidate.uid) {
            throw const EnrollmentFailure(
              EnrollmentFailureKind.permissionDenied,
            );
          }
          if (pendingDoc.exists) {
            final pending = _pendingEnrollmentFromDocument(
              pendingDoc,
              expectedCourseId: courseId,
            );
            if (pending.status == 'withdrawn' ||
                pending.email != exactEmail ||
                pending.studentCode != candidate.studentCode ||
                !_sameLinkedEnrollment(
                  enrollment,
                  rawEnrollmentData: existingDoc.data()!,
                  pending: pending,
                  studentUid: candidate.uid,
                )) {
              throw const EnrollmentFailure(
                EnrollmentFailureKind.staleEnrollment,
              );
            }
            if (pending.status == 'pending') {
              if (enrollment.status != 'active' || pendingLinkEventDoc.exists) {
                throw const EnrollmentFailure(
                  EnrollmentFailureKind.staleEnrollment,
                );
              }
              tx.update(
                pendingRef,
                _pendingLinkUpdate(exactEmail, candidate.uid),
              );
              tx.set(pendingLinkEventRef, _pendingLinkEvent(pending, uid));
            } else if (pending.status != 'linked' ||
                !_isConsistentPendingLink(
                  pending,
                  pendingLinkEventDoc,
                  studentUid: candidate.uid,
                )) {
              throw const EnrollmentFailure(
                EnrollmentFailureKind.staleEnrollment,
              );
            }
          }
          // A manual invite must not silently reactivate a withdrawn student
          // or resolve a join request as approved. Reinstatement is an explicit
          // status transition with its own audit event.
          if (resolvePendingWhenAlreadyEnrolled &&
              enrollment.status == 'active' &&
              joinRequestDoc.exists &&
              joinRequestDoc.data()?['status'] == 'pending' &&
              enrollment.email == exactEmail &&
              enrollment.studentCode == candidate.studentCode &&
              _joinRequestMatches(
                joinRequestDoc.data(),
                studentUid: candidate.uid,
                email: exactEmail,
                studentCode: candidate.studentCode,
                subject: course['subject'] as String,
                group: course['group'] as String,
                period: course['period'] as String,
              )) {
            _requireSameUser(uid);
            tx.update(joinRequestRef, {
              'status': 'approved',
              'decidedBy': uid,
              'decidedAt': FieldValue.serverTimestamp(),
              'rejectionReason': null,
            });
          }
          return EnrollmentResult(
            enrollment: enrollment,
            alreadyEnrolled: true,
          );
        }

        // A retry of an uncertain commit must recover the existing stable
        // enrollment even if the student's directory entry has since changed.
        // A new create, however, requires the reviewed identity to be current.
        final directoryDoc = await tx.get(directoryRef);
        _requireSameUser(uid);
        if (!directoryDoc.exists) {
          throw const EnrollmentFailure(EnrollmentFailureKind.candidateChanged);
        }
        final current = _candidateFromDirectory(
          directoryDoc,
          expectedEmail: candidate.email,
        );
        if (!_sameCandidate(candidate, current)) {
          throw const EnrollmentFailure(EnrollmentFailureKind.candidateChanged);
        }

        final courseDates = _courseDateRange(course);
        final pending = pendingDoc.exists
            ? _pendingEnrollmentFromDocument(
                pendingDoc,
                expectedCourseId: courseId,
              )
            : null;
        if (pending != null &&
            (pending.status != 'pending' ||
                pending.email != exactEmail ||
                pending.studentCode != current.studentCode ||
                pending.ownerUid != uid ||
                pending.subject != course['subject'] ||
                pending.group != course['group'] ||
                pending.period != course['period'])) {
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }
        if (pending != null && pendingLinkEventDoc.exists) {
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }
        final effectiveDate =
            pending?.effectiveStartDate ??
            effectiveStartDate ??
            _defaultEffectiveStartDate(courseDates.$1, courseDates.$2);
        _validateEffectiveDateForCourse(
          effectiveDate,
          courseDates.$1,
          courseDates.$2,
          allowFutureCourseStart: true,
        );

        final enrollment = Enrollment(
          courseId: courseId,
          studentUid: current.uid,
          ownerUid: uid,
          name: pending?.name ?? current.name,
          email: current.email,
          studentCode: current.studentCode,
          subject: course['subject'] as String,
          group: course['group'] as String,
          period: course['period'] as String,
          status: 'active',
          createdAt: null,
          rosterEntryId: exactEmail,
          effectiveStartDate: effectiveDate,
        );
        _requireSameUser(uid);
        tx.set(enrollmentRef, {
          'studentUid': enrollment.studentUid,
          'ownerUid': enrollment.ownerUid,
          'name': enrollment.name,
          'email': enrollment.email,
          'studentCode': enrollment.studentCode,
          'subject': enrollment.subject,
          'group': enrollment.group,
          'period': enrollment.period,
          'status': enrollment.status,
          'rosterEntryId': exactEmail,
          'effectiveStartDate': Timestamp.fromDate(
            effectiveDate.toUtcTimestamp(),
          ),
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (pending != null) {
          tx.update(pendingRef, _pendingLinkUpdate(exactEmail, current.uid));
          tx.set(pendingLinkEventRef, _pendingLinkEvent(pending, uid));
        }
        if (joinRequestDoc.exists &&
            joinRequestDoc.data()?['status'] == 'pending' &&
            _joinRequestMatches(
              joinRequestDoc.data(),
              studentUid: current.uid,
              email: current.email,
              studentCode: current.studentCode,
              subject: course['subject'] as String,
              group: course['group'] as String,
              period: course['period'] as String,
            )) {
          _requireSameUser(uid);
          tx.update(joinRequestRef, {
            'status': 'approved',
            'decidedBy': uid,
            'decidedAt': FieldValue.serverTimestamp(),
            'rejectionReason': null,
          });
        }
        return EnrollmentResult(enrollment: enrollment, alreadyEnrolled: false);
      });
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  String newStatusEventId({
    required String courseId,
    required String studentUid,
  }) {
    EnrollmentValidator.documentId(courseId);
    EnrollmentValidator.documentId(studentUid);
    return _statusEvents(courseId, studentUid).doc().id;
  }

  @override
  Future<EnrollmentStatusChangeResult> changeEnrollmentStatus({
    required Enrollment expected,
    required String nextStatus,
    required String operationId,
    AcademicDate? effectiveDate,
  }) async {
    try {
      EnrollmentValidator.documentId(expected.courseId);
      EnrollmentValidator.documentId(expected.studentUid);
      EnrollmentValidator.documentId(operationId);
      if (expected.status != 'active' && expected.status != 'withdrawn' ||
          nextStatus != 'active' && nextStatus != 'withdrawn' ||
          expected.status == nextStatus) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
      }

      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      if (expected.ownerUid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
      }
      final courseRef = _courses.doc(expected.courseId);
      final enrollmentRef = _enrollments(expected.courseId)
          .doc(expected.studentUid);
      final eventRef = _statusEvents(
        expected.courseId,
        expected.studentUid,
      ).doc(operationId);

      return await _firestore.runTransaction<EnrollmentStatusChangeResult>((
        transaction,
      ) async {
        _requireSameUser(uid);
        final courseDocument = await transaction.get(courseRef);
        final enrollmentDocument = await transaction.get(enrollmentRef);
        final eventDocument = await transaction.get(eventRef);
        _requireSameUser(uid);

        final course = courseDocument.data();
        if (!courseDocument.exists ||
            course == null ||
            course['ownerUid'] != uid ||
            course['subject'] is! String ||
            course['group'] is! String ||
            course['period'] is! String) {
          throw const EnrollmentFailure(
            EnrollmentFailureKind.courseUnavailable,
          );
        }
        if (!enrollmentDocument.exists) {
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }
        final current = _enrollmentFromDocument(
          enrollmentDocument,
          courseId: expected.courseId,
        );
        if (current.ownerUid != uid ||
            current.studentUid != expected.studentUid) {
          throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
        }

        if (eventDocument.exists) {
          final event = _statusEventFromDocument(eventDocument);
          if (current.lastStatusEventId == operationId &&
              current.status == nextStatus &&
              event.fromStatus == expected.status &&
              event.toStatus == nextStatus &&
              event.changedBy == uid &&
              _sameInstant(current.lastStatusChangedAt, event.changedAt)) {
            return EnrollmentStatusChangeResult(
              enrollment: current,
              alreadyApplied: true,
            );
          }
          // The ID exists but is no longer the latest event. Replaying it
          // after another status cycle must never apply it a second time.
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }

        if (current.lastStatusEventId == operationId ||
            !_sameEnrollmentVersion(current, expected) ||
            !_isAllowedStatusTransition(current.status, nextStatus)) {
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }

        EnrollmentStatusEvent? previousEvent;
        if (current.lastStatusEventId != null) {
          final previousEventRef = _statusEvents(
            expected.courseId,
            expected.studentUid,
          ).doc(current.lastStatusEventId);
          final previousEventSnapshot = await transaction.get(previousEventRef);
          if (!previousEventSnapshot.exists) {
            throw const EnrollmentFailure(
              EnrollmentFailureKind.staleEnrollment,
            );
          }
          previousEvent = _statusEventFromDocument(previousEventSnapshot);
        }
        final courseDates = _courseDateRange(course);
        final today = _todayInBogota();
        final canCancelBeforeCourseStart =
            nextStatus == 'withdrawn' &&
            current.effectiveStartDate!.compareTo(today) > 0;
        final changeDate =
            effectiveDate ??
            (canCancelBeforeCourseStart
                ? today
                : _defaultEffectiveStartDate(courseDates.$1, courseDates.$2));
        if (canCancelBeforeCourseStart) {
          if (changeDate.compareTo(today) > 0 ||
              changeDate.compareTo(courseDates.$2) > 0 ||
              changeDate.compareTo(_bogotaDate(current.createdAt!)) < 0) {
            throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
          }
        } else {
          _validateEffectiveDateForCourse(
            changeDate,
            courseDates.$1,
            courseDates.$2,
            allowFutureCourseStart: nextStatus == 'active',
          );
        }
        final previousEffectiveDate = canCancelBeforeCourseStart
            ? _bogotaDate(current.createdAt!)
            : previousEvent?.effectiveDate ?? current.effectiveStartDate!;
        if (changeDate.compareTo(previousEffectiveDate) < 0) {
          throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
        }

        _requireSameUser(uid);
        transaction.update(enrollmentRef, {
          'status': nextStatus,
          'lastStatusEventId': operationId,
          'lastStatusChangedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(eventRef, {
          'fromStatus': current.status,
          'toStatus': nextStatus,
          'effectiveDate': Timestamp.fromDate(changeDate.toUtcTimestamp()),
          'changedAt': FieldValue.serverTimestamp(),
          'changedBy': uid,
        });
        return EnrollmentStatusChangeResult(
          enrollment: _copyWithStatus(
            current,
            status: nextStatus,
            eventId: operationId,
          ),
          alreadyApplied: false,
        );
      });
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<Enrollment> getCourseEnrollment({
    required String courseId,
    required String studentUid,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      EnrollmentValidator.documentId(studentUid);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      final profile = await _requireValidProfile(user);
      final document = await _enrollments(courseId)
          .doc(studentUid)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      if (!document.exists) {
        throw const EnrollmentFailure(EnrollmentFailureKind.courseUnavailable);
      }
      final enrollment = _enrollmentFromDocument(document, courseId: courseId);
      final roles = profile['roles'] as List;
      final isStudentReadingOwnEnrollment =
          roles.contains('student') && enrollment.studentUid == uid;
      final isTeacherReadingOwnedEnrollment =
          roles.contains('teacher') && enrollment.ownerUid == uid;
      if (enrollment.studentUid != studentUid ||
          (!isStudentReadingOwnEnrollment &&
              !isTeacherReadingOwnedEnrollment)) {
        throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
      }
      return enrollment;
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<Enrollment?> findCourseEnrollmentByUid({
    required String courseId,
    required String studentUid,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      EnrollmentValidator.documentId(studentUid);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final document = await _enrollments(courseId)
          .doc(studentUid)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      if (!document.exists) return null;
      final enrollment = _enrollmentFromDocument(document, courseId: courseId);
      if (enrollment.ownerUid != uid || enrollment.studentUid != studentUid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
      }
      return enrollment;
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<EnrollmentHistoryPage> listEnrollmentHistory({
    required String courseId,
    required String studentUid,
    EnrollmentHistoryCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      EnrollmentValidator.documentId(studentUid);
      _validatePageSize(pageSize);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      final enrollment = await getCourseEnrollment(
        courseId: courseId,
        studentUid: studentUid,
      );
      _requireSameUser(uid);
      if (enrollment.ownerUid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
      }

      Query<Map<String, dynamic>> query = _statusEvents(courseId, studentUid)
          .orderBy('changedAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(pageSize + 1);
      if (cursor != null) {
        EnrollmentValidator.documentId(cursor.operationId);
        query = query.startAfter([
          Timestamp.fromDate(cursor.changedAt),
          cursor.operationId,
        ]);
      }
      final snapshot = await query.get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      final hasMore = snapshot.docs.length > pageSize;
      final visible = snapshot.docs.take(pageSize).toList(growable: false);
      final events = visible
          .map(_statusEventFromDocument)
          .toList(growable: false);
      if (events.any((event) => event.changedBy != enrollment.ownerUid)) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidData);
      }
      final last = hasMore && visible.isNotEmpty ? events.last : null;
      return EnrollmentHistoryPage(
        items: events,
        nextCursor: last == null
            ? null
            : EnrollmentHistoryCursor(
                changedAt: last.changedAt,
                operationId: last.operationId,
              ),
      );
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<PendingEnrollmentHistoryPage> listPendingEnrollmentHistory({
    required String courseId,
    required String email,
    PendingEnrollmentHistoryCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      final exactEmail = EnrollmentValidator.exactEmail(email);
      _validatePageSize(pageSize);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final pending = await getCoursePendingEnrollment(
        courseId: courseId,
        email: exactEmail,
      );
      _requireSameUser(uid);
      if (pending == null || pending.ownerUid != uid) {
        throw const EnrollmentFailure(EnrollmentFailureKind.courseUnavailable);
      }
      Query<Map<String, dynamic>> query =
          _pendingStatusEvents(courseId, exactEmail)
              .orderBy('changedAt', descending: true)
              .orderBy(FieldPath.documentId, descending: true)
              .limit(pageSize + 1);
      if (cursor != null) {
        EnrollmentValidator.documentId(cursor.operationId);
        query = query.startAfter([
          Timestamp.fromDate(cursor.changedAt),
          cursor.operationId,
        ]);
      }
      final snapshot = await query.get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      final hasMore = snapshot.docs.length > pageSize;
      final visible = snapshot.docs.take(pageSize).toList(growable: false);
      final events = visible
          .map(_pendingEventFromDocument)
          .toList(growable: false);
      if (events.any(
        (event) =>
            event.changedBy != uid && event.changedBy != pending.studentUid,
      )) {
        throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
      }
      final last = hasMore && visible.isNotEmpty ? events.last : null;
      return PendingEnrollmentHistoryPage(
        items: events,
        nextCursor: last == null
            ? null
            : PendingEnrollmentHistoryCursor(
                changedAt: last.changedAt,
                operationId: last.operationId,
              ),
      );
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<EnrollmentPage> listCourseStudents({
    required String courseId,
    String status = 'active',
    EnrollmentCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      _validatePageSize(pageSize);
      _validateEnrollmentStatus(status);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      Query<Map<String, dynamic>> query = _enrollments(courseId)
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(pageSize + 1);
      if (cursor != null) {
        query = query.startAfter([
          Timestamp.fromDate(cursor.createdAt),
          cursor.documentPath.split('/').last,
        ]);
      }
      final snapshot = await query.get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      return _pageFromSnapshot(
        snapshot,
        pageSize: pageSize,
        expectedCourseId: courseId,
      );
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<EnrollmentPage> listMyCourses({
    EnrollmentCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      _validatePageSize(pageSize);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'student');
      Query<Map<String, dynamic>> query = _firestore
          .collectionGroup('enrollments')
          .where('studentUid', isEqualTo: uid)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(pageSize + 1);
      if (cursor != null) {
        query = query.startAfter([
          Timestamp.fromDate(cursor.createdAt),
          cursor.documentPath,
        ]);
      }
      final snapshot = await query.get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      final page = _pageFromSnapshot(snapshot, pageSize: pageSize);
      if (page.items.any((item) => item.studentUid != uid)) {
        throw const EnrollmentFailure(EnrollmentFailureKind.permissionDenied);
      }
      return page;
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  @override
  Future<int> countCourseStudents(String courseId) async {
    try {
      EnrollmentValidator.documentId(courseId);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final result = await _enrollments(courseId)
          .where('status', isEqualTo: 'active')
          .count()
          .get(source: AggregateSource.server);
      _requireSameUser(uid);
      final count = result.count;
      if (count == null) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidData);
      }
      return count;
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<int> countCoursePendingEnrollments(String courseId) async {
    try {
      EnrollmentValidator.documentId(courseId);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final result = await _pendingEnrollments(courseId)
          .where('status', isEqualTo: 'pending')
          .count()
          .get(source: AggregateSource.server);
      _requireSameUser(uid);
      final count = result.count;
      if (count == null) {
        throw const EnrollmentFailure(EnrollmentFailureKind.invalidData);
      }
      return count;
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<Course> getMyEnrolledCourse(String courseId) async {
    try {
      EnrollmentValidator.documentId(courseId);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'student');
      final course = await FirestoreCourseRepository(
        auth: _auth,
        firestore: _firestore,
      ).getEnrolledCourse(courseId);
      _requireSameUser(uid);
      return course;
    } on EnrollmentFailure {
      rethrow;
    } on CourseFailure catch (error) {
      throw switch (error.kind) {
        CourseFailureKind.unauthenticated => const EnrollmentFailure(
          EnrollmentFailureKind.unauthenticated,
        ),
        CourseFailureKind.permissionDenied => EnrollmentFailure(
          EnrollmentFailureKind.permissionDenied,
          cause: error,
        ),
        CourseFailureKind.network => EnrollmentFailure(
          EnrollmentFailureKind.network,
          cause: error,
        ),
        _ => EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error),
      };
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  EnrollmentPage _pageFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required int pageSize,
    String? expectedCourseId,
  }) {
    final hasMore = snapshot.docs.length > pageSize;
    final visible = snapshot.docs.take(pageSize).toList(growable: false);
    final items = visible
        .map(
          (doc) => _enrollmentFromDocument(
            doc,
            courseId: expectedCourseId ?? _courseIdFromPath(doc.reference.path),
          ),
        )
        .toList(growable: false);
    final last = hasMore && visible.isNotEmpty ? visible.last : null;
    final lastDate = items.isNotEmpty ? items.last.createdAt : null;
    if (last != null && lastDate == null) {
      throw const FormatException('Missing enrollment cursor timestamp.');
    }
    return EnrollmentPage(
      items: items,
      nextCursor: last == null
          ? null
          : EnrollmentCursor(
              createdAt: lastDate!,
              documentPath: last.reference.path,
            ),
    );
  }

  PendingEnrollmentPage _pendingPageFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required int pageSize,
    required String expectedCourseId,
  }) {
    final hasMore = snapshot.docs.length > pageSize;
    final visible = snapshot.docs.take(pageSize).toList(growable: false);
    final items = visible
        .map(
          (document) => _pendingEnrollmentFromDocument(
            document,
            expectedCourseId: expectedCourseId,
          ),
        )
        .toList(growable: false);
    final last = hasMore && visible.isNotEmpty ? visible.last : null;
    return PendingEnrollmentPage(
      items: items,
      nextCursor: last == null
          ? null
          : PendingEnrollmentCursor(
              createdAt: items.last.createdAt,
              email: last.id,
            ),
    );
  }

  String _courseIdFromPath(String path) {
    final pieces = path.split('/');
    if (pieces.length != 4 ||
        pieces[0] != 'courses' ||
        pieces[2] != 'enrollments') {
      throw const FormatException('Invalid enrollment path.');
    }
    return pieces[1];
  }

  String _courseIdFromPendingPath(String path) {
    final pieces = path.split('/');
    if (pieces.length != 4 ||
        pieces[0] != 'courses' ||
        pieces[2] != 'pending_enrollments') {
      throw const FormatException('Invalid pending enrollment path.');
    }
    return pieces[1];
  }

  Enrollment _enrollmentFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String courseId,
  }) {
    final data = document.data();
    final keys = data?.keys.toSet() ?? const <String>{};
    final hasEventId = data?.containsKey('lastStatusEventId') ?? false;
    final hasChangedAt = data?.containsKey('lastStatusChangedAt') ?? false;
    final hasRosterEntryId = data?.containsKey('rosterEntryId') ?? false;
    final hasEffectiveStartDate =
        data?.containsKey('effectiveStartDate') ?? false;
    if (!document.exists ||
        data == null ||
        !keys.containsAll(_enrollmentKeys) ||
        keys.difference({
          ..._enrollmentKeys,
          ..._enrollmentTransitionKeys,
          ..._enrollmentRosterKeys,
        }).isNotEmpty ||
        hasEventId != hasChangedAt ||
        hasRosterEntryId != hasEffectiveStartDate ||
        data['studentUid'] != document.id ||
        data['ownerUid'] is! String ||
        data['name'] is! String ||
        data['email'] is! String ||
        !(data['studentCode'] == null || data['studentCode'] is String) ||
        data['subject'] is! String ||
        data['group'] is! String ||
        data['period'] is! String ||
        (data['status'] != 'active' && data['status'] != 'withdrawn') ||
        data['createdAt'] is! Timestamp) {
      throw const FormatException('Invalid enrollment document.');
    }
    if (hasEventId &&
        (data['lastStatusEventId'] is! String ||
            (data['lastStatusEventId'] as String).isEmpty ||
            data['lastStatusChangedAt'] is! Timestamp)) {
      throw const FormatException('Invalid enrollment transition marker.');
    }
    if (hasRosterEntryId &&
        (data['rosterEntryId'] != data['email'] ||
            data['rosterEntryId'] is! String ||
            (data['rosterEntryId'] as String).isEmpty ||
            data['effectiveStartDate'] is! Timestamp)) {
      throw const FormatException('Invalid enrollment roster identity.');
    }
    final createdAt = (data['createdAt'] as Timestamp).toDate();
    final effectiveStartDate = hasEffectiveStartDate
        ? _academicDateFromTimestamp(data['effectiveStartDate'])
        : _bogotaDate(createdAt);
    return Enrollment(
      courseId: courseId,
      studentUid: data['studentUid'] as String,
      ownerUid: data['ownerUid'] as String,
      name: data['name'] as String,
      email: data['email'] as String,
      studentCode: data['studentCode'] as String?,
      subject: data['subject'] as String,
      group: data['group'] as String,
      period: data['period'] as String,
      status: data['status'] as String,
      createdAt: createdAt,
      rosterEntryId: hasRosterEntryId
          ? data['rosterEntryId'] as String
          : 'legacy:${data['studentUid']}',
      effectiveStartDate: effectiveStartDate,
      lastStatusEventId: hasEventId
          ? data['lastStatusEventId'] as String
          : null,
      lastStatusChangedAt: hasChangedAt
          ? (data['lastStatusChangedAt'] as Timestamp).toDate()
          : null,
    );
  }

  PendingEnrollment _pendingEnrollmentFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String expectedCourseId,
  }) {
    final data = document.data();
    final keys = data?.keys.toSet() ?? const <String>{};
    final hasEventId = data?['lastEventId'] != null;
    final hasChangedAt = data?['lastStatusChangedAt'] != null;
    final status = data?['status'];
    final linked = status == 'linked';
    if (!document.exists ||
        data == null ||
        keys.length != _pendingKeys.length ||
        !keys.containsAll(_pendingKeys) ||
        data['courseId'] != expectedCourseId ||
        data['courseId'] != _courseIdFromPendingPath(document.reference.path) ||
        data['ownerUid'] is! String ||
        (data['ownerUid'] as String).isEmpty ||
        data['subject'] is! String ||
        (data['subject'] as String).trim().isEmpty ||
        data['group'] is! String ||
        (data['group'] as String).trim().isEmpty ||
        data['period'] is! String ||
        (data['period'] as String).trim().isEmpty ||
        data['email'] is! String ||
        data['email'] != document.id ||
        EnrollmentValidator.exactEmail(data['email'] as String) !=
            document.id ||
        data['studentCode'] is! String ||
        (data['studentCode'] as String).trim().isEmpty ||
        (data['studentCode'] as String).length > 40 ||
        data['name'] is! String ||
        (data['name'] as String).trim().isEmpty ||
        (data['name'] as String).length > 100 ||
        (status != 'pending' && status != 'linked' && status != 'withdrawn') ||
        data['rosterEntryId'] != document.id ||
        data['effectiveStartDate'] is! Timestamp ||
        !(data['studentUid'] == null || data['studentUid'] is String) ||
        !(data['linkedAt'] == null || data['linkedAt'] is Timestamp) ||
        (linked &&
            ((data['studentUid'] as String?)?.isEmpty != false ||
                data['linkedAt'] is! Timestamp)) ||
        (!linked && (data['studentUid'] != null || data['linkedAt'] != null)) ||
        data['authorizedAt'] is! Timestamp ||
        data['createdAt'] is! Timestamp ||
        data['updatedAt'] is! Timestamp ||
        hasEventId != hasChangedAt ||
        (hasEventId &&
            (data['lastEventId'] is! String ||
                (data['lastEventId'] as String).isEmpty ||
                data['lastStatusChangedAt'] is! Timestamp))) {
      throw const FormatException('Invalid pending enrollment document.');
    }
    return PendingEnrollment(
      courseId: expectedCourseId,
      ownerUid: data['ownerUid'] as String,
      subject: data['subject'] as String,
      group: data['group'] as String,
      period: data['period'] as String,
      email: document.id,
      studentCode: data['studentCode'] as String,
      name: data['name'] as String,
      status: status as String,
      effectiveStartDate: _academicDateFromTimestamp(
        data['effectiveStartDate'],
      ),
      rosterEntryId: data['rosterEntryId'] as String,
      studentUid: data['studentUid'] as String?,
      authorizedAt: (data['authorizedAt'] as Timestamp).toDate(),
      linkedAt: (data['linkedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      lastEventId: hasEventId ? data['lastEventId'] as String : null,
      lastStatusChangedAt: hasChangedAt
          ? (data['lastStatusChangedAt'] as Timestamp).toDate()
          : null,
    );
  }

  PendingEnrollmentStatusEvent _pendingEventFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (!document.exists ||
        data == null ||
        data.keys.toSet().length != _pendingEventKeys.length ||
        !data.keys.toSet().containsAll(_pendingEventKeys) ||
        data['fromStatus'] is! String ||
        data['toStatus'] is! String ||
        !_isAllowedPendingTransition(
          data['fromStatus'] as String,
          data['toStatus'] as String,
        ) ||
        data['effectiveDate'] is! Timestamp ||
        data['changedAt'] is! Timestamp ||
        data['changedBy'] is! String ||
        data['changedBy'].isEmpty) {
      throw const FormatException('Invalid pending enrollment event.');
    }
    return PendingEnrollmentStatusEvent(
      operationId: document.id,
      fromStatus: data['fromStatus'] as String,
      toStatus: data['toStatus'] as String,
      effectiveDate: _academicDateFromTimestamp(data['effectiveDate']),
      changedAt: (data['changedAt'] as Timestamp).toDate(),
      changedBy: data['changedBy'] as String,
    );
  }

  Future<PendingEnrollmentLinkRowResult> _linkPendingEnrollment({
    required PendingEnrollment pending,
    required String studentUid,
    required String email,
    required String studentCode,
  }) async {
    final pendingRef = _pendingEnrollments(pending.courseId).doc(email);
    final profileRef = _firestore.collection('users').doc(studentUid);
    final enrollmentRef = _enrollments(pending.courseId).doc(studentUid);
    final eventId = _pendingLinkOperationId(email);
    final eventRef = _pendingStatusEvents(pending.courseId, email).doc(eventId);
    final joinRequestRef = _courses
        .doc(pending.courseId)
        .collection('join_requests')
        .doc(studentUid);

    try {
      return await _firestore.runTransaction<PendingEnrollmentLinkRowResult>((
        transaction,
      ) async {
        _requireSameUser(studentUid);
        final pendingSnapshot = await transaction.get(pendingRef);
        final profileSnapshot = await transaction.get(profileRef);
        final enrollmentSnapshot = await transaction.get(enrollmentRef);
        final joinRequestSnapshot = await transaction.get(joinRequestRef);
        _requireSameUser(studentUid);
        if (!pendingSnapshot.exists) {
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }
        final current = _pendingEnrollmentFromDocument(
          pendingSnapshot,
          expectedCourseId: pending.courseId,
        );
        final profile = profileSnapshot.data();
        if (!profileSnapshot.exists ||
            profile == null ||
            profile.length != 4 ||
            !profile.keys.toSet().containsAll({
              'name',
              'email',
              'studentCode',
              'roles',
            }) ||
            profile['name'] is! String ||
            (profile['name'] as String).trim().isEmpty ||
            profile['email'] != email ||
            profile['studentCode'] != studentCode ||
            profile['roles'] is! List ||
            !(profile['roles'] as List).contains('student')) {
          throw const EnrollmentFailure(EnrollmentFailureKind.candidateChanged);
        }
        if (current.email != email ||
            current.studentCode != studentCode ||
            current.rosterEntryId != email) {
          throw const EnrollmentFailure(EnrollmentFailureKind.candidateChanged);
        }

        Enrollment? existingEnrollment;
        if (enrollmentSnapshot.exists) {
          existingEnrollment = _enrollmentFromDocument(
            enrollmentSnapshot,
            courseId: pending.courseId,
          );
          if (!_sameLinkedEnrollment(
            existingEnrollment,
            rawEnrollmentData: enrollmentSnapshot.data()!,
            pending: current,
            studentUid: studentUid,
          )) {
            return PendingEnrollmentLinkRowResult(
              courseId: current.courseId,
              email: email,
              outcome: PendingEnrollmentLinkOutcome.needsReview,
              failureKind: EnrollmentFailureKind.staleEnrollment,
            );
          }
          if (existingEnrollment.status == 'withdrawn') {
            return PendingEnrollmentLinkRowResult(
              courseId: current.courseId,
              email: email,
              outcome: PendingEnrollmentLinkOutcome.needsReview,
              failureKind: EnrollmentFailureKind.staleEnrollment,
            );
          }
        }

        if (current.status == 'linked') {
          if (current.studentUid == studentUid &&
              existingEnrollment?.status == 'active') {
            return PendingEnrollmentLinkRowResult(
              courseId: current.courseId,
              email: email,
              outcome: PendingEnrollmentLinkOutcome.alreadyLinked,
            );
          }
          return PendingEnrollmentLinkRowResult(
            courseId: current.courseId,
            email: email,
            outcome: PendingEnrollmentLinkOutcome.needsReview,
            failureKind: EnrollmentFailureKind.staleEnrollment,
          );
        }
        if (current.status != 'pending' ||
            !_samePendingVersion(current, pending)) {
          throw const EnrollmentFailure(EnrollmentFailureKind.staleEnrollment);
        }

        var requestNeedsTeacherReview = false;
        if (joinRequestSnapshot.exists &&
            joinRequestSnapshot.data()?['status'] == 'pending') {
          final request = joinRequestSnapshot.data()!;
          final requestMatches =
              request['studentUid'] == studentUid &&
              request['email'] == email &&
              request['studentCode'] == studentCode &&
              request['subject'] == current.subject &&
              request['group'] == current.group &&
              request['period'] == current.period;
          if (requestMatches) {
            transaction.update(joinRequestRef, {
              'status': 'approved',
              'decidedBy': current.ownerUid,
              'decidedAt': FieldValue.serverTimestamp(),
              'rejectionReason': null,
            });
          } else {
            requestNeedsTeacherReview = true;
          }
        }

        if (existingEnrollment == null) {
          transaction.set(enrollmentRef, {
            'studentUid': studentUid,
            'ownerUid': current.ownerUid,
            'name': current.name,
            'email': email,
            'studentCode': studentCode,
            'subject': current.subject,
            'group': current.group,
            'period': current.period,
            'status': 'active',
            'rosterEntryId': current.rosterEntryId,
            'effectiveStartDate': Timestamp.fromDate(
              current.effectiveStartDate.toUtcTimestamp(),
            ),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        transaction.update(pendingRef, _pendingLinkUpdate(email, studentUid));
        transaction.set(eventRef, _pendingLinkEvent(current, studentUid));
        return PendingEnrollmentLinkRowResult(
          courseId: current.courseId,
          email: email,
          outcome: PendingEnrollmentLinkOutcome.linked,
          joinRequestNeedsTeacherReview: requestNeedsTeacherReview,
        );
      });
    } on EnrollmentFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw EnrollmentFailure(EnrollmentFailureKind.invalidData, cause: error);
    }
  }

  bool _sameLinkedEnrollment(
    Enrollment enrollment, {
    required Map<String, dynamic> rawEnrollmentData,
    required PendingEnrollment pending,
    required String studentUid,
  }) {
    final hasRosterEntryId = rawEnrollmentData.containsKey('rosterEntryId');
    final hasEffectiveStartDate = rawEnrollmentData.containsKey(
      'effectiveStartDate',
    );
    final hasConsistentRosterMetadata =
        hasRosterEntryId == hasEffectiveStartDate;
    final rosterMetadataMatches =
        hasConsistentRosterMetadata &&
        (hasRosterEntryId
            ? enrollment.rosterEntryId == pending.rosterEntryId &&
                  enrollment.effectiveStartDate == pending.effectiveStartDate
            : true);

    return enrollment.courseId == pending.courseId &&
        enrollment.studentUid == studentUid &&
        enrollment.ownerUid == pending.ownerUid &&
        enrollment.email == pending.email &&
        enrollment.studentCode == pending.studentCode &&
        enrollment.subject == pending.subject &&
        enrollment.group == pending.group &&
        enrollment.period == pending.period &&
        rosterMetadataMatches;
  }

  bool _joinRequestMatches(
    Map<String, dynamic>? request, {
    required String studentUid,
    required String email,
    required String? studentCode,
    required String subject,
    required String group,
    required String period,
  }) =>
      request != null &&
      studentCode != null &&
      studentCode.isNotEmpty &&
      request['studentUid'] == studentUid &&
      request['email'] == email &&
      request['studentCode'] == studentCode &&
      request['subject'] == subject &&
      request['group'] == group &&
      request['period'] == period;

  String _pendingLinkOperationId(String email) => 'link';

  Map<String, dynamic> _pendingLinkUpdate(String email, String studentUid) => {
    'status': 'linked',
    'studentUid': studentUid,
    'linkedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'lastEventId': _pendingLinkOperationId(email),
    'lastStatusChangedAt': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _pendingLinkEvent(
    PendingEnrollment pending,
    String actorUid,
  ) => {
    'fromStatus': 'pending',
    'toStatus': 'linked',
    'effectiveDate': Timestamp.fromDate(
      pending.effectiveStartDate.toUtcTimestamp(),
    ),
    'changedAt': FieldValue.serverTimestamp(),
    'changedBy': actorUid,
  };

  bool _isConsistentPendingLink(
    PendingEnrollment pending,
    DocumentSnapshot<Map<String, dynamic>> eventSnapshot, {
    required String studentUid,
  }) {
    if (pending.studentUid != studentUid ||
        pending.linkedAt == null ||
        pending.lastEventId != _pendingLinkOperationId(pending.email) ||
        pending.lastStatusChangedAt == null ||
        !eventSnapshot.exists) {
      return false;
    }
    final event = _pendingEventFromDocument(eventSnapshot);
    return event.fromStatus == 'pending' &&
        event.toStatus == 'linked' &&
        event.effectiveDate == pending.effectiveStartDate &&
        (event.changedBy == pending.ownerUid ||
            event.changedBy == studentUid) &&
        _sameInstant(event.changedAt, pending.lastStatusChangedAt) &&
        _sameInstant(event.changedAt, pending.linkedAt);
  }

  EnrollmentStatusEvent _statusEventFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final changedAt = data?['changedAt'];
    final hasEffectiveDate = data?.containsKey('effectiveDate') ?? false;
    if (!document.exists ||
        data == null ||
        !data.keys.toSet().containsAll(_statusEventKeys) ||
        data.keys.toSet().difference({
          ..._statusEventKeys,
          ..._effectiveStatusEventKeys,
        }).isNotEmpty ||
        data.keys.toSet().length !=
            _statusEventKeys.length + (hasEffectiveDate ? 1 : 0) ||
        data['fromStatus'] is! String ||
        data['toStatus'] is! String ||
        !_isAllowedStatusTransition(
          data['fromStatus'] as String,
          data['toStatus'] as String,
        ) ||
        changedAt is! Timestamp ||
        (hasEffectiveDate && data['effectiveDate'] is! Timestamp) ||
        data['changedBy'] is! String ||
        data['changedBy'].isEmpty) {
      throw const FormatException('Invalid enrollment status event.');
    }
    final changedAtDate = changedAt.toDate();
    return EnrollmentStatusEvent(
      operationId: document.id,
      fromStatus: data['fromStatus'] as String,
      toStatus: data['toStatus'] as String,
      changedAt: changedAtDate,
      changedBy: data['changedBy'] as String,
      effectiveDate: hasEffectiveDate
          ? _academicDateFromTimestamp(data['effectiveDate'])
          : _bogotaDate(changedAtDate),
    );
  }

  bool _isAllowedStatusTransition(String fromStatus, String toStatus) =>
      fromStatus == 'active' && toStatus == 'withdrawn' ||
      fromStatus == 'withdrawn' && toStatus == 'active';

  bool _isAllowedPendingTransition(String fromStatus, String toStatus) =>
      fromStatus == 'pending' &&
          (toStatus == 'withdrawn' || toStatus == 'linked') ||
      fromStatus == 'withdrawn' && toStatus == 'pending';

  void _validatePendingStatus(String status, {required bool includeLinked}) {
    if (status != 'pending' &&
        status != 'withdrawn' &&
        !(includeLinked && status == 'linked')) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
  }

  bool _samePendingVersion(
    PendingEnrollment current,
    PendingEnrollment expected,
  ) =>
      current.courseId == expected.courseId &&
      current.ownerUid == expected.ownerUid &&
      current.subject == expected.subject &&
      current.group == expected.group &&
      current.period == expected.period &&
      current.email == expected.email &&
      current.studentCode == expected.studentCode &&
      current.name == expected.name &&
      current.status == expected.status &&
      current.effectiveStartDate == expected.effectiveStartDate &&
      current.rosterEntryId == expected.rosterEntryId &&
      current.studentUid == expected.studentUid &&
      _sameInstant(current.authorizedAt, expected.authorizedAt) &&
      _sameInstant(current.linkedAt, expected.linkedAt) &&
      _sameInstant(current.createdAt, expected.createdAt) &&
      _sameInstant(current.updatedAt, expected.updatedAt) &&
      current.lastEventId == expected.lastEventId &&
      _sameInstant(current.lastStatusChangedAt, expected.lastStatusChangedAt);

  (AcademicDate, AcademicDate) _courseDateRange(Map<String, dynamic> course) {
    final start = _academicDateFromTimestamp(course['startDate']);
    final end = _academicDateFromTimestamp(course['endDate']);
    if (start.compareTo(end) > 0) {
      throw const FormatException('Invalid course date range.');
    }
    return (start, end);
  }

  AcademicDate _academicDateFromTimestamp(Object? value) {
    if (value is! Timestamp) {
      throw const FormatException('Expected an academic date timestamp.');
    }
    try {
      return AcademicDate.fromUtcTimestamp(value.toDate().toUtc());
    } on ArgumentError {
      throw const FormatException('Expected UTC midnight for academic date.');
    }
  }

  AcademicDate _bogotaDate(DateTime timestamp) {
    final bogota = timestamp.toUtc().subtract(const Duration(hours: 5));
    return AcademicDate.fromDateTime(bogota);
  }

  AcademicDate _todayInBogota() => _bogotaDate(DateTime.now());

  AcademicDate _defaultEffectiveStartDate(
    AcademicDate courseStart,
    AcademicDate courseEnd,
  ) {
    final today = _todayInBogota();
    if (today.compareTo(courseStart) < 0) return courseStart;
    if (today.compareTo(courseEnd) > 0) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
    return today;
  }

  void _validateEffectiveDateForCourse(
    AcademicDate date,
    AcademicDate courseStart,
    AcademicDate courseEnd, {
    required bool allowFutureCourseStart,
  }) {
    if (courseStart.compareTo(courseEnd) > 0 ||
        date.compareTo(courseStart) < 0 ||
        date.compareTo(courseEnd) > 0) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
    final today = _todayInBogota();
    if (date.compareTo(today) > 0 &&
        !(allowFutureCourseStart && date == courseStart)) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
  }

  void _validateEnrollmentStatus(String status) {
    if (status != 'active' && status != 'withdrawn') {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
  }

  bool _sameEnrollmentVersion(Enrollment current, Enrollment expected) =>
      current.courseId == expected.courseId &&
      current.studentUid == expected.studentUid &&
      current.ownerUid == expected.ownerUid &&
      current.name == expected.name &&
      current.email == expected.email &&
      current.studentCode == expected.studentCode &&
      current.subject == expected.subject &&
      current.group == expected.group &&
      current.period == expected.period &&
      current.status == expected.status &&
      _sameInstant(current.createdAt, expected.createdAt) &&
      current.rosterEntryId == expected.rosterEntryId &&
      current.effectiveStartDate == expected.effectiveStartDate &&
      current.lastStatusEventId == expected.lastStatusEventId &&
      _sameInstant(current.lastStatusChangedAt, expected.lastStatusChangedAt);

  bool _sameInstant(DateTime? left, DateTime? right) => left == null
      ? right == null
      : right != null && left.isAtSameMomentAs(right);

  Enrollment _copyWithStatus(
    Enrollment enrollment, {
    required String status,
    required String eventId,
  }) => Enrollment(
    courseId: enrollment.courseId,
    studentUid: enrollment.studentUid,
    ownerUid: enrollment.ownerUid,
    name: enrollment.name,
    email: enrollment.email,
    studentCode: enrollment.studentCode,
    subject: enrollment.subject,
    group: enrollment.group,
    period: enrollment.period,
    status: status,
    createdAt: enrollment.createdAt,
    rosterEntryId: enrollment.rosterEntryId,
    effectiveStartDate: enrollment.effectiveStartDate,
    lastStatusEventId: eventId,
    lastStatusChangedAt: null,
  );

  StudentCandidate _candidateFromDirectory(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String expectedEmail,
  }) {
    final data = document.data();
    if (!document.exists ||
        data == null ||
        data.keys.toSet().length != _directoryKeys.length ||
        !data.keys.toSet().containsAll(_directoryKeys) ||
        data['uid'] is! String ||
        (data['uid'] as String).isEmpty ||
        data['name'] is! String ||
        (data['name'] as String).isEmpty ||
        data['email'] != expectedEmail ||
        document.id != expectedEmail ||
        !(data['studentCode'] == null ||
            data['studentCode'] is String &&
                (data['studentCode'] as String).isNotEmpty) ||
        data['updatedAt'] is! Timestamp) {
      throw const FormatException('Invalid directory entry.');
    }
    return StudentCandidate(
      uid: data['uid'] as String,
      name: data['name'] as String,
      email: data['email'] as String,
      studentCode: data['studentCode'] as String?,
    );
  }

  bool _sameCandidate(StudentCandidate a, StudentCandidate b) =>
      a.uid == b.uid &&
      a.name == b.name &&
      a.email == b.email &&
      a.studentCode == b.studentCode;

  User _requireVerifiedUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
    }
    if (!user.emailVerified || user.email == null) {
      throw const EnrollmentFailure(EnrollmentFailureKind.emailNotVerified);
    }
    return user;
  }

  Future<Map<String, dynamic>> _requireProfile(
    User user, {
    required String role,
  }) async {
    final profile = await _requireValidProfile(user);
    if (!(profile['roles'] as List).contains(role)) {
      throw EnrollmentFailure(
        role == 'teacher'
            ? EnrollmentFailureKind.teacherRoleRequired
            : EnrollmentFailureKind.studentRoleRequired,
      );
    }
    return profile;
  }

  Future<Map<String, dynamic>> _requireValidProfile(User user) async {
    final uid = user.uid;
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    _requireSameUser(uid);
    final profile = snapshot.data();
    if (!snapshot.exists ||
        profile == null ||
        profile.length != 4 ||
        !profile.keys.toSet().containsAll({
          'name',
          'email',
          'studentCode',
          'roles',
        }) ||
        profile['name'] is! String ||
        (profile['name'] as String).isEmpty ||
        profile['email'] != user.email ||
        !(profile['studentCode'] == null || profile['studentCode'] is String) ||
        profile['roles'] is! List ||
        (profile['roles'] as List).any((role) => role is! String)) {
      throw const EnrollmentFailure(EnrollmentFailureKind.profileInvalid);
    }
    return profile;
  }

  void _requireSameUser(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw const EnrollmentFailure(EnrollmentFailureKind.unauthenticated);
    }
  }

  void _validatePageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 100) {
      throw const EnrollmentFailure(EnrollmentFailureKind.invalidInput);
    }
  }

  EnrollmentFailure _translate(FirebaseException error) => switch (error.code) {
    'permission-denied' => EnrollmentFailure(
      EnrollmentFailureKind.permissionDenied,
      cause: error,
    ),
    'unauthenticated' => EnrollmentFailure(
      EnrollmentFailureKind.unauthenticated,
      cause: error,
    ),
    'unavailable' || 'network-request-failed' || 'deadline-exceeded' =>
      EnrollmentFailure(EnrollmentFailureKind.network, cause: error),
    _ => EnrollmentFailure(EnrollmentFailureKind.unknown, cause: error),
  };
}
