enum AuthAccessStatus {
  signedOut,
  verificationRequired,
  student,
  profileMissing,
  profileInvalid,
  profileEmailMismatch,
  roleNotGranted,
  accessAvailable,
  checking,
  profileUnavailable,
  pendingEmailChange,
}

enum AuthFailureKind {
  invalidCredentials,
  emailAlreadyInUse,
  weakPassword,
  network,
  tooManyRequests,
  recentLoginRequired,
  profileUnavailable,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind);

  final AuthFailureKind kind;
}

class AuthAccess {
  const AuthAccess({
    required this.status,
    this.uid,
    this.email,
    this.name,
    this.studentCode,
    this.roles = const [],
    this.failure,
  });

  final AuthAccessStatus status;
  final String? uid;
  final String? email;
  final String? name;
  final String? studentCode;
  final List<String> roles;
  final AuthFailureKind? failure;
}

class AuthRegistrationResult {
  const AuthRegistrationResult({
    required this.email,
    required this.displayNameUpdated,
    required this.profileCreated,
    required this.verificationEmailSent,
    this.setupFailure,
  });

  final String email;
  final bool displayNameUpdated;
  final bool profileCreated;
  final bool verificationEmailSent;
  final AuthFailureKind? setupFailure;
}
