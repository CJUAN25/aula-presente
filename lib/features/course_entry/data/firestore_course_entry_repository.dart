import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../enrollments/application/enrollment_validator.dart';
import '../../enrollments/domain/enrollment.dart';
import '../../schedule/domain/academic_date.dart';
import '../application/course_entry_validator.dart';
import '../domain/course_entry_failure.dart';
import '../domain/course_entry_repository.dart';
import '../domain/course_invitation.dart';
import '../domain/course_preview.dart';
import '../domain/join_request.dart';
import '../domain/join_request_page.dart';

/// Firestore-backed invite and request operations. Authorization is enforced
/// by Firestore Rules; the local profile checks provide earlier explanations.
class FirestoreCourseEntryRepository implements CourseEntryRepository {
  FirestoreCourseEntryRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const _invitationKeys = {'code', 'status', 'createdAt', 'updatedAt'};
  static const _lookupKeys = {
    'courseId',
    'subject',
    'group',
    'period',
    'createdAt',
  };
  static const _requestKeys = {
    'studentUid',
    'name',
    'email',
    'studentCode',
    'subject',
    'group',
    'period',
    'invitationCode',
    'status',
    'createdAt',
    'decidedBy',
    'decidedAt',
    'rejectionReason',
  };
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
  static const _profileKeys = {'name', 'email', 'studentCode', 'roles'};

  CollectionReference<Map<String, dynamic>> get _courses =>
      _firestore.collection('courses');

  DocumentReference<Map<String, dynamic>> _course(String courseId) =>
      _courses.doc(courseId);

  DocumentReference<Map<String, dynamic>> _currentInvitation(String courseId) =>
      _course(courseId).collection('invitation').doc('current');

  DocumentReference<Map<String, dynamic>> _inviteLookup(String code) =>
      _firestore.collection('course_invites').doc(code);

  DocumentReference<Map<String, dynamic>> _joinRequest(
    String courseId,
    String studentUid,
  ) => _course(courseId).collection('join_requests').doc(studentUid);

  DocumentReference<Map<String, dynamic>> _enrollment(
    String courseId,
    String studentUid,
  ) => _course(courseId).collection('enrollments').doc(studentUid);

  DocumentReference<Map<String, dynamic>> _pendingEnrollment(
    String courseId,
    String email,
  ) => _course(courseId).collection('pending_enrollments').doc(email);

  DocumentReference<Map<String, dynamic>> _pendingLinkEvent(
    String courseId,
    String email,
  ) => _pendingEnrollment(
    courseId,
    email,
  ).collection('status_events').doc(_pendingLinkEventId(email));

  String _pendingLinkEventId(String email) => 'link';

  @override
  String? get currentUid => _auth.currentUser?.uid;

