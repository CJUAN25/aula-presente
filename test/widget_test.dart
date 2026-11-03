import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aula_presente/app/aula_presente_app.dart';
import 'package:aula_presente/features/auth/domain/auth_access.dart';
import 'package:aula_presente/features/auth/domain/auth_repository.dart';
import 'package:aula_presente/features/administration/domain/teacher_access_repository.dart'
    as teacher_access;
import 'package:aula_presente/features/administration/domain/teacher_access_request.dart'
    as teacher_access;
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/courses/domain/course_creation_result.dart';
import 'package:aula_presente/features/courses/domain/course_cursor.dart';
import 'package:aula_presente/features/courses/domain/course_draft.dart';
import 'package:aula_presente/features/courses/domain/course_page.dart';
import 'package:aula_presente/features/courses/domain/course_repository.dart';

class _FakeAuthRepository implements AuthRepository {
  AuthAccess restoreResult = const AuthAccess(
    status: AuthAccessStatus.signedOut,
  );
  AuthAccess loginResult = const AuthAccess(status: AuthAccessStatus.signedOut);
  AuthAccess refreshResult = const AuthAccess(
    status: AuthAccessStatus.verificationRequired,
  );
  AuthFailure? loginFailure;
  bool signInCalled = false;
  bool signOutCalled = false;
  bool refreshAccessCalled = false;
  String? lastExpectedEmail;
  bool passwordResetCalled = false;
  AuthAccess currentAccess = const AuthAccess(
    status: AuthAccessStatus.signedOut,
  );
  final StreamController<AuthAccess> _accessUpdates =
      StreamController<AuthAccess>.broadcast(sync: true);

  @override
  Future<AuthAccess> restoreSession() async {
    currentAccess = restoreResult;
    return restoreResult;
  }

  @override
  Stream<AuthAccess> watchAccess() => Stream<AuthAccess>.multi((controller) {
    controller.add(currentAccess);
    final subscription = _accessUpdates.stream.listen(
      controller.add,
      onError: (Object error, StackTrace stackTrace) =>
          controller.addError(error, stackTrace),
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<AuthAccess> signIn({
    required String email,
    required String password,
  }) async {
    signInCalled = true;
    final failure = loginFailure;
    if (failure != null) throw failure;
    currentAccess = loginResult;
    _accessUpdates.add(currentAccess);
    return loginResult;
  }

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
    refreshAccessCalled = true;
    lastExpectedEmail = expectedEmail;
    currentAccess = refreshResult;
    _accessUpdates.add(currentAccess);
    return refreshResult;
  }

  @override
  Future<void> retryRegistrationSetup({
    required String name,
    required String studentCode,
  }) async {}

  @override
  Future<void> resendEmailVerification() async {}

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetCalled = true;
  }

  @override
  Future<void> requestEmailCorrection({
    required String newEmail,
    required String currentPassword,
  }) async {}

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    currentAccess = const AuthAccess(status: AuthAccessStatus.signedOut);
    _accessUpdates.add(currentAccess);
  }

  void updateAccess(AuthAccess access) {
    currentAccess = access;
    _accessUpdates.add(access);
  }
}

class _FakeTeacherAccessRepository
    implements teacher_access.TeacherAccessRepository {
  _FakeTeacherAccessRepository({
    List<teacher_access.TeacherAccessRequest>? pendingRequests,
  }) : pendingRequests = pendingRequests ?? [];

  teacher_access.TeacherAccessRequest? ownRequest;
  final List<teacher_access.TeacherAccessRequest> pendingRequests;
  int createCount = 0;
  int decisionCount = 0;

  teacher_access.TeacherAccessRequest _request({
    String uid = 'uid-estudiante',
    teacher_access.TeacherAccessStatus status =
        teacher_access.TeacherAccessStatus.pending,
    String? decidedBy,
    DateTime? decidedAt,
    String? rejectionReason,
  }) => teacher_access.TeacherAccessRequest(
    uid: uid,
    name: 'Ana Pérez',
    email: 'ana@udla.edu.co',
    studentCode: 'A123',
    status: status,
    createdAt: DateTime.utc(2026, 10, 28),
    decidedBy: decidedBy,
    decidedAt: decidedAt,
    rejectionReason: rejectionReason,
  );

  @override
  Future<teacher_access.TeacherAccessRequest?> getOwnRequest() async =>
      ownRequest;

  @override
  Stream<teacher_access.TeacherAccessRequest?> watchOwnRequest() =>
      Stream.value(ownRequest);

  @override
  Future<teacher_access.TeacherAccessRequest> createOwnRequest() async {
    createCount++;
    ownRequest = _request();
    return ownRequest!;
  }

  @override
  Stream<List<teacher_access.TeacherAccessRequest>> watchPendingRequests() =>
      Stream.value(List.unmodifiable(pendingRequests));

  @override
  Future<teacher_access.TeacherAccessReview> getReview(
    String requesterUid,
  ) async {
    final request = pendingRequests.firstWhere(
      (item) => item.uid == requesterUid,
    );
    return teacher_access.TeacherAccessReview(
      request: request,
      currentName: request.name,
      currentEmail: request.email,
      currentStudentCode: request.studentCode,
      currentRoles: const ['student'],
    );
  }

  @override
  Future<teacher_access.TeacherAccessRequest> decideRequest({
    required String requesterUid,
    required teacher_access.TeacherAccessDecision decision,
    String? rejectionReason,
  }) async {
    decisionCount++;
    final request = _request(
      uid: requesterUid,
      status: decision == teacher_access.TeacherAccessDecision.approve
          ? teacher_access.TeacherAccessStatus.approved
          : teacher_access.TeacherAccessStatus.rejected,
      decidedBy: 'uid-admin',
      decidedAt: DateTime.utc(2026, 10, 29),
      rejectionReason: rejectionReason,
    );
    ownRequest = request;
    return request;
  }
}

