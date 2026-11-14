import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../courses/data/firestore_course_repository.dart';
import '../../courses/domain/course.dart';
import '../../courses/domain/course_failure.dart';
import '../application/enrollment_validator.dart';
import '../domain/enrollment.dart';
import '../domain/enrollment_failure.dart';
import '../domain/enrollment_page.dart';
import '../domain/enrollment_repository.dart';
import '../domain/enrollment_status_change.dart';
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
  static const _statusEventKeys = {
    'fromStatus',
    'toStatus',
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

  CollectionReference<Map<String, dynamic>> _statusEvents(
    String courseId,
    String studentUid,
  ) => _enrollments(courseId).doc(studentUid).collection('status_events');

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
  Future<EnrollmentResult> enrollStudent({
    required String courseId,
    required StudentCandidate candidate,
    bool resolvePendingWhenAlreadyEnrolled = true,
  }) async {
    try {
      EnrollmentValidator.documentId(courseId);
      EnrollmentValidator.documentId(candidate.uid);
      EnrollmentValidator.exactEmail(candidate.email);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final courseRef = _courses.doc(courseId);
      final directoryRef = _directory.doc(candidate.email);
      final enrollmentRef = _enrollments(courseId).doc(candidate.uid);
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
          // A manual invite must not silently reactivate a withdrawn student
          // or resolve a join request as approved. Reinstatement is an explicit
          // status transition with its own audit event.
          if (resolvePendingWhenAlreadyEnrolled &&
              enrollment.status == 'active' &&
              joinRequestDoc.exists &&
              joinRequestDoc.data()?['status'] == 'pending') {
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

        final enrollment = Enrollment(
          courseId: courseId,
          studentUid: current.uid,
          ownerUid: uid,
          name: current.name,
          email: current.email,
          studentCode: current.studentCode,
          subject: course['subject'] as String,
          group: course['group'] as String,
          period: course['period'] as String,
          status: 'active',
          createdAt: null,
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
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (joinRequestDoc.exists &&
            joinRequestDoc.data()?['status'] == 'pending') {
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

        _requireSameUser(uid);
        transaction.update(enrollmentRef, {
          'status': nextStatus,
          'lastStatusEventId': operationId,
          'lastStatusChangedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(eventRef, {
          'fromStatus': current.status,
          'toStatus': nextStatus,
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

  String _courseIdFromPath(String path) {
    final pieces = path.split('/');
    if (pieces.length != 4 ||
        pieces[0] != 'courses' ||
        pieces[2] != 'enrollments') {
      throw const FormatException('Invalid enrollment path.');
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
    if (!document.exists ||
        data == null ||
        !keys.containsAll(_enrollmentKeys) ||
        keys.difference({
          ..._enrollmentKeys,
          ..._enrollmentTransitionKeys,
        }).isNotEmpty ||
        hasEventId != hasChangedAt ||
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
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastStatusEventId: hasEventId
          ? data['lastStatusEventId'] as String
          : null,
      lastStatusChangedAt: hasChangedAt
          ? (data['lastStatusChangedAt'] as Timestamp).toDate()
          : null,
    );
  }

  EnrollmentStatusEvent _statusEventFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (!document.exists ||
        data == null ||
        data.keys.toSet().length != _statusEventKeys.length ||
        !data.keys.toSet().containsAll(_statusEventKeys) ||
        data['fromStatus'] is! String ||
        data['toStatus'] is! String ||
        !_isAllowedStatusTransition(
          data['fromStatus'] as String,
          data['toStatus'] as String,
        ) ||
        data['changedAt'] is! Timestamp ||
        data['changedBy'] is! String ||
        (data['changedBy'] as String).isEmpty) {
      throw const FormatException('Invalid enrollment status event.');
    }
    return EnrollmentStatusEvent(
      operationId: document.id,
      fromStatus: data['fromStatus'] as String,
      toStatus: data['toStatus'] as String,
      changedAt: (data['changedAt'] as Timestamp).toDate(),
      changedBy: data['changedBy'] as String,
    );
  }

  bool _isAllowedStatusTransition(String fromStatus, String toStatus) =>
      fromStatus == 'active' && toStatus == 'withdrawn' ||
      fromStatus == 'withdrawn' && toStatus == 'active';

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
