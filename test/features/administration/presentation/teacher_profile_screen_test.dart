import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/administration/presentation/teacher_profile_screen.dart';
import 'package:aula_presente/features/auth/domain/auth_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_doubles.dart';

void main() {
  testWidgets('renderiza identidad y roles reales de la cuenta', (
    tester,
  ) async {
    final access = _teacherAndStudentAccess();
    final auth = FakeAuthRepository(access);
    await tester.pumpWidget(
      _app(
        TeacherProfileScreen(
          access: access,
          authRepository: auth,
          onChangeSpace: () {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lucía Mora'), findsOneWidget);
    expect(find.text('lucia@example.edu'), findsOneWidget);
    expect(find.text('Estudiante'), findsOneWidget);
    expect(find.text('Docente'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Cursos y estadísticas'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Cursos y estadísticas'), findsOneWidget);
    expect(find.text('Mis cursos'), findsNothing);
  });

  testWidgets('cambiar a estudiante vuelve a comprobar permiso real', (
    tester,
  ) async {
    final access = _teacherAndStudentAccess();
    final auth = FakeAuthRepository(access);
    var changedSpace = false;
    await tester.pumpWidget(
      _app(
        TeacherProfileScreen(
          access: access,
          authRepository: auth,
          onChangeSpace: () => changedSpace = true,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.text('Cambiar a estudiante'));
    await tester.pumpAndSettle();
    expect(auth.refreshCalls, 1);
    expect(changedSpace, isTrue);
  });

  testWidgets('oculta el perfil cuando la sesión pierde el rol docente', (
    tester,
  ) async {
    final access = _teacherAndStudentAccess();
    final auth = FakeAuthRepository(access);
    await tester.pumpWidget(
      _app(
        TeacherProfileScreen(
          access: access,
          authRepository: auth,
          onChangeSpace: () {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lucía Mora'), findsOneWidget);

    auth.updateAccess(studentAccess());
    await tester.pumpAndSettle();

    expect(
      find.text('El acceso docente ya no está disponible'),
      findsOneWidget,
    );
    expect(find.text('Lucía Mora'), findsNothing);
  });

  testWidgets('el perfil no desborda a 320, 390 o 430 con texto grande', (
    tester,
  ) async {
    for (final width in <double>[320, 390, 430]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      final access = _teacherAndStudentAccess();
      final auth = FakeAuthRepository(access);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: const TextScaler.linear(1.5),
            ),
            child: TeacherProfileScreen(
              access: access,
              authRepository: auth,
              onChangeSpace: () {},
              onSignOut: () async {},
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

AuthAccess _teacherAndStudentAccess() => const AuthAccess(
  status: AuthAccessStatus.accessAvailable,
  uid: 'requester-1',
  email: 'lucia@example.edu',
  name: 'Lucía Mora',
  studentCode: 'EST-7788',
  roles: ['student', 'teacher'],
);

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