Widget _testApp(_FakeAuthRepository repository) => AulaPresenteApp(
  authRepository: repository,
  teacherAccessRepository: _FakeTeacherAccessRepository(),
  courseRepository: _FakeCourseRepository(),
);

class _FakeCourseRepository implements CourseRepository {
  final List<Course> courses = [];

  @override
  Future<CoursePage> getOwnCoursePage({
    CourseCursor? cursor,
    int pageSize = 25,
  }) async => CoursePage(items: courses, nextCursor: null);

  @override
  Future<List<Course>> getAllOwnCourses({int pageSize = 25}) async =>
      List.unmodifiable(courses);

  @override
  Future<CourseCreationResult> createCourse(CourseDraft draft) async {
    final course = Course(
      id: draft.id,
      ownerUid: 'uid-docente',
      subject: draft.subject,
      group: draft.group,
      period: draft.period,
      program: draft.program,
      schedule: draft.schedule,
    );
    return CourseCreationResult(course: course, wasAlreadyCreated: false);
  }
}

Future<void> _openLogin(
  WidgetTester tester,
  _FakeAuthRepository repository,
) async {
  await tester.pumpWidget(_testApp(repository));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Entrar con mi cuenta'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abre bienvenida e inicia la ruta de acceso', (tester) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Tu clase empieza aquí.'), findsOneWidget);
    await tester.tap(find.text('Entrar con mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Qué bueno verte.'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
  });

  testWidgets('un fallo de credenciales no abre un espacio protegido', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..loginFailure = const AuthFailure(AuthFailureKind.invalidCredentials);
    await _openLogin(tester, repository);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'persona@udla.edu.co',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-segura');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(repository.signInCalled, isTrue);
    expect(find.text('No pudimos entrar'), findsOneWidget);
    expect(find.text('Perfil estudiante'), findsNothing);
  });

  testWidgets(
    'la recuperación muestra confirmación genérica y vuelve a login',
    (tester) async {
      final repository = _FakeAuthRepository();
      await _openLogin(tester, repository);

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Olvidé mi contraseña'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'persona@udla.edu.co',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Enviar enlace'));
      await tester.pumpAndSettle();

      expect(repository.passwordResetCalled, isTrue);
      expect(find.text('Revisa tu bandeja.'), findsOneWidget);
      expect(
        find.textContaining('Si el correo está registrado'),
        findsOneWidget,
      );
      expect(find.text('persona@udla.edu.co'), findsNothing);

      await tester.tap(find.text('Volver al inicio de sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Qué bueno verte.'), findsOneWidget);
    },
  );

  testWidgets('C11 vuelve a comprobar el correo antes de abrir el espacio', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..loginResult = const AuthAccess(
        status: AuthAccessStatus.verificationRequired,
        email: 'persona@udla.edu.co',
      );
    await _openLogin(tester, repository);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'persona@udla.edu.co',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-segura');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Verificar correo'), findsOneWidget);
    expect(find.text('Ya verifiqué mi correo'), findsOneWidget);
    expect(find.text('Perfil estudiante'), findsNothing);

    final verifyButton = find.text('Ya verifiqué mi correo');
    await tester.ensureVisible(verifyButton);
    await tester.pumpAndSettle();
    await tester.tap(verifyButton);
    await tester.pumpAndSettle();
    expect(repository.refreshAccessCalled, isTrue);
    expect(
      find.textContaining('Todavía no aparece la verificación.'),
      findsOneWidget,
    );
    expect(find.text('Perfil estudiante'), findsNothing);

    repository.refreshResult = const AuthAccess(
      status: AuthAccessStatus.student,
      uid: 'uid-estudiante',
      email: 'persona@udla.edu.co',
      name: 'Persona Estudiante',
      roles: ['student'],
    );
    await tester.ensureVisible(verifyButton);
    await tester.pumpAndSettle();
    await tester.tap(verifyButton);
    await tester.pumpAndSettle();
    expect(find.text('¿En qué espacio entrarás?'), findsOneWidget);
    expect(find.text('Solicitar acceso docente'), findsOneWidget);
    await tester.tap(find.text('Estudiante'));
    await tester.pumpAndSettle();
    expect(find.text('Perfil estudiante'), findsOneWidget);
    expect(find.text('Persona Estudiante'), findsOneWidget);
  });

  testWidgets(
    'solo el rol student abre el perfil y cerrar sesión limpia la ruta',
    (tester) async {
      final repository = _FakeAuthRepository()
        ..loginResult = const AuthAccess(
          status: AuthAccessStatus.student,
          uid: 'uid-estudiante',
          email: 'ana@udla.edu.co',
          name: 'Ana Pérez',
          roles: ['student'],
        );
      await _openLogin(tester, repository);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'ana@udla.edu.co',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'clave-segura');
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('¿En qué espacio entrarás?'), findsOneWidget);
      expect(find.text('Docente'), findsNothing);
      await tester.tap(find.text('Estudiante'));
      await tester.pumpAndSettle();
      expect(find.text('Perfil estudiante'), findsOneWidget);
      expect(find.text('Registros de prueba'), findsOneWidget);
      final signOutButton = find.widgetWithText(
        OutlinedButton,
        'Cerrar sesión',
      );
      await tester.ensureVisible(signOutButton);
      await tester.pumpAndSettle();
      await tester.tap(signOutButton);
      await tester.pumpAndSettle();

      expect(repository.signOutCalled, isTrue);
      expect(find.text('Tu clase empieza aquí.'), findsOneWidget);
      expect(find.text('Ana Pérez'), findsNothing);
    },
  );

  testWidgets('una cuenta admin abre solo la cola administrativa', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..loginResult = const AuthAccess(
        status: AuthAccessStatus.accessAvailable,
        uid: 'uid-admin',
        email: 'admin@udla.edu.co',
        roles: ['admin'],
      );
    await _openLogin(tester, repository);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'admin@udla.edu.co',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-segura');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('¿En qué espacio entrarás?'), findsOneWidget);
    expect(find.text('Administrador del proyecto'), findsOneWidget);
    expect(find.text('Estudiante'), findsNothing);
    expect(find.text('Docente'), findsNothing);
    expect(find.text('Perfil estudiante'), findsNothing);
    await tester.tap(find.text('Administrador del proyecto'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitudes docentes'), findsOneWidget);
  });

  testWidgets('el espacio docente abre cursos y se cierra al retirar teacher', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..loginResult = const AuthAccess(
        status: AuthAccessStatus.accessAvailable,
        uid: 'uid-docente',
        email: 'docente@udla.edu.co',
        name: 'Docente de prueba',
        roles: ['teacher'],
      );
    await _openLogin(tester, repository);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'docente@udla.edu.co',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'clave-segura');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Docente'), findsOneWidget);
    expect(find.text('Mis cursos'), findsNothing);
    await tester.tap(find.text('Docente'));
    await tester.pumpAndSettle();
    expect(find.text('Hola, profe'), findsOneWidget);

    repository.updateAccess(
      const AuthAccess(
        status: AuthAccessStatus.student,
        uid: 'uid-docente',
        email: 'docente@udla.edu.co',
        roles: ['student'],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('¿En qué espacio entrarás?'), findsOneWidget);
    expect(find.text('Crear un curso'), findsNothing);
    expect(find.text('Perfil estudiante'), findsNothing);
  });

  testWidgets('al reiniciar restaura una sesión student verificada', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..restoreResult = const AuthAccess(
        status: AuthAccessStatus.student,
        uid: 'uid-estudiante',
        email: 'ana@udla.edu.co',
        name: 'Ana Pérez',
        roles: ['student'],
      );
    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('¿En qué espacio entrarás?'), findsOneWidget);
    await tester.tap(find.text('Estudiante'));
    await tester.pumpAndSettle();
    expect(find.text('Perfil estudiante'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Tu clase empieza aquí.'), findsNothing);
  });

  testWidgets('un perfil ausente explica el bloqueo sin asignar un rol', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..restoreResult = const AuthAccess(
        status: AuthAccessStatus.profileMissing,
        uid: 'uid-sin-perfil',
        email: 'persona@udla.edu.co',
      );
    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('No encontramos tu perfil.'), findsOneWidget);
    expect(
      find.textContaining('No asignamos permisos automáticamente.'),
      findsOneWidget,
    );
    expect(find.text('Perfil estudiante'), findsNothing);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });

  testWidgets('el menú X01 es una vista previa que no llama a Firebase', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Aula\nPresente'));
    await tester.pumpAndSettle();
    expect(find.text('Estados de diseño · solo depuración'), findsOneWidget);

    await tester.tap(find.text('X01 · Error de inicio de sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Intentémoslo otra vez.'), findsOneWidget);
    expect(find.text('No pudimos entrar'), findsOneWidget);
    expect(repository.signInCalled, isFalse);
  });
}
