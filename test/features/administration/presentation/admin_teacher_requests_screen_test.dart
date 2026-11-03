import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/administration/domain/teacher_access_repository.dart';
import 'package:aula_presente/features/administration/domain/teacher_access_request.dart';
import 'package:aula_presente/features/administration/presentation/admin_teacher_requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_doubles.dart';

void main() {
  testWidgets('S04 muestra estado vacío y opciones sin datos inventados', (
    tester,
  ) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository();
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No hay solicitudes pendientes'), findsOneWidget);
    expect(find.text('Invitaciones docentes'), findsOneWidget);
    expect(find.text('Estadísticas'), findsOneWidget);
    expect(find.textContaining('no usa datos de ejemplo'), findsOneWidget);
    expect(requests.watchPendingCalls, 1);
  });

  testWidgets('S04 ofrece reintento si no llega confirmación del servidor', (
    tester,
  ) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()..pendingNever = true;
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Cargando solicitudes docentes…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar las solicitudes'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('S04 representa error de permisos de la lista', (tester) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()
      ..listError = const TeacherAccessFailure(
        TeacherAccessFailureKind.permissionDenied,
      );
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No pudimos cargar las solicitudes'), findsOneWidget);
    expect(
      find.text('Tu cuenta no tiene permiso para completar esta operación.'),
      findsOneWidget,
    );
  });

  testWidgets('S04 representa error de red y permite reintentar', (
    tester,
  ) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()
      ..listError = const TeacherAccessFailure(
        TeacherAccessFailureKind.network,
      );
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos conectar con el servicio. Revisa tu conexión.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(requests.watchPendingCalls, 2);
  });

  testWidgets('S05 compara el snapshot con el perfil actual', (tester) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()
      ..pendingRequests = [sampleRequest()]
      ..review = sampleReview();
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('teacher-request-requester-1')),
    );
    await tester.pumpAndSettle();

    expect(requests.reviewCalls, 1);
    expect(find.text('Al solicitar'), findsWidgets);
    expect(find.text('Perfil actual'), findsWidgets);
    expect(find.text('Ana Pérez'), findsWidgets);
    expect(find.text('Ana María Pérez'), findsOneWidget);
    expect(find.text('Diferencia'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('El código no acredita identidad docente'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.text('El código no acredita identidad docente'),
      findsOneWidget,
    );
  });

  testWidgets('cancelar aprobación no decide; confirmar aprobación sí', (
    tester,
  ) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()
      ..pendingRequests = [sampleRequest()]
      ..review = sampleReview();
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('teacher-request-requester-1')),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Aprobar acceso docente'));
    await tester.pumpAndSettle();
    expect(find.text('Aprobar solicitud'), findsOneWidget);
    await _tapVisible(tester, find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(requests.decisionCalls, 0);

    await _tapVisible(tester, find.text('Aprobar acceso docente'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Confirmar aprobación'));
    await tester.pumpAndSettle();

    expect(requests.decisionCalls, 1);
    expect(requests.lastDecision, TeacherAccessDecision.approve);
    expect(find.text('Autorización concedida.'), findsOneWidget);

    auth.updateAccess(studentAccess());
    await tester.pumpAndSettle();
    expect(find.text('Acceso de administración no disponible'), findsOneWidget);
    expect(find.text('Autorización concedida.'), findsNothing);
  });

  testWidgets('rechazo pide motivo y solo confirma con texto válido', (
    tester,
  ) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()
      ..pendingRequests = [sampleRequest()]
      ..review = sampleReview();
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('teacher-request-requester-1')),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Rechazar solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Motivo del rechazo'), findsOneWidget);
    await _tapVisible(tester, find.text('Confirmar rechazo'));
    await tester.pumpAndSettle();
    expect(
      find.text('Escribe un motivo de 1 a 500 caracteres.'),
      findsOneWidget,
    );
    expect(requests.decisionCalls, 0);

    await tester.enterText(
      find.byType(TextField),
      'Falta validar la institución.',
    );
    await _tapVisible(tester, find.text('Confirmar rechazo'));
    await tester.pumpAndSettle();
    expect(requests.decisionCalls, 1);
    expect(requests.lastDecision, TeacherAccessDecision.reject);
    expect(requests.lastRejectionReason, 'Falta validar la institución.');
    expect(find.text('Solicitud rechazada.'), findsOneWidget);
    expect(find.text('Falta validar la institución.'), findsOneWidget);
  });

  testWidgets('la decisión fallida permanece en revisión y enseña el error', (
    tester,
  ) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()
      ..pendingRequests = [sampleRequest()]
      ..review = sampleReview()
      ..decisionError = const TeacherAccessFailure(
        TeacherAccessFailureKind.network,
      );
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('teacher-request-requester-1')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Aprobar acceso docente'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Confirmar aprobación'));
    await tester.pumpAndSettle();

    expect(find.text('No se confirmó la decisión'), findsOneWidget);
    expect(
      find.text('No pudimos conectar con el servicio. Revisa tu conexión.'),
      findsOneWidget,
    );
    expect(find.text('Aprobar acceso docente'), findsOneWidget);
  });

  testWidgets('una decisión denegada por reglas muestra permiso y no éxito', (
    tester,
  ) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()
      ..pendingRequests = [sampleRequest()]
      ..review = sampleReview()
      ..decisionError = const TeacherAccessFailure(
        TeacherAccessFailureKind.permissionDenied,
      );
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('teacher-request-requester-1')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Aprobar acceso docente'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Confirmar aprobación'));
    await tester.pumpAndSettle();

    expect(requests.decisionCalls, 1);
    expect(find.text('No se confirmó la decisión'), findsOneWidget);
    expect(
      find.text('Tu cuenta no tiene permiso para completar esta operación.'),
      findsOneWidget,
    );
    expect(find.text('Autorización concedida.'), findsNothing);
    expect(find.text('Aprobar acceso docente'), findsOneWidget);
  });

  testWidgets('oculta S04 al perder el rol de administración', (tester) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository();
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Solicitudes pendientes · 0'), findsOneWidget);

    auth.updateAccess(studentAccess());
    await tester.pumpAndSettle();
    expect(find.text('Acceso de administración no disponible'), findsOneWidget);
    expect(find.text('No hay solicitudes pendientes'), findsNothing);
  });

  testWidgets('oculta S05 al cambiar de cuenta o perder administración', (
    tester,
  ) async {
    final auth = FakeAuthRepository(adminAccess());
    final requests = FakeTeacherAccessRepository()
      ..pendingRequests = [sampleRequest()]
      ..review = sampleReview();
    await tester.pumpWidget(
      _app(
        AdminTeacherRequestsScreen(
          access: auth.access,
          authRepository: auth,
          requestRepository: requests,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('teacher-request-requester-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ana María Pérez'), findsOneWidget);

    auth.updateAccess(studentAccess());
    await tester.pumpAndSettle();
    expect(find.text('Acceso de administración no disponible'), findsOneWidget);
    expect(find.text('Ana María Pérez'), findsNothing);
    expect(find.text('Aprobar acceso docente'), findsNothing);
  });

  testWidgets('S04, S05 y S06 se adaptan a anchuras y texto ampliado', (
    tester,
  ) async {
    for (final width in <double>[320, 390, 430]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      final auth = FakeAuthRepository(adminAccess());
      final requests = FakeTeacherAccessRepository()
        ..pendingRequests = [sampleRequest()]
        ..review = sampleReview();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('administration-width-$width'),
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: AdminTeacherRequestsScreen(
              access: auth.access,
              authRepository: auth,
              requestRepository: requests,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'S04 ancho $width');
      expect(find.text('Solicitudes pendientes · 1'), findsOneWidget);
      expect(find.byType(Scrollable), findsWidgets);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('teacher-request-requester-1')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'S05 ancho $width');

      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('decision-result-width-$width'),
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: TeacherAccessDecisionResultScreen(
              access: auth.access,
              authRepository: auth,
              request: sampleRequest(status: TeacherAccessStatus.approved),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Autorización concedida.'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'S06 ancho $width');
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  final viewport = Rect.fromLTWH(
    0,
    0,
    tester.view.physicalSize.width / tester.view.devicePixelRatio,
    tester.view.physicalSize.height / tester.view.devicePixelRatio,
  );
  final needsScroll =
      finder.evaluate().isEmpty ||
      !viewport.contains(tester.getRect(finder).topLeft) ||
      !viewport.contains(tester.getRect(finder).bottomRight);
  if (needsScroll && find.byType(Scrollable).evaluate().isNotEmpty) {
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
