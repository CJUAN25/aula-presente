import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../application/teacher_access_validator.dart';
import '../domain/teacher_access_repository.dart';
import '../domain/teacher_access_request.dart';

class FirestoreTeacherAccessRepository implements TeacherAccessRepository {
  FirestoreTeacherAccessRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('teacher_access_requests');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<TeacherAccessRequest?> getOwnRequest() async {
    try {
      final user = _requireSignedInUser();
      final snapshot = await _requests
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      _ensureCurrentUid(user.uid);
      if (!snapshot.exists) return null;
      return _requestFromDocument(snapshot);
    } on TeacherAccessFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Stream<TeacherAccessRequest?> watchOwnRequest() async* {
    try {
      final user = _requireSignedInUser();
      await for (final snapshot
          in _requests.doc(user.uid).snapshots(includeMetadataChanges: true)) {
        if (_auth.currentUser?.uid != user.uid) {
          throw const TeacherAccessFailure(
            TeacherAccessFailureKind.unauthenticated,
          );
        }
        if (snapshot.metadata.isFromCache ||
            snapshot.metadata.hasPendingWrites) {
          continue;
        }
        yield snapshot.exists ? _requestFromDocument(snapshot) : null;
      }
    } on TeacherAccessFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<TeacherAccessRequest> createOwnRequest() async {
    try {
      final user = await _refreshVerifiedCurrentUser();
      final requestReference = _requests.doc(user.uid);
      final profileReference = _users.doc(user.uid);

      await _firestore.runTransaction<void>((transaction) async {
        _ensureCurrentUid(user.uid);
        final requestSnapshot = await transaction.get(requestReference);
        final profileSnapshot = await transaction.get(profileReference);

        if (requestSnapshot.exists) {
          throw const TeacherAccessFailure(
            TeacherAccessFailureKind.alreadyExists,
          );
        }
        if (!profileSnapshot.exists) {
          throw const TeacherAccessFailure(
            TeacherAccessFailureKind.profileUnavailable,
          );
        }

        final profile = _profileFromDocument(profileSnapshot);
        if (_normalizedEmail(profile.email) != _normalizedEmail(user.email)) {
          throw const TeacherAccessFailure(
            TeacherAccessFailureKind.profileInvalid,
          );
        }

        _ensureCurrentUid(user.uid);
        transaction.set(requestReference, {
          'uid': user.uid,
          'name': profile.name,
          'email': profile.email,
          'studentCode': profile.studentCode,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'decidedBy': null,
          'decidedAt': null,
          'rejectionReason': null,
        });
      });

      _ensureCurrentUid(user.uid);
      final savedRequest = await requestReference.get(
        const GetOptions(source: Source.server),
      );
      if (!savedRequest.exists) {
        throw const TeacherAccessFailure(TeacherAccessFailureKind.notFound);
      }
      return _requestFromDocument(savedRequest);
    } on TeacherAccessFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Stream<List<TeacherAccessRequest>> watchPendingRequests() async* {
    try {
      final user = _requireSignedInUser();
      final query = _requests
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt');

      await for (final snapshot in query.snapshots(
        includeMetadataChanges: true,
      )) {
        if (_auth.currentUser?.uid != user.uid) {
          throw const TeacherAccessFailure(
            TeacherAccessFailureKind.unauthenticated,
          );
        }
        if (snapshot.metadata.isFromCache ||
            snapshot.metadata.hasPendingWrites) {
          continue;
        }
        yield snapshot.docs.map(_requestFromDocument).toList(growable: false);
      }
    } on TeacherAccessFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<TeacherAccessReview> getReview(String requesterUid) async {
    _validateRequesterUid(requesterUid);
    try {
      final viewer = _requireSignedInUser();
      final requestReference = _requests.doc(requesterUid);
      final profileReference = _users.doc(requesterUid);

      return await _firestore.runTransaction<TeacherAccessReview>((
        transaction,
      ) async {
        _ensureCurrentUid(viewer.uid);
        final requestSnapshot = await transaction.get(requestReference);
        final profileSnapshot = await transaction.get(profileReference);
        if (!requestSnapshot.exists) {
          throw const TeacherAccessFailure(TeacherAccessFailureKind.notFound);
        }
        if (!profileSnapshot.exists) {
          throw const TeacherAccessFailure(
            TeacherAccessFailureKind.profileUnavailable,
          );
        }

        final request = _requestFromDocument(requestSnapshot);
        final profile = _profileFromDocument(profileSnapshot);
        _ensureCurrentUid(viewer.uid);
        return TeacherAccessReview(
          request: request,
          currentName: profile.name,
          currentEmail: profile.email,
          currentStudentCode: profile.studentCode,
          currentRoles: profile.roles,
        );
      });
    } on TeacherAccessFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<TeacherAccessRequest> decideRequest({
    required String requesterUid,
    required TeacherAccessDecision decision,
    String? rejectionReason,
  }) async {
    _validateRequesterUid(requesterUid);
    final normalizedReason = _validatedReason(decision, rejectionReason);

    try {
      final admin = await _refreshVerifiedCurrentUser();
      if (admin.uid == requesterUid) {
        throw const TeacherAccessFailure(
          TeacherAccessFailureKind.permissionDenied,
        );
      }

      final adminProfileReference = _users.doc(admin.uid);
      final requesterProfileReference = _users.doc(requesterUid);
      final requestReference = _requests.doc(requesterUid);

      final committedRequest = await _firestore
          .runTransaction<TeacherAccessRequest>((transaction) async {
            _ensureCurrentUid(admin.uid);
            final adminSnapshot = await transaction.get(adminProfileReference);
            final requestSnapshot = await transaction.get(requestReference);
            final requesterSnapshot = await transaction.get(
              requesterProfileReference,
            );

            if (!adminSnapshot.exists) {
              throw const TeacherAccessFailure(
                TeacherAccessFailureKind.permissionDenied,
              );
            }
            final adminProfile = _profileFromDocument(adminSnapshot);
            if (!adminProfile.roles.contains('admin') ||
                _normalizedEmail(adminProfile.email) !=
                    _normalizedEmail(admin.email)) {
              throw const TeacherAccessFailure(
                TeacherAccessFailureKind.permissionDenied,
              );
            }
            if (!requestSnapshot.exists) {
              throw const TeacherAccessFailure(
                TeacherAccessFailureKind.notFound,
              );
            }
            if (!requesterSnapshot.exists) {
              throw const TeacherAccessFailure(
                TeacherAccessFailureKind.profileUnavailable,
              );
            }

            final request = _requestFromDocument(requestSnapshot);
            final requesterProfile = _profileFromDocument(requesterSnapshot);
            _ensureCurrentUid(admin.uid);
            if (request.status != TeacherAccessStatus.pending) {
              throw const TeacherAccessFailure(
                TeacherAccessFailureKind.notPending,
              );
            }

            final decidedStatus = decision == TeacherAccessDecision.approve
                ? TeacherAccessStatus.approved
                : TeacherAccessStatus.rejected;
            if (decision == TeacherAccessDecision.approve) {
              final roles = List<String>.of(requesterProfile.roles);
              if (!roles.contains('teacher')) roles.add('teacher');
              if (roles.length != requesterProfile.roles.length) {
                transaction.update(requesterProfileReference, {'roles': roles});
              }
            }

            transaction.update(requestReference, {
              'status': decision == TeacherAccessDecision.approve
                  ? 'approved'
                  : 'rejected',
              'decidedBy': admin.uid,
              'decidedAt': FieldValue.serverTimestamp(),
              'rejectionReason': normalizedReason,
            });
            // The transaction future completes only after Firestore confirms the
            // atomic write. Admin reads are intentionally limited to pending
            // requests, so do not fetch this resolved document after committing.
            // The server timestamp remains authoritative in Firestore; S06 does
            // not display a client-estimated decision time.
            return TeacherAccessRequest(
              uid: request.uid,
              name: request.name,
              email: request.email,
              studentCode: request.studentCode,
              status: decidedStatus,
              createdAt: request.createdAt,
              decidedBy: admin.uid,
              decidedAt: null,
              rejectionReason: normalizedReason,
            );
          });

      return committedRequest;
    } on TeacherAccessFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _translate(error);
    }
  }

  User _requireSignedInUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const TeacherAccessFailure(
        TeacherAccessFailureKind.unauthenticated,
      );
    }
    return user;
  }

  Future<User> _refreshVerifiedCurrentUser() async {
    final initialUser = _requireSignedInUser();
    await initialUser.reload();
    final reloadedUser = _auth.currentUser;
    if (reloadedUser == null || reloadedUser.uid != initialUser.uid) {
      throw const TeacherAccessFailure(
        TeacherAccessFailureKind.unauthenticated,
      );
    }
    await reloadedUser.getIdToken(true);
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != initialUser.uid) {
      throw const TeacherAccessFailure(
        TeacherAccessFailureKind.unauthenticated,
      );
    }
    if (!currentUser.emailVerified) {
      throw const TeacherAccessFailure(
        TeacherAccessFailureKind.verificationRequired,
      );
    }
    if (currentUser.email == null || currentUser.email!.trim().isEmpty) {
      throw const TeacherAccessFailure(TeacherAccessFailureKind.profileInvalid);
    }
    return currentUser;
  }

  void _ensureCurrentUid(String expectedUid) {
    if (_auth.currentUser?.uid != expectedUid) {
      throw const TeacherAccessFailure(
        TeacherAccessFailureKind.unauthenticated,
      );
    }
  }

  void _validateRequesterUid(String uid) {
    if (uid.trim().isEmpty || uid.contains('/')) {
      throw const TeacherAccessFailure(TeacherAccessFailureKind.notFound);
    }
  }

  String? _validatedReason(
    TeacherAccessDecision decision,
    String? rejectionReason,
  ) {
    if (decision == TeacherAccessDecision.approve) {
      if (rejectionReason != null) {
        throw const TeacherAccessFailure(
          TeacherAccessFailureKind.invalidReason,
        );
      }
      return null;
    }

    if (rejectionReason == null ||
        TeacherAccessValidator.rejectionReasonError(rejectionReason) != null) {
      throw const TeacherAccessFailure(TeacherAccessFailureKind.invalidReason);
    }
    return TeacherAccessValidator.normalizeRejectionReason(rejectionReason);
  }

  TeacherAccessRequest _requestFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    const expectedFields = {
      'uid',
      'name',
      'email',
      'studentCode',
      'status',
      'createdAt',
      'decidedBy',
      'decidedAt',
      'rejectionReason',
    };
    if (data == null ||
        data.keys.toSet().length != expectedFields.length ||
        !data.keys.toSet().containsAll(expectedFields)) {
      throw const TeacherAccessFailure(TeacherAccessFailureKind.unknown);
    }

    final uid = data['uid'];
    final name = data['name'];
    final email = data['email'];
    final studentCode = data['studentCode'];
    final rawStatus = data['status'];
    final decidedBy = data['decidedBy'];
    final rejectionReason = data['rejectionReason'];
    if (uid is! String ||
        uid != document.id ||
        name is! String ||
        !_isValidName(name) ||
        email is! String ||
        !_isValidEmail(email) ||
        (studentCode != null && !_isValidStudentCode(studentCode)) ||
        (decidedBy != null && decidedBy is! String) ||
        (rejectionReason != null && rejectionReason is! String)) {
      throw const TeacherAccessFailure(TeacherAccessFailureKind.unknown);
    }

    final TeacherAccessStatus status;
    switch (rawStatus) {
      case 'pending':
        status = TeacherAccessStatus.pending;
      case 'approved':
        status = TeacherAccessStatus.approved;
      case 'rejected':
        status = TeacherAccessStatus.rejected;
      default:
        throw const TeacherAccessFailure(TeacherAccessFailureKind.unknown);
    }

    final createdAt = _timestamp(data['createdAt']);
    final decidedAt = _timestamp(data['decidedAt']);
    if (status == TeacherAccessStatus.pending) {
      if (decidedBy != null || decidedAt != null || rejectionReason != null) {
        throw const TeacherAccessFailure(TeacherAccessFailureKind.unknown);
      }
    } else if (decidedBy is! String ||
        decidedBy.trim().isEmpty ||
        decidedAt == null ||
        (status == TeacherAccessStatus.approved && rejectionReason != null) ||
        (status == TeacherAccessStatus.rejected &&
            (rejectionReason is! String ||
                TeacherAccessValidator.rejectionReasonError(rejectionReason) !=
                    null))) {
      throw const TeacherAccessFailure(TeacherAccessFailureKind.unknown);
    }

    return TeacherAccessRequest(
      uid: uid,
      name: name,
      email: email,
      studentCode: studentCode as String?,
      status: status,
      createdAt: createdAt,
      decidedBy: decidedBy as String?,
      decidedAt: decidedAt,
      rejectionReason: rejectionReason as String?,
    );
  }

