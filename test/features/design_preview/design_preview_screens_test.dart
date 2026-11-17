import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/design_preview/mockup_catalog.dart';
import 'package:aula_presente/features/design_preview/mockup_frame.dart';
import 'package:aula_presente/features/design_preview/presentation/design_preview_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.text('Una falta. Un contexto.'), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('demo-reject')));
    await tester.pumpAndSettle();
    expect(
      find.text('Solicitud rechazada en esta demostración.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('demo-approve')), findsNothing);
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
