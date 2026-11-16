import 'package:aula_presente/app/theme/app_theme.dart';
import 'package:aula_presente/features/auth/domain/auth_access.dart';
import 'package:aula_presente/features/courses/domain/course.dart';
import 'package:aula_presente/features/courses/domain/course_creation_result.dart';
import 'package:aula_presente/features/courses/domain/course_cursor.dart';
import 'package:aula_presente/features/courses/domain/course_draft.dart';
import 'package:aula_presente/features/courses/domain/course_page.dart';
import 'package:aula_presente/features/courses/domain/course_repository.dart';
import 'package:aula_presente/features/courses/presentation/teacher_courses_screen.dart';
import 'package:aula_presente/features/schedule/domain/academic_date.dart';
import 'package:aula_presente/features/schedule/domain/course_schedule.dart';
import 'package:aula_presente/features/schedule/domain/weekly_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TeacherCoursesScreen', () {
    testWidgets('muestra el estado vacío real y no usa cursos de ejemplo', (
      tester,
    ) async {
      final repository = _FakeCourseRepository();
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      expect(find.text('Hola, profe'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Bases de Datos'), findsNothing);
      expect(repository.getAllCalls, 1);
      expect(repository.createCalls, 0);
    });

    testWidgets('permite reintentar una consulta fallida', (tester) async {
      final repository = _FakeCourseRepository()..failNextList = true;
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar tus cursos'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(repository.getAllCalls, 2);
      expect(find.text('Hola, profe'), findsOneWidget);
    });

    testWidgets('muestra error de recarga sin borrar la lista anterior', (
      tester,
    ) async {
      final repository = _FakeCourseRepository()
        ..courses = [_course()]
        ..failOnListCall = 2;
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cursos').last);
      await tester.pumpAndSettle();
      expect(find.text('Algoritmos'), findsOneWidget);

      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar cursos'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('No se pudo actualizar la lista'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(find.text('Algoritmos'), findsOneWidget);
      expect(repository.getAllCalls, 2);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 390.0, 430.0]) {
      testWidgets('home se adapta a ${width.toInt()} px y texto 1.5x', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width * 2, 844 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _FakeCourseRepository();

        await tester.pumpWidget(
          _app(repository, textScaler: const TextScaler.linear(1.5)),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Hola, profe'), findsOneWidget);
        expect(find.text('Próximos encuentros previstos'), findsOneWidget);
      });
    }

    testWidgets('el borrador conserva sus datos al volver desde el horario', (
      tester,
    ) async {
      final repository = _FakeCourseRepository();
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cursos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Datos del curso'), findsOneWidget);

      await tester.enterText(_field(0), 'Arquitectura móvil');
      await tester.enterText(_field(1), '04');
      await tester.enterText(_field(2), '2026-2');
      await tester.enterText(_field(3), 'Ingeniería de sistemas');
      await tester.ensureVisible(find.text('Por encuentro'));
      await tester.tap(find.text('Por encuentro'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.ensureVisible(find.text('Definir calendario'));
      await tester.tap(find.text('Definir calendario'));
      await tester.pumpAndSettle();
      expect(find.text('Horario del curso'), findsOneWidget);
      expect(repository.createCalls, 0);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Crear curso'), findsOneWidget);
      await tester.ensureVisible(_field(0));
      expect(
        tester.widget<TextFormField>(_field(0)).controller!.text,
        'Arquitectura móvil',
      );
    });

    testWidgets('el botón de Cursos cambia al listado y búsqueda', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_FakeCourseRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cursos').last);
      await tester.pumpAndSettle();

      expect(find.text('Mis cursos'), findsNWidgets(2));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Aún no tienes cursos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('no permite abrir un resultado confirmado bajo otra cuenta', () {
    final result = CourseCreationResult(
      course: _course(ownerUid: 'cuenta-anterior'),
      wasAlreadyCreated: false,
    );

    expect(courseCreationBelongsToSession(result, 'cuenta-actual'), isFalse);
    expect(courseCreationBelongsToSession(result, 'cuenta-anterior'), isTrue);
    expect(courseCreationBelongsToSession(result, null), isFalse);
  });
}

Finder _field(int index) => find.byType(TextFormField).at(index);

Widget _app(
  CourseRepository repository, {
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  theme: AppTheme.dark,
  home: TeacherCoursesScreen(
    repository: repository,
    access: const AuthAccess(
      status: AuthAccessStatus.accessAvailable,
      uid: 'teacher-uid',
      name: 'Profesora Ejemplo',
      roles: ['student', 'teacher'],
    ),
    onOpenProfile: _noop,
    onSignOut: _noopAsync,
    clock: () => DateTime.utc(2026, 10, 29, 12),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
);

void _noop() {}

Future<void> _noopAsync() async {}

class _FakeCourseRepository implements CourseRepository {
  int getAllCalls = 0;
  int createCalls = 0;
  bool failNextList = false;
  int? failOnListCall;
  List<Course> courses = const [];
  @override
  Future<List<Course>> getAllOwnCourses({int pageSize = 25}) async {
    getAllCalls += 1;
    if (failNextList || getAllCalls == failOnListCall) {
      failNextList = false;
      throw StateError('offline');
    }
    return courses;
  }

  @override
  Future<CoursePage> getOwnCoursePage({
    CourseCursor? cursor,
    int pageSize = 25,
  }) async => CoursePage(items: const [], nextCursor: null);

  @override
  Future<CourseCreationResult> createCourse(CourseDraft draft) async {
    createCalls += 1;
    throw UnimplementedError('This screen test does not save a course.');
  }
}

Course _course({String ownerUid = 'teacher-uid'}) => Course(
  id: 'courseidentifier00001',
  ownerUid: ownerUid,
  subject: 'Algoritmos',
  group: '01',
  period: '2026-2',
  program: 'Ingeniería',
  schedule: CourseSchedule(
    startDate: AcademicDate(year: 2026, month: 10, day: 29),
    endDate: AcademicDate(year: 2026, month: 10, day: 29),
    weeklyBlocks: const [
      WeeklyBlock(
        id: 'blockidentifier000001',
        weekday: 4,
        startTime: '08:00',
        endTime: '09:00',
      ),
    ],
  ),
);
