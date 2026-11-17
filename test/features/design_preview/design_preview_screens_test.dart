import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/design_preview/mockup_catalog.dart';
import 'package:aula_presente/features/design_preview/mockup_frame.dart';
import 'package:aula_presente/features/design_preview/presentation/design_preview_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void usePhoneViewport(WidgetTester tester, {double width = 390}) {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app() => MaterialApp(
    theme: AppTheme.dark,
    home: const DesignPreviewCatalogScreen(),
  );

  test('catalog contains every inventoried page and all four roles', () {
    expect(mockupFrames, hasLength(158));
    expect(mockupFrames.map((frame) => frame.page).toSet(), hasLength(158));
    expect(mockupFrames.map((frame) => frame.role).toSet(), hasLength(4));
    expect(
      mockupFrames.map((frame) => frame.role),
      containsAll(MockupRole.values),
    );
  });

  testWidgets('role filters open the student journey and advance locally', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(app());
    expect(find.text('158 de 158 marcos · todos los perfiles'), findsOneWidget);

    await tester.tap(find.byKey(const Key('role-student')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mockup-007')), findsOneWidget);
    expect(find.byKey(const Key('mockup-037')), findsNothing);

    final target = find.byKey(const Key('mockup-032'));
    await tester.scrollUntilVisible(
      target,
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('Una falta. Un documento.'), findsOneWidget);
    expect(find.byKey(const Key('demo-note')), findsOneWidget);
    final demoNotice = find.textContaining('no se carga');
    await tester.scrollUntilVisible(
      demoNotice,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(demoNotice, findsOneWidget);

    final primaryAction = find.byKey(const Key('demo-primary-action'));
    await tester.scrollUntilVisible(
      primaryAction,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.widget<FilledButton>(primaryAction).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('demo-note')));
    await tester.enterText(
      find.byKey(const Key('demo-note')),
      'Tuve una cita médica durante este encuentro.',
    );
    await tester.pumpAndSettle();

    await tester.tap(primaryAction);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'La solicitud queda en estado Pendiente solo en esta demostración.',
      ),
      findsOneWidget,
    );

    final nextFrame = find.byKey(const Key('demo-next-frame'));
    await tester.scrollUntilVisible(
      nextFrame,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(nextFrame);
    await tester.pumpAndSettle();
    expect(find.text('PDF p. 033'), findsOneWidget);
  });

  testWidgets('teacher can review a fictitious request without a repository', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('role-teacher')));
    await tester.pumpAndSettle();

    final target = find.byKey(const Key('mockup-054'));
    await tester.scrollUntilVisible(
      target,
      280,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('Revisa esta justificación.'), findsOneWidget);
    final reject = find.byKey(const Key('demo-reject'));
    await tester.scrollUntilVisible(
      reject,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(reject);
    await tester.tap(reject);
    await tester.pumpAndSettle();
    final rejectedMessage = find.text(
      'Solicitud rechazada en esta demostración.',
    );
    await tester.scrollUntilVisible(
      rejectedMessage,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(rejectedMessage, findsOneWidget);
    expect(find.byKey(const Key('demo-approve')), findsNothing);
  });

  testWidgets('student check-in simulation advances to its receipt locally', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('role-student')));
    await tester.pumpAndSettle();

    final checkIn = find.byKey(const Key('mockup-027'));
    await tester.scrollUntilVisible(
      checkIn,
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(checkIn);
    await tester.pumpAndSettle();
    expect(find.text('Estás cerca de tu clase.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'QR'));
    await tester.pumpAndSettle();
    expect(find.text('QR · sesión local'), findsOneWidget);

    final primaryAction = find.byKey(const Key('demo-primary-action'));
    await tester.scrollUntilVisible(
      primaryAction,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(primaryAction);
    await tester.pumpAndSettle();
    final result = find.textContaining('se simuló localmente');
    await tester.scrollUntilVisible(
      result,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(result, findsOneWidget);

    final nextFrame = find.byKey(const Key('demo-next-frame'));
    await tester.scrollUntilVisible(
      nextFrame,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(nextFrame);
    await tester.pumpAndSettle();
    expect(find.text('¡Listo, Alex!'), findsOneWidget);
    expect(find.textContaining('Asistencia registrada.'), findsOneWidget);
  });

  testWidgets(
    'teacher can dismiss and confirm a cancellation without a reason',
    (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const Key('role-teacher')));
      await tester.pumpAndSettle();

      final cancellation = find.byKey(const Key('mockup-043'));
      await tester.scrollUntilVisible(
        cancellation,
        260,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(cancellation);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('demo-note')), findsOneWidget);

      final action = find.byKey(const Key('demo-primary-action'));
      await tester.scrollUntilVisible(
        action,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Cancelar'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();
      final result = find.text(
        'La clase quedó cancelada solo en este prototipo.',
      );
      await tester.scrollUntilVisible(
        result,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      expect(result, findsOneWidget);
    },
  );

  testWidgets('teacher confirms or keeps recording from the close frame', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('role-teacher')));
    await tester.pumpAndSettle();

    final closeFrame = find.byKey(const Key('mockup-047'));
    await tester.dragUntilVisible(
      closeFrame,
      find.byKey(const Key('mockup-frame-list')),
      const Offset(0, -320),
    );
    await tester.tap(closeFrame);
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('demo-primary-action'));
    await tester.scrollUntilVisible(
      action,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Seguir registrando'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar cierre'));
    await tester.pumpAndSettle();
    final result = find.textContaining('Cierre de prueba completado');
    await tester.scrollUntilVisible(
      result,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(result, findsOneWidget);
  });

  testWidgets('teacher corrects a mark locally without a reason', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('role-teacher')));
    await tester.pumpAndSettle();

    final correction = find.byKey(const Key('mockup-048'));
    await tester.dragUntilVisible(
      correction,
      find.byKey(const Key('mockup-frame-list')),
      const Offset(0, -320),
    );
    await tester.tap(correction);
    await tester.pumpAndSettle();
    expect(find.text('Marca de asistencia'), findsOneWidget);
    expect(find.byKey(const Key('demo-note')), findsOneWidget);
    await tester.tap(find.text('Ausente'));
    await tester.pumpAndSettle();

    final action = find.byKey(const Key('demo-primary-action'));
    await tester.scrollUntilVisible(
      action,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    final result = find.text('Marca Ausente guardada en el prototipo.');
    await tester.scrollUntilVisible(
      result,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(result, findsOneWidget);
  });

  testWidgets('catalog and frame fit narrow mobile width', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('role-student')));
    await tester.pumpAndSettle();
    final studentHome = find.byKey(const Key('mockup-019'));
    await tester.scrollUntilVisible(
      studentHome,
      280,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(studentHome);
    await tester.pumpAndSettle();
    expect(find.text('Hola, Alex'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