  _CurrentProfile _profileFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw const TeacherAccessFailure(TeacherAccessFailureKind.profileInvalid);
    }

    final name = data['name'];
    final email = data['email'];
    final studentCode = data['studentCode'];
    final rawRoles = data['roles'];
    if (name is! String ||
        !_isValidName(name) ||
        email is! String ||
        !_isValidEmail(email) ||
        (studentCode != null && !_isValidStudentCode(studentCode)) ||
        rawRoles is! List ||
        rawRoles.any((role) => role is! String)) {
      throw const TeacherAccessFailure(TeacherAccessFailureKind.profileInvalid);
    }

    return _CurrentProfile(
      name: name,
      email: email,
      studentCode: studentCode as String?,
      roles: List<String>.unmodifiable(rawRoles.cast<String>()),
    );
  }

  DateTime? _timestamp(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    throw const TeacherAccessFailure(TeacherAccessFailureKind.unknown);
  }

  bool _isValidName(String value) =>
      value.trim().isNotEmpty && value.length <= 100;

  bool _isValidEmail(String value) =>
      value.trim().length >= 3 && value.length <= 254;

  bool _isValidStudentCode(Object? value) =>
      value is String && value.trim().isNotEmpty && value.length <= 40;

  String? _normalizedEmail(String? email) => email?.trim().toLowerCase();

  TeacherAccessFailure _translate(FirebaseException error) {
    return switch (error.code) {
      'unauthenticated' ||
      'user-not-found' ||
      'user-disabled' ||
      'user-token-expired' ||
      'invalid-user-token' => const TeacherAccessFailure(
        TeacherAccessFailureKind.unauthenticated,
      ),
      'permission-denied' => const TeacherAccessFailure(
        TeacherAccessFailureKind.permissionDenied,
      ),
      'already-exists' => const TeacherAccessFailure(
        TeacherAccessFailureKind.alreadyExists,
      ),
      'not-found' => const TeacherAccessFailure(
        TeacherAccessFailureKind.notFound,
      ),
      'network-request-failed' || 'unavailable' || 'deadline-exceeded' =>
        const TeacherAccessFailure(TeacherAccessFailureKind.network),
      _ => const TeacherAccessFailure(TeacherAccessFailureKind.unknown),
    };
  }
}

class _CurrentProfile {
  const _CurrentProfile({
    required this.name,
    required this.email,
    required this.studentCode,
    required this.roles,
  });

  final String name;
  final String email;
  final String? studentCode;
  final List<String> roles;
}
