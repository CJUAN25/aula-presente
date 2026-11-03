import 'dart:async';

import 'package:aula_presente/features/administration/domain/teacher_access_repository.dart';
import 'package:aula_presente/features/administration/domain/teacher_access_request.dart';
import 'package:aula_presente/features/auth/domain/auth_access.dart';
import 'package:aula_presente/features/auth/domain/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.access);

  AuthAccess access;
  final StreamController<AuthAccess> accessController =
      StreamController<AuthAccess>.broadcast();
  int refreshCalls = 0;
  int signOutCalls = 0;

  void updateAccess(AuthAccess value) {
    access = value;
    accessController.add(value);
  }

  @override
  Stream<AuthAccess> watchAccess() => Stream<AuthAccess>.multi((controller) {
    controller.add(access);
    final subscription = accessController.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<AuthAccess> restoreSession() async => access;

  @override
  Future<AuthAccess> signIn({
    required String email,
    required String password,
  }) async => access;

  @override
  Future<AuthRegistrationResult> register({
    required String name,
    required String email,
    required String studentCode,
    required String password,
  }) async => AuthRegistrationResult(
    email: email,
    displayNameUpdated: true,
    profileCreated: true,
    verificationEmailSent: true,
  );

  @override
  Future<AuthAccess> refreshAccess({String? expectedEmail}) async {
    refreshCalls++;
    return access;
  }

  @override
  Future<void> retryRegistrationSetup({
    required String name,
    required String studentCode,
  }) async {}

  @override
  Future<void> resendEmailVerification() async {}

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> requestEmailCorrection({
    required String newEmail,
    required String currentPassword,
  }) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

class FakeTeacherAccessRepository implements TeacherAccessRepository {
  final _neverOwnWatch = StreamController<TeacherAccessRequest?>.broadcast();
  final _neverPending =
      StreamController<List<TeacherAccessRequest>>.broadcast();
  TeacherAccessRequest? ownRequest;
  TeacherAccessRequest? requestOnGet;
  List<TeacherAccessRequest> pendingRequests = [];
  TeacherAccessReview? review;
  Object? ownWatchError;
  bool ownWatchNever = false;
  Object? getErrorForTest;
  Object? listError;
  bool pendingNever = false;
  Object? createError;
  Object? reviewError;
  Object? decisionError;
  Completer<TeacherAccessRequest>? createCompleter;
  int getOwnCalls = 0;
  int watchOwnCalls = 0;
  int createCalls = 0;
  int watchPendingCalls = 0;
  int reviewCalls = 0;
  int decisionCalls = 0;
  TeacherAccessDecision? lastDecision;
  String? lastRejectionReason;

  @override
  Future<TeacherAccessRequest?> getOwnRequest() async {
    getOwnCalls++;
    if (getErrorForTest != null) throw getErrorForTest!;
    return requestOnGet ?? ownRequest;
  }

  @override
  Stream<TeacherAccessRequest?> watchOwnRequest() {
    watchOwnCalls++;
    if (ownWatchNever) {
      return _neverOwnWatch.stream;
    }
    if (ownWatchError != null) {
      return Stream<TeacherAccessRequest?>.error(ownWatchError!);
    }
    return Stream<TeacherAccessRequest?>.value(ownRequest);
  }

  @override
  Future<TeacherAccessRequest> createOwnRequest() async {
    createCalls++;
    if (createError != null) throw createError!;
    if (createCompleter != null) {
      final request = await createCompleter!.future;
      ownRequest = request;
      pendingRequests = [request];
      return request;
    }
    final request = ownRequest ?? sampleRequest();
    ownRequest = request;
    pendingRequests = [request];
    return request;
  }

  @override
  Stream<List<TeacherAccessRequest>> watchPendingRequests() {
    watchPendingCalls++;
    if (pendingNever) {
      return _neverPending.stream;
    }
    if (listError != null) {
      return Stream<List<TeacherAccessRequest>>.error(listError!);
    }
    return Stream<List<TeacherAccessRequest>>.value(pendingRequests);
  }

  @override
  Future<TeacherAccessReview> getReview(String requesterUid) async {
    reviewCalls++;
    if (reviewError != null) throw reviewError!;
    return review ?? sampleReview();
  }

  @override
  Future<TeacherAccessRequest> decideRequest({
    required String requesterUid,
    required TeacherAccessDecision decision,
    String? rejectionReason,
  }) async {
    decisionCalls++;
    lastDecision = decision;
    lastRejectionReason = rejectionReason;
    if (decisionError != null) throw decisionError!;
    final previous = ownRequest ?? sampleRequest();
    final decided = TeacherAccessRequest(
      uid: previous.uid,
      name: previous.name,
      email: previous.email,
      studentCode: previous.studentCode,
      status: decision == TeacherAccessDecision.approve
          ? TeacherAccessStatus.approved
          : TeacherAccessStatus.rejected,
      createdAt: previous.createdAt,
      decidedBy: 'admin-test',
      decidedAt: DateTime(2026, 10, 28),
      rejectionReason: decision == TeacherAccessDecision.reject
          ? rejectionReason
          : null,
    );
    ownRequest = decided;
    pendingRequests = [decided];
    return decided;
  }
}

AuthAccess studentAccess({List<String> roles = const ['student']}) =>
    AuthAccess(
      status: AuthAccessStatus.student,
      uid: 'requester-1',
      email: 'persona@example.edu',
      name: 'Ana Pérez',
      studentCode: 'EST-2048',
      roles: roles,
    );

AuthAccess adminAccess({List<String> roles = const ['admin']}) => AuthAccess(
  status: AuthAccessStatus.accessAvailable,
  uid: 'admin-1',
  email: 'admin@example.edu',
  name: 'Administración',
  roles: roles,
);

TeacherAccessRequest sampleRequest({
  TeacherAccessStatus status = TeacherAccessStatus.pending,
  String? rejectionReason,
}) => TeacherAccessRequest(
  uid: 'requester-1',
  name: 'Ana Pérez',
  email: 'persona@example.edu',
  studentCode: 'EST-2048',
  status: status,
  createdAt: DateTime(2026, 10, 20),
  decidedBy: status == TeacherAccessStatus.pending ? null : 'admin-1',
  decidedAt: status == TeacherAccessStatus.pending
      ? null
      : DateTime(2026, 10, 28),
  rejectionReason: rejectionReason,
);

TeacherAccessReview sampleReview() => TeacherAccessReview(
  request: sampleRequest(),
  currentName: 'Ana María Pérez',
  currentEmail: 'persona@example.edu',
  currentStudentCode: 'EST-2048',
  currentRoles: const ['student'],
);