  @override
  Future<CourseInvitation?> getCurrentInvitation(String courseId) async {
    try {
      _validateDocumentId(courseId);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final snapshot = await _currentInvitation(courseId)
          .get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      if (!snapshot.exists) return null;
      return _invitationFromSnapshot(snapshot, courseId: courseId);
    } on CourseEntryFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
      );
    }
  }

  @override
  Future<CourseInvitation> createOrGetInvitation(
    String courseId, {
    Duration validity = CourseInvitation.defaultValidity,
  }) =>
      _writeCurrentInvitation(courseId, forceRenew: false, validity: validity);

  @override
  Future<CourseInvitation> renewInvitation(
    String courseId, {
    Duration validity = CourseInvitation.defaultValidity,
  }) => _writeCurrentInvitation(courseId, forceRenew: true, validity: validity);

  Future<CourseInvitation> _writeCurrentInvitation(
    String courseId, {
    required bool forceRenew,
    required Duration validity,
  }) async {
    try {
      CourseEntryValidator.validateValidity(validity);
      _validateDocumentId(courseId);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final courseRef = _course(courseId);
      final currentRef = _currentInvitation(courseId);
      var candidateCode = CourseEntryValidator.generateCode();
      final result = await _firestore.runTransaction<_InvitationWrite>((
        transaction,
      ) async {
        _requireSameUser(uid);
        final courseSnapshot = await transaction.get(courseRef);
        final currentSnapshot = await transaction.get(currentRef);
        final course = courseSnapshot.data();
        if (!courseSnapshot.exists ||
            course == null ||
            course['ownerUid'] != uid ||
            course['subject'] is! String ||
            course['group'] is! String ||
            course['period'] is! String) {
          throw const CourseEntryFailure(
            CourseEntryFailureKind.courseUnavailable,
          );
        }

        if (!forceRenew && currentSnapshot.exists) {
          final current = _invitationFromSnapshot(
            currentSnapshot,
            courseId: courseId,
          );
          // Firestore applies expiry using server time when a student uses the
          // code. The persisted status cannot be compared with the phone clock;
          // a teacher renews explicitly from invitation management.
          return _InvitationWrite(current, isExisting: true);
        }

        while (candidateCode == currentSnapshot.data()?['code']) {
          candidateCode = CourseEntryValidator.generateCode();
        }

        _requireSameUser(uid);

        // If this random ID already exists, Rules deny the create. Do
        // not pre-read arbitrary IDs or interpret that denial as a
        // collision; Rules intentionally provide no collision oracle.
        transaction.set(_inviteLookup(candidateCode), {
          'courseId': courseId,
          'subject': course['subject'],
          'group': course['group'],
          'period': course['period'],
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(currentRef, {
          'code': candidateCode,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'validForSeconds': validity.inSeconds,
        });
        return _InvitationWrite(
          CourseInvitation(
            courseId: courseId,
            code: candidateCode,
            status: 'active',
            createdAt: null,
            updatedAt: null,
            validity: validity,
          ),
          isExisting: false,
        );
      });
      if (result.isExisting) return result.invitation;
      return await _readInvitationAfterWrite(courseId, result.invitation);
    } on CourseEntryFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
      );
    }
  }

  /// A confirmed transaction stays successful if this optional timestamp
  /// refresh fails. The caller can refresh later without repeating the write.
  Future<CourseInvitation> _readInvitationAfterWrite(
    String courseId,
    CourseInvitation confirmed,
  ) async {
    try {
      final snapshot = await _currentInvitation(courseId)
          .get(const GetOptions(source: Source.server));
      if (!snapshot.exists) return confirmed;
      final current = _invitationFromSnapshot(snapshot, courseId: courseId);
      return current.code == confirmed.code ? current : confirmed;
    } catch (_) {
      return confirmed;
    }
  }

  @override
  Future<void> deactivateInvitation(String courseId) async {
    await _updateInvitation(courseId, status: 'inactive');
  }

  @override
  Future<CourseInvitation> pauseInvitation(String courseId) =>
      _updateInvitation(courseId, status: 'paused');

  @override
  Future<CourseInvitation> reactivateInvitation(String courseId) =>
      _updateInvitation(courseId, status: 'active');

  @override
  Future<CourseInvitation> updateInvitationValidity(
    String courseId,
    Duration validity,
  ) => _updateInvitation(courseId, validity: validity);

  Future<CourseInvitation> _updateInvitation(
    String courseId, {
    String? status,
    Duration? validity,
  }) async {
    try {
      if (validity != null) CourseEntryValidator.validateValidity(validity);
      _validateDocumentId(courseId);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final courseRef = _course(courseId);
      final invitationRef = _currentInvitation(courseId);
      final confirmed = await _firestore.runTransaction<CourseInvitation>((
        transaction,
      ) async {
        _requireSameUser(uid);
        final course = await transaction.get(courseRef);
        final invitation = await transaction.get(invitationRef);
        if (!course.exists || course.data()?['ownerUid'] != uid) {
          throw const CourseEntryFailure(
            CourseEntryFailureKind.courseUnavailable,
          );
        }
        if (!invitation.exists) {
          throw const CourseEntryFailure(
            CourseEntryFailureKind.inviteUnavailable,
          );
        }
        final current = _invitationFromSnapshot(invitation, courseId: courseId);
        if (status == 'inactive' && current.status == 'inactive') {
          return current;
        }
        if (current.status == 'inactive' ||
            (status == 'active' && current.status != 'paused') ||
            (status == 'paused' && current.status != 'active')) {
          throw const CourseEntryFailure(
            CourseEntryFailureKind.invalidTransition,
          );
        }
        _requireSameUser(uid);
        transaction.update(invitationRef, {
          'status': ?status,
          if (validity != null) 'validForSeconds': validity.inSeconds,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return CourseInvitation(
          courseId: courseId,
          code: current.code,
          status: status ?? current.status,
          createdAt: current.createdAt,
          updatedAt: null,
          validity: validity ?? current.validity,
        );
      });
      // A readback cannot turn an acknowledged write into a failed action.
      return await _readInvitationAfterWrite(courseId, confirmed);
    } on CourseEntryFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
      );
    }
  }

  @override
  Future<CoursePreview> findCourseByCode(String input) async {
    final code = CourseEntryValidator.normalizeCode(input);
    var step = 'session';
    try {
      final user = _requireVerifiedUser();
      final uid = user.uid;
      step = 'profile-get';
      await _requireProfile(user, role: 'student');
      step = 'lookup-get';
      final preview = await _readAvailablePreview(code);
      _requireSameUser(uid);
      return preview;
    } on CourseEntryFailure catch (error) {
      throw _diagnosticFailure(error, step);
    } on FirebaseException catch (error) {
      throw _translate(error, step: step);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
        diagnosticStep: step,
        diagnosticCode: 'invalid-data',
      );
    }
  }

  Future<CoursePreview> _readAvailablePreview(String code) async {
    DocumentSnapshot<Map<String, dynamic>> lookup;
    try {
      lookup = await _inviteLookup(code)
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw CourseEntryFailure(
          CourseEntryFailureKind.inviteUnavailable,
          cause: error,
          diagnosticStep: 'lookup-get',
          diagnosticCode: error.code,
        );
      }
      rethrow;
    }
    if (!lookup.exists) {
      throw const CourseEntryFailure(
        CourseEntryFailureKind.inviteUnavailable,
        diagnosticStep: 'lookup-get',
        diagnosticCode: 'not-found',
      );
    }
    // Rules validate the private current pointer, status and server-time expiry.
    // Students must never read that teacher-only document themselves.
    return _previewFromSnapshot(lookup, expectedCode: code);
  }

  @override
  Future<JoinRequestResult> requestJoin(String input) async {
    final code = CourseEntryValidator.normalizeCode(input);
    var step = 'session';
    try {
      final user = _requireVerifiedUser();
      final uid = user.uid;
      step = 'profile-get';
      await _requireProfile(user, role: 'student');
      step = 'lookup-get';
      final invitationSnapshot = await _inviteLookup(code)
          .get(const GetOptions(source: Source.server));
      if (!invitationSnapshot.exists) {
        throw const CourseEntryFailure(
          CourseEntryFailureKind.inviteUnavailable,
        );
      }
      final preview = _previewFromSnapshot(
        invitationSnapshot,
        expectedCode: code,
      );
      final requestRef = _joinRequest(preview.courseId, uid);
      final enrollmentRef = _enrollment(preview.courseId, uid);
      final profileRef = _firestore.collection('users').doc(uid);

      step = 'request-transaction';
      final result = await _firestore.runTransaction<JoinRequestResult>((
        transaction,
      ) async {
        _requireSameUser(uid);
        final lookup = await transaction.get(_inviteLookup(code));
        final enrollment = await transaction.get(enrollmentRef);
        final request = await transaction.get(requestRef);
        final profile = await transaction.get(profileRef);
        _requireSameUser(uid);

        final data = profile.data();
        _requireProfileData(data, user, role: 'student');
        final available = _previewFromSnapshot(lookup, expectedCode: code);
        if (available.courseId != preview.courseId) {
          throw const CourseEntryFailure(
            CourseEntryFailureKind.inviteUnavailable,
          );
        }

        if (enrollment.exists) {
          final existingEnrollment = _enrollmentFromSnapshot(
            enrollment,
            preview.courseId,
          );
          return JoinRequestResult(
            kind: existingEnrollment.status == 'withdrawn'
                ? JoinRequestResultKind.alreadyWithdrawn
                : JoinRequestResultKind.alreadyEnrolled,
            courseId: preview.courseId,
          );
        }
        if (request.exists) {
          final existing = _joinRequestFromSnapshot(request);
          return switch (existing.status) {
            JoinRequestStatus.pending => JoinRequestResult(
              kind: JoinRequestResultKind.alreadyPending,
              courseId: preview.courseId,
              request: existing,
            ),
            JoinRequestStatus.rejected => JoinRequestResult(
              kind: JoinRequestResultKind.alreadyRejected,
              courseId: preview.courseId,
              request: existing,
            ),
            JoinRequestStatus.approved => throw const CourseEntryFailure(
              CourseEntryFailureKind.invalidData,
            ),
          };
        }

        final name = data!['name'] as String;
        final email = data['email'] as String;
        final studentCode = data['studentCode'];
        transaction.set(requestRef, {
          'studentUid': uid,
          'name': name,
          'email': email,
          'studentCode': studentCode,
          'subject': available.subject,
          'group': available.group,
          'period': available.period,
          'invitationCode': code,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'decidedBy': null,
          'decidedAt': null,
          'rejectionReason': null,
        });
        return JoinRequestResult(
          kind: JoinRequestResultKind.created,
          courseId: preview.courseId,
        );
      });

      if (result.kind == JoinRequestResultKind.created &&
          _auth.currentUser?.uid == uid) {
        final confirmedRequest = await _readRequestAfterWrite(
          preview.courseId,
          uid,
        );
        return JoinRequestResult(
          kind: result.kind,
          courseId: result.courseId,
          request: confirmedRequest,
        );
      }
      return result;
    } on CourseEntryFailure catch (error) {
      throw _diagnosticFailure(error, step);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' && step != 'profile-get') {
        bool available;
        try {
          available = await _canStillReadCode(code);
        } catch (_) {
          // Preserve the original denial if its secondary diagnosis fails.
          throw _translate(error, step: step);
        }
        if (!available) {
          throw CourseEntryFailure(
            CourseEntryFailureKind.inviteUnavailable,
            cause: error,
            diagnosticStep: step,
            diagnosticCode: error.code,
          );
        }
      }
      throw _translate(error, step: step);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
        diagnosticStep: step,
        diagnosticCode: 'invalid-data',
      );
    }
  }

  Future<bool> _canStillReadCode(String code) async {
    try {
      await _readAvailablePreview(code);
      return true;
    } on CourseEntryFailure catch (error) {
      if (error.kind == CourseEntryFailureKind.inviteUnavailable ||
          error.kind == CourseEntryFailureKind.permissionDenied) {
        return false;
      }
      rethrow;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return false;
      throw _translate(error);
    }
  }

  Future<JoinRequest?> _readRequestAfterWrite(
    String courseId,
    String studentUid,
  ) async {
    try {
      final snapshot = await _joinRequest(
        courseId,
        studentUid,
      ).get(const GetOptions(source: Source.server));
      return snapshot.exists ? _joinRequestFromSnapshot(snapshot) : null;
    } catch (_) {
      // The transaction already confirmed the write; this is only a display
      // refresh, so a failure must not make the student retry the submission.
      return null;
    }
  }

  @override
  Future<JoinRequest?> getMyRequest(String courseId) async {
    try {
      _validateDocumentId(courseId);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'student');
      final snapshot = await _joinRequest(
        courseId,
        uid,
      ).get(const GetOptions(source: Source.server));
      _requireSameUser(uid);
      return snapshot.exists ? _joinRequestFromSnapshot(snapshot) : null;
    } on CourseEntryFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
      );
    }
  }

  @override
  Future<JoinRequestPage> listMyRequests({
    JoinRequestCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      _validatePageSize(pageSize);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'student');
      Query<Map<String, dynamic>> query = _firestore
          .collectionGroup('join_requests')
          .where('studentUid', isEqualTo: uid)
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
      final page = _joinRequestPageFromSnapshot(snapshot, pageSize: pageSize);
      if (page.items.any((request) => request.studentUid != uid)) {
        throw const CourseEntryFailure(CourseEntryFailureKind.permissionDenied);
      }
      return page;
    } on CourseEntryFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
      );
    }
  }

  @override
  Future<JoinRequestPage> listCourseRequests(
    String courseId, {
    JoinRequestCursor? cursor,
    int pageSize = 25,
  }) async {
    try {
      _validateDocumentId(courseId);
      _validatePageSize(pageSize);
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      Query<Map<String, dynamic>> query = _course(courseId)
          .collection('join_requests')
          .where('status', isEqualTo: 'pending')
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
      final page = _joinRequestPageFromSnapshot(
        snapshot,
        pageSize: pageSize,
        expectedCourseId: courseId,
      );
      if (page.items.any(
        (request) => request.status != JoinRequestStatus.pending,
      )) {
        throw const CourseEntryFailure(CourseEntryFailureKind.invalidData);
      }
      return page;
    } on CourseEntryFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
      );
    }
  }

  @override
  Future<JoinDecisionResult> decideJoinRequest({
    required String courseId,
    required String studentUid,
    required JoinRequestDecision decision,
    String? rejectionReason,
  }) async {
    try {
      _validateDocumentId(courseId);
      _validateDocumentId(studentUid);
      final reason = decision == JoinRequestDecision.reject
          ? CourseEntryValidator.normalizeRejectionReason(rejectionReason ?? '')
          : null;
      final user = _requireVerifiedUser();
      final uid = user.uid;
      await _requireProfile(user, role: 'teacher');
      final courseRef = _course(courseId);
      final requestRef = _joinRequest(courseId, studentUid);
      final enrollmentRef = _enrollment(courseId, studentUid);

      return await _firestore.runTransaction<JoinDecisionResult>((
        transaction,
      ) async {
        _requireSameUser(uid);
        final courseSnapshot = await transaction.get(courseRef);
        final requestSnapshot = await transaction.get(requestRef);
        final enrollmentSnapshot = await transaction.get(enrollmentRef);
        _requireSameUser(uid);
        final course = courseSnapshot.data();
        if (!courseSnapshot.exists ||
            course == null ||
            course['ownerUid'] != uid ||
            course['subject'] is! String ||
            course['group'] is! String ||
            course['period'] is! String ||
            !requestSnapshot.exists) {
          throw const CourseEntryFailure(
            CourseEntryFailureKind.courseUnavailable,
          );
        }
        final request = _joinRequestFromSnapshot(requestSnapshot);
        if (request.studentUid != studentUid || request.courseId != courseId) {
          throw const CourseEntryFailure(CourseEntryFailureKind.invalidData);
        }

        if (request.status != JoinRequestStatus.pending) {
          final existingEnrollment = enrollmentSnapshot.exists
              ? _enrollmentFromSnapshot(enrollmentSnapshot, courseId)
              : null;
          if (request.status == JoinRequestStatus.approved &&
              existingEnrollment == null) {
            throw const CourseEntryFailure(CourseEntryFailureKind.invalidData);
          }
          if (existingEnrollment != null &&
              (existingEnrollment.studentUid != studentUid ||
                  existingEnrollment.ownerUid != uid)) {
            throw const CourseEntryFailure(
              CourseEntryFailureKind.permissionDenied,
            );
          }
          final resultStatus = request.status == JoinRequestStatus.approved
              ? JoinDecisionResultStatus.alreadyApproved
              : JoinDecisionResultStatus.alreadyRejected;
          return JoinDecisionResult(
            status: resultStatus,
            courseId: courseId,
            request: request,
            enrollment: existingEnrollment,
          );
        }

        Enrollment? enrollment;
        Map<String, dynamic>? pendingData;
        DocumentSnapshot<Map<String, dynamic>>? pendingSnapshot;
        DocumentSnapshot<Map<String, dynamic>>? pendingLinkEventSnapshot;
        String? exactEmail;
        AcademicDate? pendingEffectiveDate;
        var linkPending = false;
        if (decision == JoinRequestDecision.approve) {
          exactEmail = EnrollmentValidator.exactEmail(request.email);
          final pendingRef = _pendingEnrollment(courseId, exactEmail);
          final linkEventRef = _pendingLinkEvent(courseId, exactEmail);
          pendingSnapshot = await transaction.get(pendingRef);
          pendingLinkEventSnapshot = await transaction.get(linkEventRef);
          _requireSameUser(uid);
          if (pendingSnapshot.exists) {
            pendingData = pendingSnapshot.data();
            if (pendingData == null ||
                pendingData['courseId'] != courseId ||
                pendingData['ownerUid'] != uid ||
                pendingData['email'] != exactEmail ||
                pendingData['rosterEntryId'] != exactEmail ||
                pendingData['name'] is! String ||
                pendingData['studentCode'] != request.studentCode ||
                pendingData['subject'] != request.subject ||
                pendingData['group'] != request.group ||
                pendingData['period'] != request.period ||
                pendingData['effectiveStartDate'] is! Timestamp) {
              throw const CourseEntryFailure(
                CourseEntryFailureKind.invalidData,
              );
            }
            if (pendingData['status'] == 'withdrawn') {
              throw const CourseEntryFailure(
                CourseEntryFailureKind.enrollmentWithdrawn,
              );
            }
            pendingEffectiveDate = _academicDateFromTimestamp(
              pendingData['effectiveStartDate'],
            );
            if (pendingData['status'] == 'pending') {
              if (pendingData['studentUid'] != null ||
                  pendingData['linkedAt'] != null ||
                  pendingData['lastEventId'] != null ||
                  pendingData['lastStatusChangedAt'] != null ||
                  pendingLinkEventSnapshot.exists) {
                throw const CourseEntryFailure(
                  CourseEntryFailureKind.invalidData,
                );
              }
              linkPending = true;
            } else if (pendingData['status'] == 'linked') {
              final linkEvent = pendingLinkEventSnapshot.data();
              final effectiveDate =
                  pendingData['effectiveStartDate'] as Timestamp;
              final linkedAt = pendingData['linkedAt'];
              final lastChangedAt = pendingData['lastStatusChangedAt'];
              final changedAt = linkEvent?['changedAt'];
              final hasPriorStartDate =
                  linkEvent?.containsKey('fromEffectiveStartDate') ?? false;
              if (pendingData['studentUid'] != studentUid ||
                  pendingData['linkedAt'] is! Timestamp ||
                  pendingData['lastEventId'] !=
                      _pendingLinkEventId(exactEmail) ||
                  pendingData['lastStatusChangedAt'] is! Timestamp ||
                  !pendingLinkEventSnapshot.exists ||
                  linkEvent == null ||
                  linkEvent.keys.toSet().length !=
                      (hasPriorStartDate ? 6 : 5) ||
                  !linkEvent.keys.toSet().containsAll({
                    'fromStatus',
                    'toStatus',
                    'effectiveDate',
                    'changedAt',
                    'changedBy',
                  }) ||
                  linkEvent.keys.toSet().difference({
                    'fromStatus',
                    'toStatus',
                    'effectiveDate',
                    'changedAt',
                    'changedBy',
                    'fromEffectiveStartDate',
                  }).isNotEmpty ||
                  linkEvent['fromStatus'] != 'pending' ||
                  linkEvent['toStatus'] != 'linked' ||
                  linkEvent['effectiveDate'] is! Timestamp ||
                  !(linkEvent['effectiveDate'] as Timestamp)
                      .toDate()
                      .isAtSameMomentAs(effectiveDate.toDate()) ||
                  (hasPriorStartDate &&
                      (linkEvent['fromEffectiveStartDate'] is! Timestamp ||
                          !(linkEvent['fromEffectiveStartDate'] as Timestamp)
                              .toDate()
                              .isAtSameMomentAs(effectiveDate.toDate()))) ||
                  changedAt is! Timestamp ||
                  !changedAt.toDate().isAtSameMomentAs(
                    (lastChangedAt as Timestamp).toDate(),
                  ) ||
                  !changedAt.toDate().isAtSameMomentAs(
                    (linkedAt as Timestamp).toDate(),
                  ) ||
                  (linkEvent['changedBy'] != uid &&
                      linkEvent['changedBy'] != studentUid) ||
                  !enrollmentSnapshot.exists) {
                throw const CourseEntryFailure(
                  CourseEntryFailureKind.invalidData,
                );
              }
            } else {
              throw const CourseEntryFailure(
                CourseEntryFailureKind.invalidData,
              );
            }
          }
        }
        if (decision == JoinRequestDecision.approve &&
            enrollmentSnapshot.exists) {
          final enrollmentData = enrollmentSnapshot.data()!;
          final hasRosterMetadata =
              enrollmentData.containsKey('rosterEntryId') &&
              enrollmentData.containsKey('effectiveStartDate');
          enrollment = _enrollmentFromSnapshot(enrollmentSnapshot, courseId);
          if (enrollment.studentUid != studentUid ||
              enrollment.ownerUid != uid) {
            throw const CourseEntryFailure(
              CourseEntryFailureKind.permissionDenied,
            );
          }
          if (enrollment.status == 'withdrawn') {
            throw const CourseEntryFailure(
              CourseEntryFailureKind.enrollmentWithdrawn,
            );
          }
          if (pendingData != null &&
              (enrollment.email != exactEmail ||
                  enrollment.studentCode != request.studentCode ||
                  enrollment.subject != request.subject ||
                  enrollment.group != request.group ||
                  enrollment.period != request.period ||
                  (hasRosterMetadata &&
                      (enrollment.rosterEntryId != exactEmail ||
                          enrollment.effectiveStartDate !=
                              pendingEffectiveDate)))) {
            throw const CourseEntryFailure(CourseEntryFailureKind.invalidData);
          }
        } else if (decision == JoinRequestDecision.approve) {
          final courseDates = _courseDateRange(course);
          final effectiveDate =
              pendingEffectiveDate ??
              _defaultEffectiveStartDate(courseDates.$1, courseDates.$2);
          _validateEffectiveDateForCourse(
            effectiveDate,
            courseDates.$1,
            courseDates.$2,
            allowFutureCourseStart: true,
          );
          enrollment = Enrollment(
            courseId: courseId,
            studentUid: request.studentUid,
            ownerUid: uid,
            name: pendingData?['name'] as String? ?? request.name,
            email: request.email,
            studentCode: request.studentCode,
            subject: request.subject,
            group: request.group,
            period: request.period,
            status: 'active',
            createdAt: null,
            rosterEntryId: exactEmail,
            effectiveStartDate: effectiveDate,
          );
          _requireSameUser(uid);
          transaction.set(enrollmentRef, _enrollmentMap(enrollment));
        }

        if (linkPending) {
          final currentPending = pendingData!;
          final email = exactEmail!;
          transaction.update(_pendingEnrollment(courseId, email), {
            'status': 'linked',
            'studentUid': studentUid,
            'linkedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'lastEventId': _pendingLinkEventId(email),
            'lastStatusChangedAt': FieldValue.serverTimestamp(),
          });
          transaction.set(_pendingLinkEvent(courseId, email), {
            'fromStatus': 'pending',
            'toStatus': 'linked',
            'fromEffectiveStartDate': currentPending['effectiveStartDate'],
            'effectiveDate': currentPending['effectiveStartDate'],
            'changedAt': FieldValue.serverTimestamp(),
            'changedBy': uid,
          });
        }

        final status = decision == JoinRequestDecision.approve
            ? JoinRequestStatus.approved
            : JoinRequestStatus.rejected;
        _requireSameUser(uid);
        transaction.update(requestRef, {
          'status': status.name,
          'decidedBy': uid,
          'decidedAt': FieldValue.serverTimestamp(),
          'rejectionReason': reason,
        });
        final decidedRequest = JoinRequest(
          courseId: request.courseId,
          studentUid: request.studentUid,
          name: request.name,
          email: request.email,
          studentCode: request.studentCode,
          subject: request.subject,
          group: request.group,
          period: request.period,
          status: status,
          createdAt: request.createdAt,
          decidedBy: uid,
          // The transaction confirms the decision, but only the server owns
          // the timestamp value. A later list read supplies it.
          decidedAt: null,
          rejectionReason: reason,
        );
        return JoinDecisionResult(
          status: status == JoinRequestStatus.approved
              ? JoinDecisionResultStatus.approved
              : JoinDecisionResultStatus.rejected,
          courseId: courseId,
          request: decidedRequest,
          enrollment: enrollment,
        );
      });
    } on CourseEntryFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    } on FormatException catch (error) {
      throw CourseEntryFailure(
        CourseEntryFailureKind.invalidData,
        cause: error,
      );
    }
  }

  JoinRequestPage _joinRequestPageFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required int pageSize,
    String? expectedCourseId,
  }) {
    final hasMore = snapshot.docs.length > pageSize;
    final visible = snapshot.docs.take(pageSize).toList(growable: false);
    final items = visible
        .map(
          (document) => _joinRequestFromSnapshot(
            document,
            expectedCourseId: expectedCourseId,
          ),
        )
        .toList(growable: false);
    final last = hasMore && visible.isNotEmpty ? visible.last : null;
    final lastDate = items.isNotEmpty ? items.last.createdAt : null;
    if (last != null && lastDate == null) {
      throw const FormatException('Missing join request cursor timestamp.');
    }
    return JoinRequestPage(
      items: items,
      nextCursor: last == null
          ? null
          : JoinRequestCursor(
              createdAt: lastDate!,
              documentPath: last.reference.path,
            ),
    );
  }

  JoinRequest _joinRequestFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    String? expectedCourseId,
  }) {
    final data = snapshot.data();
    final courseId =
        expectedCourseId ?? _courseIdFromRequestPath(snapshot.reference.path);
    if (!snapshot.exists ||
        data == null ||
        data.keys.toSet().length != _requestKeys.length ||
        !data.keys.toSet().containsAll(_requestKeys) ||
        data['studentUid'] != snapshot.id ||
        data['name'] is! String ||
        (data['name'] as String).trim().isEmpty ||
        (data['name'] as String).length > 100 ||
        data['email'] is! String ||
        (data['email'] as String).length < 3 ||
        (data['email'] as String).length > 254 ||
        !(data['studentCode'] == null || data['studentCode'] is String) ||
        data['subject'] is! String ||
        (data['subject'] as String).trim().isEmpty ||
        (data['subject'] as String).length > 120 ||
        data['group'] is! String ||
        (data['group'] as String).trim().isEmpty ||
        (data['group'] as String).length > 40 ||
        data['period'] is! String ||
        (data['period'] as String).trim().isEmpty ||
        (data['period'] as String).length > 32 ||
        data['invitationCode'] is! String ||
        !_isNormalizedCode(data['invitationCode'] as String) ||
        data['createdAt'] is! Timestamp ||
        !(data['decidedBy'] == null || data['decidedBy'] is String) ||
        !(data['decidedAt'] == null || data['decidedAt'] is Timestamp) ||
        !(data['rejectionReason'] == null ||
            data['rejectionReason'] is String)) {
      throw const FormatException('Invalid join request document.');
    }
    final status = switch (data['status']) {
      'pending' => JoinRequestStatus.pending,
      'approved' => JoinRequestStatus.approved,
      'rejected' => JoinRequestStatus.rejected,
      _ => throw const FormatException('Invalid join request status.'),
    };
    final decidedBy = data['decidedBy'] as String?;
    final decidedAt = data['decidedAt'] as Timestamp?;
    final rejectionReason = data['rejectionReason'] as String?;
    final decisionFieldsMatch = switch (status) {
      JoinRequestStatus.pending =>
        decidedBy == null && decidedAt == null && rejectionReason == null,
      JoinRequestStatus.approved =>
        decidedBy != null &&
            decidedBy.isNotEmpty &&
            decidedAt != null &&
            rejectionReason == null,
      JoinRequestStatus.rejected =>
        decidedBy != null &&
            decidedBy.isNotEmpty &&
            decidedAt != null &&
            rejectionReason != null &&
            rejectionReason.trim().isNotEmpty &&
            rejectionReason.length <= 500,
    };
    if (!decisionFieldsMatch ||
        (expectedCourseId != null && expectedCourseId != courseId)) {
      throw const FormatException('Join request fields do not match status.');
    }
    return JoinRequest(
      courseId: courseId,
      studentUid: data['studentUid'] as String,
      name: data['name'] as String,
      email: data['email'] as String,
      studentCode: data['studentCode'] as String?,
      subject: data['subject'] as String,
      group: data['group'] as String,
      period: data['period'] as String,
      status: status,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      decidedBy: decidedBy,
      decidedAt: decidedAt?.toDate(),
      rejectionReason: rejectionReason,
    );
  }

  CourseInvitation _invitationFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String courseId,
  }) {
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data.keys.any(
          (key) => !_invitationKeys.contains(key) && key != 'validForSeconds',
        ) ||
        !data.keys.toSet().containsAll(_invitationKeys) ||
        !_isNormalizedCode(data['code']) ||
        !['active', 'paused', 'inactive'].contains(data['status']) ||
        (data.containsKey('validForSeconds') &&
            (data['validForSeconds'] is! int ||
                (data['validForSeconds'] as int) <
                    CourseInvitation.minValidity.inSeconds ||
                (data['validForSeconds'] as int) >
                    CourseInvitation.maxValidity.inSeconds)) ||
        data['createdAt'] is! Timestamp ||
        data['updatedAt'] is! Timestamp) {
      throw const FormatException('Invalid current invitation document.');
    }
    return CourseInvitation(
      courseId: courseId,
      code: data['code'] as String,
      status: data['status'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      validity: Duration(
        seconds:
            data['validForSeconds'] as int? ??
            CourseInvitation.defaultValidity.inSeconds,
      ),
    );
  }

  CoursePreview _previewFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String expectedCode,
  }) {
    final data = snapshot.data();
    if (!snapshot.exists ||
        data == null ||
        data.keys.toSet().length != _lookupKeys.length ||
        !data.keys.toSet().containsAll(_lookupKeys) ||
        snapshot.id != expectedCode ||
        data['courseId'] is! String ||
        (data['courseId'] as String).isEmpty ||
        data['subject'] is! String ||
        (data['subject'] as String).trim().isEmpty ||
        data['group'] is! String ||
        (data['group'] as String).trim().isEmpty ||
        data['period'] is! String ||
        (data['period'] as String).trim().isEmpty ||
        data['createdAt'] is! Timestamp) {
      throw const FormatException('Invalid course invitation lookup.');
    }
    return CoursePreview(
      courseId: data['courseId'] as String,
      subject: data['subject'] as String,
      group: data['group'] as String,
      period: data['period'] as String,
      code: expectedCode,
    );
  }

  Enrollment _enrollmentFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String courseId,
  ) {
    final data = snapshot.data();
    final keys = data?.keys.toSet() ?? const <String>{};
    final hasEventId = data?.containsKey('lastStatusEventId') ?? false;
    final hasChangedAt = data?.containsKey('lastStatusChangedAt') ?? false;
    final hasRosterEntryId = data?.containsKey('rosterEntryId') ?? false;
    final hasEffectiveStartDate =
        data?.containsKey('effectiveStartDate') ?? false;
    if (!snapshot.exists ||
        data == null ||
        !keys.containsAll(_enrollmentKeys) ||
        keys.difference({
          ..._enrollmentKeys,
          ..._enrollmentTransitionKeys,
          ..._enrollmentRosterKeys,
        }).isNotEmpty ||
        hasEventId != hasChangedAt ||
        hasRosterEntryId != hasEffectiveStartDate ||
        data['studentUid'] != snapshot.id ||
        data['ownerUid'] is! String ||
        data['name'] is! String ||
        data['email'] is! String ||
        !(data['studentCode'] == null || data['studentCode'] is String) ||
        data['subject'] is! String ||
        data['group'] is! String ||
        data['period'] is! String ||
        (data['status'] != 'active' && data['status'] != 'withdrawn') ||
        data['createdAt'] is! Timestamp) {
      throw const FormatException('Invalid canonical enrollment document.');
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
      effectiveStartDate: hasEffectiveStartDate
          ? _academicDateFromTimestamp(data['effectiveStartDate'])
          : _bogotaDate(createdAt),
      lastStatusEventId: hasEventId
          ? data['lastStatusEventId'] as String
          : null,
      lastStatusChangedAt: hasChangedAt
          ? (data['lastStatusChangedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> _enrollmentMap(Enrollment enrollment) => {
    'studentUid': enrollment.studentUid,
    'ownerUid': enrollment.ownerUid,
    'name': enrollment.name,
    'email': enrollment.email,
    'studentCode': enrollment.studentCode,
    'subject': enrollment.subject,
    'group': enrollment.group,
    'period': enrollment.period,
    'status': 'active',
    'rosterEntryId': enrollment.rosterEntryId,
    'effectiveStartDate': Timestamp.fromDate(
      enrollment.effectiveStartDate!.toUtcTimestamp(),
    ),
    'createdAt': FieldValue.serverTimestamp(),
  };

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

  AcademicDate _bogotaDate(DateTime instant) => AcademicDate.fromDateTime(
    instant.toUtc().subtract(const Duration(hours: 5)),
  );

  AcademicDate _defaultEffectiveStartDate(
    AcademicDate start,
    AcademicDate end,
  ) {
    final today = _bogotaDate(DateTime.now());
    if (today.compareTo(start) < 0) return start;
    if (today.compareTo(end) > 0) {
      throw const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
    }
    return today;
  }

  void _validateEffectiveDateForCourse(
    AcademicDate date,
    AcademicDate start,
    AcademicDate end, {
    required bool allowFutureCourseStart,
  }) {
    if (start.compareTo(end) > 0 ||
        date.compareTo(start) < 0 ||
        date.compareTo(end) > 0) {
      throw const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
    }
    final today = _bogotaDate(DateTime.now());
    if (date.compareTo(today) > 0 &&
        !(allowFutureCourseStart && date == start)) {
      throw const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
    }
  }

  String _courseIdFromRequestPath(String path) {
    final parts = path.split('/');
    if (parts.length != 4 ||
        parts[0] != 'courses' ||
        parts[2] != 'join_requests') {
      throw const FormatException('Invalid join request path.');
    }
    return parts[1];
  }

  bool _isNormalizedCode(Object? value) =>
      value is String &&
      value.length == 16 &&
      value.split('').every(CourseEntryValidator.alphabet.contains);

  void _requireProfileData(
    Map<String, dynamic>? profile,
    User user, {
    required String role,
  }) {
    if (profile == null ||
        profile.keys.toSet().length != _profileKeys.length ||
        !profile.keys.toSet().containsAll(_profileKeys) ||
        profile['name'] is! String ||
        (profile['name'] as String).trim().isEmpty ||
        (profile['name'] as String).length > 100 ||
        profile['email'] != user.email ||
        !(profile['studentCode'] == null || profile['studentCode'] is String) ||
        profile['roles'] is! List) {
      throw const CourseEntryFailure(CourseEntryFailureKind.profileInvalid);
    }
    if (!(profile['roles'] as List).contains(role)) {
      throw CourseEntryFailure(
        role == 'teacher'
            ? CourseEntryFailureKind.teacherRoleRequired
            : CourseEntryFailureKind.studentRoleRequired,
      );
    }
  }

  User _requireVerifiedUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const CourseEntryFailure(CourseEntryFailureKind.unauthenticated);
    }
    if (!user.emailVerified || user.email == null) {
      throw const CourseEntryFailure(CourseEntryFailureKind.emailNotVerified);
    }
    return user;
  }

  Future<Map<String, dynamic>> _requireProfile(
    User user, {
    required String role,
  }) async {
    final uid = user.uid;
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    _requireSameUser(uid);
    final profile = snapshot.data();
    _requireProfileData(profile, user, role: role);
    return profile!;
  }

  void _requireSameUser(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw const CourseEntryFailure(CourseEntryFailureKind.unauthenticated);
    }
  }

  void _validateDocumentId(String value) {
    if (value.isEmpty || value.contains('/')) {
      throw const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
    }
  }

  void _validatePageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 100) {
      throw const CourseEntryFailure(CourseEntryFailureKind.invalidInput);
    }
  }

  CourseEntryFailure _diagnosticFailure(
    CourseEntryFailure error,
    String step,
  ) => CourseEntryFailure(
    error.kind,
    cause: error.cause,
    diagnosticStep: error.diagnosticStep ?? step,
    diagnosticCode: error.diagnosticCode ?? error.kind.name,
  );

  CourseEntryFailure _translate(
    FirebaseException error, {
    String step = 'operation',
  }) {
    final kind = switch (error.code) {
      'permission-denied' => CourseEntryFailureKind.permissionDenied,
      'unauthenticated' => CourseEntryFailureKind.unauthenticated,
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' => CourseEntryFailureKind.network,
      _ => CourseEntryFailureKind.unknown,
    };
    return CourseEntryFailure(
      kind,
      cause: error,
      diagnosticStep: step,
      diagnosticCode: error.code,
    );
  }
}

class _InvitationWrite {
  const _InvitationWrite(this.invitation, {required this.isExisting});

  final CourseInvitation invitation;
  final bool isExisting;
}
