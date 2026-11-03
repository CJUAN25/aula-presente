import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_access.dart';
import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<AuthAccess> restoreSession() async {
    try {
      await _auth.authStateChanges().first;
      final user = _auth.currentUser;
      if (user == null) {
        return const AuthAccess(status: AuthAccessStatus.signedOut);
      }

      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        return const AuthAccess(status: AuthAccessStatus.signedOut);
      }
      await refreshedUser.getIdToken(true);
      return await _resolveUser(refreshedUser);
    } on FirebaseException catch (error) {
      throw AuthFailure(_failureKind(error));
    }
  }

  @override
  Stream<AuthAccess> watchAccess() {
    String? previousUid;
    return _auth.userChanges().asyncExpand((user) {
      if (user == null) {
        previousUid = null;
        return Stream.value(
          const AuthAccess(status: AuthAccessStatus.signedOut),
        );
      }
      final accountChanged = previousUid != null && previousUid != user.uid;
      previousUid = user.uid;
      return _watchProfile(user, showCheckingState: accountChanged);
    });
  }

  Stream<AuthAccess> _watchProfile(
    User initialUser, {
    bool showCheckingState = false,
  }) async* {
    final profileReference = _users.doc(initialUser.uid);
    if (showCheckingState) {
      yield AuthAccess(
        status: AuthAccessStatus.checking,
        uid: initialUser.uid,
        email: initialUser.email,
        name: initialUser.displayName,
      );
    }
    try {
      await for (final snapshot in profileReference.snapshots(
        includeMetadataChanges: true,
      )) {
        final user = _auth.currentUser;
        if (user == null || user.uid != initialUser.uid) {
          yield const AuthAccess(status: AuthAccessStatus.signedOut);
          return;
        }

        if (!user.emailVerified) {
          yield AuthAccess(
            status: AuthAccessStatus.verificationRequired,
            uid: user.uid,
            email: user.email,
            name: user.displayName,
          );
          continue;
        }

        if (snapshot.metadata.isFromCache) {
          continue;
        }

        yield await _resolveProfileSnapshot(user, snapshot);
      }
    } on FirebaseException catch (error) {
      final user = _auth.currentUser;
      if (user?.uid == initialUser.uid) {
        yield AuthAccess(
          status: AuthAccessStatus.profileUnavailable,
          uid: user!.uid,
          email: user.email,
          name: user.displayName,
          failure: _failureKind(error),
        );
      }
    }
  }

  @override
  Future<AuthAccess> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const AuthFailure(AuthFailureKind.unknown);
      return await _resolveUser(user);
    } on AuthFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw AuthFailure(_failureKind(error));
    }
  }

  @override
  Future<AuthRegistrationResult> register({
    required String name,
    required String email,
    required String studentCode,
    required String password,
  }) async {
    try {
      await _setSpanishEmailLanguage();
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null || user.email == null) {
        throw const AuthFailure(AuthFailureKind.unknown);
      }

      AuthFailureKind? setupFailure;
      var displayNameUpdated = false;
      var profileCreated = false;
      var verificationEmailSent = false;

      try {
        await user.updateDisplayName(name.trim());
        displayNameUpdated = true;
      } on FirebaseException catch (error) {
        setupFailure = _failureKind(error);
      }

      try {
        await _writeStudentProfile(
          user: user,
          name: name,
          studentCode: studentCode,
        );
        profileCreated = true;
      } on FirebaseException catch (error) {
        setupFailure ??= _failureKind(error);
      }

      try {
        await _setSpanishEmailLanguage();
        await user.sendEmailVerification();
        verificationEmailSent = true;
      } on FirebaseException catch (error) {
        setupFailure ??= _failureKind(error);
      }

      return AuthRegistrationResult(
        email: user.email!,
        displayNameUpdated: displayNameUpdated,
        profileCreated: profileCreated,
        verificationEmailSent: verificationEmailSent,
        setupFailure: setupFailure,
      );
    } on AuthFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw AuthFailure(_failureKind(error));
    }
  }

  @override
  Future<AuthAccess> refreshAccess({String? expectedEmail}) async {
    try {
      final current = _auth.currentUser;
      if (current == null) {
        return const AuthAccess(status: AuthAccessStatus.signedOut);
      }

      await current.reload();
      final user = _auth.currentUser;
      if (user == null) {
        return const AuthAccess(status: AuthAccessStatus.signedOut);
      }
      await user.getIdToken(true);

      if (expectedEmail != null &&
          _normalizedEmail(user.email) != _normalizedEmail(expectedEmail)) {
        return AuthAccess(
          status: AuthAccessStatus.pendingEmailChange,
          uid: user.uid,
          email: user.email,
          name: user.displayName,
        );
      }

      return await _resolveUser(user);
    } on AuthFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw AuthFailure(_failureKind(error));
    }
  }

  @override
  Future<void> retryRegistrationSetup({
    required String name,
    required String studentCode,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthFailure(AuthFailureKind.unknown);
    }

    try {
      await user.updateDisplayName(name.trim());
      await _writeStudentProfile(
        user: user,
        name: name,
        studentCode: studentCode,
      );
    } on FirebaseException catch (error) {
      throw AuthFailure(_failureKind(error));
    }
  }

  @override
  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure(AuthFailureKind.unknown);

    try {
      await _setSpanishEmailLanguage();
      await user.sendEmailVerification();
    } on FirebaseException catch (error) {
      throw AuthFailure(_failureKind(error));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _setSpanishEmailLanguage();
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        throw const AuthFailure(AuthFailureKind.network);
      }
      // Keep account existence, disabled status, and throttling indistinguishable.
    } on FirebaseException catch (error) {
      throw AuthFailure(_failureKind(error));
    }
  }

  @override
  Future<void> requestEmailCorrection({
    required String newEmail,
    required String currentPassword,
  }) async {
    final user = _auth.currentUser;
    final currentEmail = user?.email;
    if (user == null || currentEmail == null) {
      throw const AuthFailure(AuthFailureKind.unknown);
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: currentEmail,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await _setSpanishEmailLanguage();
      await user.verifyBeforeUpdateEmail(newEmail.trim());
    } on FirebaseException catch (error) {
      throw AuthFailure(_failureKind(error));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  Future<void> _setSpanishEmailLanguage() => _auth.setLanguageCode('es');

  Future<void> _writeStudentProfile({
    required User user,
    required String name,
    required String studentCode,
  }) async {
    final email = user.email;
    if (email == null) throw const AuthFailure(AuthFailureKind.unknown);
    final profileReference = _users.doc(user.uid);
    await _firestore.runTransaction<void>((transaction) async {
      final profileSnapshot = await transaction.get(profileReference);
      if (profileSnapshot.exists) {
        // Setup retries must not replace roles granted by a trusted admin.
        return;
      }
      transaction.set(profileReference, {
        'name': name.trim(),
        'email': email,
        'studentCode': studentCode.trim().isEmpty ? null : studentCode.trim(),
        'roles': ['student'],
      });
    });
  }

  Future<AuthAccess> _resolveUser(User user) async {
    if (!user.emailVerified) {
      return AuthAccess(
        status: AuthAccessStatus.verificationRequired,
        uid: user.uid,
        email: user.email,
        name: user.displayName,
      );
    }

    try {
      final profileSnapshot = await _users.doc(user.uid).get(
        const GetOptions(source: Source.server),
      );
      return await _resolveProfileSnapshot(user, profileSnapshot);
    } on FirebaseException catch (error) {
      return AuthAccess(
        status: AuthAccessStatus.profileUnavailable,
        uid: user.uid,
        email: user.email,
        name: user.displayName,
        failure: _failureKind(error),
      );
    }
  }

  Future<AuthAccess> _resolveProfileSnapshot(
    User user,
    DocumentSnapshot<Map<String, dynamic>> profileSnapshot,
  ) async {
    if (!user.emailVerified) {
      return AuthAccess(
        status: AuthAccessStatus.verificationRequired,
        uid: user.uid,
        email: user.email,
        name: user.displayName,
      );
    }

    try {
      if (!profileSnapshot.exists) {
        return AuthAccess(
          status: AuthAccessStatus.profileMissing,
          uid: user.uid,
          email: user.email,
          name: user.displayName,
        );
      }

      final profile = profileSnapshot.data();
      var profileEmail = profile?['email'];
      if (profileEmail is String && profileEmail != user.email) {
        // Firebase Auth is the source of truth after its email is verified.
        // This also lets a later retry finish a previously interrupted sync.
        await _users.doc(user.uid).update({'email': user.email});
        profileEmail = user.email;
      }
      if (profileEmail is! String ||
          _normalizedEmail(profileEmail) != _normalizedEmail(user.email)) {
        return AuthAccess(
          status: AuthAccessStatus.profileEmailMismatch,
          uid: user.uid,
          email: user.email,
          name: user.displayName,
        );
      }

      final nameValue = profile?['name'];
      final studentCodeValue = profile?['studentCode'];
      final rolesValue = profile?['roles'];
      if (nameValue is! String ||
          (studentCodeValue != null && studentCodeValue is! String) ||
          rolesValue is! List ||
          rolesValue.isEmpty ||
          rolesValue.length > 3 ||
          rolesValue.any(
            (role) =>
                role is! String ||
                !const {'student', 'teacher', 'admin'}.contains(role),
          )) {
        return AuthAccess(
          status: AuthAccessStatus.profileInvalid,
          uid: user.uid,
          email: user.email,
        );
      }
      final roles = rolesValue.cast<String>().toList(growable: false);
      if (!roles.any(const {'student', 'teacher', 'admin'}.contains)) {
        return AuthAccess(
          status: AuthAccessStatus.roleNotGranted,
          uid: user.uid,
          email: user.email,
          name: nameValue,
          roles: roles,
        );
      }

      return AuthAccess(
        status: AuthAccessStatus.accessAvailable,
        uid: user.uid,
        email: user.email,
        name: nameValue,
        studentCode: studentCodeValue as String?,
        roles: roles,
      );
    } on FirebaseException catch (error) {
      return AuthAccess(
        status: AuthAccessStatus.profileUnavailable,
        uid: user.uid,
        email: user.email,
        name: user.displayName,
        failure: _failureKind(error),
      );
    }
  }

  AuthFailureKind _failureKind(FirebaseException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return AuthFailureKind.invalidCredentials;
      case 'email-already-in-use':
        return AuthFailureKind.emailAlreadyInUse;
      case 'weak-password':
        return AuthFailureKind.weakPassword;
      case 'network-request-failed':
      case 'unavailable':
      case 'deadline-exceeded':
        return AuthFailureKind.network;
      case 'too-many-requests':
        return AuthFailureKind.tooManyRequests;
      case 'requires-recent-login':
        return AuthFailureKind.recentLoginRequired;
      case 'permission-denied':
      case 'not-found':
        return AuthFailureKind.profileUnavailable;
      default:
        return AuthFailureKind.unknown;
    }
  }

  String? _normalizedEmail(String? email) => email?.trim().toLowerCase();
}
