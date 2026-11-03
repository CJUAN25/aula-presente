import 'dart:async';

import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/administration/domain/teacher_access_repository.dart';
import 'package:aula_presente/features/administration/domain/teacher_access_request.dart';
import 'package:aula_presente/features/administration/presentation/teacher_access_screens.dart';
import 'package:aula_presente/features/auth/domain/auth_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_doubles.dart';

void main() {
  testWidgets('crea una solicitud y abre su estado confirmado', (tester) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository();
    await tester.pumpWidget(
      _app(
        TeacherAccessScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Solicitar acceso docente'));
    await tester.pumpAndSettle();

    expect(requests.createCalls, 1);
    expect(find.text('Solicitud docente'), findsWidgets);
    expect(find.text('Pendiente de revisión'), findsWidgets);
    expect(
      find.text('La administración todavía no ha registrado una decisión.'),
      findsOneWidget,
    );
  });

  testWidgets('no envía dos veces mientras la creación sigue ocupada', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository()
      ..createCompleter = Completer<TeacherAccessRequest>();
    await tester.pumpWidget(
      _app(
        TeacherAccessScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.text('Solicitar acceso docente');
    await _tapVisible(tester, button);
    await tester.tap(button);
    await tester.pump();
    expect(requests.createCalls, 1);
    expect(find.text('Enviando…'), findsOneWidget);

    requests.createCompleter!.complete(sampleRequest());
    await tester.pumpAndSettle();
    expect(find.text('Pendiente de revisión'), findsWidgets);
  });

  testWidgets('explica que las invitaciones aún no están disponibles', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository();
    await tester.pumpWidget(
      _app(
        TeacherAccessScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Aún no disponible'));
    await tester.pumpAndSettle();
    expect(find.text('Invitaciones docentes'), findsOneWidget);
    expect(
      find.textContaining('El ingreso con código todavía no está disponible.'),
      findsOneWidget,
    );
    expect(requests.createCalls, 0);
  });

  testWidgets('sin sesión permite volver al registro sin crear solicitud', (
    tester,
  ) async {
    final signedOut = AuthAccess(status: AuthAccessStatus.signedOut);
    final auth = FakeAuthRepository(signedOut);
    final requests = FakeTeacherAccessRepository();
    var returnedToRegistration = false;
    await tester.pumpWidget(
      _app(
        TeacherAccessScreen(
          access: signedOut,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () => returnedToRegistration = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Aún no se envió ninguna solicitud.'),
      findsOneWidget,
    );
    await _tapVisible(tester, find.text('Volver al registro'));
    expect(returnedToRegistration, isTrue);
    expect(requests.createCalls, 0);
  });

  testWidgets('una solicitud duplicada abre el estado consultado', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository()
      ..createError = const TeacherAccessFailure(
        TeacherAccessFailureKind.alreadyExists,
      )
      ..requestOnGet = sampleRequest(status: TeacherAccessStatus.approved);
    await tester.pumpWidget(
      _app(
        TeacherAccessScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Solicitar acceso docente'));
    await tester.pumpAndSettle();
    expect(requests.getOwnCalls, greaterThanOrEqualTo(2));
    expect(find.text('Aprobada'), findsWidgets);
  });

  testWidgets('representa un error de permisos sin afirmar que se creó', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository()
      ..createError = const TeacherAccessFailure(
        TeacherAccessFailureKind.permissionDenied,
      );
    await tester.pumpWidget(
      _app(
        TeacherAccessScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Solicitar acceso docente'));
    await tester.pumpAndSettle();

    expect(requests.createCalls, 1);
    expect(find.text('No se envió la solicitud'), findsOneWidget);
    expect(
      find.text('Tu cuenta no tiene permiso para completar esta operación.'),
      findsOneWidget,
    );
    expect(find.text('Pendiente de revisión'), findsNothing);
  });

  testWidgets('representa error de red al consultar la solicitud', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository()
      ..ownWatchError = const TeacherAccessFailure(
        TeacherAccessFailureKind.network,
      );
    await tester.pumpWidget(
      _app(
        TeacherAccessScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No pudimos consultar tu solicitud'), findsOneWidget);
    expect(
      find.text('No pudimos conectar con el servicio. Revisa tu conexión.'),
      findsOneWidget,
    );
    expect(find.text('Solicitar acceso docente'), findsNothing);
  });

  testWidgets('consulta desde servidor y representa estado pendiente', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository()
      ..ownRequest = sampleRequest();
    await tester.pumpWidget(
      _app(
        TeacherRequestStatusScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.getOwnCalls, 1);
    expect(find.text('Pendiente de revisión'), findsWidgets);

    await _tapVisible(tester, find.text('Consultar solicitud'));
    await tester.pumpAndSettle();
    expect(requests.getOwnCalls, 2);
  });

  testWidgets('representa solicitud aprobada y rechazada con motivo real', (
    tester,
  ) async {
    for (final item in <(TeacherAccessRequest, String, String)>[
      (
        sampleRequest(status: TeacherAccessStatus.approved),
        'Aprobada',
        'La aprobación fue confirmada.',
      ),
      (
        sampleRequest(
          status: TeacherAccessStatus.rejected,
          rejectionReason: 'Falta validar la institución.',
        ),
        'Rechazada',
        'Falta validar la institución.',
      ),
    ]) {
      final auth = FakeAuthRepository(studentAccess());
      final requests = FakeTeacherAccessRepository()..ownRequest = item.$1;
      await tester.pumpWidget(
        _app(
          TeacherRequestStatusScreen(
            key: ValueKey('status-${item.$2}'),
            access: auth.access,
            authRepository: auth,
            requestRepository: requests,
            onContinueAsStudent: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(item.$2), findsWidgets);
      expect(find.textContaining(item.$3), findsOneWidget);
    }
  });

  testWidgets('oculta la solicitud anterior si cambia la cuenta en C13', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository()
      ..ownRequest = sampleRequest(
        status: TeacherAccessStatus.rejected,
        rejectionReason: 'Motivo privado de la cuenta anterior',
      );
    await tester.pumpWidget(
      _app(
        TeacherRequestStatusScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Motivo privado de la cuenta anterior'), findsOneWidget);

    auth.updateAccess(
      const AuthAccess(
        status: AuthAccessStatus.student,
        uid: 'otra-cuenta',
        email: 'otra@example.edu',
        roles: ['student'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('La sesión cambió'), findsOneWidget);
    expect(find.textContaining('Motivo privado de la cuenta anterior'), findsNothing);
    expect(find.text('Rechazada'), findsNothing);
  });

  testWidgets('C12 ofrece reintento si no llega confirmación del servidor', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository()..ownWatchNever = true;
    await tester.pumpWidget(
      _app(
        TeacherAccessScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Consultando tu solicitud…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos consultar tu solicitud'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('error de red al consultar no confirma un cambio de estado', (
    tester,
  ) async {
    final auth = FakeAuthRepository(studentAccess());
    final requests = FakeTeacherAccessRepository()
      ..ownRequest = sampleRequest()
      ..getErrorForTest = const TeacherAccessFailure(
        TeacherAccessFailureKind.network,
      );
    await tester.pumpWidget(
      _app(
        TeacherRequestStatusScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
          onContinueAsStudent: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pendiente de revisión'), findsWidgets);
    expect(
      find.text('No pudimos confirmar si el estado cambió'),
      findsOneWidget,
    );
  });

  testWidgets('la pantalla se adapta a anchos comunes con texto ampliado', (
    tester,
  ) async {
    for (final width in <double>[320, 390, 430]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      final auth = FakeAuthRepository(studentAccess());
      final requests = FakeTeacherAccessRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: TeacherAccessScreen(
              access: auth.access,
              authRepository: auth,
              requestRepository: requests,
              onContinueAsStudent: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'ancho lógico $width');
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).last,
    );
  } else {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
  await tester.tap(finder);
}

Widget _app(Widget child) => MaterialApp(theme: AppTheme.dark, home: child);
